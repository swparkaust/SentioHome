import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "GuestDetection")

/// Infers the presence of guests (people without the companion app) by
/// combining multiple passive signals: calendar events, motion patterns,
/// contact sensors, and the primary user's known location.
///
/// Each signal contributes a confidence score. When the combined score
/// exceeds a threshold, the system reports "guests likely present."
@Observable
@MainActor
final class GuestDetectionService {

    private(set) var guestsLikelyPresent = false
    private(set) var inferenceReason: String?
    private(set) var confidence: Double = 0
    private(set) var signals: [Signal] = []

    private let confidenceThreshold = 0.5

    /// In apartment mode, require at least this many independent signals
    /// above 0.2 before reporting guest presence. Prevents single-signal
    /// false positives from shared walls, hallways, and common areas.
    var apartmentMode = true
    private let apartmentMinimumSignals = 2

    struct Signal: Sendable {
        let name: String
        let score: Double      // 0.0–1.0
        let detail: String
    }

    // MARK: - Evaluation

    func evaluate(
        calendarEvents: [CalendarEvent],
        isInEvent: Bool,
        userIsHome: Bool,
        userCurrentRoom: String?,
        activeMotionRooms: [String],
        occupiedRooms: [String] = [],
        openContacts: [String],
        userActivity: String?,
        timeOfDay: HomeContext.TimeOfDay,
        networkDiscovery: NetworkDiscoveryService? = nil,
        bleScanner: BLEScannerService? = nil
    ) {
        var newSignals: [Signal] = []

        let calendarScore = evaluateCalendar(events: calendarEvents, isInEvent: isInEvent)
        if calendarScore.score > 0 {
            newSignals.append(calendarScore)
        }

        let motionScore = evaluateMotionPattern(
            userRoom: userCurrentRoom,
            activeRooms: activeMotionRooms,
            userActivity: userActivity,
            userIsHome: userIsHome
        )
        if motionScore.score > 0 {
            newSignals.append(motionScore)
        }

        let doorScore = evaluateDoorActivity(
            openContacts: openContacts,
            userIsHome: userIsHome,
            userActivity: userActivity
        )
        if doorScore.score > 0 {
            newSignals.append(doorScore)
        }

        let timeScore = evaluateTimeBias(timeOfDay: timeOfDay)
        if timeScore.score > 0 {
            newSignals.append(timeScore)
        }

        let occupancyScore = evaluateOccupancy(
            occupiedRooms: occupiedRooms,
            userRoom: userCurrentRoom,
            userIsHome: userIsHome
        )
        if occupancyScore.score > 0 {
            newSignals.append(occupancyScore)
        }

        if let network = networkDiscovery, network.guestSignalScore > 0 {
            newSignals.append(Signal(
                name: "network",
                score: network.guestSignalScore,
                detail: network.signalDetail
            ))
        }

        if let ble = bleScanner, !ble.bluetoothDenied, ble.guestSignalScore > 0 {
            newSignals.append(Signal(
                name: "bluetooth",
                score: ble.guestSignalScore,
                detail: ble.signalDetail
            ))
        }

        signals = newSignals
        if newSignals.isEmpty {
            confidence = 0
        } else {
            let sorted = newSignals.sorted { $0.score > $1.score }
            var combined = sorted[0].score
            for signal in sorted.dropFirst() {
                combined += signal.score * 0.3 * (1.0 - combined)
            }
            confidence = min(combined, 1.0)
        }

        let wasPresent = guestsLikelyPresent

        let significantSignals = newSignals.filter { $0.score > 0.2 }.count
        if apartmentMode {
            guestsLikelyPresent = confidence >= confidenceThreshold
                && significantSignals >= apartmentMinimumSignals
        } else {
            guestsLikelyPresent = confidence >= confidenceThreshold
        }

        if guestsLikelyPresent {
            inferenceReason = newSignals
                .filter { $0.score > 0.2 }
                .map(\.detail)
                .joined(separator: "; ")
        } else {
            inferenceReason = nil
        }

        if guestsLikelyPresent != wasPresent {
            logger.info("Guest presence changed: \(self.guestsLikelyPresent) (confidence: \(String(format: "%.2f", self.confidence)), signals: \(significantSignals))")
        }
    }

    // MARK: - Individual Signal Evaluators

