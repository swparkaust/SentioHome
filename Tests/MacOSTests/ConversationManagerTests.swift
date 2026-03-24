import Testing
import Foundation
@testable import SentioKit

#if canImport(FoundationModels)

@Suite("ConversationManager")
@MainActor
struct ConversationManagerTests {

    // MARK: - Helpers

    private func makeManager() -> ConversationManager {
        let engine = IntelligenceEngine()
        return ConversationManager(intelligenceEngine: engine)
    }

    private var modelAvailable: Bool {
        IntelligenceEngine().isAvailable
    }

    private func minimalContext(userIsHome: Bool = true) -> HomeContext {
        HomeContext(
            timestamp: Date(),
            timeOfDay: .evening,
            dayOfWeek: 3,
            isWeekend: false,
            userIsHome: userIsHome,
            devices: []
        )
    }

    // MARK: - Initial State

    @Test("New manager has zero active conversations")
    func emptyOnInit() {
        let manager = makeManager()
        #expect(manager.activeConversationCount == 0)
    }

    @Test("isConversationActive returns false for unknown ID")
    func unknownConversation() {
        let manager = makeManager()
        #expect(manager.isConversationActive("nonexistent") == false)
    }

    // MARK: - End Conversation

    @Test("endConversation on non-existent ID does not crash")
    func endNonexistent() {
        let manager = makeManager()
        manager.endConversation("no-such-id")
        #expect(manager.activeConversationCount == 0)
    }

    // MARK: - Expiry

    @Test("expireStaleConversations returns empty when no conversations exist")
    func expireEmpty() {
        let manager = makeManager()
        let expired = manager.expireStaleConversations()
        #expect(expired.isEmpty)
    }

    @Test("Timeout interval defaults to 120 seconds")
    func defaultTimeout() {
        let manager = makeManager()
        #expect(manager.timeoutInterval == 120)
    }

    @Test("Timeout interval can be customized")
    func customTimeout() {
        let manager = makeManager()
        manager.timeoutInterval = 60
        #expect(manager.timeoutInterval == 60)
    }

    // MARK: - handleTurn creates and tracks conversations

    @Test("First turn creates a new conversation")
    func firstTurnCreatesConversation() async throws {
        guard modelAvailable else { return }
        let manager = makeManager()
        let request = UserRequest(
            id: "req-1",
            message: "Hello",
            timestamp: Date(),
            intent: "auto",
            conversationID: "conv-1"
        )
        let context = minimalContext()

        _ = try await manager.handleTurn(
            request,
            context: context,
            preferenceHistory: nil,
            activeOverrides: nil
        )

        #expect(manager.activeConversationCount == 1)
        #expect(manager.isConversationActive("conv-1"))
    }

    @Test("Second turn on same conversationID reuses session (not creates new)")
    func secondTurnReusesSession() async throws {
        guard modelAvailable else { return }
        let manager = makeManager()
        let context = minimalContext()

        let req1 = UserRequest(
            id: "req-1", message: "Hi",
            timestamp: Date(), intent: "auto", conversationID: "conv-2"
        )
        _ = try await manager.handleTurn(req1, context: context, preferenceHistory: nil, activeOverrides: nil)
        #expect(manager.activeConversationCount == 1)

        let req2 = UserRequest(
            id: "req-2", message: "OK",
            timestamp: Date(), intent: "auto", conversationID: "conv-2"
        )
        _ = try await manager.handleTurn(req2, context: context, preferenceHistory: nil, activeOverrides: nil)

        // Still only one conversation — second turn reused the existing session
        #expect(manager.activeConversationCount == 1)
        #expect(manager.isConversationActive("conv-2"))
    }

    @Test("Different conversationIDs create separate conversations")
    func separateConversations() async throws {
        guard modelAvailable else { return }
        let manager = makeManager()
        let context = minimalContext()

        let req1 = UserRequest(
            id: "req-1", message: "Hello",
            timestamp: Date(), intent: "auto", conversationID: "conv-a"
        )
        let req2 = UserRequest(
            id: "req-2", message: "Hi",
            timestamp: Date(), intent: "auto", conversationID: "conv-b"
        )

        _ = try await manager.handleTurn(req1, context: context, preferenceHistory: nil, activeOverrides: nil)
        _ = try await manager.handleTurn(req2, context: context, preferenceHistory: nil, activeOverrides: nil)

        #expect(manager.activeConversationCount == 2)
        #expect(manager.isConversationActive("conv-a"))
        #expect(manager.isConversationActive("conv-b"))
    }

