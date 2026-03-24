import Foundation

/// Data sent from iOS or watchOS companion apps to the macOS server via CloudKit.
/// Each source fills in the fields it has — iPhone provides ambient light and screen
/// brightness; Watch provides heart rate, sleep state, workout, and wrist temperature.
struct CompanionData: Codable, Sendable {

    var timestamp: Date
    var source: Source

    /// Per-device identifier (UIDevice.identifierForVendor on iOS, WKInterfaceDevice
    /// on watchOS). Used to distinguish multiple companion devices on the same iCloud
    /// account for occupant counting.
    var deviceID: String?

    var motionActivity: String?
    var latitude: Double?
    var longitude: Double?
    var batteryLevel: Double?

    var ambientLightLux: Double?
    var screenBrightness: Double?

    var airPodsConnected: Bool?
    /// Whether AirPods are currently being worn (in-ear), not just connected.
    /// When false, voice delivery to AirPods is unsafe — they may be on a table.
    var airPodsInEar: Bool?
    var headPosture: String?

    var focusMode: String?
    var approachingHome: Bool?

    var heartRate: Double?
    var heartRateVariability: Double?
    var sleepState: String?
    var isWorkingOut: Bool?
    var wristTemperatureDelta: Double?
    var bloodOxygen: Double?

    enum Source: String, Codable, Sendable {
        case iphone
        case watch
    }

    static let recordType = "CompanionData"
}
