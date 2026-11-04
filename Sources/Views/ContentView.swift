import SwiftUI

struct ContentView: View {
    @EnvironmentObject var destinationStore: DestinationStore
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var sessionManager: SessionManager

    @State private var selectedDestination: Destination?
    @State private var showSearch = false
    @State private var alertDistance: Double = 800

    var body: some View {
        NavigationStack {
            if let session = sessionManager.activeSession {
                ActiveSessionView(session: session)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        header

                        if locationManager.isAccessDenied {
                            Label("Location is off. Turn it on in Settings to use Orio.", systemImage: "location.slash")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        destinationSection(title: "Nearby", destinations: nearby)

                        destinationSection(title: "Favorites", destinations: destinationStore.favorites)

                        destinationSection(title: "Most Used", destinations: destinationStore.topUsed)

                        destinationSection(title: "Recent", destinations: destinationStore.recent, isRecent: true)

                        Button {
                            showSearch = true
                        } label: {
                            Label("Search Destination", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                    }
                    .padding()
                }
                .navigationTitle("Orio")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showSearch) {
                    LocationSearchView { dest in
                        showSearch = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            selectedDestination = dest
                        }
                    }
                }
                .sheet(item: $selectedDestination) { dest in
                    AlertSettingsView(destination: dest, alertDistance: $alertDistance) { session in
                        sessionManager.startSession(session)
                        destinationStore.recordUse(dest)
                        locationManager.startTracking(destination: dest, alertDistance: alertDistance)
                        selectedDestination = nil
                    }
                }
            }
        }
        .onAppear {
            locationManager.requestAuthorization()
            locationManager.refreshCurrentLocation()
            sessionManager.requestNotificationAuthorization()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 32))
                .foregroundStyle(.cyan)
            Text("Rest easy on transit")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if sessionManager.totalNapMinutes > 0 {
                Text(formatTotalNapTime(sessionManager.totalNapMinutes))
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                    .onLongPressGesture {
                        sessionManager.resetTotalNapTime()
                    }
            }
        }
        .padding(.vertical, 8)
    }

    private func formatTotalNapTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "Total: \(hours)h \(mins)m (hold to reset)"
        }
        return "Total: \(mins)m (hold to reset)"
    }

    private var nearby: [Destination] {
        if let loc = locationManager.currentLocation?.coordinate {
            return destinationStore.nearbyDestinations(current: loc)
        }
        return []
    }

    private func destinationSection(title: String, destinations: [Destination], isRecent: Bool = false) -> some View {
        Group {
            if !destinations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    ForEach(destinations) { dest in
                        DestinationRow(
                            destination: dest,
                            onDelete: isRecent ? { destinationStore.deleteRecent(dest) } : nil
                        ) {
                            selectedDestination = dest
                        }
                    }
                }
            }
        }
    }
}

struct DestinationRow: View {
    @EnvironmentObject var destinationStore: DestinationStore
    let destination: Destination
    var onDelete: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let addr = destination.address {
                        Text(addr)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                destinationStore.toggleFavorite(destination)
            } label: {
                Image(systemName: destinationStore.isFavorite(destination) ? "star.fill" : "star")
                    .font(.footnote)
                    .foregroundStyle(destinationStore.isFavorite(destination) ? .yellow : .secondary)
                    .padding(.leading, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(destinationStore.isFavorite(destination) ? "Remove from favorites" : "Add to favorites")
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button {
                destinationStore.toggleFavorite(destination)
            } label: {
                Label(
                    destinationStore.isFavorite(destination) ? "Unfavorite" : "Favorite",
                    systemImage: destinationStore.isFavorite(destination) ? "star.slash" : "star"
                )
            }
            if let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}
