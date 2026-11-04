import Foundation
import CoreLocation

@MainActor
class LocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// Latest fix that passes `LocationFixFilter.coarse`; used for nearby stations and maps.
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    /// Only updated from fixes that pass `LocationFixFilter.proximity`.
    @Published var distanceToDestination: Double?
    /// Timestamp of the last fix precise enough to evaluate proximity.
    @Published var lastPreciseFixDate: Date?
    @Published var isAlreadyInsideAlertDistance = false
    @Published var errorMessage: String?

    private(set) var targetDestination: Destination?
    private(set) var alertDistance: Double?

    var onProximityReached: (() -> Void)?

    private var proximity: ProximityEvaluator?
    private var precision: TrackingPrecision?
    private var backgroundActivity: CLBackgroundActivitySession?

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        apply(.near)
        manager.allowsBackgroundLocationUpdates = true
        manager.activityType = .otherNavigation
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// One-shot fix for the home screen's Nearby list when no trip is being tracked.
    func refreshCurrentLocation() {
        guard isAuthorized, !isTracking else { return }
        manager.requestLocation()
    }

    func startTracking(destination: Destination, alertDistance: Double, isResumingTrip: Bool = false) {
        self.targetDestination = destination
        self.alertDistance = alertDistance
        proximity = ProximityEvaluator(alertDistance: alertDistance, isResumingTrip: isResumingTrip)
        isAlreadyInsideAlertDistance = false
        distanceToDestination = nil
        lastPreciseFixDate = nil
        beginUpdatesIfAuthorized()
    }

    private func beginUpdatesIfAuthorized() {
        guard isAuthorized else {
            requestAuthorization()
            return
        }

        isTracking = true
        if backgroundActivity == nil {
            backgroundActivity = CLBackgroundActivitySession()
        }
        apply(.near)
        manager.startUpdatingLocation()

        if let location = currentLocation, LocationFixFilter.proximity.accepts(location) {
            updateDistance(from: location)
        }
    }

    func stopTracking() {
        isTracking = false
        manager.stopUpdatingLocation()
        backgroundActivity?.invalidate()
        backgroundActivity = nil
        targetDestination = nil
        alertDistance = nil
        distanceToDestination = nil
        lastPreciseFixDate = nil
        isAlreadyInsideAlertDistance = false
        proximity = nil
        apply(.near)
    }

    private var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    var isAccessDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coarse = LocationFixFilter.coarse.bestFix(in: locations) {
            currentLocation = coarse
        }
        if let precise = LocationFixFilter.proximity.bestFix(in: locations) {
            errorMessage = nil
            updateDistance(from: precise)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAccessDenied {
            if isTracking {
                isTracking = false
                manager.stopUpdatingLocation()
            }
            errorMessage = "Location access is off. Turn it on in Settings > Privacy & Security > Location Services > Orio."
            return
        }
        errorMessage = nil
        if isAuthorized, targetDestination != nil, !isTracking {
            beginUpdatesIfAuthorized()
        } else if isAuthorized {
            refreshCurrentLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // locationUnknown is transient; Core Location keeps trying.
        if (error as? CLError)?.code == .locationUnknown { return }
        if isAccessDenied { return }
        errorMessage = error.localizedDescription
    }

    // MARK: - Helper Methods

    private func updateDistance(from location: CLLocation) {
        guard let target = targetDestination, let threshold = alertDistance else { return }
        let destLoc = CLLocation(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude)
        let dist = location.distance(from: destLoc)
        distanceToDestination = dist
        lastPreciseFixDate = location.timestamp

        apply(.forRemaining(dist, alertDistance: threshold))

        guard var evaluator = proximity else { return }
        let fire = evaluator.shouldTrigger(atDistance: dist)
        proximity = evaluator
        isAlreadyInsideAlertDistance = evaluator.isAlreadyInside
        if fire {
            onProximityReached?()
        }
    }

    private func apply(_ newPrecision: TrackingPrecision) {
        guard newPrecision != precision else { return }
        precision = newPrecision
        manager.desiredAccuracy = newPrecision.desiredAccuracy
        manager.distanceFilter = newPrecision.distanceFilter
    }
}
