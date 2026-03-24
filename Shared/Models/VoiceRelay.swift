import Foundation

/// A message sent from macOS to the iOS companion to be spoken through AirPods.
struct VoiceRelay: Codable, Sendable {
    var message: String
    var expectsReply: Bool
    var timestamp: Date
}
