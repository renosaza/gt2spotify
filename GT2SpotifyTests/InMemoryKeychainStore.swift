import Foundation
@testable import GT2Spotify

final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func set(_ data: Data, for key: String) throws {
        lock.withLock { values[key] = data }
    }

    func data(for key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func removeValue(for key: String) throws {
        lock.withLock { values.removeValue(forKey: key) }
    }
}
