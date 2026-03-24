import Foundation

/// Alert types for safety-critical HomeKit events.
enum EmergencyAlertType: String, Codable, Sendable {
    case smoke = "smoke"
    case carbonMonoxide = "carbonMonoxide"
    case carbonDioxide = "carbonDioxide"
    case waterLeak = "waterLeak"

    var title: String {
        switch self {
        case .smoke:          return "Smoke Detected"
        case .carbonMonoxide: return "Carbon Monoxide Detected"
        case .carbonDioxide:  return "High CO₂ Detected"
        case .waterLeak:      return "Water Leak Detected"
        }
    }

    var severity: EmergencyAlertSeverity {
        switch self {
        case .smoke, .carbonMonoxide: return .critical
        case .waterLeak:              return .urgent
        case .carbonDioxide:          return .warning
        }
    }
}

enum EmergencyAlertSeverity: Int, Comparable, Codable, Sendable {
    case warning = 0
    case urgent = 1
    case critical = 2

    static func < (lhs: EmergencyAlertSeverity, rhs: EmergencyAlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
