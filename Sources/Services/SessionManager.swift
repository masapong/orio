import Foundation
import WatchKit
import UserNotifications

@MainActor
class SessionManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var activeSession: NapSession?
    @Published var isAlerting = false
    @Published var totalNapMinutes: Int = 0

    var onSessionEnded: (() -> Void)?

    private let totalKey = "totalNapMinutes"
    private let alarmRuntime: AlarmRuntimeController
    private var alarmTimer: Timer?
    private var alarmNotificationIDs: [String] = []

    static let stopAlarmActionIdentifier = "STOP_ALARM_ACTION"
    static let alertCategoryIdentifier = "ARRIVAL_ALERT"

    init(alarmRuntime: AlarmRuntimeController) {
        self.alarmRuntime = alarmRuntime
        super.init()
        totalNapMinutes = UserDefaults.standard.integer(forKey: totalKey)
        setupNotificationCategories()
        UNUserNotificationCenter.current().delegate = self
        alarmRuntime.onSystemAlarmStopped = { [weak self] in
            self?.endSession()
        }
    }

    /// Smart-alarm sessions can only be scheduled while the app is active and expire after
    /// 30 minutes, so every return to the foreground re-arms the wrist-down alarm.
    func appDidBecomeActive() {
        guard activeSession != nil, !isAlerting else { return }
        alarmRuntime.arm()
    }

    private func setupNotificationCategories() {
        let stopAction = UNNotificationAction(
            identifier: Self.stopAlarmActionIdentifier,
            title: "Stop Alarm",
            options: [.foreground, .destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.alertCategoryIdentifier,
            actions: [stopAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    func startSession(_ session: NapSession) {
        activeSession = session
        isAlerting = false
        alarmRuntime.arm()
    }

    func endSession() {
        if let session = activeSession {
            let elapsedMin = Int(Date().timeIntervalSince(session.startTime) / 60)
            if elapsedMin > 0 {
                totalNapMinutes += elapsedMin
                UserDefaults.standard.set(totalNapMinutes, forKey: totalKey)
            }
        }
        stopAlerting()
        alarmRuntime.disarm()
        activeSession = nil
        onSessionEnded?()
    }

    func resetTotalNapTime() {
        totalNapMinutes = 0
        UserDefaults.standard.set(0, forKey: totalKey)
    }

    func triggerAlert() {
        guard !isAlerting else { return }
        isAlerting = true
        startAlarmLoop()
    }

    func stopAlerting() {
        isAlerting = false
        alarmTimer?.invalidate()
        alarmTimer = nil
        removeAlarmNotifications()
    }

    private func startAlarmLoop() {
        alarmRuntime.soundAlarm()
        fireHapticPattern()
        sendImmediateAlarmNotification()
        schedulePersistentNotifications()

        alarmTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fireHapticPattern()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        alarmTimer = timer
    }

    private func fireHapticPattern() {
        WKInterfaceDevice.current().play(.notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func sendImmediateAlarmNotification() {
        let content = UNMutableNotificationContent()
        let destinationName = activeSession?.destination.name ?? "your destination"
        content.title = "WAKE UP NOW"
        content.body = "Approaching \(destinationName)! Time to get off."
        content.sound = .default
        content.categoryIdentifier = Self.alertCategoryIdentifier
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(identifier: "orio.alarm.immediate", content: content, trigger: nil)
        addNotificationRequest(request, description: "immediate alarm")
    }

    private func schedulePersistentNotifications() {
        let destinationName = activeSession?.destination.name ?? "your destination"

        for index in 1...20 {
            let id = "orio.alarm.\(index)"
            alarmNotificationIDs.append(id)

            let content = UNMutableNotificationContent()
            content.title = "WAKE UP NOW"
            content.body = "Approaching \(destinationName)! Time to get off."
            content.sound = .default
            content.categoryIdentifier = Self.alertCategoryIdentifier
            content.interruptionLevel = .timeSensitive

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(index * 10), repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            addNotificationRequest(request, description: "alarm reminder \(index)")
        }
    }

    private func addNotificationRequest(_ request: UNNotificationRequest, description: String) {
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule \(description): \(error)")
            }
        }
    }

    private func removeAlarmNotifications() {
        var idsToRemove = alarmNotificationIDs
        idsToRemove.append("orio.alarm.immediate")
        idsToRemove.append("orio.arrival")

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: idsToRemove)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: idsToRemove)
        alarmNotificationIDs.removeAll()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
        Task { @MainActor in
            if response.actionIdentifier == Self.stopAlarmActionIdentifier {
                self.endSession()
            }
        }
    }
}
