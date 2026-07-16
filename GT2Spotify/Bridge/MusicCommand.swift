import Foundation

enum MusicCommand: Equatable, Sendable {
    case play
    case pause
    case previous
    case next
    case volumeUp
    case volumeDown
    case setVolume(Int)
}
