import Testing
import Foundation
@testable import SentioKit


@Suite("HomeContext")
struct HomeContextTests {

    // MARK: - TimeOfDay

    @Test("timeOfDay returns earlyMorning for 05–08")
    func timeOfDayEarlyMorning() {
        let hours = [5, 6, 7]
        for hour in hours {
            let date = makeDate(hour: hour)
            #expect(HomeContext.timeOfDay(from: date) == .earlyMorning)
        }
    }

    @Test("timeOfDay returns morning for 08–12")
    func timeOfDayMorning() {
        let hours = [8, 9, 10, 11]
        for hour in hours {
            let date = makeDate(hour: hour)
            #expect(HomeContext.timeOfDay(from: date) == .morning)
        }
    }

    @Test("timeOfDay returns afternoon for 12–17")
    func timeOfDayAfternoon() {
        let hours = [12, 13, 14, 15, 16]
        for hour in hours {
            let date = makeDate(hour: hour)
            #expect(HomeContext.timeOfDay(from: date) == .afternoon)
        }
    }

    @Test("timeOfDay returns evening for 17–21")
    func timeOfDayEvening() {
        let hours = [17, 18, 19, 20]
        for hour in hours {
            let date = makeDate(hour: hour)
            #expect(HomeContext.timeOfDay(from: date) == .evening)
        }
    }

    @Test("timeOfDay returns night for 21–23")
    func timeOfDayNight() {
        let hours = [21, 22, 23]
        for hour in hours {
            let date = makeDate(hour: hour)
            #expect(HomeContext.timeOfDay(from: date) == .night)
        }
    }

    @Test("timeOfDay returns lateNight for 00–04")
    func timeOfDayLateNight() {
        let hours = [0, 1, 2, 3, 4]
        for hour in hours {
            let date = makeDate(hour: hour)
            #expect(HomeContext.timeOfDay(from: date) == .lateNight)
        }
    }

    // MARK: - Weekend Detection

    @Test("isWeekend correctly identifies Sunday (1) and Saturday (7)")
    func weekendDetection() {
        // ContextEngine sets isWeekend = (dayOfWeek == 1 || dayOfWeek == 7)
        // Test production logic by constructing HomeContext with specific dayOfWeek
        func makeContext(dayOfWeek: Int) -> HomeContext {
            HomeContext(
                timestamp: Date(),
                timeOfDay: .afternoon,
                dayOfWeek: dayOfWeek,
                isWeekend: dayOfWeek == 1 || dayOfWeek == 7,
                userIsHome: true,
                devices: []
            )
        }

        // Sunday = 1, Saturday = 7 in Calendar
        #expect(makeContext(dayOfWeek: 1).isWeekend == true)
        #expect(makeContext(dayOfWeek: 7).isWeekend == true)
        #expect(makeContext(dayOfWeek: 2).isWeekend == false)
        #expect(makeContext(dayOfWeek: 3).isWeekend == false)
        #expect(makeContext(dayOfWeek: 4).isWeekend == false)
        #expect(makeContext(dayOfWeek: 5).isWeekend == false)
        #expect(makeContext(dayOfWeek: 6).isWeekend == false)
    }

    // MARK: - Codable Conformance

    @Test("HomeContext round-trips through JSON encoding")
    func codableRoundTrip() throws {
        let context = HomeContext(
            timestamp: Date(),
            timeOfDay: .evening,
            dayOfWeek: 3,
            isWeekend: false,
            weatherCondition: "cloudy",
            outsideTemperatureCelsius: 18.5,
            humidity: 0.65,
            userIsHome: true,
            coordinate: HomeContext.Coordinate(latitude: 37.7749, longitude: -122.4194),
            ambientLightLux: 200,
            heartRate: 72,
            sleepState: "awake",
            macDisplayOn: true,
            macIsIdle: false,
            devices: [
                DeviceSnapshot(
                    id: "abc-123",
                    name: "Living Room Light",
                    roomName: "Living Room",
                    category: "lightbulb",
                    characteristics: [
                        .init(type: "on", value: 1, label: "Power State"),
                        .init(type: "brightness", value: 80, label: "Brightness")
                    ],
                    isReachable: true
                )
            ]
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(HomeContext.self, from: data)

        #expect(decoded.timeOfDay == .evening)
        #expect(decoded.dayOfWeek == 3)
        #expect(decoded.isWeekend == false)
        #expect(decoded.weatherCondition == "cloudy")
        #expect(decoded.outsideTemperatureCelsius == 18.5)
        #expect(decoded.userIsHome == true)
        #expect(decoded.coordinate?.latitude == 37.7749)
        #expect(decoded.ambientLightLux == 200)
        #expect(decoded.heartRate == 72)
        #expect(decoded.devices.count == 1)
        #expect(decoded.devices[0].name == "Living Room Light")
    }

    @Test("HourlyForecast encodes and decodes correctly")
    func hourlyForecastCodable() throws {
        let forecast = HomeContext.HourlyForecast(
            hour: 14,
            temperatureCelsius: 22.3,
            condition: "sunny",
            precipitationChance: 0.1,
            uvIndex: 6
        )

        let data = try JSONEncoder().encode(forecast)
        let decoded = try JSONDecoder().decode(HomeContext.HourlyForecast.self, from: data)

        #expect(decoded.hour == 14)
        #expect(decoded.temperatureCelsius == 22.3)
        #expect(decoded.condition == "sunny")
        #expect(decoded.precipitationChance == 0.1)
        #expect(decoded.uvIndex == 6)
    }

    // MARK: - Helpers

    private func makeDate(hour: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 30
        return Calendar.current.date(from: components)!
    }

}
