import Foundation

struct AppConfiguration: Sendable {
    let spotifyClientID: String
    let spotifyRedirectURI: URL
    let appURLScheme: String
    let spotifyAuthorizationURL: URL
    let spotifyTokenURL: URL
    let spotifyAPIBaseURL: URL
    let spotifyScopes: [String]
    let keychainService: String

    var isSpotifyConfigured: Bool {
        let trimmed = spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("YOUR_SPOTIFY_CLIENT_ID") && !trimmed.contains("$(")
    }

    static let current: AppConfiguration = {
        let info = Bundle.main.infoDictionary ?? [:]
        let clientID = info["SpotifyClientID"] as? String ?? ""
        let redirectString = info["SpotifyRedirectURI"] as? String
            ?? "https://renosaza.github.io/gt2spotify/oauth/callback.html"
        let scheme = info["AppURLScheme"] as? String ?? "gt2spotify"

        return AppConfiguration(
            spotifyClientID: clientID,
            spotifyRedirectURI: URL(string: redirectString)!,
            appURLScheme: scheme,
            spotifyAuthorizationURL: URL(string: "https://accounts.spotify.com/authorize")!,
            spotifyTokenURL: URL(string: "https://accounts.spotify.com/api/token")!,
            spotifyAPIBaseURL: URL(string: "https://api.spotify.com/v1")!,
            spotifyScopes: [
                "user-read-playback-state",
                "user-modify-playback-state"
            ],
            keychainService: "com.renosaza.gt2spotify"
        )
    }()
}
