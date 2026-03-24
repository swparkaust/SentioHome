import Testing
import Foundation
@testable import SentioKit


@Suite("VoiceThrottler")
@MainActor
struct VoiceThrottlerTests {

    // MARK: - Basic Allow

    @Test("First announcement is allowed")
    func firstAllowed() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Hello",
            expectsReply: false,
            route: "auto",
            sleepState: "awake",
            isInEvent: false,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: false,
            airPodsConnected: false
        )
        #expect(isAllow(decision))
    }

    // MARK: - Hard Suppression

    @Test("Suppressed when user is in deep sleep")
    func sleepSuppression() {
        let throttler = makeThrottler()
        for sleepState in ["asleepCore", "asleepDeep", "asleepREM"] {
            let decision = throttler.evaluate(
                message: "Test",
                expectsReply: false,
                route: "auto",
                sleepState: sleepState,
                isInEvent: false,
                cameraInUse: false,
                userIsHome: true,
                houseOccupied: true,
                guestsPresent: false,
                airPodsConnected: false
            )
            #expect(isSuppress(decision), "Should suppress during \(sleepState)")
        }
    }

    @Test("Not suppressed when user is awake or in bed")
    func awakeNotSuppressed() {
        let throttler = makeThrottler()
        for sleepState in ["awake", "inBed"] {
            let decision = throttler.evaluate(
                message: "Test",
                expectsReply: false,
                route: "auto",
                sleepState: sleepState,
                isInEvent: false,
                cameraInUse: false,
                userIsHome: true,
                houseOccupied: true,
                guestsPresent: false,
                airPodsConnected: false
            )
            #expect(!isSuppress(decision), "Should not suppress during \(sleepState)")
        }
    }

    @Test("Suppressed when in a calendar event")
    func eventSuppression() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Test",
            expectsReply: false,
            route: "auto",
            sleepState: nil,
            isInEvent: true,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: false,
            airPodsConnected: false
        )
        #expect(isSuppress(decision))
    }

    @Test("Suppressed when camera is in use")
    func cameraSuppression() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Test",
            expectsReply: false,
            route: "auto",
            sleepState: nil,
            isInEvent: false,
            cameraInUse: true,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: false,
            airPodsConnected: false
        )
        #expect(isSuppress(decision))
    }

    @Test("Suppressed when house is empty and no AirPods")
    func emptyHouseSuppression() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Test",
            expectsReply: false,
            route: "auto",
            sleepState: nil,
            isInEvent: false,
            cameraInUse: false,
            userIsHome: false,
            houseOccupied: false,
            guestsPresent: false,
            airPodsConnected: false
        )
        #expect(isSuppress(decision))
    }

    @Test("Force private when house is empty but AirPods connected")
    func emptyHouseAirPods() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Warming up the house",
            expectsReply: false,
            route: "auto",
            sleepState: nil,
            isInEvent: false,
            cameraInUse: false,
            userIsHome: false,
            houseOccupied: false,
            guestsPresent: false,
            airPodsConnected: true
        )
        #expect(isForcePrivate(decision))
    }

    // MARK: - Guest-Aware Routing

    @Test("Suppressed when user is away and guests are present")
    func guestsPresentUserAway() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Test",
            expectsReply: false,
            route: "auto",
            sleepState: nil,
            isInEvent: false,
            cameraInUse: false,
            userIsHome: false,
            houseOccupied: true,
            guestsPresent: true,
            airPodsConnected: false
        )
        #expect(isSuppress(decision))
    }

    @Test("Force private when user is home with guests and has AirPods")
    func guestsPresentUserHomeAirPods() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Test",
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
        #expect(isForcePrivate(decision))
    }

    @Test("Suppressed when guests present, user home, no AirPods")
    func guestsPresentNoAirPods() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Test",
            expectsReply: false,
            route: "auto",
            sleepState: nil,
            isInEvent: false,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: true,
            airPodsConnected: false
        )
        #expect(isSuppress(decision))
    }

    // MARK: - Rate Limiting

    @Test("Global cooldown suppresses rapid announcements")
    func globalCooldown() {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 300

        // First one allowed
        let first = throttler.evaluate(
            message: "Hello",
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
        #expect(isAllow(first))
        throttler.recordAnnouncement(message: "Hello", expectsReply: false)

        // Second one suppressed (within cooldown)
        let second = throttler.evaluate(
            message: "Another message",
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
        #expect(isSuppress(second))
    }

    @Test("Hourly rate limit enforced")
    func hourlyLimit() {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0  // Disable cooldown to test rate limit
        throttler.categoryCooldowns = [:]    // Disable per-category cooldowns
        throttler.maxAnnouncementsPerHour = 3
        throttler.enforceQuietHours = false

        for i in 0..<3 {
            let decision = throttler.evaluate(
                message: "Message \(i)",
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
            #expect(isAllow(decision))
            throttler.recordAnnouncement(message: "Message \(i)", expectsReply: false)
        }

        // 4th should be suppressed
        let fourth = throttler.evaluate(
            message: "Message 3",
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
        #expect(isSuppress(fourth))
    }

    // MARK: - Priority Order (sleep checked before guests, etc.)

    @Test("Sleep suppression takes priority over guest routing")
    func sleepPriority() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Test",
            expectsReply: false,
            route: "auto",
            sleepState: "asleepDeep",
            isInEvent: false,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: true,
            airPodsConnected: true
        )
        // Should suppress (sleep) rather than force private (guests)
        #expect(isSuppress(decision))
    }

    // MARK: - Helpers

    private func makeThrottler() -> VoiceThrottler {
        let throttler = VoiceThrottler()
        throttler.enforceQuietHours = false  // Disable for predictable testing
        return throttler
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

    private func suppressReason(_ decision: VoiceThrottler.Decision) -> String? {
        if case .suppress(let reason) = decision { return reason }
        return nil
    }

    /// Helper that builds a throttler with quiet hours set so the *current* hour
    /// is inside the quiet window.  Works regardless of when the tests run.
    private func makeQuietHoursThrottler() -> VoiceThrottler {
        let throttler = VoiceThrottler()
        let currentHour = Calendar.current.component(.hour, from: Date())
        // Set a quiet window that spans 3 hours centered on *now*.
        throttler.quietHoursStart = (currentHour - 1 + 24) % 24
        throttler.quietHoursEnd   = (currentHour + 1) % 24
        throttler.enforceQuietHours = true
        return throttler
    }

    /// Helper that builds a throttler where quiet hours do NOT include the
    /// current hour, so announcements are *not* suppressed by quiet hours.
    private func makeNonQuietHoursThrottler() -> VoiceThrottler {
        let throttler = VoiceThrottler()
        let currentHour = Calendar.current.component(.hour, from: Date())
        // Place the quiet window far from the current hour.
        throttler.quietHoursStart = (currentHour + 6) % 24
        throttler.quietHoursEnd   = (currentHour + 8) % 24
        throttler.enforceQuietHours = true
        return throttler
    }

    private func baseEvaluate(
        _ throttler: VoiceThrottler,
        message: String = "Test",
        expectsReply: Bool = false
    ) -> VoiceThrottler.Decision {
        throttler.evaluate(
            message: message,
            expectsReply: expectsReply,
            route: "auto",
            sleepState: nil,
            isInEvent: false,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: false,
            airPodsConnected: false
        )
    }

    // MARK: - classify() — indirect via category cooldowns

    @Test("classify: welcome messages", arguments: [
        "Welcome home!",
        "Welcome back, friend",
        "You're home, welcome back!"
    ])
    func classifyWelcome(message: String) {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [.welcome: 9999]

        // Record an announcement so the welcome cooldown starts.
        throttler.recordAnnouncement(message: message, expectsReply: false)

        // A second welcome-classified message should hit the category cooldown.
        let decision = baseEvaluate(throttler, message: "Welcome home again")
        #expect(isSuppress(decision))
        #expect(suppressReason(decision)?.contains("welcome") == true)
    }

    @Test("classify: goodnight messages", arguments: [
        "Goodnight, sleep well",
        "Good night everyone",
        "Time to sleep"
    ])
    func classifyGoodnight(message: String) {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [.goodnight: 9999]

        throttler.recordAnnouncement(message: message, expectsReply: false)
        let decision = baseEvaluate(throttler, message: "Good night!")
        #expect(isSuppress(decision))
        #expect(suppressReason(decision)?.contains("goodnight") == true)
    }

    @Test("classify: door/window alerts", arguments: [
        "The front door is open",
        "Garage door left open",
        "Window detected open"
    ])
    func classifyDoorAlert(message: String) {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [.doorAlert: 9999]

        throttler.recordAnnouncement(message: message, expectsReply: false)
        let decision = baseEvaluate(throttler, message: "The door is still open")
        #expect(isSuppress(decision))
        #expect(suppressReason(decision)?.contains("doorAlert") == true)
    }

    @Test("classify: energy alerts", arguments: [
        "Power usage is high",
        "Energy consumption spiked",
        "The dryer is running at 4000 watts"
    ])
    func classifyEnergyAlert(message: String) {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [.energyAlert: 9999]

        throttler.recordAnnouncement(message: message, expectsReply: false)
        let decision = baseEvaluate(throttler, message: "Energy is still high, 3000 watts")
        #expect(isSuppress(decision))
        #expect(suppressReason(decision)?.contains("energyAlert") == true)
    }

    @Test("classify: status updates (weather, schedule, update)", arguments: [
        "Here's your weather update",
        "Schedule for today looks clear",
        "System update complete"
    ])
    func classifyStatusUpdate(message: String) {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [.statusUpdate: 9999]

        throttler.recordAnnouncement(message: message, expectsReply: false)
        let decision = baseEvaluate(throttler, message: "Weather update: rain tonight")
        #expect(isSuppress(decision))
        #expect(suppressReason(decision)?.contains("statusUpdate") == true)
    }

    @Test("classify: expectsReply forces question category")
    func classifyQuestion() {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [.question: 9999]

        // Even though the text contains "door", expectsReply should override to .question
        throttler.recordAnnouncement(message: "The door is open, should I close it?", expectsReply: true)
        let decision = baseEvaluate(throttler, message: "Any other message?", expectsReply: true)
        #expect(isSuppress(decision))
        #expect(suppressReason(decision)?.contains("question") == true)
    }

    @Test("classify: unrecognized message falls back to general")
    func classifyGeneral() {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [.general: 9999]

        throttler.recordAnnouncement(message: "Something random happened", expectsReply: false)
        let decision = baseEvaluate(throttler, message: "Another random thing")
        #expect(isSuppress(decision))
        #expect(suppressReason(decision)?.contains("general") == true)
    }

    // MARK: - Quiet Hours

    @Test("Suppressed during quiet hours when expectsReply is false")
    func quietHoursSuppression() {
        let throttler = makeQuietHoursThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [:]

        let decision = baseEvaluate(throttler, message: "Hello", expectsReply: false)
        #expect(isSuppress(decision))
    }

    @Test("Allowed during quiet hours when expectsReply is true")
    func quietHoursAllowReply() {
        let throttler = makeQuietHoursThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [:]

        let decision = baseEvaluate(throttler, message: "Should I turn off the lights?", expectsReply: true)
        #expect(isAllow(decision))
    }

    @Test("Not suppressed when current hour is outside quiet window")
    func outsideQuietHours() {
        let throttler = makeNonQuietHoursThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [:]

        let decision = baseEvaluate(throttler, message: "Hello", expectsReply: false)
        #expect(isAllow(decision))
    }

    @Test("Quiet hours disabled allows announcements at any time")
    func quietHoursDisabled() {
        let throttler = makeQuietHoursThrottler()
        throttler.enforceQuietHours = false
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [:]

        let decision = baseEvaluate(throttler, message: "Hello", expectsReply: false)
        #expect(isAllow(decision))
    }

    @Test("Quiet hours boundary: start hour is included")
    func quietHoursBoundaryStart() {
        let throttler = VoiceThrottler()
        let currentHour = Calendar.current.component(.hour, from: Date())
        // Set start to exactly current hour
        throttler.quietHoursStart = currentHour
        throttler.quietHoursEnd = (currentHour + 2) % 24
        throttler.enforceQuietHours = true
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [:]

        let decision = baseEvaluate(throttler, message: "Test", expectsReply: false)
        #expect(isSuppress(decision), "Start hour should be inside quiet window")
    }

    @Test("Quiet hours boundary: end hour is included")
    func quietHoursBoundaryEnd() {
        let throttler = VoiceThrottler()
        let currentHour = Calendar.current.component(.hour, from: Date())
        // Set end to exactly current hour (start 2 hours before)
        throttler.quietHoursStart = (currentHour - 2 + 24) % 24
        throttler.quietHoursEnd = currentHour
        throttler.enforceQuietHours = true
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [:]

        let decision = baseEvaluate(throttler, message: "Test", expectsReply: false)
        #expect(isSuppress(decision), "End hour should be inside quiet window (<=)")
    }

    // MARK: - Per-Category Cooldowns

    @Test("Category cooldown suppresses same-category message")
    func categoryCooldownSuppresses() {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [.doorAlert: 600]

        throttler.recordAnnouncement(message: "The door is open", expectsReply: false)

        let decision = baseEvaluate(throttler, message: "The door is still open")
        #expect(isSuppress(decision))
        #expect(suppressReason(decision)?.contains("doorAlert") == true)
    }

    @Test("Different category is not blocked by another category's cooldown")
    func categoryCooldownIndependent() {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [
            .doorAlert: 9999,
            .energyAlert: 9999
        ]

        // Record a door alert
        throttler.recordAnnouncement(message: "The door is open", expectsReply: false)

        // Energy alert should not be blocked by doorAlert cooldown
        let decision = baseEvaluate(throttler, message: "Power usage is very high")
        #expect(isAllow(decision))
    }

    @Test("Category with no configured cooldown is not suppressed")
    func categoryNoCooldown() {
        let throttler = makeThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [:]  // No category cooldowns at all

        throttler.recordAnnouncement(message: "The door is open", expectsReply: false)

        let decision = baseEvaluate(throttler, message: "Door still open")
        #expect(isAllow(decision))
    }

    // MARK: - expectsReply Interaction with Suppression

    @Test("expectsReply bypasses quiet hours but not global cooldown")
    func expectsReplyBypassesQuietHoursOnly() {
        let throttler = makeQuietHoursThrottler()
        throttler.globalCooldownSeconds = 9999
        throttler.categoryCooldowns = [:]

        // Record first announcement to start global cooldown
        throttler.recordAnnouncement(message: "First", expectsReply: false)

        // expectsReply should bypass quiet hours but still be blocked by global cooldown
        let decision = baseEvaluate(throttler, message: "Want me to adjust?", expectsReply: true)
        #expect(isSuppress(decision), "Global cooldown should still suppress even with expectsReply")
    }

    @Test("expectsReply bypasses quiet hours but not category cooldown")
    func expectsReplyDoesNotBypassCategoryCooldown() {
        let throttler = makeQuietHoursThrottler()
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [.question: 9999]

        // Record a question to start category cooldown
        throttler.recordAnnouncement(message: "Should I lock up?", expectsReply: true)

        // Another question during quiet hours: quiet hours bypassed, but category cooldown applies
        let decision = baseEvaluate(throttler, message: "Should I turn off lights?", expectsReply: true)
        #expect(isSuppress(decision), "Category cooldown should still suppress even with expectsReply")
        #expect(suppressReason(decision)?.contains("question") == true)
    }

    @Test("expectsReply true still suppressed when user is asleep")
    func expectsReplySuppressedDuringSleep() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Should I lock the door?",
            expectsReply: true,
            route: "auto",
            sleepState: "asleepDeep",
            isInEvent: false,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: false,
            airPodsConnected: false
        )
        #expect(isSuppress(decision), "Sleep suppression takes priority over expectsReply")
    }

    // MARK: - Quiet Hours Wrap-Around (Overnight)

    @Test("Quiet hours wrapping midnight: hour inside wrapped window is suppressed")
    func quietHoursWrapAround() {
        let throttler = VoiceThrottler()
        let currentHour = Calendar.current.component(.hour, from: Date())
        // Place current hour at the start boundary of a wrap-around window.
        // hour >= start is always true when start == currentHour (or start == 1 for hour 0).
        if currentHour == 0 {
            throttler.quietHoursStart = 1
            throttler.quietHoursEnd = 0
        } else {
            throttler.quietHoursStart = currentHour
            throttler.quietHoursEnd = currentHour - 1
        }
        throttler.enforceQuietHours = true
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [:]

        #expect(throttler.quietHoursStart > throttler.quietHoursEnd,
                "Test requires start > end for wrap-around branch")

        let decision = baseEvaluate(throttler, message: "Test", expectsReply: false)
        #expect(isSuppress(decision), "Current hour should be inside wrapped quiet window")
    }

    @Test("Quiet hours wrapping midnight: hour outside wrapped window is allowed")
    func quietHoursWrapAroundOutside() {
        let throttler = VoiceThrottler()
        let currentHour = Calendar.current.component(.hour, from: Date())
        // Place current hour OUTSIDE a wrap-around window.
        // For wrap-around (start > end), the outside zone is (end+1)...(start-1).
        // We need: end < currentHour < start, and start > end.
        // Set start = currentHour + 1, end = currentHour - 1.
        // start > end is always true except when they cross the 0 boundary.
        let start: Int
        let end: Int
        if currentHour == 0 {
            // Outside zone of start=2, end=22 is hours 23, 0, 1. Hour 0 is outside.
            start = 2; end = 22
        } else if currentHour == 23 {
            // Outside zone of start=1, end=21 is hours 22, 23, 0. Hour 23 is outside.
            start = 1; end = 21
        } else {
            start = currentHour + 1; end = currentHour - 1
        }

        throttler.quietHoursStart = start
        throttler.quietHoursEnd = end
        throttler.enforceQuietHours = true
        throttler.globalCooldownSeconds = 0
        throttler.categoryCooldowns = [:]

        #expect(throttler.quietHoursStart > throttler.quietHoursEnd,
                "Test requires start > end for wrap-around branch")

        let decision = baseEvaluate(throttler, message: "Test", expectsReply: false)
        #expect(isAllow(decision), "Current hour should be outside wrapped quiet window")
    }

    @Test("expectsReply true still suppressed during calendar event")
    func expectsReplySuppressedDuringEvent() {
        let throttler = makeThrottler()
        let decision = throttler.evaluate(
            message: "Want me to adjust the thermostat?",
            expectsReply: true,
            route: "auto",
            sleepState: nil,
            isInEvent: true,
            cameraInUse: false,
            userIsHome: true,
            houseOccupied: true,
            guestsPresent: false,
            airPodsConnected: false
        )
        #expect(isSuppress(decision), "Event suppression takes priority over expectsReply")
    }
}
