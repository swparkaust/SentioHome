import Foundation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "VoiceThrottle")

/// Enforces cooldowns, quiet hours, and per-category rate limits
/// between the AI's communication output and VoiceService delivery.
@MainActor
final class VoiceThrottler {

    var globalCooldownSeconds: TimeInterval = 300

    var categoryCooldowns: [Category: TimeInterval] = [
        .welcome:       600,   // 10 min — don't re-welcome
        .goodnight:     3600,  // 1 hour — one goodnight is enough
        .statusUpdate:  900,   // 15 min
        .doorAlert:     300,   // 5 min — important but don't nag
        .energyAlert:   600,   // 10 min
        .question:      120,   // 2 min — questions are high-intent
        .general:       300    // 5 min
    ]

    var maxAnnouncementsPerHour = 6

    var quietHoursStart = 23
    var quietHoursEnd = 7
    var enforceQuietHours = true

    private var lastAnnouncementTime: Date?
    private var categoryLastUsed: [Category: Date] = [:]
    private var recentAnnouncements: [Date] = []

    enum Category: String {
        case welcome
        case goodnight
        case statusUpdate
        case doorAlert
        case energyAlert
        case question
        case general
    }

    enum Decision {
        case allow
        case forcePrivate(reason: String)
        case suppress(reason: String)
    }

    func evaluate(
        message: String,
        expectsReply: Bool,
        route: String,
        sleepState: String?,
        isInEvent: Bool,
        cameraInUse: Bool,
        userIsHome: Bool,
        houseOccupied: Bool,
        guestsPresent: Bool,
        airPodsConnected: Bool
    ) -> Decision {

        if let sleep = sleepState,
           ["asleepCore", "asleepDeep", "asleepREM"].contains(sleep) {
            return .suppress(reason: "user is asleep")
        }

        if isInEvent {
            return .suppress(reason: "user is in a calendar event")
        }
        if cameraInUse {
            return .suppress(reason: "camera is in use (likely on a call)")
        }

        if !houseOccupied {
            if airPodsConnected {
                return .forcePrivate(reason: "house empty, routing to AirPods")
            }
            return .suppress(reason: "house is empty — no one to hear it")
        }

        // Guests present: never play personal announcements on shared speakers
        if guestsPresent && !userIsHome {
            return .suppress(reason: "user away, guests present — no personal announcements")
        }
        if guestsPresent && userIsHome {
            if airPodsConnected {
                return .forcePrivate(reason: "guests present, routing to AirPods for privacy")
            }
            return .suppress(reason: "guests present, no AirPods — suppressing to protect privacy")
        }

        if enforceQuietHours && isQuietHour() {
            if !expectsReply {
                return .suppress(reason: "quiet hours (\(quietHoursStart):00–\(quietHoursEnd):00)")
            }
        }

        if let last = lastAnnouncementTime,
           Date().timeIntervalSince(last) < globalCooldownSeconds {
            let remaining = Int(globalCooldownSeconds - Date().timeIntervalSince(last))
            return .suppress(reason: "global cooldown (\(remaining)s remaining)")
        }

        let category = classify(message: message, expectsReply: expectsReply)
        if let categoryLast = categoryLastUsed[category],
           let cooldown = categoryCooldowns[category],
           Date().timeIntervalSince(categoryLast) < cooldown {
            return .suppress(reason: "\(category.rawValue) cooldown")
        }

        pruneOldAnnouncements()
        if recentAnnouncements.count >= maxAnnouncementsPerHour {
            return .suppress(reason: "hourly limit reached (\(maxAnnouncementsPerHour)/hr)")
        }

        return .allow
    }

    func recordAnnouncement(message: String, expectsReply: Bool) {
        let now = Date()
        lastAnnouncementTime = now
        recentAnnouncements.append(now)

        let category = classify(message: message, expectsReply: expectsReply)
        categoryLastUsed[category] = now

        logger.info("Voice delivered [\(category.rawValue)]: \(message.prefix(60))")
    }

    private func classify(message: String, expectsReply: Bool) -> Category {
        if expectsReply { return .question }

        let lower = message.lowercased()

        if lower.contains("welcome") || (lower.contains("home") && lower.contains("back")) {
            return .welcome
        }
        if lower.contains("goodnight") || lower.contains("good night") || lower.contains("sleep") {
            return .goodnight
        }
        if lower.contains("door") || lower.contains("window") || lower.contains("garage") || lower.contains("open") {
            return .doorAlert
        }
        if lower.contains("watt") || lower.contains("power") || lower.contains("energy") || lower.contains("running") {
            return .energyAlert
        }
        if lower.contains("update") || lower.contains("weather") || lower.contains("schedule") {
            return .statusUpdate
        }

        return .general
    }

    private func isQuietHour() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        // <= so the end hour is fully included in quiet period.
        if quietHoursStart > quietHoursEnd {
            return hour >= quietHoursStart || hour <= quietHoursEnd
        } else {
            return hour >= quietHoursStart && hour <= quietHoursEnd
        }
    }

    private func pruneOldAnnouncements() {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        recentAnnouncements.removeAll { $0 < oneHourAgo }
    }
}
