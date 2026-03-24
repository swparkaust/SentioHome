import Testing
import Foundation
@testable import SentioKit

@Suite("CommunicationAction")
struct CommunicationActionTests {

    // MARK: - Codable

    @Test("CommunicationAction round-trips through JSON")
    func codableRoundTrip() throws {
        let action = CommunicationAction(
            message: "Welcome home, warming things up.",
            route: "auto",
            expectsReply: false
        )
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(CommunicationAction.self, from: data)
        #expect(decoded.message == "Welcome home, warming things up.")
        #expect(decoded.route == "auto")
        #expect(decoded.expectsReply == false)
    }

    @Test("ExpectsReply true round-trips correctly")
    func expectsReplyTrue() throws {
        let action = CommunicationAction(
            message: "Want me to lock up?",
            route: "airpods",
            expectsReply: true
        )
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(CommunicationAction.self, from: data)
        #expect(decoded.expectsReply == true)
    }

    // MARK: - Route Values

    @Test("All route values encode correctly", arguments: ["airpods", "auto"])
    func routeValues(route: String) throws {
        let action = CommunicationAction(message: "Test", route: route, expectsReply: false)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(CommunicationAction.self, from: data)
        #expect(decoded.route == route)
    }
}

@Suite("AutomationPlanV2")
struct AutomationPlanV2Tests {

    @Test("Full plan with all fields round-trips")
    func fullPlanRoundTrip() throws {
        let plan = AutomationPlanV2(
            actions: [
                DeviceAction(accessoryID: "a1", accessoryName: "Lamp", characteristic: "on", value: 1, reason: "Evening")
            ],
            communication: CommunicationAction(message: "Good evening", route: "auto", expectsReply: false),
            music: MusicAction(query: "soft jazz", volume: 0.3, stop: false),
            summary: "Setting evening ambiance"
        )
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(AutomationPlanV2.self, from: data)
        #expect(decoded.actions.count == 1)
        #expect(decoded.communication?.message == "Good evening")
        #expect(decoded.music?.query == "soft jazz")
        #expect(decoded.summary == "Setting evening ambiance")
    }

    @Test("Plan with nil optional fields round-trips")
    func nilOptionals() throws {
        let plan = AutomationPlanV2(
            actions: [],
            communication: nil,
            music: nil,
            summary: "No changes needed"
        )
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(AutomationPlanV2.self, from: data)
        #expect(decoded.actions.isEmpty)
        #expect(decoded.communication == nil)
        #expect(decoded.music == nil)
        #expect(decoded.summary == "No changes needed")
    }

    @Test("Plan with only device actions")
    func deviceActionsOnly() throws {
        let plan = AutomationPlanV2(
            actions: [
                DeviceAction(accessoryID: "a1", accessoryName: "Light", characteristic: "brightness", value: 80, reason: "Dim"),
                DeviceAction(accessoryID: "a2", accessoryName: "Thermostat", characteristic: "targetTemperature", value: 21, reason: "Comfort")
            ],
            communication: nil,
            music: nil,
            summary: "Adjusting comfort settings"
        )
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(AutomationPlanV2.self, from: data)
        #expect(decoded.actions.count == 2)
        #expect(decoded.actions[0].accessoryName == "Light")
        #expect(decoded.actions[1].accessoryName == "Thermostat")
    }
}
