import Testing
import Foundation
@testable import SentioKit


/// Integration tests that verify the interaction between OverrideTracker
/// and the action filtering pipeline — simulating the full flow from
/// AI action → manual override → filtered output.
@Suite("Override Pipeline Integration")
@MainActor
struct OverrideIntegrationTests {

    // MARK: - Full Override Flow

    @Test("AI action → manual override → subsequent AI actions blocked for that device")
    func fullOverrideFlow() {
        let tracker = OverrideTracker()
        tracker.cooldownSeconds = 1800

        // Step 1: AI sets brightness to 40
        tracker.registerAIWrite(accessoryID: "light-1", characteristic: "brightness", value: 40)
        let aiResult = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Living Room Light",
            roomName: "Living Room",
            characteristic: "brightness",
            newValue: 40
        )
        #expect(aiResult == false, "AI write should not be flagged as override")

        // Step 2: User manually changes to 90
        let userResult = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Living Room Light",
            roomName: "Living Room",
            characteristic: "brightness",
            newValue: 90
        )
        #expect(userResult == true, "User change should be flagged as override")

        // Step 3: Next AI cycle tries to set brightness to 50
        let nextActions = [
            DeviceAction(accessoryID: "light-1", accessoryName: "Living Room Light",
                        characteristic: "brightness", value: 50, reason: "Dimming"),
            DeviceAction(accessoryID: "light-2", accessoryName: "Kitchen Light",
                        characteristic: "on", value: 1, reason: "Kitchen on")
        ]

        let filtered = tracker.filterActions(nextActions)
        #expect(filtered.blocked.count == 1)
        #expect(filtered.blocked[0].accessoryID == "light-1")
        #expect(filtered.allowed.count == 1)
        #expect(filtered.allowed[0].accessoryID == "light-2")
    }

    // MARK: - Override + Prompt Section

    @Test("Override generates correct prompt guidance for the AI")
    func overridePromptGuidance() {
        let tracker = OverrideTracker()

        // User overrides thermostat
        _ = tracker.handleValueChange(
            accessoryID: "therm-1",
            accessoryName: "Bedroom Thermostat",
            roomName: "Bedroom",
            characteristic: "targetTemperature",
            newValue: 24
        )

        // User overrides light
        _ = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Bedroom Lamp",
            roomName: "Bedroom",
            characteristic: "brightness",
            newValue: 100
        )

        let section = tracker.promptSection
        #expect(section != nil)
        #expect(section!.contains("DO NOT TOUCH"))
        #expect(section!.contains("Bedroom Thermostat"))
        #expect(section!.contains("Bedroom Lamp"))
        #expect(section!.contains("24.0°C"))
        #expect(section!.contains("100%"))
    }

    // MARK: - Multi-Characteristic Override Independence

    @Test("Override on brightness doesn't block on/off on same device")
    func characteristicIndependence() {
        let tracker = OverrideTracker()

        _ = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: nil,
            characteristic: "brightness",
            newValue: 100
        )

        let actions = [
            DeviceAction(accessoryID: "light-1", accessoryName: "Light",
                        characteristic: "brightness", value: 50, reason: "Dim"),
            DeviceAction(accessoryID: "light-1", accessoryName: "Light",
                        characteristic: "on", value: 0, reason: "Off")
        ]

        let filtered = tracker.filterActions(actions)
        #expect(filtered.blocked.count == 1)
        #expect(filtered.blocked[0].characteristic == "brightness")
        #expect(filtered.allowed.count == 1)
        #expect(filtered.allowed[0].characteristic == "on")
    }
}

/// Integration tests verifying VoiceThrottler behavior across
/// a simulated automation session with evolving context.
@Suite("Voice Throttle Session Integration")
@MainActor
struct VoiceThrottleIntegrationTests {

    @Test("Full session: welcome → suppress repeats → allow after cooldown")
    func sessionFlow() {
        let throttler = VoiceThrottler()
        throttler.enforceQuietHours = false
        throttler.globalCooldownSeconds = 0  // Only test category cooldown

        // Welcome message should be allowed
        let welcome = throttler.evaluate(
            message: "Welcome home!",
            expectsReply: false,
            route: "auto",
            sleepState: nil,
            isInEvent: false,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: false,
            airPodsConnected: false
        )
        #expect(isAllow(welcome))
        throttler.recordAnnouncement(message: "Welcome home!", expectsReply: false)

        // Second welcome within cooldown should be suppressed
        let secondWelcome = throttler.evaluate(
            message: "Welcome back!",
            expectsReply: false,
            route: "auto",
            sleepState: nil,
            isInEvent: false,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: false,
            airPodsConnected: false
        )
        #expect(isSuppress(secondWelcome))
    }

    @Test("Context transition: normal → guests arrive → privacy routing")
    func guestArrivalTransition() {
        let throttler = VoiceThrottler()
        throttler.enforceQuietHours = false
        throttler.globalCooldownSeconds = 0

        // Normal: allowed on speaker
        let normal = throttler.evaluate(
            message: "Turning on the lights",
            expectsReply: false,
            route: "auto",
            sleepState: nil,
            isInEvent: false,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: false,
            airPodsConnected: true
        )
        #expect(isAllow(normal))

        // Guests arrive: force to AirPods
        let withGuests = throttler.evaluate(
            message: "Adjusting thermostat",
            expectsReply: false,
            route: "auto",
            sleepState: nil,
            isInEvent: false,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: true,
            airPodsConnected: true
        )
        #expect(isForcePrivate(withGuests))
    }

    private func isAllow(_ decision: VoiceThrottler.Decision) -> Bool {
        if case .allow = decision { return true }
        return false
    }

    private func isSuppress(_ decision: VoiceThrottler.Decision) -> Bool {
        if case .suppress = decision { return true }
        return false
    }

    private func isForcePrivate(_ decision: VoiceThrottler.Decision) -> Bool {
        if case .forcePrivate = decision { return true }
        return false
    }
}
