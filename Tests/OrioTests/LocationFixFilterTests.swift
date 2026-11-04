import XCTest
import CoreLocation
@testable import Orio

final class LocationFixFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fix(accuracy: CLLocationAccuracy, age: TimeInterval, latitude: Double = 35.68) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 139.76),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: now.addingTimeInterval(-age)
        )
    }

    func testAcceptsRecentPreciseFix() {
        XCTAssertTrue(LocationFixFilter.proximity.accepts(fix(accuracy: 15, age: 2), now: now))
        XCTAssertTrue(LocationFixFilter.proximity.accepts(fix(accuracy: 100, age: 30), now: now))
    }

    func testRejectsImpreciseFix() {
        XCTAssertFalse(LocationFixFilter.proximity.accepts(fix(accuracy: 100.1, age: 1), now: now))
        XCTAssertFalse(LocationFixFilter.proximity.accepts(fix(accuracy: 1500, age: 1), now: now))
    }

    func testRejectsInvalidAccuracy() {
        XCTAssertFalse(LocationFixFilter.proximity.accepts(fix(accuracy: -1, age: 1), now: now))
    }

    func testRejectsStaleFix() {
        XCTAssertFalse(LocationFixFilter.proximity.accepts(fix(accuracy: 10, age: 30.1), now: now))
        XCTAssertFalse(LocationFixFilter.proximity.accepts(fix(accuracy: 10, age: 3600), now: now))
    }

    func testCoarseFilterAcceptsCellFixButNotVeryOldOnes() {
        XCTAssertTrue(LocationFixFilter.coarse.accepts(fix(accuracy: 900, age: 120), now: now))
        XCTAssertFalse(LocationFixFilter.coarse.accepts(fix(accuracy: 1500, age: 10), now: now))
        XCTAssertFalse(LocationFixFilter.coarse.accepts(fix(accuracy: 50, age: 301), now: now))
    }

    func testBestFixPicksNewestAcceptableFix() {
        let older = fix(accuracy: 10, age: 20, latitude: 35.1)
        let newer = fix(accuracy: 20, age: 5, latitude: 35.2)
        let newestButImprecise = fix(accuracy: 2000, age: 1, latitude: 35.3)

        let best = LocationFixFilter.proximity.bestFix(in: [newer, newestButImprecise, older], now: now)
        XCTAssertEqual(best?.coordinate.latitude, 35.2)
    }

    func testBestFixIsNilWhenNothingIsAcceptable() {
        let fixes = [fix(accuracy: 2000, age: 1), fix(accuracy: 10, age: 600)]
        XCTAssertNil(LocationFixFilter.proximity.bestFix(in: fixes, now: now))
    }
}
