import Testing
import Foundation
@testable import SentioKit

@Suite("EmergencyAlert")
struct EmergencyAlertTests {

    // MARK: - AlertType titles

    @Test("Smoke alert has correct title")
    func smokeTitle() {
        #expect(EmergencyAlertType.smoke.title == "Smoke Detected")
    }

    @Test("Carbon monoxide alert has correct title")
    func coTitle() {
        #expect(EmergencyAlertType.carbonMonoxide.title == "Carbon Monoxide Detected")
    }

    @Test("Carbon dioxide alert has correct title")
    func co2Title() {
        #expect(EmergencyAlertType.carbonDioxide.title == "High CO₂ Detected")
    }

    @Test("Water leak alert has correct title")
    func waterLeakTitle() {
        #expect(EmergencyAlertType.waterLeak.title == "Water Leak Detected")
    }

    // MARK: - Severity levels

    @Test("Smoke severity is critical")
    func smokeSeverity() {
        #expect(EmergencyAlertType.smoke.severity == .critical)
    }

    @Test("Carbon monoxide severity is critical")
    func coSeverity() {
        #expect(EmergencyAlertType.carbonMonoxide.severity == .critical)
    }

    @Test("Water leak severity is urgent")
    func waterLeakSeverity() {
        #expect(EmergencyAlertType.waterLeak.severity == .urgent)
    }

    @Test("Carbon dioxide severity is warning")
    func co2Severity() {
        #expect(EmergencyAlertType.carbonDioxide.severity == .warning)
    }

    // MARK: - Severity ordering

    @Test("Critical is greater than urgent")
    func criticalGreaterThanUrgent() {
        #expect(EmergencyAlertSeverity.critical > .urgent)
    }

    @Test("Urgent is greater than warning")
    func urgentGreaterThanWarning() {
        #expect(EmergencyAlertSeverity.urgent > .warning)
    }

    @Test("Critical is greater than warning")
    func criticalGreaterThanWarning() {
        #expect(EmergencyAlertSeverity.critical > .warning)
    }

    @Test("Warning is not greater than critical")
    func warningNotGreaterThanCritical() {
        #expect(!(EmergencyAlertSeverity.warning > .critical))
    }

    // MARK: - Raw values

    @Test("AlertType raw values are correct for serialization")
    func alertTypeRawValues() {
        #expect(EmergencyAlertType.smoke.rawValue == "smoke")
        #expect(EmergencyAlertType.carbonMonoxide.rawValue == "carbonMonoxide")
        #expect(EmergencyAlertType.carbonDioxide.rawValue == "carbonDioxide")
        #expect(EmergencyAlertType.waterLeak.rawValue == "waterLeak")
    }

    @Test("AlertType round-trips through JSON")
    func alertTypeCodable() throws {
        let types: [EmergencyAlertType] = [.smoke, .carbonMonoxide, .carbonDioxide, .waterLeak]
        for type in types {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(EmergencyAlertType.self, from: data)
            #expect(decoded == type)
        }
    }

    // MARK: - Severity raw values

    @Test("Severity raw values enable correct ordering")
    func severityRawValues() {
        #expect(EmergencyAlertSeverity.warning.rawValue == 0)
        #expect(EmergencyAlertSeverity.urgent.rawValue == 1)
        #expect(EmergencyAlertSeverity.critical.rawValue == 2)
    }
}
