import Foundation
import WatchKit

/// Wraps a smart-alarm `WKExtendedRuntimeSession`, the only watchOS API that keeps playing
/// alarm haptics (with the system alarm UI) while Orio is not frontmost and the wrist is down.
/// watchOS only lets the app schedule such a session while it is active, and each session
/// runs for at most 30 minutes, so the controller re-arms whenever the app becomes active.
@MainActor
final class AlarmRuntimeController: NSObject, ObservableObject {
    @Published private(set) var armedUntil: Date?
    @Published private(set) var isArmed = false

    /// Called when the user stops the alarm from the system alarm UI.
    var onSystemAlarmStopped: (() -> Void)?

    private var session: WKExtendedRuntimeSession?
    private var isNotifying = false

    func arm() {
        if let session, session.state == .scheduled || session.state == .running { return }
        guard WKApplication.shared().applicationState == .active else { return }

        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start(at: Date().addingTimeInterval(1))
        self.session = session
        isArmed = true
    }

    /// Starts the repeating system alarm. Returns false when no smart-alarm session is
    /// running (expired, or never armed), in which case only notifications can wake the user.
    @discardableResult
    func soundAlarm() -> Bool {
        guard let session, session.state == .running else { return false }
        isNotifying = true
        session.notifyUser(hapticType: .notification) { hapticType in
            hapticType.pointee = .notification
            return 2
        }
        return true
    }

    func disarm() {
        let current = session
        session = nil
        isNotifying = false
        isArmed = false
        armedUntil = nil
        current?.invalidate()
    }

    private func sessionDidInvalidate(_ id: ObjectIdentifier, reason: WKExtendedRuntimeSessionInvalidationReason) {
        guard let session, ObjectIdentifier(session) == id else { return }
        let wasNotifying = isNotifying
        self.session = nil
        isNotifying = false
        isArmed = false
        armedUntil = nil
        if wasNotifying && reason == .none {
            onSystemAlarmStopped?()
        }
    }

    private func sessionDidStart(_ id: ObjectIdentifier, expiration: Date?) {
        guard let session, ObjectIdentifier(session) == id else { return }
        armedUntil = expiration
    }
}

extension AlarmRuntimeController: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        let id = ObjectIdentifier(extendedRuntimeSession)
        let expiration = extendedRuntimeSession.expirationDate
        Task { @MainActor in
            self.sessionDidStart(id, expiration: expiration)
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        if let error {
            print("Smart alarm session invalidated: \(error.localizedDescription)")
        }
        let id = ObjectIdentifier(extendedRuntimeSession)
        Task { @MainActor in
            self.sessionDidInvalidate(id, reason: reason)
        }
    }
}
