import XCTest
import CoreLocation
@testable import Orio

final class DestinationIdentityTests: XCTestCase {
    private let tokyo = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)

    func testSamePlaceGetsSameID() {
        let a = Destination(name: "Tokyo Station", coordinate: tokyo)
        let b = Destination(name: "Tokyo Station", coordinate: tokyo, address: "Different", useCount: 9)
        XCTAssertEqual(a.id, b.id)
    }

    func testIDIgnoresCaseWhitespaceAndSmallCoordinateDrift() {
        let a = Destination(name: "Tokyo Station", coordinate: tokyo)
        let b = Destination(
            name: "  tokyo   STATION ",
            coordinate: CLLocationCoordinate2D(latitude: 35.68124, longitude: 139.76712)
        )
        XCTAssertEqual(a.id, b.id)
    }

    func testDifferentPlacesGetDifferentIDs() {
        let a = Destination(name: "Tokyo Station", coordinate: tokyo)
        let otherName = Destination(name: "Shinjuku Station", coordinate: tokyo)
        let otherPlace = Destination(name: "Tokyo Station", coordinate: CLLocationCoordinate2D(latitude: 35.6896, longitude: 139.7006))
        XCTAssertNotEqual(a.id, otherName.id)
        XCTAssertNotEqual(a.id, otherPlace.id)
    }

    func testExplicitIDIsKept() {
        let id = UUID()
        XCTAssertEqual(Destination(id: id, name: "X", coordinate: tokyo).id, id)
    }

    func testBuiltInStationIDsAreStableAndUnique() {
        let ids = DestinationStore.defaultStations.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for station in DestinationStore.defaultStations {
            XCTAssertEqual(station.id, Destination.stableID(name: station.name, coordinate: station.coordinate))
        }
    }

    func testCodableRoundTripKeepsID() throws {
        let original = Destination(name: "Tokyo Station", coordinate: tokyo, address: "Marunouchi", useCount: 3)
        let decoded = try JSONDecoder().decode(Destination.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.useCount, 3)
        XCTAssertEqual(decoded.coordinate.latitude, tokyo.latitude)
    }
}

