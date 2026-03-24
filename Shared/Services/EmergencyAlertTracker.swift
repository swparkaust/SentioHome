import Foundation
import Observation

@Observable
final class EmergencyAlertTracker {

    struct Alert: Sendable, Identifiable {
        let id: String
        let type: EmergencyAlertType
        let accessoryID: String
        let accessoryName: String
        let roomName: String?
        let timestamp: Date
        var resolved: Bool = false
        var resolvedAt: Date?
    }

    private(set) var activeAlerts: [Alert] = []
    private(set) var alertHistory: [Alert] = []

    private var alertCooldowns: [String: Date] = [:]
    let cooldownSeconds: TimeInterval

    init(cooldownSeconds: TimeInterval = 120) {
        self.cooldownSeconds = cooldownSeconds
    }

    // Raw HAP UUID strings (avoids HomeKit framework dependency)
    static let characteristicToAlertType: [String: EmergencyAlertType] = [
        // HMCharacteristicTypeSmokeDetected
        "00000076-0000-1000-8000-0026BB765291": .smoke,
        // HMCharacteristicTypeCarbonMonoxideDetected
        "00000069-0000-1000-8000-0026BB765291": .carbonMonoxide,
        // HMCharacteristicTypeCarbonDioxideDetected
        "00000092-0000-1000-8000-0026BB765291": .carbonDioxide,
        // LeakDetected (no HMCharacteristicType constant)
        "00000070-0000-1000-8000-0026BB765291": .waterLeak,
    ]

    static let emergencyCharacteristicTypes: Set<String> = Set(characteristicToAlertType.keys)

    func alertType(for characteristicType: String) -> EmergencyAlertType? {
        Self.characteristicToAlertType[characteristicType]
    }

    @discardableResult
    func handleSensorUpdate(
        characteristicType: String,
        value: Bool,
        accessoryID: String,
        accessoryName: String,
        roomName: String?,
        now: Date = Date()
    ) -> Alert? {
        guard value else {
            resolveAlert(accessoryID: accessoryID, characteristicType: characteristicType, now: now)
            return nil
        }

        guard let alertType = alertType(for: characteristicType) else { return nil }

        let cooldownKey = "\(accessoryID)|\(characteristicType)"
        if let lastAlert = alertCooldowns[cooldownKey],
           now.timeIntervalSince(lastAlert) < cooldownSeconds {
            return nil
        }
        alertCooldowns[cooldownKey] = now

        let alert = Alert(
            id: UUID().uuidString,
            type: alertType,
            accessoryID: accessoryID,
            accessoryName: accessoryName,
            roomName: roomName,
            timestamp: now
        )

        activeAlerts.append(alert)
        alertHistory.append(alert)
        return alert
    }

    func resolveAlert(accessoryID: String, characteristicType: String, now: Date = Date()) {
        guard let alertType = alertType(for: characteristicType) else { return }

        for i in activeAlerts.indices where
            activeAlerts[i].accessoryID == accessoryID &&
            activeAlerts[i].type == alertType &&
            !activeAlerts[i].resolved
        {
            activeAlerts[i].resolved = true
            activeAlerts[i].resolvedAt = now

            if let histIdx = alertHistory.firstIndex(where: { $0.id == activeAlerts[i].id }) {
                alertHistory[histIdx].resolved = true
                alertHistory[histIdx].resolvedAt = now
            }
        }

        activeAlerts.removeAll { $0.resolved }
    }

    func locationDescription(_ alert: Alert) -> String {
        if let room = alert.roomName {
            return "\(alert.type.title) in \(room) (\(alert.accessoryName))."
        }
        return "\(alert.type.title) — \(alert.accessoryName)."
    }

    func voiceMessage(for alert: Alert) -> String {
        let room = alert.roomName ?? "your home"
        switch alert.type {
        case .smoke:
            return "Warning. Smoke has been detected in \(room). Please check immediately."
        case .carbonMonoxide:
            return "Warning. Carbon monoxide has been detected in \(room). Evacuate immediately and call emergency services."
        case .waterLeak:
            return "Alert. A water leak has been detected in \(room). Water valves are being shut off."
        case .carbonDioxide:
            return "Notice. High carbon dioxide levels detected in \(room). Opening ventilation."
        }
    }
}
