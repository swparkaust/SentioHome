import Testing
import Foundation
@testable import SentioKit


@Suite("GuestDetectionService")
@MainActor
struct GuestDetectionTests {

    // MARK: - No Guests Baseline

    @Test("No signals produces no guest detection")
    func noSignals() {
        let service = GuestDetectionService()
        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Living Room",
            activeMotionRooms: ["Living Room"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .morning
        )

        #expect(service.guestsLikelyPresent == false)
        #expect(service.confidence == 0)
    }

    // MARK: - Calendar Signal

    @Test("Calendar event with guest keyword triggers signal")
    func calendarGuestKeyword() {
        let service = GuestDetectionService()
        service.apartmentMode = false

        let now = Date()
        let event = CalendarEvent(
            title: "Dinner party",
            startDate: now.addingTimeInterval(-1800),
            endDate: now.addingTimeInterval(3600),
            isAllDay: false,
            location: "Home",
            hasAlarms: false
        )

        service.evaluate(
            calendarEvents: [event],
            isInEvent: true,
            userIsHome: true,
            userCurrentRoom: "Kitchen",
            activeMotionRooms: ["Kitchen", "Living Room", "Dining Room"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .evening
        )

        #expect(service.confidence > 0.5)
        #expect(service.guestsLikelyPresent == true)
    }

    @Test("Calendar event without guest keywords has low score")
    func calendarNoKeyword() {
        let service = GuestDetectionService()

        let event = CalendarEvent(
            title: "Team standup",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            isAllDay: false,
            location: nil,
            hasAlarms: false
        )

        service.evaluate(
            calendarEvents: [event],
            isInEvent: true,
            userIsHome: true,
            userCurrentRoom: "Office",
            activeMotionRooms: ["Office"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .morning
        )

        // No guest keywords → calendar signal = 0
        #expect(service.guestsLikelyPresent == false)
    }

    // MARK: - Motion Signal

    @Test("Multi-room motion while user is stationary triggers signal")
    func multiRoomMotion() {
        let service = GuestDetectionService()
        service.apartmentMode = false

        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Living Room",
            activeMotionRooms: ["Living Room", "Kitchen", "Bedroom"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .evening
        )

        // 2 rooms with motion other than user's room → score 0.7
        #expect(service.confidence > 0)
        let motionSignal = service.signals.first { $0.name == "motion" }
        #expect(motionSignal != nil)
        #expect(motionSignal!.score == 0.7)
    }

    @Test("Single room motion while user is stationary gives moderate signal")
    func singleRoomMotion() {
        let service = GuestDetectionService()

        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Living Room",
            activeMotionRooms: ["Living Room", "Kitchen"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .afternoon
        )

        let motionSignal = service.signals.first { $0.name == "motion" }
        #expect(motionSignal != nil)
        #expect(motionSignal!.score == 0.4)
    }

    @Test("Motion while user is away gives moderate signal")
    func motionWhileAway() {
        let service = GuestDetectionService()

        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: false,
            userCurrentRoom: nil,
            activeMotionRooms: ["Kitchen"],
            openContacts: [],
            userActivity: nil,
            timeOfDay: .afternoon
        )

        let motionSignal = service.signals.first { $0.name == "motion" }
        #expect(motionSignal != nil)
        #expect(motionSignal!.score == 0.4)
    }

    // MARK: - Door Signal

    @Test("Entry door opening while user is stationary triggers signal")
    func entryDoorSignal() {
        let service = GuestDetectionService()

        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Living Room",
            activeMotionRooms: ["Living Room"],
            openContacts: ["Front Door (Hallway)"],
            userActivity: "stationary",
            timeOfDay: .evening
        )

        let doorSignal = service.signals.first { $0.name == "door" }
        #expect(doorSignal != nil)
        #expect(doorSignal!.score == 0.5)
    }

    @Test("Non-entry door gives lower signal")
    func nonEntryDoor() {
        let service = GuestDetectionService()

        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Living Room",
            activeMotionRooms: ["Living Room"],
            openContacts: ["Bathroom Window (Bathroom)"],
            userActivity: "stationary",
            timeOfDay: .afternoon
        )

