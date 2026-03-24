import Testing
import Foundation
@testable import SentioKit

@Suite("CalendarEvent")
struct CalendarEventTests {

    // MARK: - Prompt Description

    @Test("promptDescription formats time range and title")
    func basicPromptDescription() {
        let start = Date(timeIntervalSince1970: 1_700_000_000) // fixed reference
        let end = start.addingTimeInterval(3600) // 1 hour later
        let event = CalendarEvent(
            title: "Team Standup",
            startDate: start,
            endDate: end,
            isAllDay: false,
            location: nil,
            hasAlarms: false
        )

        let desc = event.promptDescription
        #expect(desc.contains("Team Standup"))
        #expect(desc.hasPrefix("•"))
        #expect(desc.contains("–")) // en-dash between times
    }

    @Test("promptDescription includes location when present")
    func promptDescriptionWithLocation() {
        let start = Date()
        let event = CalendarEvent(
            title: "Dinner",
            startDate: start,
            endDate: start.addingTimeInterval(7200),
            isAllDay: false,
            location: "The Italian Place",
            hasAlarms: false
        )

        let desc = event.promptDescription
        #expect(desc.contains("at The Italian Place"))
    }

    @Test("promptDescription omits location when nil")
    func promptDescriptionWithoutLocation() {
        let start = Date()
        let event = CalendarEvent(
            title: "Focus Time",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            isAllDay: false,
            location: nil,
            hasAlarms: true
        )

        let desc = event.promptDescription
        #expect(!desc.contains(" at "))
    }

    @Test("promptDescription omits empty location string")
    func promptDescriptionWithEmptyLocation() {
        let start = Date()
        let event = CalendarEvent(
            title: "Quick Sync",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            isAllDay: false,
            location: "",
            hasAlarms: false
        )

        let desc = event.promptDescription
        #expect(!desc.contains(" at "))
    }

    // MARK: - Codable

    @Test("CalendarEvent round-trips through JSON")
    func codableRoundTrip() throws {
        let start = Date()
        let event = CalendarEvent(
            title: "Sprint Planning",
            startDate: start,
            endDate: start.addingTimeInterval(5400),
            isAllDay: false,
            location: "Conference Room B",
            hasAlarms: true
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CalendarEvent.self, from: data)

        #expect(decoded.title == event.title)
        #expect(decoded.isAllDay == false)
        #expect(decoded.location == "Conference Room B")
        #expect(decoded.hasAlarms == true)
    }
}
