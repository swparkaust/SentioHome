import Foundation

/// Strip newlines and markdown heading markers from external strings
/// to prevent prompt injection via user-controlled names.
func sanitizeForPrompt(_ input: String) -> String {
    input.replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "#", with: "")
}

struct DeviceSnapshot: Codable, Sendable, Identifiable {

    var id: String
    var name: String
    var roomName: String?
    var category: String
    var characteristics: [CharacteristicValue]
    var isReachable: Bool

    struct CharacteristicValue: Codable, Sendable {
        var type: String
        var value: Double?
        var label: String
    }

    var promptDescription: String {
        let room = sanitizeForPrompt(roomName ?? "Unknown Room")
        let safeName = sanitizeForPrompt(name)
        let state = characteristics
            .compactMap { c -> String? in
                guard let v = c.value else { return nil }
                return "\(c.type)=\(formatted(v, for: c.type))"
            }
            .joined(separator: ", ")
        let reachable = isReachable ? "" : " [unreachable]"
        return "• [\(sanitizeForPrompt(id))] \(safeName) (\(category), \(room)) — \(state)\(reachable)"
    }

    private func formatted(_ value: Double, for type: String) -> String {
        switch type {
        case "on":
            return value >= 1 ? "on" : "off"
        case "brightness", "saturation":
            return "\(Int(value))%"
        case "hue":
            return "\(Int(value))°"
        case "targetTemperature", "currentTemperature":
            return String(format: "%.1f°C", value)
        case "active":
            return value >= 1 ? "active" : "inactive"
        case "rotationSpeed":
            return "\(Int(value)) rpm"
        case "motionDetected":
            return value >= 1 ? "detected" : "clear"
        case "contactState":
            return value >= 1 ? "open" : "closed"
        case "currentHumidity":
            return "\(Int(value))%"
        case "currentDoorState", "targetDoorState":
            return value == 0 ? "open" : value == 1 ? "closed" : "unknown"
        default:
            return String(format: "%.1f", value)
        }
    }
}
