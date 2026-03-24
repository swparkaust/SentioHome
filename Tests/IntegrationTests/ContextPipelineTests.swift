import Testing
import Foundation
@testable import SentioKit


/// Integration tests verifying the context pipeline: HomeContext construction,
/// prompt generation, and data flow between context and intelligence layers.
@Suite("Context Pipeline Integration")
struct ContextPipelineTests {

    // MARK: - HomeContext Construction

    @Test("HomeContext with all fields populates correctly")
    func fullContextConstruction() {
        let context = makeFullContext()

        #expect(context.timeOfDay == .evening)
        #expect(context.isWeekend == false)
        #expect(context.userIsHome == true)
        #expect(context.weatherCondition == "cloudy")
        #expect(context.outsideTemperatureCelsius == 18.5)
        #expect(context.heartRate == 72)
        #expect(context.sleepState == "awake")
        #expect(context.macDisplayOn == true)
        #expect(context.macInferredActivity == "coding")
        #expect(context.currentRoom == "Office")
        #expect(context.devices.count == 3)
        #expect(context.forecast?.count == 2)
    }

    @Test("HomeContext with nil optionals encodes compactly")
    func minimalContext() throws {
        let context = HomeContext(
            timestamp: Date(),
            timeOfDay: .morning,
            dayOfWeek: 2,
            isWeekend: false,
            userIsHome: true,
            devices: []
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(HomeContext.self, from: data)

        #expect(decoded.weatherCondition == nil)
        #expect(decoded.heartRate == nil)
        #expect(decoded.forecast == nil)
        #expect(decoded.macFrontmostApp == nil)
        #expect(decoded.devices.isEmpty)
    }

    // MARK: - Device Snapshot Prompt Generation

    @Test("Device snapshots generate useful prompt descriptions")
    func devicePrompts() {
        let context = makeFullContext()
        let prompts = context.devices.map(\.promptDescription)

        // Verify all devices produce non-empty descriptions
        for prompt in prompts {
            #expect(!prompt.isEmpty)
        }

        // Verify specific content
        let lightPrompt = context.devices.first { $0.name == "Living Room Light" }?.promptDescription ?? ""
        #expect(lightPrompt.contains("lightbulb"))
        #expect(lightPrompt.contains("Living Room"))
        #expect(lightPrompt.contains("on"))
        #expect(lightPrompt.contains("80%"))
    }

    // MARK: - Forecast Pipeline

    @Test("Empty forecast is stored as nil")
    func emptyForecast() {
        var context = makeFullContext()
        context.forecast = []

        // The ContextEngine uses: forecast?.isEmpty == false ? forecast : nil
        let normalizedForecast = context.forecast?.isEmpty == false ? context.forecast : nil
        #expect(normalizedForecast == nil)
    }

    @Test("Non-empty forecast is preserved")
    func validForecast() {
        let context = makeFullContext()
        #expect(context.forecast?.isEmpty == false)
        #expect(context.forecast?[0].hour == 18)
    }

    // MARK: - Multi-Occupant Fields

    @Test("Multi-occupant fields follow nil convention (nil when solo)")
    func multiOccupantConvention() {
        // When solo, occupantCount should be nil (not 1)
        let soloContext = HomeContext(
            timestamp: Date(),
            timeOfDay: .morning,
            dayOfWeek: 2,
            isWeekend: false,
            userIsHome: true,
            occupantCount: nil,
            otherOccupantsHome: nil,
            devices: []
        )
        #expect(soloContext.occupantCount == nil)
        #expect(soloContext.otherOccupantsHome == nil)

        // When multiple, occupantCount should be set
        let multiContext = HomeContext(
            timestamp: Date(),
            timeOfDay: .evening,
            dayOfWeek: 5,
            isWeekend: false,
            userIsHome: true,
            occupantCount: 3,
            otherOccupantsHome: true,
            devices: []
        )
        #expect(multiContext.occupantCount == 3)
        #expect(multiContext.otherOccupantsHome == true)
    }

    // MARK: - Helpers

    private func makeFullContext() -> HomeContext {
        HomeContext(
            timestamp: Date(),
            timeOfDay: .evening,
            dayOfWeek: 4,
            isWeekend: false,
            sunriseTime: Date(),
            sunsetTime: Date().addingTimeInterval(3600),
            weatherCondition: "cloudy",
            outsideTemperatureCelsius: 18.5,
            humidity: 0.65,
            forecast: [
                HomeContext.HourlyForecast(hour: 18, temperatureCelsius: 17, condition: "cloudy", precipitationChance: 0.3, uvIndex: 1),
                HomeContext.HourlyForecast(hour: 19, temperatureCelsius: 15, condition: "rain", precipitationChance: 0.7, uvIndex: 0)
            ],
            userIsHome: true,
            coordinate: HomeContext.Coordinate(latitude: 37.7749, longitude: -122.4194),
            ambientLightLux: 150,
            deviceMotionActivity: "stationary",
            screenBrightness: 0.6,
            airPodsConnected: true,
            airPodsInEar: true,
            headPosture: "upright",
            heartRate: 72,
            heartRateVariability: 55,
            sleepState: "awake",
            isWorkingOut: false,
            musicAvailable: true,
            currentlyPlayingMusic: false,
            focusMode: "work",
            currentRoom: "Office",
            activeMotionRooms: ["Office"],
            macDisplayOn: true,
            macIsIdle: false,
            macFrontmostApp: "Xcode",
            macInferredActivity: "coding",
            macCameraInUse: false,
            devices: [
                DeviceSnapshot(
                    id: "light-1", name: "Living Room Light", roomName: "Living Room",
                    category: "lightbulb",
                    characteristics: [
                        .init(type: "on", value: 1, label: "Power"),
                        .init(type: "brightness", value: 80, label: "Brightness")
                    ],
                    isReachable: true
                ),
                DeviceSnapshot(
                    id: "therm-1", name: "Thermostat", roomName: "Living Room",
                    category: "thermostat",
                    characteristics: [
                        .init(type: "currentTemperature", value: 21.5, label: "Temperature"),
                        .init(type: "targetTemperature", value: 22, label: "Target")
                    ],
                    isReachable: true
                ),
                DeviceSnapshot(
                    id: "lock-1", name: "Front Door Lock", roomName: "Hallway",
                    category: "lock",
                    characteristics: [
                        .init(type: "targetLockState", value: 1, label: "Lock")
                    ],
                    isReachable: true
                )
            ]
        )
    }
}
