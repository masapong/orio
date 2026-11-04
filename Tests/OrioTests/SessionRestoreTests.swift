import XCTest
import CoreLocation
@testable import Orio

@MainActor
final class SessionRestoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "OrioTests.Session.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeSession(startTime: Date = Date()) -> NapSession {
        NapSession(
            destination: DestinationStore.defaultStations[1],
            alertDistance: 1500,
            transportMode: .subway,
            startTime: startTime
        )
    }

    func testSessionStoreRoundTrip() {
        let store = SessionStore(defaults: defaults)
        XCTAssertNil(store.load())

        var session = makeSession(startTime: Date(timeIntervalSince1970: 1_000))
        session.alertTriggeredAt = Date(timeIntervalSince1970: 1_600)
        store.save(session)

        let loaded = store.load()
        XCTAssertEqual(loaded?.id, session.id)
        XCTAssertEqual(loaded?.destination.id, session.destination.id)
        XCTAssertEqual(loaded?.alertDistance, 1500)
        XCTAssertEqual(loaded?.transportMode, .subway)
        XCTAssertEqual(loaded?.startTime, session.startTime)
        XCTAssertEqual(loaded?.alertTriggeredAt, session.alertTriggeredAt)

        store.save(nil)
        XCTAssertNil(store.load())
    }

    func testStartedSessionIsRestoredByANewSessionManager() {
        let session = makeSession()
        let first = SessionManager(alarmRuntime: AlarmRuntimeController(), defaults: defaults)
        XCTAssertNil(first.activeSession)
        XCTAssertFalse(first.isRestoredSession)
        first.startSession(session)
        XCTAssertFalse(first.isRestoredSession)

        let relaunched = SessionManager(alarmRuntime: AlarmRuntimeController(), defaults: defaults)
        XCTAssertEqual(relaunched.activeSession?.id, session.id)
        XCTAssertEqual(relaunched.activeSession?.destination.name, session.destination.name)
        XCTAssertTrue(relaunched.isRestoredSession)
        XCTAssertFalse(relaunched.isAlerting)

        relaunched.endSession()
    }

    func testEndedSessionIsNotRestored() {
        let manager = SessionManager(alarmRuntime: AlarmRuntimeController(), defaults: defaults)
        var ended = false
        manager.onSessionEnded = { ended = true }
        manager.startSession(makeSession())
        manager.endSession()
        XCTAssertTrue(ended)

        let relaunched = SessionManager(alarmRuntime: AlarmRuntimeController(), defaults: defaults)
        XCTAssertNil(relaunched.activeSession)
    }

    func testFiredAlarmIsPersistedAndResumedAfterRelaunch() {
        let manager = SessionManager(alarmRuntime: AlarmRuntimeController(), defaults: defaults)
        manager.startSession(makeSession())
        manager.triggerAlert()
        XCTAssertTrue(manager.isAlerting)
        XCTAssertNotNil(manager.activeSession?.alertTriggeredAt)

        let relaunched = SessionManager(alarmRuntime: AlarmRuntimeController(), defaults: defaults)
        XCTAssertNotNil(relaunched.activeSession?.alertTriggeredAt)
        XCTAssertFalse(relaunched.isAlerting)
        relaunched.resumeRestoredSession()
        XCTAssertTrue(relaunched.isAlerting)

        relaunched.endSession()
        XCTAssertFalse(relaunched.isAlerting)
    }

    func testNapMinutesStopCountingWhenTheAlarmFires() {
        let start = Date(timeIntervalSince1970: 0)
        var session = makeSession(startTime: start)
        XCTAssertEqual(session.napMinutes(endingAt: start.addingTimeInterval(25 * 60)), 25)

        session.alertTriggeredAt = start.addingTimeInterval(18 * 60)
        XCTAssertEqual(session.napMinutes(endingAt: start.addingTimeInterval(40 * 60)), 18)
    }

    func testEndSessionAddsNapMinutesToPersistedTotal() {
        let manager = SessionManager(alarmRuntime: AlarmRuntimeController(), defaults: defaults)
        manager.startSession(makeSession(startTime: Date().addingTimeInterval(-12 * 60)))
        manager.endSession()
        XCTAssertEqual(manager.totalNapMinutes, 12)
        XCTAssertEqual(SessionManager(alarmRuntime: AlarmRuntimeController(), defaults: defaults).totalNapMinutes, 12)
    }
}
