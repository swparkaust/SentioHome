import Testing
import Foundation
@testable import SentioKit


@Suite("OverrideTracker")
@MainActor
struct OverrideTrackerTests {

    // MARK: - AI Write Detection

    @Test("AI write is correctly identified and not treated as manual override")
    func aiWriteNotOverride() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "light-1", characteristic: "brightness", value: 75)

        let isManual = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Living Room Light",
            roomName: "Living Room",
            characteristic: "brightness",
            newValue: 75
        )

        #expect(isManual == false)
        #expect(tracker.activeOverrides.isEmpty)
    }

    @Test("AI write with small tolerance is still recognized")
    func aiWriteWithTolerance() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "light-1", characteristic: "brightness", value: 75)

        // HomeKit may round to slightly different value
        let isManual = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: "Room",
            characteristic: "brightness",
            newValue: 76
        )

        #expect(isManual == false)
    }

    @Test("Boolean AI write recognizes on/off correctly")
    func booleanAIWrite() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "light-1", characteristic: "on", value: 1)

        let isManual = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: nil,
            characteristic: "on",
            newValue: 1
        )

        #expect(isManual == false)
    }

    @Test("Temperature AI write uses 0.3° tolerance")
    func temperatureTolerance() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "therm-1", characteristic: "targetTemperature", value: 22.0)

        let isManual = tracker.handleValueChange(
            accessoryID: "therm-1",
            accessoryName: "Thermostat",
            roomName: "Room",
            characteristic: "targetTemperature",
            newValue: 22.2
        )

        #expect(isManual == false)
    }

    // MARK: - Manual Override Detection

    @Test("Value change without prior AI write is detected as manual override")
    func manualOverrideDetected() {
        let tracker = OverrideTracker()

        let isManual = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Living Room Light",
            roomName: "Living Room",
            characteristic: "brightness",
            newValue: 80
        )

        #expect(isManual == true)
        #expect(tracker.activeOverrides.count == 1)
        #expect(tracker.activeOverrides[0].userValue == 80)
        #expect(tracker.activeOverrides[0].accessoryName == "Living Room Light")
    }

    @Test("Value significantly different from AI write is detected as override")
    func significantDifference() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "light-1", characteristic: "brightness", value: 40)

        let isManual = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: nil,
            characteristic: "brightness",
            newValue: 80
        )

        #expect(isManual == true)
    }

    @Test("Boolean flip is detected as override")
    func booleanFlip() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "light-1", characteristic: "on", value: 1)

        let isManual = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: nil,
            characteristic: "on",
            newValue: 0
        )

        #expect(isManual == true)
    }

    // MARK: - Cooldown

    @Test("Override creates a cooldown that blocks actions")
    func cooldownBlocks() {
        let tracker = OverrideTracker()
        tracker.cooldownSeconds = 1800

        _ = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: nil,
            characteristic: "brightness",
            newValue: 100
        )

        #expect(tracker.isOverridden(accessoryID: "light-1", characteristic: "brightness") == true)
        #expect(tracker.isOverridden(accessoryID: "light-1", characteristic: "on") == false)
        #expect(tracker.isOverridden(accessoryID: "light-2", characteristic: "brightness") == false)
    }

    // MARK: - Action Filtering

    @Test("filterActions separates allowed and blocked actions")
    func filterActions() {
        let tracker = OverrideTracker()

        // Create an override for light-1 brightness
        _ = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light 1",
            roomName: nil,
            characteristic: "brightness",
            newValue: 100
        )

        let actions = [
            DeviceAction(
                accessoryID: "light-1",
                accessoryName: "Light 1",
                characteristic: "brightness",
                value: 50,
                reason: "Dimming"
            ),
            DeviceAction(
                accessoryID: "light-1",
                accessoryName: "Light 1",
                characteristic: "on",
                value: 1,
                reason: "Turning on"
            ),
            DeviceAction(
                accessoryID: "light-2",
                accessoryName: "Light 2",
                characteristic: "brightness",
                value: 60,
                reason: "Setting"
            )
        ]

        let result = tracker.filterActions(actions)

        #expect(result.blocked.count == 1)
        #expect(result.blocked[0].accessoryID == "light-1")
        #expect(result.blocked[0].characteristic == "brightness")
        #expect(result.allowed.count == 2)
    }

    // MARK: - Prompt Section

    @Test("promptSection returns nil when no overrides are active")
    func emptyPromptSection() {
        let tracker = OverrideTracker()
        #expect(tracker.promptSection == nil)
    }

    @Test("promptSection includes override details")
    func promptSectionContent() {
        let tracker = OverrideTracker()

        _ = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Bedroom Lamp",
            roomName: "Bedroom",
            characteristic: "brightness",
            newValue: 90
        )

        let section = tracker.promptSection
        #expect(section != nil)
        #expect(section!.contains("Bedroom Lamp"))
        #expect(section!.contains("Bedroom"))
        #expect(section!.contains("90%"))
        #expect(section!.contains("DO NOT TOUCH"))
    }

    // MARK: - Stale Pending Writes

    @Test("clearStalePendingWrites removes old entries")
    func clearStale() {
        let tracker = OverrideTracker()

        // Register a write, then clear stale after it "ages"
        tracker.registerAIWrite(accessoryID: "light-1", characteristic: "on", value: 1)

        // Immediately clearing shouldn't remove fresh entries
        tracker.clearStalePendingWrites()

        // The pending write should still work
        let isManual = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: nil,
            characteristic: "on",
            newValue: 1
        )
        #expect(isManual == false)
    }

    // MARK: - Multiple Overrides

    @Test("Multiple overrides on different devices are tracked independently")
    func multipleOverrides() {
        let tracker = OverrideTracker()

        _ = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light 1",
            roomName: "Room A",
            characteristic: "brightness",
            newValue: 100
        )

        _ = tracker.handleValueChange(
            accessoryID: "therm-1",
            accessoryName: "Thermostat",
            roomName: "Room B",
            characteristic: "targetTemperature",
            newValue: 24
        )

        #expect(tracker.activeOverrides.count == 2)
        #expect(tracker.isOverridden(accessoryID: "light-1", characteristic: "brightness"))
        #expect(tracker.isOverridden(accessoryID: "therm-1", characteristic: "targetTemperature"))
    }

    // MARK: - Tolerance Boundary Tests

    @Test("Brightness at exactly tolerance boundary (delta=2) is AI write")
    func brightnessBoundaryExact() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "light-1", characteristic: "brightness", value: 75)

        let isManual = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: nil,
            characteristic: "brightness",
            newValue: 77 // delta = 2, exactly at threshold (<=2)
        )

        #expect(isManual == false, "Delta of exactly 2 should be within brightness tolerance")
    }

    @Test("Brightness just beyond tolerance boundary (delta=2.1) is manual override")
    func brightnessBoundaryExceeded() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "light-1", characteristic: "brightness", value: 75)

        let isManual = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: nil,
            characteristic: "brightness",
            newValue: 77.1 // delta = 2.1, just beyond threshold
        )

        #expect(isManual == true, "Delta of 2.1 should exceed brightness tolerance")
    }

    @Test("Temperature within tolerance boundary (delta=0.25) is AI write")
    func temperatureBoundaryWithin() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "therm-1", characteristic: "targetTemperature", value: 22.0)

        let isManual = tracker.handleValueChange(
            accessoryID: "therm-1",
            accessoryName: "Thermostat",
            roomName: nil,
            characteristic: "targetTemperature",
            newValue: 22.25 // delta = 0.25, within threshold (<=0.3)
        )

        #expect(isManual == false, "Delta of 0.25 should be within temperature tolerance")
    }

    @Test("Temperature beyond tolerance boundary (delta=0.5) is manual override")
    func temperatureBoundaryExceeded() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "therm-1", characteristic: "targetTemperature", value: 22.0)

        let isManual = tracker.handleValueChange(
            accessoryID: "therm-1",
            accessoryName: "Thermostat",
            roomName: nil,
            characteristic: "targetTemperature",
            newValue: 22.5 // delta = 0.5, beyond threshold
        )

        #expect(isManual == true, "Delta of 0.5 should exceed temperature tolerance")
    }

    @Test("Default characteristic at exactly tolerance boundary (delta=1) is AI write")
    func defaultBoundaryExact() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "fan-1", characteristic: "speed", value: 50)

        let isManual = tracker.handleValueChange(
            accessoryID: "fan-1",
            accessoryName: "Fan",
            roomName: nil,
            characteristic: "speed",
            newValue: 51 // delta = 1, exactly at default threshold (<=1)
        )

        #expect(isManual == false, "Delta of exactly 1 should be within default tolerance")
    }

    @Test("Default characteristic just beyond tolerance boundary (delta=1.1) is manual override")
    func defaultBoundaryExceeded() {
        let tracker = OverrideTracker()
        tracker.registerAIWrite(accessoryID: "fan-1", characteristic: "speed", value: 50)

        let isManual = tracker.handleValueChange(
            accessoryID: "fan-1",
            accessoryName: "Fan",
            roomName: nil,
            characteristic: "speed",
            newValue: 51.1 // delta = 1.1, beyond threshold
        )

        #expect(isManual == true, "Delta of 1.1 should exceed default tolerance")
    }

    @Test("Subsequent override on same device+characteristic updates the entry")
    func overrideUpdate() {
        let tracker = OverrideTracker()

        _ = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: nil,
            characteristic: "brightness",
            newValue: 80
        )

        _ = tracker.handleValueChange(
            accessoryID: "light-1",
            accessoryName: "Light",
            roomName: nil,
            characteristic: "brightness",
            newValue: 90
        )

        // Should still be 1 override (updated), not 2
        #expect(tracker.activeCooldowns.count == 1)
        #expect(tracker.activeOverrides[0].userValue == 90)
    }
}