final class DestinationStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OrioTests.DestinationStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func place(_ name: String, _ lat: Double, _ lon: Double) -> Destination {
        Destination(name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    func testFavoritedStationStaysFavoriteAfterRelaunch() {
        let station = DestinationStore.defaultStations[0]
        DestinationStore(defaults: defaults).addFavorite(station)

        let relaunched = DestinationStore(defaults: defaults)
        XCTAssertTrue(relaunched.isFavorite(DestinationStore.defaultStations[0]))
    }

    func testRepeatedSearchResultDoesNotDuplicateRecentOrUsage() {
        let store = DestinationStore(defaults: defaults)
        store.recordUse(place("Shibuya Station", 35.6580, 139.7016))
        store.recordUse(place("Shibuya Station", 35.6580, 139.7016))
        store.recordUse(place("Shibuya Station", 35.6580, 139.7016))

        XCTAssertEqual(store.recent.count, 1)
        XCTAssertEqual(store.usage.count, 1)
        XCTAssertEqual(store.topUsed.first?.useCount, 3)
    }

    func testMostUsedRanksByStoredCount() {
        let store = DestinationStore(defaults: defaults)
        let a = place("A", 35.0, 139.0)
        let b = place("B", 35.1, 139.1)
        store.recordUse(a, at: Date(timeIntervalSince1970: 1))
        store.recordUse(b, at: Date(timeIntervalSince1970: 2))
        store.recordUse(b, at: Date(timeIntervalSince1970: 3))
        // A fresh copy (useCount 0) must still increment the stored count.
        store.recordUse(place("A", 35.0, 139.0), at: Date(timeIntervalSince1970: 4))
        store.recordUse(place("A", 35.0, 139.0), at: Date(timeIntervalSince1970: 5))

        XCTAssertEqual(store.topUsed.map(\.name), ["A", "B"])
        XCTAssertEqual(store.topUsed.map(\.useCount), [3, 2])
        XCTAssertEqual(store.recent.map(\.name), ["A", "B"])
    }

    func testNewPlaceIsCountedEvenWhenTopFiveIsFull() {
        let store = DestinationStore(defaults: defaults)
        for i in 0..<5 {
            let p = place("P\(i)", 35.0 + Double(i) * 0.1, 139.0)
            store.recordUse(p)
            store.recordUse(p)
        }
        let newcomer = place("New", 34.0, 135.0)
        for _ in 0..<3 { store.recordUse(newcomer) }

        XCTAssertEqual(store.topUsed.count, DestinationStore.topUsedLimit)
        XCTAssertEqual(store.topUsed.first?.name, "New")
        XCTAssertEqual(store.topUsed.first?.useCount, 3)
    }

    func testRecentIsCappedAndPersisted() {
        let store = DestinationStore(defaults: defaults)
        for i in 0..<12 {
            store.recordUse(place("P\(i)", 35.0 + Double(i) * 0.01, 139.0))
        }
        XCTAssertEqual(store.recent.count, DestinationStore.recentLimit)
        XCTAssertEqual(store.recent.first?.name, "P11")

        let relaunched = DestinationStore(defaults: defaults)
        XCTAssertEqual(relaunched.recent.map(\.id), store.recent.map(\.id))
        XCTAssertEqual(relaunched.usage.map(\.id), store.usage.map(\.id))
    }

    func testMigratesSchemaOneDataWithRandomIDs() throws {
        let tokyo = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
        let shibuya = CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016)
        let old = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        // Schema 1 stored a fresh random UUID per launch/search for the same place.
        let tokyoA = Destination(id: UUID(), name: "Tokyo Station", coordinate: tokyo, lastUsed: old, useCount: 1)
        let tokyoB = Destination(id: UUID(), name: "Tokyo Station", coordinate: tokyo, lastUsed: newer, useCount: 2)
        let shibuyaA = Destination(id: UUID(), name: "Shibuya Station", coordinate: shibuya, lastUsed: old, useCount: 1)
        let favoriteA = Destination(id: UUID(), name: "Tokyo Station", coordinate: tokyo)
        let favoriteB = Destination(id: UUID(), name: "Tokyo Station", coordinate: tokyo)

        let encoder = JSONEncoder()
        defaults.set(try encoder.encode([favoriteA, favoriteB]), forKey: "favorites")
        // tokyoB appears in both lists as two copies of the same old entry.
        defaults.set(try encoder.encode([tokyoB, shibuyaA, tokyoA]), forKey: "recent")
        defaults.set(try encoder.encode([tokyoB, tokyoA]), forKey: "topUsed")

        let store = DestinationStore(defaults: defaults)
        let tokyoID = Destination.stableID(name: "Tokyo Station", coordinate: tokyo)

        XCTAssertEqual(store.favorites.map(\.id), [tokyoID])
        XCTAssertTrue(store.isFavorite(DestinationStore.defaultStations.first { $0.name == "Tokyo Station" }!))
        XCTAssertEqual(store.recent.map(\.name), ["Tokyo Station", "Shibuya Station"])
        XCTAssertEqual(store.recent.first?.lastUsed, newer)
        XCTAssertEqual(store.topUsed.map(\.name), ["Tokyo Station", "Shibuya Station"])
        XCTAssertEqual(store.topUsed.first?.useCount, 3)
        XCTAssertEqual(store.topUsed.last?.useCount, 1)
        XCTAssertEqual(defaults.integer(forKey: "destinationsSchemaVersion"), DestinationStore.currentSchemaVersion)

        // Migration runs once; further use builds on the merged counts.
        let relaunched = DestinationStore(defaults: defaults)
        relaunched.recordUse(Destination(name: "Tokyo Station", coordinate: tokyo))
        XCTAssertEqual(relaunched.topUsed.first?.useCount, 4)
        XCTAssertEqual(relaunched.recent.count, 2)
    }
}
