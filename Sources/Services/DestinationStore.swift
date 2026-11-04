import Foundation
import CoreLocation

class DestinationStore: ObservableObject {
    @Published var favorites: [Destination] = []
    @Published var recent: [Destination] = []
    /// Every used destination with its use count, most used first.
    @Published private(set) var usage: [Destination] = []

    var topUsed: [Destination] {
        Array(usage.prefix(Self.topUsedLimit))
    }

    static let recentLimit = 10
    static let topUsedLimit = 5
    static let usageLimit = 50
    static let currentSchemaVersion = 2

    private let defaults: UserDefaults
    private let favoritesKey = "favorites"
    private let recentKey = "recent"
    private let usageKey = "topUsed"
    private let schemaVersionKey = "destinationsSchemaVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func addFavorite(_ destination: Destination) {
        if !favorites.contains(where: { $0.id == destination.id }) {
            favorites.append(destination)
            save()
        }
    }

    func removeFavorite(_ destination: Destination) {
        favorites.removeAll { $0.id == destination.id }
        save()
    }

    func recordUse(_ destination: Destination, at date: Date = Date()) {
        let previousCount = usage.first(where: { $0.id == destination.id })?.useCount ?? 0
        var updated = destination
        updated.lastUsed = date
        updated.useCount = previousCount + 1

        recent.removeAll { $0.id == updated.id }
        recent.insert(updated, at: 0)
        recent = Array(recent.prefix(Self.recentLimit))

        usage.removeAll { $0.id == updated.id }
        usage.append(updated)
        usage = Array(Self.sortedByUse(usage).prefix(Self.usageLimit))

        save()
    }

    static let defaultStations: [Destination] = [
        Destination(name: "Tokyo Station", coordinate: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671), address: "Marunouchi, Chiyoda-ku"),
        Destination(name: "Shinjuku Station", coordinate: CLLocationCoordinate2D(latitude: 35.6896, longitude: 139.7006), address: "Shinjuku-ku"),
        Destination(name: "Shibuya Station", coordinate: CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016), address: "Shibuya-ku"),
        Destination(name: "Ikebukuro Station", coordinate: CLLocationCoordinate2D(latitude: 35.7303, longitude: 139.7110), address: "Toshima-ku"),
        Destination(name: "Nishi-Ogikubo Station", coordinate: CLLocationCoordinate2D(latitude: 35.7042, longitude: 139.6004), address: "Suginami-ku"),
        Destination(name: "Kichijoji Station", coordinate: CLLocationCoordinate2D(latitude: 35.7034, longitude: 139.5799), address: "Musashino-shi"),
        Destination(name: "Mitaka Station", coordinate: CLLocationCoordinate2D(latitude: 35.7033, longitude: 139.5608), address: "Mitaka-shi"),
        Destination(name: "Koenji Station", coordinate: CLLocationCoordinate2D(latitude: 35.7058, longitude: 139.6494), address: "Suginami-ku"),
        Destination(name: "Nakano Station", coordinate: CLLocationCoordinate2D(latitude: 35.7075, longitude: 139.6639), address: "Nakano-ku"),
        Destination(name: "Tachikawa Station", coordinate: CLLocationCoordinate2D(latitude: 35.6981, longitude: 139.4132), address: "Tachikawa-shi"),
        Destination(name: "Yokohama Station", coordinate: CLLocationCoordinate2D(latitude: 35.4658, longitude: 139.6224), address: "Nishi-ku, Yokohama"),
        Destination(name: "Kawasaki Station", coordinate: CLLocationCoordinate2D(latitude: 35.5311, longitude: 139.6970), address: "Kawasaki-ku"),
        Destination(name: "Omiya Station", coordinate: CLLocationCoordinate2D(latitude: 35.9061, longitude: 139.6233), address: "Omiya-ku, Saitama"),
        Destination(name: "Ueno Station", coordinate: CLLocationCoordinate2D(latitude: 35.7138, longitude: 139.7773), address: "Taito-ku"),
        Destination(name: "Akihabara Station", coordinate: CLLocationCoordinate2D(latitude: 35.6984, longitude: 139.7731), address: "Chiyoda-ku"),
        Destination(name: "Osaka Station", coordinate: CLLocationCoordinate2D(latitude: 34.7024, longitude: 135.4959), address: "Umeda, Kita-ku"),
        Destination(name: "Kyoto Station", coordinate: CLLocationCoordinate2D(latitude: 34.9858, longitude: 135.7588), address: "Shimogyo-ku, Kyoto"),
        Destination(name: "Nagoya Station", coordinate: CLLocationCoordinate2D(latitude: 35.1709, longitude: 136.8815), address: "Nakamura-ku, Nagoya"),
        Destination(name: "Hiroshima Station", coordinate: CLLocationCoordinate2D(latitude: 34.3979, longitude: 132.4756), address: "Minami-ku, Hiroshima"),
        Destination(name: "Fukuoka Station", coordinate: CLLocationCoordinate2D(latitude: 33.5899, longitude: 130.4206), address: "Hakata-ku, Fukuoka"),
    ]

    func isFavorite(_ destination: Destination) -> Bool {
        favorites.contains(where: { $0.id == destination.id })
    }

    func toggleFavorite(_ destination: Destination) {
        if isFavorite(destination) {
            removeFavorite(destination)
        } else {
            addFavorite(destination)
        }
    }

    func deleteRecent(_ destination: Destination) {
        recent.removeAll { $0.id == destination.id }
        save()
    }

    func clearRecent() {
        recent.removeAll()
        save()
    }

    func nearbyDestinations(current: CLLocationCoordinate2D, limit: Int = 5) -> [Destination] {
        let here = CLLocation(latitude: current.latitude, longitude: current.longitude)
        func distance(_ destination: Destination) -> CLLocationDistance {
            CLLocation(latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude)
                .distance(from: here)
        }
        return Self.defaultStations.sorted { distance($0) < distance($1) }.prefix(limit).map { $0 }
    }

    private static func sortedByUse(_ destinations: [Destination]) -> [Destination] {
        destinations.sorted {
            $0.useCount != $1.useCount ? $0.useCount > $1.useCount : $0.lastUsed > $1.lastUsed
        }
    }

    // MARK: - Persistence

    private func load() {
        favorites = decode(favoritesKey)
        recent = decode(recentKey)
        usage = decode(usageKey)

        if defaults.integer(forKey: schemaVersionKey) < Self.currentSchemaVersion {
            migrateToStableIDs()
            defaults.set(Self.currentSchemaVersion, forKey: schemaVersionKey)
            save()
        }
    }

    /// Schema 1 gave every station and search result a random UUID, so the same place could be
    /// saved several times under different IDs. Re-key everything with stable IDs and merge.
    private func migrateToStableIDs() {
        let oldRecent = recent
        let oldUsage = usage

        favorites = Self.uniqued(favorites.map { $0.withStableID() })

        recent = Self.uniqued(
            oldRecent.map { $0.withStableID() }.sorted { $0.lastUsed > $1.lastUsed }
        )

        // Schema 1 only kept 5 "top used" entries and rarely incremented counts, so also count
        // places that only survive in Recent. Copies of the same old entry share one count;
        // different old entries for the same place add up.
        var countsByOldID: [UUID: Destination] = [:]
        for entry in oldUsage + oldRecent {
            if let existing = countsByOldID[entry.id] {
                var merged = existing
                merged.useCount = max(existing.useCount, entry.useCount, 1)
                merged.lastUsed = max(existing.lastUsed, entry.lastUsed)
                countsByOldID[entry.id] = merged
            } else {
                var first = entry
                first.useCount = max(entry.useCount, 1)
                countsByOldID[entry.id] = first
            }
        }
        var merged: [UUID: Destination] = [:]
        for entry in countsByOldID.values.map({ $0.withStableID() }) {
            if var existing = merged[entry.id] {
                existing.useCount += entry.useCount
                existing.lastUsed = max(existing.lastUsed, entry.lastUsed)
                merged[entry.id] = existing
            } else {
                merged[entry.id] = entry
            }
        }
        usage = Array(Self.sortedByUse(Array(merged.values)).prefix(Self.usageLimit))
        recent = Array(recent.prefix(Self.recentLimit))
    }

    private static func uniqued(_ destinations: [Destination]) -> [Destination] {
        var seen = Set<UUID>()
        return destinations.filter { seen.insert($0.id).inserted }
    }

    private func decode(_ key: String) -> [Destination] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Destination].self, from: data) else { return [] }
        return decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: favoritesKey)
        }
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: recentKey)
        }
        if let data = try? JSONEncoder().encode(usage) {
            defaults.set(data, forKey: usageKey)
        }
    }
}
