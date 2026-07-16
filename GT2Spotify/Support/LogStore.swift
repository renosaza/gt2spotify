import OSLog

extension Logger {
    static let auth = Logger(subsystem: "com.renosaza.gt2spotify", category: "spotify-auth")
    static let spotifyAPI = Logger(subsystem: "com.renosaza.gt2spotify", category: "spotify-api")
    static let ui = Logger(subsystem: "com.renosaza.gt2spotify", category: "ui")
}
