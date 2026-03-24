import Testing
import Foundation
@testable import SentioKit


@Suite("CompanionData")
struct CompanionDataTests {

    // MARK: - Source

    @Test("Source raw values are correct")
    func sourceRawValues() {
        #expect(CompanionData.Source.iphone.rawValue == "iphone")
        #expect(CompanionData.Source.watch.rawValue == "watch")
    }

    // MARK: - Codable

    @Test("iPhone CompanionData round-trips through JSON")
    func iPhoneCodable() throws {
        let data = CompanionData(
            timestamp: Date(),
            source: .iphone,
            motionActivity: "stationary",
            latitude: 37.7749,
            longitude: -122.4194,
            batteryLevel: 0.85,
            ambientLightLux: 500,
            screenBrightness: 0.7,
            airPodsConnected: true,
            airPodsInEar: true,
            headPosture: "upright",
            focusMode: "work",
            approachingHome: false
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(CompanionData.self, from: encoded)

        #expect(decoded.source == .iphone)
        #expect(decoded.motionActivity == "stationary")
        #expect(decoded.latitude == 37.7749)
        #expect(decoded.longitude == -122.4194)
        #expect(decoded.batteryLevel == 0.85)
        #expect(decoded.ambientLightLux == 500)
        #expect(decoded.screenBrightness == 0.7)
        #expect(decoded.airPodsConnected == true)
        #expect(decoded.airPodsInEar == true)
        #expect(decoded.headPosture == "upright")
        #expect(decoded.focusMode == "work")
        #expect(decoded.approachingHome == false)
    }

    @Test("Watch CompanionData round-trips through JSON")
    func watchCodable() throws {
        let data = CompanionData(
            timestamp: Date(),
            source: .watch,
            motionActivity: "walking",
            latitude: 37.78,
            longitude: -122.42,
            heartRate: 85,
            heartRateVariability: 45,
            sleepState: "awake",
            isWorkingOut: false,
            wristTemperatureDelta: 0.3,
            bloodOxygen: 0.98
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(CompanionData.self, from: encoded)

        #expect(decoded.source == .watch)
        #expect(decoded.heartRate == 85)
        #expect(decoded.heartRateVariability == 45)
        #expect(decoded.sleepState == "awake")
        #expect(decoded.isWorkingOut == false)
        #expect(decoded.wristTemperatureDelta == 0.3)
        #expect(decoded.bloodOxygen == 0.98)
    }

    @Test("Minimal CompanionData with only required fields")
    func minimalData() throws {
        let data = CompanionData(
            timestamp: Date(),
            source: .iphone
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(CompanionData.self, from: encoded)

        #expect(decoded.source == .iphone)
        #expect(decoded.motionActivity == nil)
        #expect(decoded.latitude == nil)
        #expect(decoded.heartRate == nil)
        #expect(decoded.airPodsConnected == nil)
    }
}
