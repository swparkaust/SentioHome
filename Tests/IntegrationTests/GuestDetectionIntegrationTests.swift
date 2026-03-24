import Testing
import Foundation
@testable import SentioKit


/// End-to-end integration tests simulating realistic guest detection scenarios
/// with multiple evolving signals over time.
@Suite("Guest Detection E2E")
@MainActor
struct GuestDetectionIntegrationTests {

    // MARK: - Scenario: Dinner Party

    @Test("Dinner party scenario: calendar + motion + door → guests detected")
    func dinnerPartyScenario() {
        let service = GuestDetectionService()
        service.apartmentMode = true

        let now = Date()

        // Phase 1: Calendar event appears, no other signals yet
        let dinnerEvent = CalendarEvent(
            title: "Dinner with friends",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(7200),
            isAllDay: false,
            location: "Home",
            hasAlarms: true
        )

        service.evaluate(
            calendarEvents: [dinnerEvent],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Kitchen",
            activeMotionRooms: ["Kitchen"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .evening
        )

        // Calendar alone in apartment mode shouldn't trigger
        // (upcoming event has score 0.5, but only 1 signal > 0.2)
        // Depends on time signal too — evening = 0.15 which is < 0.2
        // So only calendar is > 0.2 → apartment mode blocks

        // Phase 2: Guests start arriving — door opens, motion in multiple rooms
        service.evaluate(
            calendarEvents: [dinnerEvent],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Kitchen",
            activeMotionRooms: ["Kitchen", "Living Room", "Hallway"],
            openContacts: ["Front Door (Hallway)"],
            userActivity: "stationary",
            timeOfDay: .evening
        )

        // Calendar (0.5) + motion (0.7) + door (0.5) + time (0.15) = high confidence
        #expect(service.guestsLikelyPresent == true)
        #expect(service.confidence > 0.7)
        #expect(service.inferenceReason != nil)
    }

    // MARK: - Scenario: False Positive Prevention

    @Test("Single motion signal in apartment doesn't trigger false positive")
    func apartmentFalsePositive() {
        let service = GuestDetectionService()
        service.apartmentMode = true

        // Neighbor walking past shared hallway sensor
        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Bedroom",
            activeMotionRooms: ["Bedroom", "Hallway"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .night
        )

        // Single motion signal + time bias < 0.2 → apartment mode blocks
        #expect(service.guestsLikelyPresent == false)
    }

    // MARK: - Scenario: User Returns Home

    @Test("Guests leave → signals clear → detection resets")
    func guestsLeaveScenario() {
        let service = GuestDetectionService()
        service.apartmentMode = false

        let now = Date()
        let partyEvent = CalendarEvent(
            title: "Birthday party",
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(1800),
            isAllDay: false,
            location: nil,
            hasAlarms: false
        )

        // During party
        service.evaluate(
            calendarEvents: [partyEvent],
            isInEvent: true,
            userIsHome: true,
            userCurrentRoom: "Living Room",
            activeMotionRooms: ["Living Room", "Kitchen", "Bathroom"],
            openContacts: ["Front Door (Hallway)"],
            userActivity: "stationary",
            timeOfDay: .evening
        )
        #expect(service.guestsLikelyPresent == true)

        // After party — everyone left, user alone
        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Bedroom",
            activeMotionRooms: ["Bedroom"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .night
        )
        #expect(service.guestsLikelyPresent == false)
        #expect(service.inferenceReason == nil)
    }

    // MARK: - Scenario: Working from Home

    @Test("Work meeting at home doesn't trigger guest detection")
    func workMeetingNotGuest() {
        let service = GuestDetectionService()
        service.apartmentMode = true

        let meeting = CalendarEvent(
            title: "Weekly team sync",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            isAllDay: false,
            location: nil,
            hasAlarms: false
        )

        service.evaluate(
            calendarEvents: [meeting],
            isInEvent: true,
            userIsHome: true,
            userCurrentRoom: "Office",
            activeMotionRooms: ["Office"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .morning
        )

        #expect(service.guestsLikelyPresent == false)
    }

    // MARK: - Scenario: Away Mode

    @Test("Motion while user is away creates moderate signal")
    func awayModeMotion() {
        let service = GuestDetectionService()
        service.apartmentMode = false

        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: false,
            userCurrentRoom: nil,
            activeMotionRooms: ["Living Room", "Kitchen"],
            openContacts: ["Front Door (Hallway)"],
            userActivity: nil,
            timeOfDay: .afternoon
        )

        // Motion while away (0.4) + door (not triggered because user not home/stationary)
        // Actually door check requires userIsHome=true, so only motion signal
        #expect(service.confidence > 0)
    }
}
