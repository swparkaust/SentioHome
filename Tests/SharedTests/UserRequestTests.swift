import Testing
import Foundation
@testable import SentioKit


@Suite("UserRequest & UserResponse")
struct UserRequestTests {

    // MARK: - UserRequest

    @Test("UserRequest round-trips through JSON")
    func requestCodable() throws {
        let request = UserRequest(
            id: "req-001",
            message: "Turn off the living room lights",
            timestamp: Date(),
            intent: "command",
            conversationID: "conv-001"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UserRequest.self, from: data)

        #expect(decoded.id == "req-001")
        #expect(decoded.message == "Turn off the living room lights")
        #expect(decoded.intent == "command")
        #expect(decoded.conversationID == "conv-001")
    }

    @Test("UserRequest supports all intent types")
    func intentTypes() {
        let query = UserRequest(id: "1", message: "What's the temp?", timestamp: Date(), intent: "query", conversationID: "c1")
        let command = UserRequest(id: "2", message: "Lock the door", timestamp: Date(), intent: "command", conversationID: "c2")
        let auto = UserRequest(id: "3", message: "It's cold", timestamp: Date(), intent: "auto", conversationID: "c3")

        #expect(query.intent == "query")
        #expect(command.intent == "command")
        #expect(auto.intent == "auto")
    }

    @Test("UserRequest conversationID round-trips through JSON")
    func requestConversationID() throws {
        let request = UserRequest(
            id: "req-010",
            message: "Dim the lights",
            timestamp: Date(),
            intent: "auto",
            conversationID: "conv-abc-123"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UserRequest.self, from: data)

        #expect(decoded.conversationID == "conv-abc-123")
    }

    // MARK: - UserResponse

    @Test("UserResponse round-trips through JSON")
    func responseCodable() throws {
        let response = UserResponse(
            requestID: "req-001",
            message: "Done! I've turned off the living room lights.",
            actionsPerformed: ["Turned off Living Room Light"],
            timestamp: Date(),
            expectsContinuation: false,
            conversationID: "conv-001"
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(UserResponse.self, from: data)

        #expect(decoded.requestID == "req-001")
        #expect(decoded.message.contains("turned off"))
        #expect(decoded.actionsPerformed.count == 1)
        #expect(decoded.expectsContinuation == false)
        #expect(decoded.conversationID == "conv-001")
    }

    @Test("UserResponse handles empty actions array")
    func emptyActions() throws {
        let response = UserResponse(
            requestID: "req-002",
            message: "The temperature is 22°C.",
            actionsPerformed: [],
            timestamp: Date(),
            expectsContinuation: false,
            conversationID: "conv-002"
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(UserResponse.self, from: data)

        #expect(decoded.actionsPerformed.isEmpty)
    }

    @Test("UserResponse expectsContinuation true round-trips")
    func expectsContinuationTrue() throws {
        let response = UserResponse(
            requestID: "req-003",
            message: "Which room did you mean?",
            actionsPerformed: [],
            timestamp: Date(),
            expectsContinuation: true,
            conversationID: "conv-003"
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(UserResponse.self, from: data)

        #expect(decoded.expectsContinuation == true)
        #expect(decoded.conversationID == "conv-003")
    }

    @Test("UserResponse expectsContinuation false round-trips")
    func expectsContinuationFalse() throws {
        let response = UserResponse(
            requestID: "req-004",
            message: "All done.",
            actionsPerformed: ["Dimmed lights"],
            timestamp: Date(),
            expectsContinuation: false,
            conversationID: "conv-004"
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(UserResponse.self, from: data)

        #expect(decoded.expectsContinuation == false)
    }
}
