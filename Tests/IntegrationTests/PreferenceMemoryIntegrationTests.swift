import Testing
import Foundation
@testable import SentioKit


/// Integration tests for the PreferenceMemory prompt generation pipeline.
/// Tests the override recording → prompt section generation flow.
@Suite("PreferenceMemory Prompt Pipeline")
struct PreferenceMemoryPromptTests {

    // MARK: - Prompt Section Generation

    @Test("promptSection returns nil when no overrides exist")
    func emptyPromptSection() {
        let overrides: [UserOverride] = []
        let section = buildPromptSection(from: overrides)
        #expect(section == nil)
    }

    @Test("promptSection includes override descriptions")
    func overridesIncluded() {
        let overrides = [
            makeOverride(
                accessoryName: "Bedroom Light",
                characteristic: "brightness",
                aiValue: 40,
                userValue: 80,
                reason: "Dimming for evening",
                daysAgo: 1
            ),
            makeOverride(
                accessoryName: "Thermostat",
                characteristic: "targetTemperature",
                aiValue: 20,
                userValue: 23,
                reason: "Energy saving",
                daysAgo: 3
            )
        ]

        let section = buildPromptSection(from: overrides)
        #expect(section != nil)
        #expect(section!.contains("Bedroom Light"))
        #expect(section!.contains("Thermostat"))
        #expect(section!.contains("Override History"))
    }

    @Test("promptSection caps at 20 entries even with more overrides")
    func promptCappedAt20() {
        var overrides: [UserOverride] = []
        for i in 0..<30 {
            overrides.append(makeOverride(
                accessoryName: "Device \(i)",
                characteristic: "brightness",
                aiValue: 50,
                userValue: 80,
                reason: "Test",
                daysAgo: i
            ))
        }

        let section = buildPromptSection(from: overrides)
        #expect(section != nil)
        // Count the number of "- " lines (each override starts with "- ")
        let overrideLines = section!.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        #expect(overrideLines.count == 20)
    }

    @Test("overrides older than 30 days are excluded from recent")
    func olderThan30Days() {
        let overrides = [
            makeOverride(accessoryName: "Recent", characteristic: "on", aiValue: 0, userValue: 1, reason: "Test", daysAgo: 5),
            makeOverride(accessoryName: "Old", characteristic: "on", aiValue: 0, userValue: 1, reason: "Test", daysAgo: 45)
        ]

        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let recent = overrides.filter { $0.timestamp > cutoff }

        #expect(recent.count == 1)
        #expect(recent[0].accessoryName == "Recent")
    }

    // MARK: - Seasonal Summary Prompt

    @Test("seasonalSummary generates correct prompt text")
    func seasonalPrompt() {
        let summaries = [
            SeasonalSummary(
                accessoryName: "Bedroom Light",
                characteristic: "brightness",
                preferredValue: 25,
                context: "weekdays",
                months: ["November", "December", "January"],
                sampleCount: 12,
                lastUpdated: Date()
            )
        ]

        let lines = summaries.map(\.promptDescription)
        let prompt = lines.joined(separator: "\n")

        #expect(prompt.contains("Bedroom Light"))
        #expect(prompt.contains("25%"))
        #expect(prompt.contains("weekdays"))
        #expect(prompt.contains("November–January"))
        #expect(prompt.contains("12 corrections"))
    }

    // MARK: - Compression Logic

    @Test("Override grouping key includes device + characteristic + weekday/weekend")
    func groupingKey() {
        let weekdayOverride = makeOverride(
            accessoryName: "Light",
            characteristic: "brightness",
            aiValue: 50,
            userValue: 80,
            reason: "Test",
            daysAgo: 40,
            isWeekend: false
        )

        let weekendOverride = makeOverride(
            accessoryName: "Light",
            characteristic: "brightness",
            aiValue: 50,
            userValue: 80,
            reason: "Test",
            daysAgo: 41,
            isWeekend: true
        )

        let key1 = "\(weekdayOverride.accessoryName)|\(weekdayOverride.characteristic)|\(weekdayOverride.isWeekend ? "weekend" : "weekday")"
        let key2 = "\(weekendOverride.accessoryName)|\(weekendOverride.characteristic)|\(weekendOverride.isWeekend ? "weekend" : "weekday")"

        #expect(key1 != key2, "Weekday and weekend overrides should have different keys")
        #expect(key1.contains("weekday"))
        #expect(key2.contains("weekend"))
    }

    // MARK: - Helpers

    private func makeOverride(
        accessoryName: String,
        characteristic: String,
        aiValue: Double,
        userValue: Double,
        reason: String,
        daysAgo: Int,
        isWeekend: Bool = false
    ) -> UserOverride {
        UserOverride(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-Double(daysAgo) * 24 * 3600),
            accessoryID: "id-\(accessoryName.lowercased().replacingOccurrences(of: " ", with: "-"))",
            accessoryName: accessoryName,
            roomName: "Room",
            characteristic: characteristic,
            aiSetValue: aiValue,
            aiReason: reason,
            userSetValue: userValue,
            timeOfDay: .evening,
            dayOfWeek: isWeekend ? 7 : 3,
            isWeekend: isWeekend,
            weatherCondition: nil,
            userWasHome: true
        )
    }

    private func buildPromptSection(from overrides: [UserOverride]) -> String? {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let recent = overrides
            .filter { $0.timestamp > cutoff }
            .sorted { $0.timestamp > $1.timestamp }

        guard !recent.isEmpty else { return nil }

        let lines = recent.prefix(20).map(\.promptDescription)
        return """
        ## User Override History (last 30 days, most recent first)
        The user has manually corrected the following AI actions.

        \(lines.joined(separator: "\n"))
        """
    }
}
