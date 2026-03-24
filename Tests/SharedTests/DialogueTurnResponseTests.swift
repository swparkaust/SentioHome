import Testing
import Foundation
@testable import SentioKit

@Suite("DialogueTurnResponse")
struct DialogueTurnResponseTests {

    @Test("DialogueTurnResponse round-trips through JSON")
    func codableRoundTrip() throws {
        let response = DialogueTurnResponse(
            responseText: "Set the lights to 30%.",
            actions: [
                DeviceAction(
                    accessoryID: "light-001",
                    accessoryName: "Living Room Light",
                    characteristic: "brightness",
                    value: 30,
                    reason: "User requested dim lights"
                )
            ],
            music: nil,
            conversationComplete: true
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DialogueTurnResponse.self, from: data)

        #expect(decoded.responseText == "Set the lights to 30%.")
        #expect(decoded.actions.count == 1)
        #expect(decoded.actions[0].accessoryName == "Living Room Light")
        #expect(decoded.music == nil)
        #expect(decoded.conversationComplete == true)
    }

    @Test("Empty actions array encodes and decodes")
    func emptyActions() throws {
        let response = DialogueTurnResponse(
            responseText: "The temperature is 22°C.",
            actions: [],
            music: nil,
            conversationComplete: true
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DialogueTurnResponse.self, from: data)

        #expect(decoded.actions.isEmpty)
        #expect(decoded.responseText == "The temperature is 22°C.")
    }

    @Test("conversationComplete false preserved")
    func conversationInProgress() throws {
        let response = DialogueTurnResponse(
            responseText: "Which room did you mean?",
            actions: [],
            music: nil,
            conversationComplete: false
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DialogueTurnResponse.self, from: data)

        #expect(decoded.conversationComplete == false)
    }

    @Test("conversationComplete true preserved")
    func conversationDone() throws {
        let response = DialogueTurnResponse(
            responseText: "All done.",
            actions: [],
            music: nil,
            conversationComplete: true
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DialogueTurnResponse.self, from: data)

        #expect(decoded.conversationComplete == true)
    }

    @Test("Music action round-trips")
    func withMusicAction() throws {
        let response = DialogueTurnResponse(
            responseText: "Playing some mellow jazz.",
            actions: [],
            music: MusicAction(query: "mellow jazz", volume: 0.3, stop: false),
            conversationComplete: true
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DialogueTurnResponse.self, from: data)

        #expect(decoded.music?.query == "mellow jazz")
        #expect(decoded.music?.volume == 0.3)
        #expect(decoded.music?.stop == false)
    }
}
