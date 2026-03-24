import Foundation
import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "Context")

/// Gathers all available context — time, weather, location, companion data, device states —
/// and assembles a `HomeContext` for the Intelligence Engine.
/// Merges data from both iPhone and Apple Watch companions.
@MainActor
final class ContextEngine {

    private let homeKit: HomeKitService
    private let cloudSync: CloudSyncService

    var musicAvailable = false
    var musicIsPlaying = false
    var musicTrackName: String?
    var musicMood: String?

    var calendarEvents: [CalendarEvent] = []
    var isInEvent = false
    var macDisplayOn = true
    var macIsIdle = false
    var macFrontmostApp: String?
    var macInferredActivity: String?
    var macCameraInUse = false

    var occupantCount = 1
    var otherOccupantsHome = false

    var guestsLikelyPresent = false
    var guestConfidence: Double = 0
    var guestInferenceReason: String?

    #if canImport(WeatherKit)
    private let weatherService = WeatherService.shared
    #endif

    private let locationManager = CLLocationManager()
    private let locationDelegate = LocationDelegate()

    init(homeKit: HomeKitService, cloudSync: CloudSyncService) {
        self.homeKit = homeKit
        self.cloudSync = cloudSync

        locationManager.delegate = locationDelegate
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 500 // meters

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    func gatherContext() async -> HomeContext {
        let now = Date()
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: now)

        let location = locationManager.location
        let coordinate = location.map {
            HomeContext.Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }

        // Weather (best effort)
        var weatherCondition: String?
        var outsideTemp: Double?
        var humidity: Double?
        var sunrise: Date?
        var sunset: Date?
        var hourlyForecast: [HomeContext.HourlyForecast]?

        #if canImport(WeatherKit)
        if let location {
            do {
                let weather = try await weatherService.weather(for: location)
                weatherCondition = weather.currentWeather.condition.description
                outsideTemp = weather.currentWeather.temperature.value
                humidity = weather.currentWeather.humidity

                let dailyForecast = weather.dailyForecast.first
                sunrise = dailyForecast?.sun.sunrise
                sunset = dailyForecast?.sun.sunset

                let cal = Calendar.current
                hourlyForecast = weather.hourlyForecast
                    .filter { $0.date > now && $0.date < now.addingTimeInterval(6 * 3600) }
                    .prefix(6)
                    .map { hour in
                        HomeContext.HourlyForecast(
                            hour: cal.component(.hour, from: hour.date),
                            temperatureCelsius: hour.temperature.value,
                            condition: hour.condition.description,
                            precipitationChance: hour.precipitationChance,
                            uvIndex: hour.uvIndex.value
                        )
                    }
            } catch {
                logger.warning("Weather fetch failed: \(error.localizedDescription)")
            }
        }
        #endif

        let iPhone = cloudSync.latestIPhoneData
        let watch = cloudSync.latestWatchData

        let bestLocationSource = bestRecent(iPhone, watch, keyPath: \.latitude)
        var userIsHome = determinePresence(companion: bestLocationSource, currentLocation: location)

        let activity = recent(watch)?.motionActivity ?? recent(iPhone)?.motionActivity

        if userIsHome,
           let watchActivity = recent(watch)?.motionActivity,
           (watchActivity == "walking" || watchActivity == "running" || watchActivity == "cycling"),
           let watchLat = recent(watch)?.latitude,
           let watchLon = recent(watch)?.longitude,
           let home = location {
            let watchLocation = CLLocation(latitude: watchLat, longitude: watchLon)
            let distanceFromHome = watchLocation.distance(from: home)
            if distanceFromHome > 100 {
                userIsHome = false
                logger.info("Watch override: user walking \(Int(distanceFromHome))m from home, iPhone left behind")
            }
        }

        if userIsHome,
           let watchActivity = recent(watch)?.motionActivity,
           (watchActivity == "walking" || watchActivity == "running"),
           recent(watch)?.latitude == nil,
           recent(iPhone)?.motionActivity == "stationary" {
            logger.info("Watch reports \(watchActivity) but no GPS — iPhone may be left behind")
        }

        let devices = homeKit.allDeviceSnapshots

        let currentRoom = homeKit.lastMotionRoom
        let motionRooms = homeKit.activeMotionRooms

        let powerReadings = homeKit.powerReadings
        let totalPower = homeKit.totalPowerWatts
        let highPowerDevices = powerReadings.filter { $0.watts > 100 }.map { "\($0.accessoryName): \(Int($0.watts))W" }

        let occupiedRooms = homeKit.occupiedRooms

        let openContacts = homeKit.openContactRooms

        return HomeContext(
            timestamp: now,
            timeOfDay: HomeContext.timeOfDay(from: now),
            dayOfWeek: dayOfWeek,
            isWeekend: dayOfWeek == 1 || dayOfWeek == 7,
            sunriseTime: sunrise,
            sunsetTime: sunset,
            weatherCondition: weatherCondition,
            outsideTemperatureCelsius: outsideTemp,
            humidity: humidity,
            forecast: hourlyForecast?.isEmpty == false ? hourlyForecast : nil,
            userIsHome: userIsHome,
            coordinate: coordinate,
            ambientLightLux: recent(iPhone)?.ambientLightLux,
            deviceMotionActivity: activity,
            screenBrightness: recent(iPhone)?.screenBrightness,
            airPodsConnected: recent(iPhone)?.airPodsConnected,
            airPodsInEar: recent(iPhone)?.airPodsInEar,
            headPosture: recent(iPhone)?.headPosture,
            heartRate: recent(watch)?.heartRate,
            heartRateVariability: recent(watch)?.heartRateVariability,
            sleepState: recent(watch)?.sleepState,
            isWorkingOut: recent(watch)?.isWorkingOut,
            wristTemperatureDelta: recent(watch)?.wristTemperatureDelta,
            bloodOxygen: recent(watch)?.bloodOxygen,
            airPodsAvailable: recent(iPhone)?.airPodsConnected,
            musicAvailable: musicAvailable,
            currentlyPlayingMusic: musicIsPlaying,
            currentMusicTrack: musicTrackName,
            currentMusicMood: musicMood,
            upcomingEvents: calendarEvents.isEmpty ? nil : calendarEvents,
            isInEvent: isInEvent,
            focusMode: recent(iPhone)?.focusMode,
            approachingHome: recent(iPhone)?.approachingHome,
            currentRoom: currentRoom,
            activeMotionRooms: motionRooms.isEmpty ? nil : motionRooms,
            occupiedRooms: occupiedRooms.isEmpty ? nil : occupiedRooms,
            openContacts: openContacts.isEmpty ? nil : openContacts,
            totalPowerWatts: totalPower > 0 ? totalPower : nil,
            highPowerDevices: highPowerDevices.isEmpty ? nil : highPowerDevices,
            macDisplayOn: macDisplayOn,
            macIsIdle: macIsIdle,
            macFrontmostApp: macFrontmostApp,
            macInferredActivity: macInferredActivity,
            macCameraInUse: macCameraInUse,
            occupantCount: occupantCount > 1 ? occupantCount : nil,
            otherOccupantsHome: otherOccupantsHome ? true : nil,
            guestsLikelyPresent: guestsLikelyPresent ? true : nil,
            guestConfidence: guestsLikelyPresent ? guestConfidence : nil,
            guestInferenceReason: guestsLikelyPresent ? guestInferenceReason : nil,
            devices: devices
        )
    }

    // MARK: - Helpers (delegates to PresenceLogic for testability)

    private func recent(_ data: CompanionData?) -> CompanionData? {
        PresenceLogic.recent(data)
    }

    private func bestRecent(_ a: CompanionData?, _ b: CompanionData?, keyPath: KeyPath<CompanionData, Double?>) -> CompanionData? {
        PresenceLogic.bestRecent(a, b, keyPath: keyPath)
    }

    private func determinePresence(companion: CompanionData?, currentLocation: CLLocation?) -> Bool {
        PresenceLogic.determinePresence(companion: companion, homeLocation: currentLocation)
    }
}

// MARK: - Location Delegate

private class LocationDelegate: NSObject, CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}
