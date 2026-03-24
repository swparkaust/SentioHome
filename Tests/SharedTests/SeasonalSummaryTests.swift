import Testing
import Foundation
@testable import SentioKit


@Suite("SeasonalSummary")
struct SeasonalSummaryTests {

    @Test("promptDescription formats brightness correctly")
    func brightnessPrompt() {
        let summary = SeasonalSummary(
            accessoryName: "Bedroom Light",
            characteristic: "brightness",
            preferredValue: 30,
            context: "weekdays",
            months: ["November", "December", "January"],
            sampleCount: 15,
            lastUpdated: Date()
        )

        let desc = summary.promptDescription
        #expect(desc.contains("Bedroom Light"))
        #expect(desc.contains("30%"))
        #expect(desc.contains("weekdays"))
        #expect(desc.contains("November–January"))
        #expect(desc.contains("15 corrections"))
    }

    @Test("promptDescription formats on/off correctly")
    func onOffPrompt() {
        let on = SeasonalSummary(
            accessoryName: "Desk Lamp",
            characteristic: "on",
            preferredValue: 1,
            context: "weekends",
            months: ["March"],
            sampleCount: 5,
            lastUpdated: Date()
        )
        #expect(on.promptDescription.contains("on"))

        let off = SeasonalSummary(
            accessoryName: "Desk Lamp",
            characteristic: "on",
            preferredValue: 0,
            context: "weekdays",
            months: ["April"],
            sampleCount: 3,
            lastUpdated: Date()
        )
        #expect(off.promptDescription.contains("off"))
    }

    @Test("promptDescription formats temperature correctly")
    func temperaturePrompt() {
        let summary = SeasonalSummary(
            accessoryName: "Thermostat",
            characteristic: "targetTemperature",
            preferredValue: 21.5,
            context: "weekdays",
            months: ["December", "January"],
            sampleCount: 20,
            lastUpdated: Date()
        )
        #expect(summary.promptDescription.contains("21.5°C"))
    }

    @Test("month range displays correctly for 2 months")
    func twoMonthRange() {
        let summary = SeasonalSummary(
            accessoryName: "Test",
            characteristic: "brightness",
            preferredValue: 50,
            context: "weekdays",
            months: ["June", "July"],
            sampleCount: 5,
            lastUpdated: Date()
        )
        // 2 months → comma-separated
        #expect(summary.promptDescription.contains("June, July"))
    }

    @Test("month range displays correctly for 3+ months")
    func multiMonthRange() {
        let summary = SeasonalSummary(
            accessoryName: "Test",
            characteristic: "brightness",
            preferredValue: 50,
            context: "weekends",
            months: ["October", "November", "December"],
            sampleCount: 10,
            lastUpdated: Date()
        )
        // 3+ months → dash range
        #expect(summary.promptDescription.contains("October–December"))
    }

    @Test("Codable round-trip")
    func codable() throws {
        let summary = SeasonalSummary(
            accessoryName: "Light",
            characteristic: "brightness",
            preferredValue: 60,
            context: "weekdays",
            months: ["January"],
            sampleCount: 8,
            lastUpdated: Date()
        )

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(SeasonalSummary.self, from: data)

        #expect(decoded.accessoryName == "Light")
        #expect(decoded.preferredValue == 60)
        #expect(decoded.sampleCount == 8)
    }
}
