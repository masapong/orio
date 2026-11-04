import SwiftUI
import CoreLocation
import MapKit
import UIKit

struct ActiveSessionView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var alarmRuntime: AlarmRuntimeController
    let session: NapSession

    @State private var napTimer: Timer?
    @State private var mapImage: UIImage?
    @State private var mapUpdateTimer: Timer?
    @State private var napMinutes: Int = 0

    private var currentDistance: Double? {
        locationManager.distanceToDestination
    }

    var body: some View {
        ZStack {
            // Map background (subtle)
            if let img = mapImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Dark overlay to make UI readable
            Color.black
                .ignoresSafeArea()
                .opacity(0.65)

            if sessionManager.isAlerting {
                Color.red
                    .ignoresSafeArea()
                    .opacity(0.4)
            }

            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Image(systemName: session.transportMode.icon)
                            .font(.system(size: 32))
                            .foregroundStyle(.cyan)
                        Text("Napping to")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(session.destination.name)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                        if napMinutes > 0 {
                            Text("Napping for \(napMinutes) min")
                                .font(.caption2)
                                .foregroundStyle(.cyan)
                        } else {
                            Text("Just started")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)

                    if let d = currentDistance {
                        VStack(spacing: 2) {
                            Text(d.formattedDistance)
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(d <= session.alertDistance ? .red : .primary)
                            Text("to destination")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        ProgressView("Locating...")
                    }

                    VStack(spacing: 2) {
                        Text("Alert at")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(session.alertDistanceLabel)
                            .font(.headline)
                            .foregroundStyle(.cyan)
                    }

                    if !sessionManager.isAlerting {
                        wristDownAlarmStatus
                    }

                    if sessionManager.isAlerting {
                        Text("WAKE UP")
                            .font(.title3.bold())
                            .foregroundStyle(.red)
                    }

                    #if DEBUG
                    if !sessionManager.isAlerting {
                        Button {
                            sessionManager.triggerAlert()
                        } label: {
                            Label("Demo Alert", systemImage: "bell.badge")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    #endif

                    Button(role: .destructive) {
                        stopSession()
                    } label: {
                        Label(sessionManager.isAlerting ? "Stop Alarm" : "Cancel", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
            }
        }
        .onAppear {
            startNapTimer()
            startMapUpdates()
        }
        .onDisappear {
            napTimer?.invalidate()
            mapUpdateTimer?.invalidate()
        }
    }

    @ViewBuilder
    private var wristDownAlarmStatus: some View {
        if let until = alarmRuntime.armedUntil {
            Label("Wrist-down alarm until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "alarm")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if !alarmRuntime.isArmed {
            Label("Wrist-down alarm off; notifications only", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }

    private func startNapTimer() {
        napMinutes = Int(Date().timeIntervalSince(session.startTime) / 60)
        let timer = Timer(timeInterval: 10, repeats: true) { _ in
            let elapsedMin = Int(Date().timeIntervalSince(session.startTime) / 60)
            if elapsedMin != napMinutes {
                napMinutes = elapsedMin
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        napTimer = timer
    }

    private func stopSession() {
        napTimer?.invalidate()
        mapUpdateTimer?.invalidate()
        locationManager.stopTracking()
        sessionManager.endSession()
    }

    private func startMapUpdates() {
        updateMapImage()
        let timer = Timer(timeInterval: 120, repeats: true) { _ in
            updateMapImage()
        }
        RunLoop.main.add(timer, forMode: .common)
        mapUpdateTimer = timer
    }

    private func updateMapImage() {
        let dest = session.destination.coordinate
        let current = locationManager.currentLocation?.coordinate ?? dest

        let minLat = min(current.latitude, dest.latitude) - 0.01
        let maxLat = max(current.latitude, dest.latitude) + 0.01
        let minLon = min(current.longitude, dest.longitude) - 0.01
        let maxLon = max(current.longitude, dest.longitude) + 0.01

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max(maxLat - minLat, 0.01), 120.0),
            longitudeDelta: min(max(maxLon - minLon, 0.01), 120.0)
        )
        let region = MKCoordinateRegion(center: center, span: span)

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 400, height: 400)
        options.scale = 2.0

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            guard let snapshot = snapshot, error == nil else { return }
            Task { @MainActor in
                mapImage = snapshot.image
            }
        }
    }
}
