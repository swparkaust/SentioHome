import Foundation
import AppIntents

struct AskSentioIntent: AppIntent {

    static let title: LocalizedStringResource = "Ask Sentio"

    static let description = IntentDescription(
        "Ask your Sentio Home assistant to control devices, play music, or answer questions.",
        categoryName: "Home"
    )

    static let openAppWhenRun = false

    @Parameter(title: "Message")
    var message: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let conversationID = ConversationTracker.shared.activeConversationID
        let requestID = UUID().uuidString

        let request = UserRequest(
            id: requestID,
            message: message,
            timestamp: Date(),
            intent: "auto",
            conversationID: conversationID
        )

        let cloudSync = CloudSyncService.shared

        do {
            try await cloudSync.pushUserRequest(request)
        } catch {
            return .result(dialog: "I couldn't reach your home right now.")
        }

        // Poll for response — Siri has a ~10 second budget for App Intents
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let response = await cloudSync.pullUserResponse(requestID: requestID) {
                if response.expectsContinuation {
                    ConversationTracker.shared.keepAlive()
                } else {
                    ConversationTracker.shared.endConversation()
                }
                return .result(dialog: "\(response.message)")
            }
            try? await Task.sleep(for: .seconds(1))
        }

        return .result(dialog: "Your home didn't respond in time. Please try again.")
    }
}

/// Tracks conversation state across Siri invocations.
/// Reuses the same conversationID for requests within 2 minutes,
/// enabling implicit multi-turn: "Hey Siri, Ask Sentio to dim the lights"
/// → "Hey Siri, Ask Sentio actually keep the bedroom on" shares context.
final class ConversationTracker: @unchecked Sendable {

    static let shared = ConversationTracker()

    private var conversationID: String = UUID().uuidString
    private var lastActivity: Date = .distantPast
    private let timeout: TimeInterval = 120  // 2 minutes
    private let lock = NSLock()

    private init() {}

    var activeConversationID: String {
        lock.lock()
        defer { lock.unlock() }

        if Date().timeIntervalSince(lastActivity) > timeout {
            conversationID = UUID().uuidString
        }
        lastActivity = Date()
        return conversationID
    }

    func keepAlive() {
        lock.lock()
        defer { lock.unlock() }
        lastActivity = Date()
    }

    func endConversation() {
        lock.lock()
        defer { lock.unlock() }
        lastActivity = .distantPast
    }
}
