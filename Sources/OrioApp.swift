import SwiftUI

@main
struct OrioApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var destinationStore: DestinationStore
    @StateObject private var locationManager: LocationManager
    @StateObject private var alarmRuntime: AlarmRuntimeController
    @StateObject private var sessionManager: SessionManager

    // Wiring and session restore live in init rather than onAppear because watchOS can
    // relaunch the app in the background (for location events) without showing any UI.
    init() {
        let destinationStore = DestinationStore()
        let locationManager = LocationManager()
        let alarmRuntime = AlarmRuntimeController()
        let sessionManager = SessionManager(alarmRuntime: alarmRuntime)

        locationManager.onProximityReached = { [weak sessionManager] in
            sessionManager?.triggerAlert()
        }
        sessionManager.onSessionEnded = { [weak locationManager] in
            locationManager?.stopTracking()
        }
        if let session = sessionManager.activeSession {
            locationManager.startTracking(destination: session.destination, alertDistance: session.alertDistance)
            sessionManager.resumeRestoredSession()
        }

        _destinationStore = StateObject(wrappedValue: destinationStore)
        _locationManager = StateObject(wrappedValue: locationManager)
        _alarmRuntime = StateObject(wrappedValue: alarmRuntime)
        _sessionManager = StateObject(wrappedValue: sessionManager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(destinationStore)
                .environmentObject(locationManager)
                .environmentObject(sessionManager)
                .environmentObject(alarmRuntime)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                sessionManager.appDidBecomeActive()
            }
        }
    }
}
