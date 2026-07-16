import Foundation

actor MusicBridgeCoordinator {
    private let player: SpotifyPlayerController

    init(player: SpotifyPlayerController) {
        self.player = player
    }

    func execute(_ command: MusicCommand) async throws {
        switch command {
        case .play: try await player.play()
        case .pause: try await player.pause()
        case .previous: try await player.previous()
        case .next: try await player.next()
        case .volumeUp: try await player.changeVolume(by: 5)
        case .volumeDown: try await player.changeVolume(by: -5)
        case .setVolume(let value): try await player.setVolume(value)
        }
    }
}
