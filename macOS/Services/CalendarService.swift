import Foundation
import EventKit
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "Calendar")

/// Reads the user's calendar events via EventKit to provide schedule context
/// for the Intelligence Engine. Fully on-device, no network calls.
@Observable
@MainActor
final class CalendarService {

    private(set) var upcomingEvents: [CalendarEvent] = []
    private(set) var isInEvent = false

    private let store = EKEventStore()
    private var authorized = false

    func requestAccess() async {
        do {
            authorized = try await store.requestFullAccessToEvents()
            logger.info("EventKit access granted: \(self.authorized)")
        } catch {
            logger.warning("EventKit access denied: \(error.localizedDescription)")
        }
    }

    func refreshEvents(lookAheadMinutes: Double = 120) {
        guard authorized else { return }

        let now = Date()
        let end = now.addingTimeInterval(lookAheadMinutes * 60)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        upcomingEvents = ekEvents
            .filter { !$0.isAllDay }  // Skip all-day events — they don't imply the user is busy
            .sorted { $0.startDate < $1.startDate }
            .prefix(10)
            .map { event in
                CalendarEvent(
                    title: event.title ?? "Untitled",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    hasAlarms: !(event.alarms?.isEmpty ?? true)
                )
            }

        isInEvent = upcomingEvents.contains { $0.startDate <= now && $0.endDate > now }
    }
}
