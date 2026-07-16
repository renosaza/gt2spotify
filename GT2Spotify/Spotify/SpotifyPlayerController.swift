import Foundation

actor SpotifyPlayerController {
    private let apiClient: SpotifyAPIClient

    init(apiClient: SpotifyAPIClient) {
        self.apiClient = apiClient
    }

    func playback() async throws -> PlaybackSnapshot? {
        try await apiClient.currentPlayback()
    }

    func devices() async throws -> [SpotifyDevice] {
        try await apiClient.devices()
    }

    func play() async throws { try await apiClient.play() }
    func pause() async throws { try await apiClient.pause() }
    func next() async throws { try await apiClient.next() }
    func previous() async throws { try await apiClient.previous() }

    func setVolume(_ percent: Int) async throws {
        try await apiClient.setVolume(percent)
    }

    func changeVolume(by delta: Int) async throws {
        guard let current = try await apiClient.currentPlayback() else {
            throw SpotifyError.noActiveDevice
        }
        guard let volume = current.volumePercent else {
            throw SpotifyError.volumeUnavailable
        }
        try await apiClient.setVolume(volume + delta)
    }
}
