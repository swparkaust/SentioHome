import Testing
import Foundation
@testable import SentioKit


@Suite("VoiceRelay")
struct VoiceRelayTests {

    @Test("VoiceRelay round-trips through JSON")
    func codable() throws {
        let relay = VoiceRelay(
            message: "Welcome home!",
            expectsReply: false,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(relay)
        let decoded = try JSONDecoder().decode(VoiceRelay.self, from: data)

        #expect(decoded.message == "Welcome home!")
        #expect(decoded.expectsReply == false)
    }

    @Test("VoiceRelay with reply expected")
    func withReply() throws {
        let relay = VoiceRelay(
            message: "Should I lock the door?",
            expectsReply: true,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(relay)
        let decoded = try JSONDecoder().decode(VoiceRelay.self, from: data)

        #expect(decoded.expectsReply == true)
    }
}