    @Test("endConversation removes a tracked conversation")
    func endTrackedConversation() async throws {
        guard modelAvailable else { return }
        let manager = makeManager()
        let context = minimalContext()

        let request = UserRequest(
            id: "req-1", message: "Hello",
            timestamp: Date(), intent: "auto", conversationID: "conv-end"
        )
        _ = try await manager.handleTurn(request, context: context, preferenceHistory: nil, activeOverrides: nil)
        #expect(manager.activeConversationCount == 1)

        manager.endConversation("conv-end")
        #expect(manager.activeConversationCount == 0)
        #expect(manager.isConversationActive("conv-end") == false)
    }

    // MARK: - Response Structure

    @Test("handleTurn returns a valid UserResponse with matching IDs")
    func responseStructure() async throws {
        guard modelAvailable else { return }
        let manager = makeManager()
        let request = UserRequest(
            id: "req-42", message: "What's the temperature?",
            timestamp: Date(), intent: "auto", conversationID: "conv-resp"
        )
        let context = minimalContext()

        let (response, _, _) = try await manager.handleTurn(
            request, context: context, preferenceHistory: nil, activeOverrides: nil
        )

        #expect(response.requestID == "req-42")
        #expect(response.conversationID == "conv-resp")
        #expect(!response.message.isEmpty)
    }

    // MARK: - Stale Conversation Expiry

    @Test("Stale conversation is expired before reuse")
    func staleConversationExpired() async throws {
        guard modelAvailable else { return }
        let manager = makeManager()
        manager.timeoutInterval = 0  // Expire immediately

        let context = minimalContext()
        let req1 = UserRequest(
            id: "req-1", message: "Hello",
            timestamp: Date(), intent: "auto", conversationID: "conv-stale"
        )

        _ = try await manager.handleTurn(req1, context: context, preferenceHistory: nil, activeOverrides: nil)

        // With timeoutInterval = 0, the next turn with the same ID should
        // expire the old conversation and create a fresh one.
        let req2 = UserRequest(
            id: "req-2", message: "Hi again",
            timestamp: Date(), intent: "auto", conversationID: "conv-stale"
        )
        _ = try await manager.handleTurn(req2, context: context, preferenceHistory: nil, activeOverrides: nil)

        // Still one conversation (old one expired, new one created)
        #expect(manager.activeConversationCount == 1)
    }

    @Test("expireStaleConversations removes only expired conversations")
    func expireOnlyStale() async throws {
        guard modelAvailable else { return }
        let manager = makeManager()
        manager.timeoutInterval = 0  // Everything expires immediately

        let context = minimalContext()
        let req = UserRequest(
            id: "req-1", message: "Hello",
            timestamp: Date(), intent: "auto", conversationID: "conv-expire"
        )
        _ = try await manager.handleTurn(req, context: context, preferenceHistory: nil, activeOverrides: nil)

        let expired = manager.expireStaleConversations()
        #expect(expired.contains("conv-expire"))
        #expect(manager.activeConversationCount == 0)
    }

    // MARK: - Cleanup Loop

    @Test("Cleanup loop can be started and stopped without crash")
    func cleanupLoopLifecycle() async throws {
        let manager = makeManager()
        manager.startCleanupLoop()
        try await Task.sleep(for: .milliseconds(50))
        manager.stopCleanupLoop()
    }

    @Test("Starting cleanup loop twice cancels the first")
    func cleanupLoopRestart() async throws {
        let manager = makeManager()
        manager.startCleanupLoop()
        manager.startCleanupLoop()  // Should not double-schedule
        try await Task.sleep(for: .milliseconds(50))
        manager.stopCleanupLoop()
    }
}

#endif
