import Foundation
import CoreLocation

/// Rejects location fixes that are too imprecise or too old to act on. Cached fixes and the
/// 1–3 km cell/Wi-Fi fixes common on trains and in tunnels would otherwise fire the alarm
/// early or show a misleading distance.
struct LocationFixFilter {
    var maxHorizontalAccuracy: CLLocationAccuracy
    var maxAge: TimeInterval

    /// Precise enough to decide whether the user is within the smallest (500 m) alert distance.
    static let proximity = LocationFixFilter(maxHorizontalAccuracy: 100, maxAge: 30)
    /// Good enough to rank nearby stations and centre maps.
    static let coarse = LocationFixFilter(maxHorizontalAccuracy: 1000, maxAge: 300)

    func accepts(_ location: CLLocation, now: Date = Date()) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maxHorizontalAccuracy
            && now.timeIntervalSince(location.timestamp) <= maxAge
    }

    /// The newest acceptable fix in a batch delivered by Core Location.
    func bestFix(in locations: [CLLocation], now: Date = Date()) -> CLLocation? {
        locations
            .filter { accepts($0, now: now) }
            .max { $0.timestamp < $1.timestamp }
    }
}
