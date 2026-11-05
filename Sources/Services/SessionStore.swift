import Foundation

/// Persists the in-progress trip so it survives the app being terminated by watchOS.
struct SessionStore {
    private let defaults: UserDefaults
    private let key = "activeSession"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> NapSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NapSession.self, from: data)
    }

    func save(_ session: NapSession?) {
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
