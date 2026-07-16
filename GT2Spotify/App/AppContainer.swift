import Foundation
import Combine

@MainActor
final class AppContainer: ObservableObject {
    let dashboardViewModel: DashboardViewModel

    init(configuration: AppConfiguration = .current) {
        let keychain = SystemKeychainStore(service: configuration.keychainService)
        let tokenStore = SpotifyTokenStore(keychain: keychain)
        let oauthClient = SpotifyOAuthClient(configuration: configuration)
        let tokenManager = SpotifyTokenManager(
            configuration: configuration,
            tokenStore: tokenStore,
            oauthClient: oauthClient
        )
        let apiClient = SpotifyAPIClient(
            tokenManager: tokenManager,
            baseURL: configuration.spotifyAPIBaseURL
        )
        let playerController = SpotifyPlayerController(apiClient: apiClient)
        let authorizationController = SpotifyAuthorizationController(
            configuration: configuration,
            tokenStore: tokenStore,
            oauthClient: oauthClient
        )

        dashboardViewModel = DashboardViewModel(
            configuration: configuration,
            tokenStore: tokenStore,
            authorizationController: authorizationController,
            playerController: playerController
        )
    }
}
