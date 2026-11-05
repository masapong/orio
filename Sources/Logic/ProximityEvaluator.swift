import Foundation
import CoreLocation

/// Decides when the arrival alarm should fire from a stream of (already filtered) distances.
struct ProximityEvaluator {
    let alertDistance: CLLocationDistance
    let requiredConsecutiveFixes: Int

    private(set) var hasFired = false
    /// The trip started inside the alert radius. The alarm stays quiet until the user has been
    /// outside it, instead of going off the moment the trip starts.
    private(set) var isAlreadyInside = false
    private var hasBeenOutside = false
    private var consecutiveInsideFixes = 0

    /// Pass `isResumingTrip` for a trip restored after a relaunch: the user may have crossed
    /// into the radius while the app was not running, so the already-inside guard must not apply.
    init(alertDistance: CLLocationDistance, requiredConsecutiveFixes: Int = 2, isResumingTrip: Bool = false) {
        self.alertDistance = alertDistance
        self.requiredConsecutiveFixes = max(1, requiredConsecutiveFixes)
        self.hasBeenOutside = isResumingTrip
    }

    /// Returns true exactly once: when the alarm should fire.
    mutating func shouldTrigger(atDistance distance: CLLocationDistance) -> Bool {
        guard !hasFired else { return false }

        guard distance <= alertDistance else {
            hasBeenOutside = true
            isAlreadyInside = false
            consecutiveInsideFixes = 0
            return false
        }

        guard hasBeenOutside else {
            isAlreadyInside = true
            return false
        }

        consecutiveInsideFixes += 1
        if consecutiveInsideFixes >= requiredConsecutiveFixes {
            hasFired = true
            return true
        }
        return false
    }
}

/// Location precision for the remaining distance: GPS at full accuracy for a whole ride is a
/// heavy drain on a watch battery, so stay coarser until the stop is getting close.
struct TrackingPrecision: Equatable {
    let desiredAccuracy: CLLocationAccuracy
    let distanceFilter: CLLocationDistance

    static let far = TrackingPrecision(desiredAccuracy: kCLLocationAccuracyNearestTenMeters, distanceFilter: 50)
    static let near = TrackingPrecision(desiredAccuracy: kCLLocationAccuracyBest, distanceFilter: 10)

    static let nearMargin: CLLocationDistance = 3000

    static func forRemaining(_ distance: CLLocationDistance?, alertDistance: CLLocationDistance) -> TrackingPrecision {
        guard let distance else { return .near }
        return distance > alertDistance + nearMargin ? .far : .near
    }
}