        let doorSignal = service.signals.first { $0.name == "door" }
        #expect(doorSignal != nil)
        #expect(doorSignal!.score == 0.2)
    }

    // MARK: - Occupancy Signal

    @Test("Occupancy in rooms user isn't in triggers signal")
    func occupancySignal() {
        let service = GuestDetectionService()

        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Office",
            activeMotionRooms: [],
            occupiedRooms: ["Office", "Kitchen", "Living Room"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .evening
        )

        let occupancySignal = service.signals.first { $0.name == "occupancy" }
        #expect(occupancySignal != nil)
        #expect(occupancySignal!.score == 0.75)
    }

    // MARK: - Time Bias

    @Test("Evening has positive time bias")
    func eveningBias() {
        let service = GuestDetectionService()

        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Room",
            activeMotionRooms: [],
            openContacts: [],
            userActivity: nil,
            timeOfDay: .evening
        )

        let timeSignal = service.signals.first { $0.name == "time" }
        #expect(timeSignal != nil)
        #expect(timeSignal!.score == 0.15)
    }

    @Test("Early morning has no time bias")
    func earlyMorningNoBias() {
        let service = GuestDetectionService()

        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Room",
            activeMotionRooms: [],
            openContacts: [],
            userActivity: nil,
            timeOfDay: .earlyMorning
        )

        let timeSignal = service.signals.first { $0.name == "time" }
        #expect(timeSignal == nil) // Score 0 → not added
    }

    // MARK: - Apartment Mode

    @Test("Apartment mode requires 2+ significant signals")
    func apartmentModeFiltering() {
        let service = GuestDetectionService()
        service.apartmentMode = true

        // Single signal (motion only) with moderate score
        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Living Room",
            activeMotionRooms: ["Living Room", "Kitchen", "Bedroom"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .morning
        )

        // Even with high motion score, apartment mode needs corroboration
        #expect(service.guestsLikelyPresent == false)
    }

    @Test("Apartment mode allows detection with 2+ signals")
    func apartmentModeAllow() {
        let service = GuestDetectionService()
        service.apartmentMode = true

        let now = Date()
        let event = CalendarEvent(
            title: "Dinner party",
            startDate: now.addingTimeInterval(-1800),
            endDate: now.addingTimeInterval(3600),
            isAllDay: false,
            location: nil,
            hasAlarms: false
        )

        service.evaluate(
            calendarEvents: [event],
            isInEvent: true,
            userIsHome: true,
            userCurrentRoom: "Kitchen",
            activeMotionRooms: ["Kitchen", "Living Room", "Hallway"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .evening
        )

        // Calendar (0.8) + motion (0.7) + time (0.15) = multiple significant signals
        #expect(service.guestsLikelyPresent == true)
    }

    // MARK: - Confidence Scoring

    @Test("Combined confidence uses highest signal as base")
    func confidenceScoring() {
        let service = GuestDetectionService()
        service.apartmentMode = false

        let now = Date()
        let event = CalendarEvent(
            title: "Game night",
            startDate: now.addingTimeInterval(-600),
            endDate: now.addingTimeInterval(7200),
            isAllDay: false,
            location: nil,
            hasAlarms: false
        )

        service.evaluate(
            calendarEvents: [event],
            isInEvent: true,
            userIsHome: true,
            userCurrentRoom: "Living Room",
            activeMotionRooms: ["Living Room", "Kitchen", "Dining Room"],
            openContacts: ["Front Door (Hallway)"],
            userActivity: "stationary",
            timeOfDay: .evening
        )

        // Multiple strong signals should give high confidence
        #expect(service.confidence > 0.8)
        #expect(service.guestsLikelyPresent == true)
        #expect(service.inferenceReason != nil)
    }

    // MARK: - State Reset

    @Test("No guests clears inference reason")
    func clearInference() {
        let service = GuestDetectionService()
        service.apartmentMode = false

        let now = Date()
        let event = CalendarEvent(
            title: "Dinner party",
            startDate: now.addingTimeInterval(-1800),
            endDate: now.addingTimeInterval(3600),
            isAllDay: false,
            location: nil,
            hasAlarms: false
        )

        // First: guests detected
        service.evaluate(
            calendarEvents: [event],
            isInEvent: true,
            userIsHome: true,
            userCurrentRoom: "Kitchen",
            activeMotionRooms: ["Kitchen", "Living Room"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .evening
        )
        #expect(service.guestsLikelyPresent == true)

        // Second: no signals
        service.evaluate(
            calendarEvents: [],
            isInEvent: false,
            userIsHome: true,
            userCurrentRoom: "Bedroom",
            activeMotionRooms: ["Bedroom"],
            openContacts: [],
            userActivity: "stationary",
            timeOfDay: .lateNight
        )
        #expect(service.guestsLikelyPresent == false)
        #expect(service.inferenceReason == nil)
    }
}
