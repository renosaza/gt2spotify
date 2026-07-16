import AuthenticationServices
import CryptoKit
import Foundation
import OSLog
import Security
import UIKit

struct SpotifyPKCE: Equatable, Sendable {
    let state: String
    let codeVerifier: String
    let codeChallenge: String

    static func generate() throws -> SpotifyPKCE {
        let verifier = try randomURLSafeString(byteCount: 64)
        let state = try randomURLSafeString(byteCount: 32)
        return SpotifyPKCE(
            state: state,
            codeVerifier: verifier,
            codeChallenge: codeChallenge(for: verifier)
        )
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct SpotifyOAuthCallback: Equatable, Sendable {
    let code: String?
    let state: String
    let error: String?

    static func parse(_ url: URL, expectedScheme: String) throws -> SpotifyOAuthCallback {
        guard url.scheme == expectedScheme,
              url.host == "oauth",
              url.path == "/callback",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SpotifyError.invalidCallback
        }

        var values: [String: String] = [:]
        for item in components.queryItems ?? [] where values[item.name] == nil {
            values[item.name] = item.value ?? ""
        }
        guard let state = values["state"], !state.isEmpty else {
            throw SpotifyError.invalidCallback
        }
        let code = values["code"].flatMap { $0.isEmpty ? nil : $0 }
        let error = values["error"].flatMap { $0.isEmpty ? nil : $0 }
        guard code != nil || error != nil else {
            throw SpotifyError.invalidCallback
        }
        return SpotifyOAuthCallback(code: code, state: state, error: error)
    }

    func authorizationCode(expectedState: String) throws -> String {
        guard state == expectedState else { throw SpotifyError.stateMismatch }
        if let error { throw SpotifyError.oauthError(error) }
        guard let code else { throw SpotifyError.invalidCallback }
        return code
    }
}

actor SpotifyOAuthClient {
    private nonisolated let configuration: AppConfiguration
    private let session: URLSession
    private let now: @Sendable () -> Date

    init(
        configuration: AppConfiguration,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.session = session
        self.now = now
    }

    nonisolated func authorizationURL(pkce: SpotifyPKCE) throws -> URL {
        guard configuration.isSpotifyConfigured else { throw SpotifyError.notConfigured }
        var components = URLComponents(url: configuration.spotifyAuthorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.spotifyClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.spotifyRedirectURI.absoluteString),
            URLQueryItem(name: "scope", value: configuration.spotifyScopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge)
        ]
        guard let url = components?.url else { throw SpotifyError.invalidCallback }
        return url
    }

    func exchangeCode(_ code: String, verifier: String) async throws -> SpotifyTokenSet {
        let response = try await tokenRequest(items: [
            URLQueryItem(name: "client_id", value: configuration.spotifyClientID),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: configuration.spotifyRedirectURI.absoluteString),
            URLQueryItem(name: "code_verifier", value: verifier)
        ])

        guard let refreshToken = response.refreshToken else {
            throw SpotifyError.decoding("initial token response omitted refresh_token")
        }
        let issuedAt = now()
        return SpotifyTokenSet(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            accessTokenExpiresAt: issuedAt.addingTimeInterval(TimeInterval(response.expiresIn)),
            refreshTokenExpiresAt: Calendar(identifier: .gregorian).date(byAdding: .month, value: 6, to: issuedAt),
            scope: response.scope ?? configuration.spotifyScopes.joined(separator: " ")
        )
    }

    func refreshToken(_ current: SpotifyTokenSet) async throws -> SpotifyTokenSet {
        let response = try await tokenRequest(items: [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: current.refreshToken),
            URLQueryItem(name: "client_id", value: configuration.spotifyClientID)
        ])
        let issuedAt = now()
        return SpotifyTokenSet(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? current.refreshToken,
            accessTokenExpiresAt: issuedAt.addingTimeInterval(TimeInterval(response.expiresIn)),
            refreshTokenExpiresAt: current.refreshTokenExpiresAt,
            scope: response.scope ?? current.scope
        )
    }

    private func tokenRequest(items: [URLQueryItem]) async throws -> SpotifyTokenResponse {
        guard configuration.isSpotifyConfigured else { throw SpotifyError.notConfigured }
        var request = URLRequest(url: configuration.spotifyTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = items
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let oauthError = try? JSONDecoder().decode(SpotifyOAuthErrorResponse.self, from: data)
                if oauthError?.error == "invalid_grant" {
                    throw SpotifyError.authorizationRequired
                }
                throw SpotifyError.tokenExchangeFailed(
                    status: http.statusCode,
                    message: oauthError?.errorDescription ?? oauthError?.error
                )
            }
            do {
                return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            } catch {
                throw SpotifyError.decoding(error.localizedDescription)
            }
        } catch let error as SpotifyError {
            throw error
        } catch {
            throw SpotifyError.network(error.localizedDescription)
        }
    }
}

