import Foundation

struct CalendarEvent: Codable, Sendable {
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String?
    var hasAlarms: Bool

    var promptDescription: String {
        let timeRange = "\(formatted(startDate))–\(formatted(endDate))"
        var desc = "• \(sanitizeForPrompt(title)) (\(timeRange))"
        if let location, !location.isEmpty {
            desc += " at \(sanitizeForPrompt(location))"
        }
        return desc
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
