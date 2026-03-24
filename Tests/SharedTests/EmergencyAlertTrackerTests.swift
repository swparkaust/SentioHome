import Foundation
import Testing
@testable import SentioKit

@Suite("EmergencyAlertTracker")
struct EmergencyAlertTrackerTests {

    // HAP characteristic UUIDs (same as EmergencyAlertTracker.characteristicToAlertType)
    private let smokeUUID = "00000076-0000-1000-8000-0026BB765291"
    private let coUUID = "00000069-0000-1000-8000-0026BB765291"
    private let co2UUID = "00000092-0000-1000-8000-0026BB765291"
    private let leakUUID = "00000070-0000-1000-8000-0026BB765291"

    // MARK: - Alert Type Mapping

    @Test("Smoke characteristic maps to smoke alert")
    func smokeMapping() {
        let tracker = EmergencyAlertTracker()
        #expect(tracker.alertType(for: smokeUUID) == .smoke)
    }

    @Test("CO characteristic maps to carbonMonoxide alert")
    func coMapping() {
        let tracker = EmergencyAlertTracker()
        #expect(tracker.alertType(for: coUUID) == .carbonMonoxide)
    }

    @Test("CO2 characteristic maps to carbonDioxide alert")
    func co2Mapping() {
        let tracker = EmergencyAlertTracker()
        #expect(tracker.alertType(for: co2UUID) == .carbonDioxide)
    }

    @Test("Leak characteristic maps to waterLeak alert")
    func leakMapping() {
        let tracker = EmergencyAlertTracker()
        #expect(tracker.alertType(for: leakUUID) == .waterLeak)
    }

    @Test("Unknown characteristic returns nil")
    func unknownMapping() {
        let tracker = EmergencyAlertTracker()
        #expect(tracker.alertType(for: "00000025-0000-1000-8000-0026BB765291") == nil)
    }

    @Test("emergencyCharacteristicTypes contains all four types")
    func characteristicTypeSet() {
        let types = EmergencyAlertTracker.emergencyCharacteristicTypes
        #expect(types.count == 4)
        #expect(types.contains(smokeUUID))
        #expect(types.contains(coUUID))
        #expect(types.contains(co2UUID))
        #expect(types.contains(leakUUID))
    }

    // MARK: - Alert Creation

