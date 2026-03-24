import Foundation

/// Records a single instance where the user manually changed a device
/// shortly after the AI automated it — signaling a preference.
struct UserOverride: Codable, Sendable, Identifiable {

    var id: UUID
    var timestamp: Date

    var accessoryID: String
    var accessoryName: String
    var roomName: String?
    var characteristic: String
    var aiSetValue: Double
    var aiReason: String
    var userSetValue: Double

    var timeOfDay: HomeContext.TimeOfDay
    var dayOfWeek: Int
    var isWeekend: Bool
    var weatherCondition: String?
    var userWasHome: Bool

    var promptDescription: String {
        let time = "\(timeOfDay.rawValue), \(isWeekend ? "weekend" : "weekday")"
        let weather = weatherCondition.map { ", \(sanitizeForPrompt($0))" } ?? ""
        let room = roomName.map { " in \(sanitizeForPrompt($0))" } ?? ""

        return "- \(sanitizeForPrompt(accessoryName))\(room): AI set \(sanitizeForPrompt(characteristic)) to \(formatted(aiSetValue)) " +
               "(\"\(sanitizeForPrompt(aiReason))\"), user changed it to \(formatted(userSetValue)). " +
               "Context: \(time)\(weather)."
    }

    private func formatted(_ value: Double) -> String {
        switch characteristic {
        case "on":
            return value >= 1 ? "on" : "off"
        case "brightness", "saturation":
            return "\(Int(value))%"
        case "hue":
            return "\(Int(value))°"
        case "targetTemperature":
            return String(format: "%.1f°C", value)
        default:
            return String(format: "%.1f", value)
        }
    }
}