actor SpotifyTokenManager {
    private let configuration: AppConfiguration
    private let tokenStore: SpotifyTokenStore
    private let oauthClient: SpotifyOAuthClient

    init(
        configuration: AppConfiguration,
        tokenStore: SpotifyTokenStore,
        oauthClient: SpotifyOAuthClient
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.oauthClient = oauthClient
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard configuration.isSpotifyConfigured else { throw SpotifyError.notConfigured }
        guard let current = try await tokenStore.loadTokenSet() else {
            throw SpotifyError.authorizationRequired
        }
        if !forceRefresh && current.hasValidAccessToken() {
            return current.accessToken
        }
        guard current.hasValidRefreshToken() else {
            try await tokenStore.clearTokenSet()
            throw SpotifyError.authorizationRequired
        }

        do {
            let refreshed = try await oauthClient.refreshToken(current)
            try await tokenStore.saveTokenSet(refreshed)
            return refreshed.accessToken
        } catch SpotifyError.authorizationRequired {
            try await tokenStore.clearTokenSet()
            throw SpotifyError.authorizationRequired
        }
    }
}

@MainActor
final class SpotifyAuthorizationController: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let configuration: AppConfiguration
    private let tokenStore: SpotifyTokenStore
    private let oauthClient: SpotifyOAuthClient
    private var authenticationSession: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<Void, Error>?

    init(
        configuration: AppConfiguration,
        tokenStore: SpotifyTokenStore,
        oauthClient: SpotifyOAuthClient
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.oauthClient = oauthClient
    }

    func authorize() async throws {
        guard continuation == nil else { return }
        guard configuration.isSpotifyConfigured else { throw SpotifyError.notConfigured }

        let pkce = try SpotifyPKCE.generate()
        try await tokenStore.savePendingAuthorization(
            PendingSpotifyAuthorization(state: pkce.state, codeVerifier: pkce.codeVerifier, createdAt: Date())
        )
        let url = try oauthClient.authorizationURL(pkce: pkce)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: configuration.appURLScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        self.finish(.failure(SpotifyError.authorizationCancelled))
                        return
                    }
                    if let error {
                        self.finish(.failure(SpotifyError.network(error.localizedDescription)))
                        return
                    }
                    guard let callbackURL else {
                        self.finish(.failure(SpotifyError.invalidCallback))
                        return
                    }
                    await self.processCallback(callbackURL)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authenticationSession = session
            guard session.start() else {
                self.finish(.failure(SpotifyError.invalidCallback))
                return
            }
        }
    }

    func handleExternalCallback(_ url: URL) {
        Task { @MainActor in
            await processCallback(url)
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func processCallback(_ url: URL) async {
        guard let pending = try? await tokenStore.loadPendingAuthorization() else {
            finish(.failure(SpotifyError.invalidCallback))
            return
        }

        do {
            let callback = try SpotifyOAuthCallback.parse(url, expectedScheme: configuration.appURLScheme)
            let code = try callback.authorizationCode(expectedState: pending.state)
            let tokenSet = try await oauthClient.exchangeCode(code, verifier: pending.codeVerifier)
            try await tokenStore.saveTokenSet(tokenSet)
            try await tokenStore.clearPendingAuthorization()
            Logger.auth.info("Spotify authorization completed")
            finish(.success(()))
        } catch {
            try? await tokenStore.clearPendingAuthorization()
            Logger.auth.error("Spotify authorization failed: \(error.localizedDescription, privacy: .public)")
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        authenticationSession?.cancel()
        authenticationSession = nil
        let pending = continuation
        continuation = nil
        switch result {
        case .success:
            pending?.resume()
        case .failure(let error):
            pending?.resume(throwing: error)
        }
    }
}
