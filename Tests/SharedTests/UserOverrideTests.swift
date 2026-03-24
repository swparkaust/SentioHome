import Testing
import Foundation
@testable import SentioKit


@Suite("UserOverride")
struct UserOverrideTests {

    // MARK: - Prompt Description

    @Test("promptDescription formats brightness override correctly")
    func brightnessOverride() {
        let override = makeOverride(
            characteristic: "brightness",
            aiValue: 40,
            userValue: 80,
            reason: "Dimming for evening"
        )

        let desc = override.promptDescription
        #expect(desc.contains("Living Room Light"))
        #expect(desc.contains("brightness"))
        #expect(desc.contains("40%"))
        #expect(desc.contains("80%"))
        #expect(desc.contains("Dimming for evening"))
    }

    @Test("promptDescription formats on/off override correctly")
    func onOffOverride() {
        let override = makeOverride(
            characteristic: "on",
            aiValue: 0,
            userValue: 1,
            reason: "Turning off for bedtime"
        )

        let desc = override.promptDescription
        #expect(desc.contains("off"))
        #expect(desc.contains("on"))
    }

    @Test("promptDescription formats temperature override correctly")
    func temperatureOverride() {
        let override = makeOverride(
            characteristic: "targetTemperature",
            aiValue: 20.0,
            userValue: 22.5,
            reason: "Adjusting for comfort"
        )

        let desc = override.promptDescription
        #expect(desc.contains("20.0°C"))
        #expect(desc.contains("22.5°C"))
    }

    @Test("promptDescription formats hue override correctly")
    func hueOverride() {
        let override = makeOverride(
            characteristic: "hue",
            aiValue: 180,
            userValue: 240,
            reason: "Color shift"
        )

        let desc = override.promptDescription
        #expect(desc.contains("180°"))
        #expect(desc.contains("240°"))
    }

    @Test("promptDescription includes context info")
    func contextInfo() {
        let override = makeOverride(
            characteristic: "brightness",
            aiValue: 50,
            userValue: 100,
            reason: "Dimming",
            timeOfDay: .evening,
            isWeekend: true,
            weather: "rainy"
        )

        let desc = override.promptDescription
        #expect(desc.contains("evening"))
        #expect(desc.contains("weekend"))
        #expect(desc.contains("rainy"))
    }

    @Test("promptDescription includes room name when present")
    func roomNamePresent() {
        let override = makeOverride(roomName: "Kitchen")
        #expect(override.promptDescription.contains("in Kitchen"))
    }

    @Test("promptDescription omits room when nil")
    func roomNameNil() {
        let override = makeOverride(roomName: nil)
        #expect(!override.promptDescription.contains("in "))
    }

    // MARK: - Codable

    @Test("UserOverride round-trips through JSON")
    func codableRoundTrip() throws {
        let override = makeOverride()
        let data = try JSONEncoder().encode(override)
        let decoded = try JSONDecoder().decode(UserOverride.self, from: data)

        #expect(decoded.accessoryName == override.accessoryName)
        #expect(decoded.characteristic == override.characteristic)
        #expect(decoded.aiSetValue == override.aiSetValue)
        #expect(decoded.userSetValue == override.userSetValue)
        #expect(decoded.timeOfDay == override.timeOfDay)
    }

    // MARK: - Helpers

    private func makeOverride(
        characteristic: String = "brightness",
        aiValue: Double = 50,
        userValue: Double = 80,
        reason: String = "Test reason",
        roomName: String? = "Living Room",
        timeOfDay: HomeContext.TimeOfDay = .evening,
        isWeekend: Bool = false,
        weather: String? = nil
    ) -> UserOverride {
        UserOverride(
            id: UUID(),
            timestamp: Date(),
            accessoryID: "uuid-test",
            accessoryName: "Living Room Light",
            roomName: roomName,
            characteristic: characteristic,
            aiSetValue: aiValue,
            aiReason: reason,
            userSetValue: userValue,
            timeOfDay: timeOfDay,
            dayOfWeek: 3,
            isWeekend: isWeekend,
            weatherCondition: weather,
            userWasHome: true
        )
    }
}
