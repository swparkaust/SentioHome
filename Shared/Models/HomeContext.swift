import Foundation

/// A complete snapshot of the user's current context, fed to the Intelligence Engine
/// so it can make informed automation decisions.
struct HomeContext: Codable, Sendable {

    // MARK: - Temporal

    var timestamp: Date
    var timeOfDay: TimeOfDay
    var dayOfWeek: Int          // 1 = Sunday … 7 = Saturday
    var isWeekend: Bool

    // MARK: - Environmental

    var sunriseTime: Date?
    var sunsetTime: Date?
    var weatherCondition: String?   // e.g. "sunny", "rainy", "cloudy"
    var outsideTemperatureCelsius: Double?
    var humidity: Double?
    var forecast: [HourlyForecast]? // Next several hours of weather

    var userIsHome: Bool
    var coordinate: Coordinate?

    // MARK: - iPhone Sensor Data

    var ambientLightLux: Double?
    var deviceMotionActivity: String?   // "stationary", "walking", "running", "driving"
    var screenBrightness: Double?       // 0…1

    // MARK: - AirPods Data (via iPhone)

    var airPodsConnected: Bool?
    var airPodsInEar: Bool?
    var headPosture: String?

    // MARK: - Watch Health Data

    var heartRate: Double?              // bpm
    var heartRateVariability: Double?   // ms (SDNN)
    var sleepState: String?             // "awake", "inBed", "asleepCore", "asleepDeep", "asleepREM"
    var isWorkingOut: Bool?
    var wristTemperatureDelta: Double?  // °C deviation from baseline
    var bloodOxygen: Double?            // 0…1

    var airPodsAvailable: Bool?

    // MARK: - Music State

    var musicAvailable: Bool?
    var currentlyPlayingMusic: Bool?
    var currentMusicTrack: String?
    var currentMusicMood: String?

    var upcomingEvents: [CalendarEvent]?
    var isInEvent: Bool?
    var focusMode: String?

    // MARK: - Presence Detail

    var approachingHome: Bool?              // Geofence triggered — user is nearby but not yet home
    var currentRoom: String?                // Room with most recent motion detection
    var activeMotionRooms: [String]?        // All rooms with active motion sensors
    var occupiedRooms: [String]?            // Rooms with occupancy sensors detecting presence
    var openContacts: [String]?             // Open door/window contact sensors

    var totalPowerWatts: Double?
    var highPowerDevices: [String]?

    // MARK: - Mac Screen State

    var macDisplayOn: Bool?
    var macIsIdle: Bool?
    var macFrontmostApp: String?
    var macInferredActivity: String?         // "video call", "watching media", "coding", etc.
    var macCameraInUse: Bool?

    var occupantCount: Int?
    var otherOccupantsHome: Bool?

    // MARK: - Guest Detection

    var guestsLikelyPresent: Bool?
    var guestConfidence: Double?
    var guestInferenceReason: String?

    var devices: [DeviceSnapshot]

    enum TimeOfDay: String, Codable, Sendable {
        case earlyMorning   // 05–07
        case morning        // 08–11
        case afternoon      // 12–16
        case evening        // 17–20
        case night          // 21–23
        case lateNight      // 00–04
    }

    struct Coordinate: Codable, Sendable {
        var latitude: Double
        var longitude: Double
    }

    struct HourlyForecast: Codable, Sendable {
        var hour: Int                       // 0–23
        var temperatureCelsius: Double
        var condition: String               // e.g. "sunny", "rain", "cloudy"
        var precipitationChance: Double     // 0–1
        var uvIndex: Int
    }

    static func timeOfDay(from date: Date) -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<8:   return .earlyMorning
        case 8..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        case 21..<24: return .night
        default:      return .lateNight
        }
    }
}
