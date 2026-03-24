import Foundation

/// A compressed long-term preference pattern derived from many individual overrides.
/// Captures seasonal or habitual preferences that persist beyond the 30-day override window.
struct SeasonalSummary: Codable, Sendable, Identifiable {
    var id = UUID()
    var accessoryName: String
    var characteristic: String
    var preferredValue: Double
    var context: String
    var months: [String]
    var sampleCount: Int
    var lastUpdated: Date

    var promptDescription: String {
        let valueStr: String
        switch characteristic {
        case "on":
            valueStr = preferredValue >= 1 ? "on" : "off"
        case "brightness", "saturation":
            valueStr = "\(Int(preferredValue))%"
        case "hue":
            valueStr = "\(Int(preferredValue))°"
        case "targetTemperature":
            valueStr = String(format: "%.1f°C", preferredValue)
        default:
            valueStr = String(format: "%.1f", preferredValue)
        }

        let monthRange: String
        if months.count > 2, let first = months.first, let last = months.last {
            monthRange = "\(first)–\(last)"
        } else {
            monthRange = months.joined(separator: ", ")
        }

        return "• \(sanitizeForPrompt(accessoryName)) \(sanitizeForPrompt(characteristic)) → \(valueStr) on \(sanitizeForPrompt(context)) during \(monthRange) (based on \(sampleCount) corrections)"
    }
}
