import Foundation
import CoreLocation
import CryptoKit

struct Destination: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var coordinate: CLLocationCoordinate2D
    var address: String?
    var lastUsed: Date
    var useCount: Int

    /// Omitting `id` derives it from the name and coordinate, so the same place gets the same
    /// identity across launches and repeated searches.
    init(id: UUID? = nil, name: String, coordinate: CLLocationCoordinate2D, address: String? = nil, lastUsed: Date = Date(), useCount: Int = 0) {
        self.id = id ?? Self.stableID(name: name, coordinate: coordinate)
        self.name = name
        self.coordinate = coordinate
        self.address = address
        self.lastUsed = lastUsed
        self.useCount = useCount
    }

    /// Case- and whitespace-insensitive name plus the coordinate rounded to 3 decimal places
    /// (about 100 m), hashed into a name-based UUID.
    static func stableID(name: String, coordinate: CLLocationCoordinate2D) -> UUID {
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let key = String(format: "%@|%.3f|%.3f", normalizedName, coordinate.latitude, coordinate.longitude)
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// A copy whose `id` is the stable ID for its name and coordinate.
    func withStableID() -> Destination {
        Destination(name: name, coordinate: coordinate, address: address, lastUsed: lastUsed, useCount: useCount)
    }

    static func == (lhs: Destination, rhs: Destination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, address, lastUsed, useCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        lastUsed = try container.decode(Date.self, forKey: .lastUsed)
        useCount = try container.decode(Int.self, forKey: .useCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encode(lastUsed, forKey: .lastUsed)
        try container.encode(useCount, forKey: .useCount)
    }
}
