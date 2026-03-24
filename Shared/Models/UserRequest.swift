import Foundation

/// A user-initiated request sent from the iOS companion to the macOS server
/// via CloudKit. The server processes it with full home context and responds.
struct UserRequest: Codable, Sendable {

    var id: String
    var message: String
    var timestamp: Date

    /// Whether this request should trigger device actions or just return information.
    /// "query" = informational ("What's the temperature?")
    /// "command" = actionable ("Turn off the living room lights")
    /// "auto" = let the AI decide
    var intent: String

    /// Groups related messages into a multi-turn conversation.
    /// The server maintains a persistent `LanguageModelSession` per conversation ID.
    var conversationID: String

    static let recordType = "UserRequest"
}

struct UserResponse: Codable, Sendable {

    var requestID: String
    var message: String
    var actionsPerformed: [String]
    var timestamp: Date

    /// Whether the server expects the user to continue the conversation.
    /// `true` when the AI asked a clarifying question; `false` otherwise.
    var expectsContinuation: Bool

    var conversationID: String

    static let recordType = "UserResponse"
}
