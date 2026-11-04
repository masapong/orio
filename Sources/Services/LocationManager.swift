import Foundation
import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    @Published var distanceToDestination: Double?
    @Published var errorMessage: String?

    private(set) var targetDestination: Destination?
    private(set) var alertDistance: Double?

    var onProximityReached: (() -> Void)?

    private var hasFiredProximity = false
    private var backgroundActivity: CLBackgroundActivitySession?

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.allowsBackgroundLocationUpdates = true
        #if !os(watchOS)
        manager.pausesLocationUpdatesAutomatically = false
        #endif
        manager.activityType = .otherNavigation
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking(destination: Destination, alertDistance: Double) {
        self.targetDestination = destination
        self.alertDistance = alertDistance

        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            requestAuthorization()
            return
        }

        isTracking = true
        if backgroundActivity == nil {
            backgroundActivity = CLBackgroundActivitySession()
        }
        manager.startUpdatingLocation()

        // If we already have a recent location, immediately compute distance
        if let location = currentLocation {
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
        hasFiredProximity = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        updateDistance(from: location)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            errorMessage = "Location access denied. Enable in Settings."
        } else if (authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse),
                  let target = targetDestination, let threshold = alertDistance, !isTracking {
            startTracking(destination: target, alertDistance: threshold)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }

    // MARK: - Helper Methods

    private func updateDistance(from location: CLLocation) {
        guard let target = targetDestination else { return }
        let destLoc = CLLocation(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude)
        let dist = location.distance(from: destLoc)
        distanceToDestination = dist

        if let threshold = alertDistance, dist <= threshold, !hasFiredProximity {
            hasFiredProximity = true
            onProximityReached?()
        }
    }

    func distance(to destination: Destination) -> Double? {
        guard let current = currentLocation else { return nil }
        let destLoc = CLLocation(latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude)
        return current.distance(from: destLoc)
    }
}
