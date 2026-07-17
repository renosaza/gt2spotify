import Foundation
import OSLog

actor SpotifyAPIClient {
    private enum Endpoint {
        case playback
        case devices
        case play
        case pause
        case next
        case previous
        case volume(Int, String?)

        var method: String {
            switch self {
            case .play, .pause, .volume: return "PUT"
            case .next, .previous: return "POST"
            case .playback, .devices: return "GET"
            }
        }

        var path: String {
            switch self {
            case .playback: return "/me/player"
            case .devices: return "/me/player/devices"
            case .play: return "/me/player/play"
            case .pause: return "/me/player/pause"
            case .next: return "/me/player/next"
            case .previous: return "/me/player/previous"
            case .volume: return "/me/player/volume"
            }
        }
    }

    private let tokenManager: SpotifyTokenManager
    private let session: URLSession
    private let baseURL: URL

    init(
        tokenManager: SpotifyTokenManager,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.spotify.com/v1")!
    ) {
        self.tokenManager = tokenManager
        self.session = session
        self.baseURL = baseURL
    }

    func currentPlayback() async throws -> PlaybackSnapshot? {
        let data = try await request(.playback)
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(SpotifyPlaybackResponse.self, from: data).snapshot()
        } catch {
            throw SpotifyError.decoding(error.localizedDescription)
        }
    }

    func devices() async throws -> [SpotifyDevice] {
        let data = try await request(.devices)
        do {
            return try JSONDecoder().decode(SpotifyDevicesResponse.self, from: data).devices
        } catch {
            throw SpotifyError.decoding(error.localizedDescription)
        }
    }

    func play() async throws { _ = try await request(.play) }
    func pause() async throws { _ = try await request(.pause) }
    func next() async throws { _ = try await request(.next) }
    func previous() async throws { _ = try await request(.previous) }

    func setVolume(_ percent: Int, deviceID: String? = nil) async throws {
        _ = try await request(.volume(min(max(percent, 0), 100), deviceID))
    }

    private func request(_ endpoint: Endpoint, allowUnauthorizedRetry: Bool = true) async throws -> Data {
        let token = try await tokenManager.accessToken()
        let request = try makeRequest(endpoint: endpoint, token: token)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
            Logger.spotifyAPI.debug("\(endpoint.method, privacy: .public) \(endpoint.path, privacy: .public) -> \(http.statusCode)")

            if http.statusCode == 401, allowUnauthorizedRetry {
                let refreshedToken = try await tokenManager.accessToken(forceRefresh: true)
                let retry = try makeRequest(endpoint: endpoint, token: refreshedToken)
                return try await responseData(for: retry)
            }
            return try validate(data: data, response: http)
        } catch let error as SpotifyError {
            throw error
        } catch {
            throw SpotifyError.network(error.localizedDescription)
        }
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
            return try validate(data: data, response: http)
        } catch let error as SpotifyError {
            throw error
        } catch {
            throw SpotifyError.network(error.localizedDescription)
        }
    }

    private func validate(data: Data, response: HTTPURLResponse) throws -> Data {
        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw SpotifyError.authorizationRequired
        case 403:
            throw SpotifyError.forbidden
        case 404:
            throw SpotifyError.noActiveDevice
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw SpotifyError.rateLimited(retryAfter: retryAfter)
        default:
            throw SpotifyError.http(status: response.statusCode)
        }
    }

    private func makeRequest(endpoint: Endpoint, token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)
        if case .volume(let percent, let deviceID) = endpoint {
            var queryItems = [URLQueryItem(name: "volume_percent", value: String(percent))]
            if let deviceID, !deviceID.isEmpty {
                queryItems.append(URLQueryItem(name: "device_id", value: deviceID))
            }
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw SpotifyError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
