import XCTest
@testable import GT2Spotify

final class SpotifyOAuthPKCETests: XCTestCase {
    func testRFC7636S256Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(
            SpotifyPKCE.codeChallenge(for: verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testAuthorizationURLContainsExactPKCEAndScopes() throws {
        let configuration = testConfiguration()
        let client = SpotifyOAuthClient(configuration: configuration)
        let pkce = SpotifyPKCE(state: "state-value", codeVerifier: "verifier", codeChallenge: "challenge")
        let url = try client.authorizationURL(pkce: pkce)
        let values = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["client_id"], "client-id")
        XCTAssertEqual(values["response_type"], "code")
        XCTAssertEqual(values["redirect_uri"], "https://example.test/oauth/callback.html")
        XCTAssertEqual(values["scope"], "user-read-playback-state user-modify-playback-state")
        XCTAssertEqual(values["state"], "state-value")
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["code_challenge"], "challenge")
    }

    func testStateMismatchIsRejected() throws {
        let url = URL(string: "gt2spotify://oauth/callback?code=abc&state=unexpected")!
        let callback = try SpotifyOAuthCallback.parse(url, expectedScheme: "gt2spotify")
        XCTAssertThrowsError(try callback.authorizationCode(expectedState: "expected")) { error in
            XCTAssertEqual(error as? SpotifyError, .stateMismatch)
        }
    }

    func testSuccessfulTokenExchangeUsesPKCEFormBody() async throws {
        let session = MockURLProtocol.session()
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://accounts.test/api/token")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("grant_type=authorization_code"))
            XCTAssertTrue(body.contains("code=auth-code"))
            XCTAssertTrue(body.contains("code_verifier=verifier"))
            XCTAssertTrue(body.contains("client_id=client-id"))
            return response(
                request,
                status: 200,
                body: #"{"access_token":"access","token_type":"Bearer","scope":"user-read-playback-state user-modify-playback-state","expires_in":3600,"refresh_token":"refresh"}"#
            )
        }

        let client = SpotifyOAuthClient(
            configuration: testConfiguration(),
            session: session,
            now: { fixedNow }
        )
        let token = try await client.exchangeCode("auth-code", verifier: "verifier")
        XCTAssertEqual(token.accessToken, "access")
        XCTAssertEqual(token.refreshToken, "refresh")
        XCTAssertEqual(token.accessTokenExpiresAt, fixedNow.addingTimeInterval(3_600))
        XCTAssertNotNil(token.refreshTokenExpiresAt)
    }
}

func testConfiguration(
    tokenURL: URL = URL(string: "https://accounts.test/api/token")!,
    apiBaseURL: URL = URL(string: "https://api.test/v1")!
) -> AppConfiguration {
    AppConfiguration(
        spotifyClientID: "client-id",
        spotifyRedirectURI: URL(string: "https://example.test/oauth/callback.html")!,
        appURLScheme: "gt2spotify",
        spotifyAuthorizationURL: URL(string: "https://accounts.test/authorize")!,
        spotifyTokenURL: tokenURL,
        spotifyAPIBaseURL: apiBaseURL,
        spotifyScopes: ["user-read-playback-state", "user-modify-playback-state"],
        keychainService: "tests"
    )
}
