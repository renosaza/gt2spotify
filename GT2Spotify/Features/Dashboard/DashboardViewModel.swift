import Foundation
import Combine
import OSLog

@MainActor
final class DashboardViewModel: ObservableObject {
    enum Action {
        case play, pause, next, previous, volumeUp, volumeDown
    }

    @Published private(set) var isAuthorized = false
    @Published private(set) var isBusy = false
    @Published private(set) var playback: PlaybackSnapshot?
    @Published private(set) var devices: [SpotifyDevice] = []
    @Published private(set) var statusMessage = "Not connected to Spotify"
    @Published var volume: Double = 50

    let isConfigured: Bool

    var activeDevice: SpotifyDevice? {
        devices.first(where: \.isActive)
    }

    var volumeCapabilityKnown: Bool {
        playback != nil || activeDevice != nil
    }

    var supportsSpotifyVolumeControl: Bool {
        playback?.supportsVolume ?? activeDevice?.supportsVolume ?? false
    }

    var shouldUseSystemVolumeControl: Bool {
        isAuthorized && volumeCapabilityKnown && !supportsSpotifyVolumeControl
    }

    private let tokenStore: SpotifyTokenStore
    private let authorizationController: SpotifyAuthorizationController
    private let playerController: SpotifyPlayerController

    init(
        configuration: AppConfiguration,
        tokenStore: SpotifyTokenStore,
        authorizationController: SpotifyAuthorizationController,
        playerController: SpotifyPlayerController
    ) {
        isConfigured = configuration.isSpotifyConfigured
        self.tokenStore = tokenStore
        self.authorizationController = authorizationController
        self.playerController = playerController

        Task { await loadAuthorizationState() }
    }

    func connectSpotify() {
        Task {
            await run {
                try await authorizationController.authorize()
                await loadAuthorizationState()
                try await refreshData()
            }
        }
    }

    func handleOAuthCallback(_ url: URL) {
        authorizationController.handleExternalCallback(url)
    }

    func refresh() {
        Task {
            await run { try await refreshData() }
        }
    }

    func perform(_ action: Action) {
        Task {
            await run {
                switch action {
                case .play: try await playerController.play()
                case .pause: try await playerController.pause()
                case .next: try await playerController.next()
                case .previous: try await playerController.previous()
                case .volumeUp: try await playerController.changeVolume(by: 5)
                case .volumeDown: try await playerController.changeVolume(by: -5)
                }
                try await refreshData()
            }
        }
    }

    func setAbsoluteVolume() {
        Task {
            await run {
                try await playerController.setVolume(Int(volume.rounded()))
                try await refreshData()
            }
        }
    }

    private func loadAuthorizationState() async {
        isAuthorized = (try? await tokenStore.loadTokenSet()) != nil
        if !isConfigured {
            statusMessage = SpotifyError.notConfigured.localizedDescription
        } else if isAuthorized {
            statusMessage = "Spotify token found in Keychain"
        }
    }

    private func refreshData() async throws {
        async let playbackResult = playerController.playback()
        async let deviceResult = playerController.devices()
        playback = try await playbackResult
        devices = try await deviceResult
        if let playback {
            volume = Double(playback.volumePercent ?? Int(volume))
            statusMessage = playback.isPlaying ? "Spotify is playing" : "Spotify is paused"
        } else {
            statusMessage = "No current playback state"
        }
        isAuthorized = true
    }

    private func run(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            Logger.ui.error("UI action failed: \(error.localizedDescription, privacy: .public)")
            statusMessage = error.localizedDescription
            if error as? SpotifyError == .authorizationRequired {
                isAuthorized = false
            }
        }
    }
}