    @Test("Sensor triggered creates active alert")
    func sensorTriggeredCreatesAlert() {
        let tracker = EmergencyAlertTracker()
        let alert = tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "sensor-1", accessoryName: "Hallway Smoke",
            roomName: "Hallway"
        )
        #expect(alert != nil)
        #expect(alert?.type == .smoke)
        #expect(alert?.accessoryName == "Hallway Smoke")
        #expect(alert?.roomName == "Hallway")
        #expect(tracker.activeAlerts.count == 1)
        #expect(tracker.alertHistory.count == 1)
    }

    @Test("Unknown characteristic does not create alert")
    func unknownCharacteristicIgnored() {
        let tracker = EmergencyAlertTracker()
        let alert = tracker.handleSensorUpdate(
            characteristicType: "00000025-0000-1000-8000-0026BB765291", value: true,
            accessoryID: "sensor-1", accessoryName: "Unknown",
            roomName: nil
        )
        #expect(alert == nil)
        #expect(tracker.activeAlerts.isEmpty)
    }

    @Test("Value=false triggers resolution, not creation")
    func falseValueResolvesInsteadOfCreating() {
        let tracker = EmergencyAlertTracker()
        // First create an alert
        tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "sensor-1", accessoryName: "Smoke Sensor",
            roomName: "Kitchen"
        )
        #expect(tracker.activeAlerts.count == 1)

        // Now resolve it
        let result = tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: false,
            accessoryID: "sensor-1", accessoryName: "Smoke Sensor",
            roomName: "Kitchen"
        )
        #expect(result == nil)
        #expect(tracker.activeAlerts.isEmpty)
    }

    // MARK: - Cooldown

    @Test("Duplicate alert within cooldown is suppressed")
    func cooldownSuppressesDuplicate() {
        let tracker = EmergencyAlertTracker(cooldownSeconds: 120)
        let now = Date()

        let first = tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "sensor-1", accessoryName: "Smoke",
            roomName: "Kitchen", now: now
        )
        #expect(first != nil)

        let second = tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "sensor-1", accessoryName: "Smoke",
            roomName: "Kitchen", now: now.addingTimeInterval(60)
        )
        #expect(second == nil)
        #expect(tracker.activeAlerts.count == 1)
    }

    @Test("Alert after cooldown expires is allowed")
    func alertAfterCooldownAllowed() {
        let tracker = EmergencyAlertTracker(cooldownSeconds: 120)
        let now = Date()

        tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "sensor-1", accessoryName: "Smoke",
            roomName: "Kitchen", now: now
        )

        let second = tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "sensor-1", accessoryName: "Smoke",
            roomName: "Kitchen", now: now.addingTimeInterval(121)
        )
        #expect(second != nil)
        #expect(tracker.activeAlerts.count == 2)
    }

    @Test("Different sensors are not subject to each other's cooldown")
    func differentSensorsIndependentCooldown() {
        let tracker = EmergencyAlertTracker(cooldownSeconds: 120)
        let now = Date()

        let first = tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "sensor-1", accessoryName: "Kitchen Smoke",
            roomName: "Kitchen", now: now
        )
        let second = tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "sensor-2", accessoryName: "Bedroom Smoke",
            roomName: "Bedroom", now: now.addingTimeInterval(5)
        )
        #expect(first != nil)
        #expect(second != nil)
        #expect(tracker.activeAlerts.count == 2)
    }

    // MARK: - Resolution

    @Test("Resolving marks alert as resolved in history")
    func resolvingUpdatesHistory() {
        let tracker = EmergencyAlertTracker()
        tracker.handleSensorUpdate(
            characteristicType: leakUUID, value: true,
            accessoryID: "leak-1", accessoryName: "Water Sensor",
            roomName: "Basement"
        )

        tracker.resolveAlert(accessoryID: "leak-1", characteristicType: leakUUID)

        #expect(tracker.activeAlerts.isEmpty)
        #expect(tracker.alertHistory.count == 1)
        #expect(tracker.alertHistory[0].resolved == true)
        #expect(tracker.alertHistory[0].resolvedAt != nil)
    }

    @Test("Resolving wrong accessory does not affect other alerts")
    func resolvingWrongAccessoryNoEffect() {
        let tracker = EmergencyAlertTracker()
        tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "sensor-1", accessoryName: "Kitchen Smoke",
            roomName: "Kitchen"
        )

        tracker.resolveAlert(accessoryID: "sensor-999", characteristicType: smokeUUID)

        #expect(tracker.activeAlerts.count == 1)
    }

    @Test("Multiple alerts resolved independently")
    func multipleAlertsResolvedIndependently() {
        let tracker = EmergencyAlertTracker()
        let now = Date()

        tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "sensor-1", accessoryName: "Kitchen Smoke",
            roomName: "Kitchen", now: now
        )
        tracker.handleSensorUpdate(
            characteristicType: coUUID, value: true,
            accessoryID: "sensor-2", accessoryName: "Garage CO",
            roomName: "Garage", now: now
        )
        #expect(tracker.activeAlerts.count == 2)

        tracker.resolveAlert(accessoryID: "sensor-1", characteristicType: smokeUUID)
        #expect(tracker.activeAlerts.count == 1)
        #expect(tracker.activeAlerts[0].type == .carbonMonoxide)
    }

    // MARK: - Location Description

    @Test("Location description with room")
    func locationDescriptionWithRoom() {
        let tracker = EmergencyAlertTracker()
        let alert = tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "s1", accessoryName: "Hallway Smoke",
            roomName: "Hallway"
        )!
        #expect(tracker.locationDescription(alert) == "Smoke Detected in Hallway (Hallway Smoke).")
    }

    @Test("Location description without room")
    func locationDescriptionNoRoom() {
        let tracker = EmergencyAlertTracker()
        let alert = tracker.handleSensorUpdate(
            characteristicType: leakUUID, value: true,
            accessoryID: "s1", accessoryName: "Water Sensor",
            roomName: nil
        )!
        #expect(tracker.locationDescription(alert) == "Water Leak Detected — Water Sensor.")
    }

    // MARK: - Voice Messages

    @Test("Smoke voice message includes room")
    func smokeVoiceMessage() {
        let tracker = EmergencyAlertTracker()
        let alert = tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "s1", accessoryName: "Sensor",
            roomName: "Kitchen"
        )!
        let msg = tracker.voiceMessage(for: alert)
        #expect(msg.contains("Smoke"))
        #expect(msg.contains("Kitchen"))
    }

    @Test("CO voice message says evacuate")
    func coVoiceMessageEvacuate() {
        let tracker = EmergencyAlertTracker()
        let alert = tracker.handleSensorUpdate(
            characteristicType: coUUID, value: true,
            accessoryID: "s1", accessoryName: "Sensor",
            roomName: "Garage"
        )!
        let msg = tracker.voiceMessage(for: alert)
        #expect(msg.contains("Evacuate"))
    }

    @Test("Water leak voice message mentions valve")
    func leakVoiceMessageValve() {
        let tracker = EmergencyAlertTracker()
        let alert = tracker.handleSensorUpdate(
            characteristicType: leakUUID, value: true,
            accessoryID: "s1", accessoryName: "Sensor",
            roomName: "Basement"
        )!
        let msg = tracker.voiceMessage(for: alert)
        #expect(msg.contains("Water valves"))
    }

    @Test("CO2 voice message mentions ventilation")
    func co2VoiceMessageVentilation() {
        let tracker = EmergencyAlertTracker()
        let alert = tracker.handleSensorUpdate(
            characteristicType: co2UUID, value: true,
            accessoryID: "s1", accessoryName: "Sensor",
            roomName: "Office"
        )!
        let msg = tracker.voiceMessage(for: alert)
        #expect(msg.contains("ventilation"))
    }

    @Test("Voice message with nil room uses 'your home'")
    func voiceMessageNilRoom() {
        let tracker = EmergencyAlertTracker()
        let alert = tracker.handleSensorUpdate(
            characteristicType: smokeUUID, value: true,
            accessoryID: "s1", accessoryName: "Sensor",
            roomName: nil
        )!
        let msg = tracker.voiceMessage(for: alert)
        #expect(msg.contains("your home"))
    }
}