    private func evaluateCalendar(events: [CalendarEvent], isInEvent: Bool) -> Signal {
        let guestKeywords = [
            "dinner", "party", "visit", "guest", "hosting", "gathering",
            "bbq", "barbecue", "brunch", "lunch with", "drinks",
            "game night", "movie night", "hangout", "get-together",
            "birthday", "celebration", "potluck", "housewarming"
        ]

        for event in events {
            let titleLower = event.title.lowercased()
            for keyword in guestKeywords {
                if titleLower.contains(keyword) {
                    let isCurrent = event.startDate <= Date() && event.endDate > Date()
                    let score: Double = isCurrent ? 0.8 : 0.5
                    return Signal(
                        name: "calendar",
                        score: score,
                        detail: isCurrent
                            ? "calendar event suggests guests now"
                            : "upcoming event suggests guests soon"
                    )
                }
            }

            if let location = event.location?.lowercased(),
               (location.contains("home") || location.contains("my place") || location.isEmpty) {
                let isCurrent = event.startDate <= Date() && event.endDate > Date()
                if isCurrent {
                    return Signal(name: "calendar", score: 0.4, detail: "event at home in progress")
                }
            }
        }

        return Signal(name: "calendar", score: 0, detail: "")
    }

    private func evaluateMotionPattern(
        userRoom: String?,
        activeRooms: [String],
        userActivity: String?,
        userIsHome: Bool
    ) -> Signal {
        guard userIsHome else {
            if !activeRooms.isEmpty {
                return Signal(
                    name: "motion",
                    score: 0.4,
                    detail: "motion detected while user is away"
                )
            }
            return Signal(name: "motion", score: 0, detail: "")
        }

        guard let userRoom else {
            return Signal(name: "motion", score: 0, detail: "")
        }

        let isStationary = userActivity == "stationary" || userActivity == nil

        let otherRooms = activeRooms.filter { $0 != userRoom }

        if isStationary && otherRooms.count >= 2 {
            return Signal(
                name: "motion",
                score: 0.7,
                detail: "motion in \(otherRooms.count) rooms while user is in \(userRoom)"
            )
        } else if isStationary && otherRooms.count == 1 {
            return Signal(
                name: "motion",
                score: 0.4,
                detail: "motion in \(otherRooms[0]) while user is in \(userRoom)"
            )
        }

        return Signal(name: "motion", score: 0, detail: "")
    }

    private func evaluateDoorActivity(
        openContacts: [String],
        userIsHome: Bool,
        userActivity: String?
    ) -> Signal {
        guard userIsHome,
              userActivity == "stationary" || userActivity == nil,
              !openContacts.isEmpty else {
            return Signal(name: "door", score: 0, detail: "")
        }

        let entryKeywords = ["front", "entry", "main", "door"]
        let isEntryDoor = openContacts.contains { contact in
            let lower = contact.lowercased()
            return entryKeywords.contains { lower.contains($0) }
        }

        if isEntryDoor {
            return Signal(
                name: "door",
                score: 0.5,
                detail: "entry door opened while user is stationary"
            )
        }

        return Signal(name: "door", score: 0.2, detail: "door/window opened")
    }

    /// Occupancy sensors detecting presence in rooms the user isn't in.
    /// Occupancy sensors (mmWave/PIR) detect sustained presence, making
    /// them more reliable than motion sensors for stationary guests.
    private func evaluateOccupancy(
        occupiedRooms: [String],
        userRoom: String?,
        userIsHome: Bool
    ) -> Signal {
        guard userIsHome, !occupiedRooms.isEmpty else {
            return Signal(name: "occupancy", score: 0, detail: "")
        }

        let otherOccupied = occupiedRooms.filter { $0 != userRoom }

        if otherOccupied.count >= 2 {
            return Signal(
                name: "occupancy",
                score: 0.75,
                detail: "occupancy detected in \(otherOccupied.count) rooms user isn't in"
            )
        } else if otherOccupied.count == 1 {
            return Signal(
                name: "occupancy",
                score: 0.5,
                detail: "occupancy detected in \(otherOccupied[0]) while user is elsewhere"
            )
        }

        return Signal(name: "occupancy", score: 0, detail: "")
    }

    private func evaluateTimeBias(timeOfDay: HomeContext.TimeOfDay) -> Signal {
        switch timeOfDay {
        case .evening:
            return Signal(name: "time", score: 0.15, detail: "evening — social hours")
        case .afternoon:
            return Signal(name: "time", score: 0.1, detail: "afternoon — possible visitors")
        case .night:
            return Signal(name: "time", score: 0.1, detail: "night — possible late guests")
        default:
            return Signal(name: "time", score: 0, detail: "")
        }
    }
}
