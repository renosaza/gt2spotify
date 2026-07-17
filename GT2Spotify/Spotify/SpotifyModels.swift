import Foundation

struct SpotifyTokenSet: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date
    let refreshTokenExpiresAt: Date?
    let scope: String

    func hasValidAccessToken(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        accessTokenExpiresAt.timeIntervalSince(now) > leeway
    }

    func hasValidRefreshToken(now: Date = Date()) -> Bool {
        guard let refreshTokenExpiresAt else { return true }
        return refreshTokenExpiresAt > now
    }
}

struct PendingSpotifyAuthorization: Codable, Equatable, Sendable {
    let state: String
    let codeVerifier: String
    let createdAt: Date
}

struct PlaybackSnapshot: Equatable, Sendable {
    let track: String
    let artist: String
    let isPlaying: Bool
    let volumePercent: Int?
    let supportsVolume: Bool
    let deviceID: String?
    let deviceName: String?
    let timestamp: Date
}

struct SpotifyDevice: Codable, Equatable, Sendable, Identifiable {
    let id: String?
    let isActive: Bool
    let isPrivateSession: Bool
    let isRestricted: Bool
    let name: String
    let type: String
    let volumePercent: Int?
    let supportsVolume: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case isActive = "is_active"
        case isPrivateSession = "is_private_session"
        case isRestricted = "is_restricted"
        case name
        case type
        case volumePercent = "volume_percent"
        case supportsVolume = "supports_volume"
    }
}

struct SpotifyDevicesResponse: Codable, Sendable {
    let devices: [SpotifyDevice]
}

struct SpotifyPlaybackResponse: Codable, Sendable {
    let isPlaying: Bool
    let device: SpotifyDevice
    let item: SpotifyPlayableItem?

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case device
        case item
    }

    func snapshot(now: Date = Date()) -> PlaybackSnapshot {
        PlaybackSnapshot(
            track: item?.name ?? "Unknown track",
            artist: item?.displayArtist ?? "Unknown artist",
            isPlaying: isPlaying,
            volumePercent: device.volumePercent,
            supportsVolume: device.supportsVolume,
            deviceID: device.id,
            deviceName: device.name,
            timestamp: now
        )
    }
}

struct SpotifyPlayableItem: Codable, Sendable {
    let name: String
    let artists: [SpotifyArtist]?
    let show: SpotifyShow?

    var displayArtist: String {
        if let artists, !artists.isEmpty {
            return artists.map(\.name).joined(separator: ", ")
        }
        return show?.publisher ?? "Unknown artist"
    }
}

struct SpotifyArtist: Codable, Sendable {
    let name: String
}

struct SpotifyShow: Codable, Sendable {
    let publisher: String?
}

struct SpotifyTokenResponse: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

struct SpotifyOAuthErrorResponse: Codable, Sendable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum SpotifyError: Error, LocalizedError, Equatable, Sendable {
    case notConfigured
    case authorizationCancelled
    case authorizationRequired
    case invalidCallback
    case stateMismatch
    case oauthError(String)
    case tokenExchangeFailed(status: Int, message: String?)
    case forbidden
    case noActiveDevice
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int)
    case invalidResponse
    case decoding(String)
    case network(String)
    case volumeUnavailable
    case volumeControlUnavailable(deviceName: String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Spotify Client ID is not configured. Copy Config.example.xcconfig to Config.xcconfig."
        case .authorizationCancelled:
            return "Spotify authorization was cancelled."
        case .authorizationRequired:
            return "Spotify authorization is required."
        case .invalidCallback:
            return "The Spotify callback was invalid."
        case .stateMismatch:
            return "OAuth state did not match; authorization was rejected."
        case .oauthError(let value):
            return "Spotify authorization failed: \(value)."
        case .tokenExchangeFailed(let status, let message):
            return "Spotify token request failed (HTTP \(status))\(message.map { ": \($0)" } ?? "")."
        case .forbidden:
            return "Spotify rejected playback control. Check Premium, scopes, and playback restrictions."
        case .noActiveDevice:
            return "No active Spotify device. Open Spotify and start playback first."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Spotify rate limit reached. Retry after about \(Int(retryAfter)) seconds."
            }
            return "Spotify rate limit reached."
        case .http(let status):
            return "Spotify request failed with HTTP \(status)."
        case .invalidResponse:
            return "Spotify returned an invalid HTTP response."
        case .decoding(let message):
            return "Spotify response could not be decoded: \(message)."
        case .network(let message):
            return "Network request failed: \(message)."
        case .volumeUnavailable:
            return "The active Spotify device did not report a volume."
        case .volumeControlUnavailable(let deviceName):
            let name = deviceName ?? "The active Spotify device"
            return "\(name) does not support Spotify Web API volume control. Use the system volume slider instead."
        }
    }
}
