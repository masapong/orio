import XCTest
import CoreLocation
@testable import Orio

final class ProximityEvaluatorTests: XCTestCase {
    func testFiresAfterTwoConsecutiveFixesInsideRadius() {
        var evaluator = ProximityEvaluator(alertDistance: 800)
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 5000))
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 790))
        XCTAssertTrue(evaluator.shouldTrigger(atDistance: 700))
        XCTAssertTrue(evaluator.hasFired)
    }

    func testFiresExactlyAtAlertDistance() {
        var evaluator = ProximityEvaluator(alertDistance: 800, requiredConsecutiveFixes: 1)
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 800.1))
        XCTAssertTrue(evaluator.shouldTrigger(atDistance: 800))
    }

    func testSingleInsideFixFollowedByOutsideFixDoesNotFire() {
        var evaluator = ProximityEvaluator(alertDistance: 800)
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 2000))
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 750))
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 900))
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 780))
        XCTAssertTrue(evaluator.shouldTrigger(atDistance: 760))
    }

    func testFiresOnlyOnce() {
        var evaluator = ProximityEvaluator(alertDistance: 500, requiredConsecutiveFixes: 1)
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 1000))
        XCTAssertTrue(evaluator.shouldTrigger(atDistance: 400))
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 300))
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 1000))
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 200))
    }

    func testTripStartingInsideRadiusDoesNotFireUntilUserHasLeft() {
        var evaluator = ProximityEvaluator(alertDistance: 2000)
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 1500))
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 1400))
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 1300))
        XCTAssertTrue(evaluator.isAlreadyInside)

        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 2500))
        XCTAssertFalse(evaluator.isAlreadyInside)
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 1900))
        XCTAssertTrue(evaluator.shouldTrigger(atDistance: 1800))
    }

    func testResumedTripInsideRadiusFiresWithoutLeavingFirst() {
        var evaluator = ProximityEvaluator(alertDistance: 800, isResumingTrip: true)
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 600))
        XCTAssertTrue(evaluator.shouldTrigger(atDistance: 550))
        XCTAssertFalse(evaluator.isAlreadyInside)
    }

    func testRequiredFixesIsAtLeastOne() {
        var evaluator = ProximityEvaluator(alertDistance: 800, requiredConsecutiveFixes: 0)
        XCTAssertFalse(evaluator.shouldTrigger(atDistance: 900))
        XCTAssertTrue(evaluator.shouldTrigger(atDistance: 100))
    }
}

final class TrackingPrecisionTests: XCTestCase {
    func testUsesCoarsePrecisionWhenFarFromAlertRadius() {
        XCTAssertEqual(TrackingPrecision.forRemaining(10_000, alertDistance: 800), .far)
    }

    func testUsesBestPrecisionWhenCloseOrUnknown() {
        XCTAssertEqual(TrackingPrecision.forRemaining(800 + TrackingPrecision.nearMargin, alertDistance: 800), .near)
        XCTAssertEqual(TrackingPrecision.forRemaining(1000, alertDistance: 800), .near)
        XCTAssertEqual(TrackingPrecision.forRemaining(nil, alertDistance: 800), .near)
    }
}

final class DistanceFormatterTests: XCTestCase {
    func testFormatsMetersAndKilometers() {
        XCTAssertEqual(500.0.formattedDistance, "500 m")
        XCTAssertEqual(999.4.formattedDistance, "999 m")
        XCTAssertEqual(1000.0.formattedDistance, "1 km")
        XCTAssertEqual(1500.0.formattedDistance, "1.5 km")
        XCTAssertEqual(2000.0.formattedDistance, "2 km")
        XCTAssertEqual((-5.0).formattedDistance, "0 m")
    }

    func testPresetLabels() {
        XCTAssertEqual(NapSession.presetAlertDistances.map(\.formattedDistance), ["500 m", "800 m", "1 km", "1.5 km", "2 km"])
    }
}
