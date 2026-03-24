import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "Conversation")

#if canImport(FoundationModels)
/// Manages multi-turn conversations between the user and the AI.
/// Each conversation maintains a persistent `LanguageModelSession` so the AI
/// retains context across turns. Actions returned per turn are executed
/// immediately by the caller (AutomationScheduler).
@MainActor
final class ConversationManager {

    struct ActiveConversation {
        let id: String
        let session: LanguageModelSession
        var lastActivity: Date
        var turnCount: Int
    }

    private var conversations: [String: ActiveConversation] = [:]
    private var cleanupTask: Task<Void, Never>?
    var timeoutInterval: TimeInterval = 120

    private let intelligenceEngine: IntelligenceEngine

    init(intelligenceEngine: IntelligenceEngine) {
        self.intelligenceEngine = intelligenceEngine
    }

    // MARK: - Handle Turn

    func handleTurn(
        _ request: UserRequest,
        context: HomeContext,
        preferenceHistory: String?,
        activeOverrides: String?,
        isLocal: Bool = false
    ) async throws -> (response: UserResponse, actions: [DeviceAction], music: MusicAction?) {

        let conversationID = request.conversationID

        if let existing = conversations[conversationID],
           Date().timeIntervalSince(existing.lastActivity) > timeoutInterval {
            conversations.removeValue(forKey: conversationID)
            logger.info("Expired stale conversation \(conversationID) before reuse")
        }

        let isFirstTurn = conversations[conversationID] == nil

        let contextPrompt: String?
        if isFirstTurn {
            contextPrompt = PromptBuilder.buildPrompt(
                from: context,
                preferenceHistory: preferenceHistory,
                activeOverrides: activeOverrides
            )
        } else {
            contextPrompt = nil
        }

        if isFirstTurn {
            let session = intelligenceEngine.createDialogueSession(
                isLocal: isLocal,
                userIsHome: context.userIsHome
            )
            conversations[conversationID] = ActiveConversation(
                id: conversationID,
                session: session,
                lastActivity: Date(),
                turnCount: 0
            )
        }

        guard var conversation = conversations[conversationID] else {
            throw ConversationError.sessionNotFound
        }

        let turnResponse = try await intelligenceEngine.processDialogueTurn(
            session: conversation.session,
            userMessage: request.message,
            contextPrompt: contextPrompt,
            isFirstTurn: isFirstTurn
        )

        conversation.lastActivity = Date()
        conversation.turnCount += 1
        conversations[conversationID] = conversation

        let expectsContinuation = !turnResponse.conversationComplete
        logger.info("Conversation \(conversationID) turn \(conversation.turnCount): complete=\(turnResponse.conversationComplete), actions=\(turnResponse.actions.count)")

        let response = UserResponse(
            requestID: request.id,
            message: turnResponse.responseText,
            actionsPerformed: turnResponse.actions.map {
                "\($0.accessoryName): \($0.characteristic) → \($0.value)"
            },
            timestamp: Date(),
            expectsContinuation: expectsContinuation,
            conversationID: conversationID
        )

        return (response: response, actions: turnResponse.actions, music: turnResponse.music)
    }

    // MARK: - End / Expire

    func endConversation(_ id: String) {
        if conversations.removeValue(forKey: id) != nil {
            logger.info("Ended conversation \(id)")
        }
    }

    @discardableResult
    func expireStaleConversations() -> [String] {
        let now = Date()
        let expired = conversations.filter {
            now.timeIntervalSince($0.value.lastActivity) > timeoutInterval
        }
        for id in expired.keys {
            conversations.removeValue(forKey: id)
            logger.info("Expired idle conversation \(id)")
        }
        return Array(expired.keys)
    }

    // MARK: - Cleanup Loop

    func startCleanupLoop() {
        cleanupTask?.cancel()
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                expireStaleConversations()
            }
        }
    }

    func stopCleanupLoop() {
        cleanupTask?.cancel()
        cleanupTask = nil
    }

    var activeConversationCount: Int { conversations.count }

    func isConversationActive(_ id: String) -> Bool {
        conversations[id] != nil
    }
}

enum ConversationError: Error, LocalizedError {
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .sessionNotFound: "Conversation session not found"
        }
    }
}
#endif
