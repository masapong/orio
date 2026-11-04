import SwiftUI

@main
struct OrioApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var destinationStore = DestinationStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var alarmRuntime: AlarmRuntimeController
    @StateObject private var sessionManager: SessionManager

    init() {
        let alarmRuntime = AlarmRuntimeController()
        _alarmRuntime = StateObject(wrappedValue: alarmRuntime)
        _sessionManager = StateObject(wrappedValue: SessionManager(alarmRuntime: alarmRuntime))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(destinationStore)
                .environmentObject(locationManager)
                .environmentObject(sessionManager)
                .environmentObject(alarmRuntime)
                .onAppear {
                    setupCoordination()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                sessionManager.appDidBecomeActive()
            }
        }
    }

    private func setupCoordination() {
        locationManager.onProximityReached = { [weak sessionManager] in
            sessionManager?.triggerAlert()
        }
        sessionManager.onSessionEnded = { [weak locationManager] in
            locationManager?.stopTracking()
        }
    }
}
