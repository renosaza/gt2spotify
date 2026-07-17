import XCTest
@testable import GT2Spotify

final class SpotifyAPIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testPlaybackDecoding() async throws {
        let context = try await makeContext()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/me/player")
            return response(
                request,
                status: 200,
                body: #"{"is_playing":true,"device":{"id":"iphone","is_active":true,"is_private_session":false,"is_restricted":false,"name":"iPhone","type":"Smartphone","volume_percent":42,"supports_volume":false},"item":{"name":"Track","artists":[{"name":"Artist"}]}}"#
            )
        }

        let snapshot = try await context.api.currentPlayback()
        XCTAssertEqual(snapshot?.track, "Track")
        XCTAssertEqual(snapshot?.artist, "Artist")
        XCTAssertEqual(snapshot?.volumePercent, 42)
        XCTAssertEqual(snapshot?.supportsVolume, false)
        XCTAssertEqual(snapshot?.deviceID, "iphone")
        XCTAssertEqual(snapshot?.isPlaying, true)
    }

    func testDevicesDecodeVolumeCapability() async throws {
        let context = try await makeContext()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/me/player/devices")
            return response(
                request,
                status: 200,
                body: #"{"devices":[{"id":"mac","is_active":true,"is_private_session":false,"is_restricted":false,"name":"MacBook","type":"Computer","volume_percent":68,"supports_volume":true},{"id":"iphone","is_active":false,"is_private_session":false,"is_restricted":false,"name":"iPhone","type":"Smartphone","volume_percent":null,"supports_volume":false}]}"#
            )
        }

        let devices = try await context.api.devices()
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].supportsVolume, true)
        XCTAssertEqual(devices[1].supportsVolume, false)
    }

    func testEmptyPlaybackReturnsNil() async throws {
        let context = try await makeContext()
        MockURLProtocol.requestHandler = { request in response(request, status: 204) }
        let snapshot = try await context.api.currentPlayback()
        XCTAssertNil(snapshot)
    }

    func test401RefreshesAndRetriesExactlyOnce() async throws {
        let context = try await makeContext()
        var playerCalls = 0
        var refreshCalls = 0

        MockURLProtocol.requestHandler = { request in
            if request.url?.host == "accounts.test" {
                refreshCalls += 1
                XCTAssertEqual(request.httpMethod, "POST")
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                XCTAssertTrue(body.contains("grant_type=refresh_token"))
                return response(request, status: 200, body: #"{"access_token":"new-access","token_type":"Bearer","expires_in":3600,"scope":"user-read-playback-state user-modify-playback-state"}"#)
            }

            playerCalls += 1
            if playerCalls == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
                return response(request, status: 401)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
            return response(request, status: 204)
        }

        try await context.api.play()
        XCTAssertEqual(playerCalls, 2)
        XCTAssertEqual(refreshCalls, 1)
        let stored = try await context.store.loadTokenSet()
        XCTAssertEqual(stored?.refreshToken, "refresh-token")
        XCTAssertEqual(stored?.accessToken, "new-access")
    }

    func test404MapsToNoActiveDevice() async throws {
        let context = try await makeContext()
        MockURLProtocol.requestHandler = { request in response(request, status: 404) }
        do {
            try await context.api.next()
            XCTFail("Expected noActiveDevice")
        } catch let error as SpotifyError {
            XCTAssertEqual(error, .noActiveDevice)
        }
    }

    func test403MapsToForbidden() async throws {
        let context = try await makeContext()
        MockURLProtocol.requestHandler = { request in response(request, status: 403) }
        do {
            try await context.api.pause()
            XCTFail("Expected forbidden")
        } catch let error as SpotifyError {
            XCTAssertEqual(error, .forbidden)
        }
    }

    func test429CarriesRetryAfter() async throws {
        let context = try await makeContext()
        MockURLProtocol.requestHandler = { request in
            response(request, status: 429, headers: ["Retry-After": "7"])
        }
        do {
            try await context.api.previous()
            XCTFail("Expected rateLimited")
        } catch let error as SpotifyError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 7))
        }
    }

    func testVolumeIsClamped() async throws {
        let context = try await makeContext()
        MockURLProtocol.requestHandler = { request in
            let query = Dictionary(
                uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                    .compactMap { item in item.value.map { (item.name, $0) } }
            )
            XCTAssertEqual(query["volume_percent"], "100")
            XCTAssertNil(query["device_id"])
            return response(request, status: 204)
        }
        try await context.api.setVolume(150)
    }

    func testPlayerControllerTargetsSupportedActiveDevice() async throws {
        let context = try await makeContext()
        let controller = SpotifyPlayerController(apiClient: context.api)
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            switch request.url?.path {
            case "/v1/me/player":
                return response(
                    request,
                    status: 200,
                    body: #"{"is_playing":true,"device":{"id":"mac","is_active":true,"is_private_session":false,"is_restricted":false,"name":"MacBook","type":"Computer","volume_percent":40,"supports_volume":true},"item":{"name":"Track","artists":[{"name":"Artist"}]}}"#
                )
            case "/v1/me/player/volume":
                let query = Dictionary(
                    uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                        .compactMap { item in item.value.map { (item.name, $0) } }
                )
                XCTAssertEqual(query["volume_percent"], "55")
                XCTAssertEqual(query["device_id"], "mac")
                return response(request, status: 204)
            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "nil")")
                return response(request, status: 500)
            }
        }

        try await controller.setVolume(55)
        XCTAssertEqual(requestCount, 2)
    }

    func testPlayerControllerRejectsUnsupportedVolumeDevice() async throws {
        let context = try await makeContext()
        let controller = SpotifyPlayerController(apiClient: context.api)
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            XCTAssertEqual(request.url?.path, "/v1/me/player")
            return response(
                request,
                status: 200,
                body: #"{"is_playing":true,"device":{"id":"iphone","is_active":true,"is_private_session":false,"is_restricted":false,"name":"iPhone","type":"Smartphone","volume_percent":42,"supports_volume":false},"item":{"name":"Track","artists":[{"name":"Artist"}]}}"#
            )
        }

        do {
            try await controller.setVolume(55)
            XCTFail("Expected volumeControlUnavailable")
        } catch let error as SpotifyError {
            XCTAssertEqual(error, .volumeControlUnavailable(deviceName: "iPhone"))
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testMalformedPlaybackJSONMapsToDecodingError() async throws {
        let context = try await makeContext()
        MockURLProtocol.requestHandler = { request in response(request, status: 200, body: "not-json") }
        do {
            _ = try await context.api.currentPlayback()
            XCTFail("Expected decoding error")
        } catch let error as SpotifyError {
            guard case .decoding = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeContext() async throws -> (api: SpotifyAPIClient, store: SpotifyTokenStore) {
        let session = MockURLProtocol.session()
        let configuration = testConfiguration()
        let store = SpotifyTokenStore(keychain: InMemoryKeychainStore())
        try await store.saveTokenSet(
            SpotifyTokenSet(
                accessToken: "old-access",
                refreshToken: "refresh-token",
                accessTokenExpiresAt: Date().addingTimeInterval(3_600),
                refreshTokenExpiresAt: Date().addingTimeInterval(86_400),
                scope: "user-read-playback-state user-modify-playback-state"
            )
        )
        let oauth = SpotifyOAuthClient(configuration: configuration, session: session)
        let manager = SpotifyTokenManager(configuration: configuration, tokenStore: store, oauthClient: oauth)
        let api = SpotifyAPIClient(tokenManager: manager, session: session, baseURL: configuration.spotifyAPIBaseURL)
        return (api, store)
    }
}
