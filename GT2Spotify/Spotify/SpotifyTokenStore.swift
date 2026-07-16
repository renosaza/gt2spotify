import Foundation

actor SpotifyTokenStore {
    private enum Key {
        static let tokenSet = "spotify.token-set"
        static let pendingAuthorization = "spotify.pending-authorization"
    }

    private let keychain: any KeychainStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(keychain: any KeychainStoring) {
        self.keychain = keychain
    }

    func loadTokenSet() throws -> SpotifyTokenSet? {
        guard let data = try keychain.data(for: Key.tokenSet) else { return nil }
        return try decoder.decode(SpotifyTokenSet.self, from: data)
    }

    func saveTokenSet(_ tokenSet: SpotifyTokenSet) throws {
        try keychain.set(encoder.encode(tokenSet), for: Key.tokenSet)
    }

    func clearTokenSet() throws {
        try keychain.removeValue(for: Key.tokenSet)
    }

    func loadPendingAuthorization() throws -> PendingSpotifyAuthorization? {
        guard let data = try keychain.data(for: Key.pendingAuthorization) else { return nil }
        return try decoder.decode(PendingSpotifyAuthorization.self, from: data)
    }

    func savePendingAuthorization(_ pending: PendingSpotifyAuthorization) throws {
        try keychain.set(encoder.encode(pending), for: Key.pendingAuthorization)
    }

    func clearPendingAuthorization() throws {
        try keychain.removeValue(for: Key.pendingAuthorization)
    }
}
