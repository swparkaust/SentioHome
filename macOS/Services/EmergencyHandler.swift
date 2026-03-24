import Foundation
import HomeKit
@preconcurrency import UserNotifications
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "Emergency")

/// Responds instantly to safety-critical HomeKit events — smoke, CO, water leaks.
/// Unlike the automation loop (which polls every 1–30 minutes), this handler
/// is triggered directly by `HMAccessoryDelegate` and acts within seconds.
///
/// Response hierarchy:
/// 1. Critical push notification with sound (always)
/// 2. Automatic mitigation actions (e.g. shut water valve on leak)
/// 3. CloudKit alert pushed to all companion devices
/// 4. Voice announcement through all available speakers
@Observable
@MainActor
final class EmergencyHandler: EmergencyHandling {

    typealias AlertType = EmergencyAlertType
    typealias Severity = EmergencyAlertSeverity
    typealias Alert = EmergencyAlertTracker.Alert

    let tracker = EmergencyAlertTracker()

    var activeAlerts: [Alert] { tracker.activeAlerts }
    var alertHistory: [Alert] { tracker.alertHistory }

    static func notificationSound(for type: AlertType) -> UNNotificationSound {
        switch type.severity {
        case .critical, .urgent: return .defaultCritical
        case .warning:           return .default
        }
    }

    private var homeKit: HomeKitService?
    private var cloudSync: CloudSyncService?
    private var voiceService: VoiceService?

    func configure(homeKit: HomeKitService, cloudSync: CloudSyncService, voiceService: VoiceService?) {
        self.homeKit = homeKit
        self.cloudSync = cloudSync
        self.voiceService = voiceService
    }

    // MARK: - Emergency Detection

    func handleSensorUpdate(
        characteristicType: String,
        value: Bool,
        accessoryID: String,
        accessoryName: String,
        roomName: String?
    ) {
        guard let alert = tracker.handleSensorUpdate(
            characteristicType: characteristicType,
            value: value,
            accessoryID: accessoryID,
            accessoryName: accessoryName,
            roomName: roomName
        ) else { return }

        logger.critical("\(alert.type.title) — \(accessoryName) in \(roomName ?? "unknown room")")

        Task {
            await respondToEmergency(alert)
        }
    }

    // MARK: - Emergency Response

    private func respondToEmergency(_ alert: Alert) async {
        async let notification: () = postCriticalNotification(alert)
        async let mitigation: () = executeMitigation(alert)
        async let companion: () = pushCompanionAlert(alert)
        async let voice: () = announceEmergency(alert)

        _ = await (notification, mitigation, companion, voice)
    }

    private func postCriticalNotification(_ alert: Alert) async {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ \(alert.type.title)"
        content.body = tracker.locationDescription(alert)
        content.sound = Self.notificationSound(for: alert.type)
        content.interruptionLevel = alert.type.severity >= .urgent ? .critical : .timeSensitive
        content.categoryIdentifier = "EMERGENCY_ALERT"

        let request = UNNotificationRequest(
            identifier: "emergency-\(alert.id)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Critical notification posted for \(alert.type.rawValue)")
        } catch {
            logger.error("Failed to post emergency notification: \(error.localizedDescription)")
        }
    }

    private func executeMitigation(_ alert: Alert) async {
        guard let homeKit else { return }

        switch alert.type {
        case .waterLeak:
            await shutWaterValves(homeKit: homeKit, triggerRoom: alert.roomName)

        case .smoke:
            await lightsFullBrightness(homeKit: homeKit)
            await stopHVAC(homeKit: homeKit)

        case .carbonMonoxide:
            await lightsFullBrightness(homeKit: homeKit)
            await stopHVAC(homeKit: homeKit)

        case .carbonDioxide:
            await startPurifiers(homeKit: homeKit)
        }
    }

    private func pushCompanionAlert(_ alert: Alert) async {
        guard let cloudSync else { return }
        do {
            try await cloudSync.pushEmergencyAlert(
                type: alert.type.rawValue,
                message: tracker.locationDescription(alert),
                timestamp: alert.timestamp
            )
            logger.info("Emergency alert pushed to companions")
        } catch {
            logger.error("Failed to push emergency alert: \(error.localizedDescription)")
        }
    }

    private func announceEmergency(_ alert: Alert) async {
        guard let voiceService else { return }
        let message = tracker.voiceMessage(for: alert)
        await voiceService.speakEverywhere(message)
    }

    // MARK: - Mitigation Actions

    private func shutWaterValves(homeKit: HomeKitService, triggerRoom: String?) async {
        // Don't filter by category — HomeKit valve accessories may report various
        // category types. Instead, look for accessories with a "Valve" service type.
        // HAP service type 0xD0 = Valve
        let valveActions = findAccessories(homeKit: homeKit, withCharacteristic: HMCharacteristicTypeActive, serviceType: "000000D0-0000-1000-8000-0026BB765291")
        var failedValves: [String] = []
        for (accessory, _) in valveActions {
            let action = DeviceAction(
                accessoryID: accessory.uniqueIdentifier.uuidString,
                accessoryName: accessory.name,
                characteristic: "active",
                value: 0,
                reason: "Emergency: water leak — shutting valve"
            )
            do {
                try await homeKit.execute(action)
                logger.info("Shut water valve: \(accessory.name)")
            } catch {
                failedValves.append(accessory.name)
                logger.error("Failed to shut valve \(accessory.name): \(error.localizedDescription)")
            }
        }
        if !failedValves.isEmpty {
            await postMitigationFailureNotification(
                type: "Water Valve",
                failedDevices: failedValves
            )
        }
    }

    private func lightsFullBrightness(homeKit: HomeKitService) async {
        let snapshots = homeKit.allDeviceSnapshots.filter { $0.category == "lightbulb" && $0.isReachable }
        var failedLights: [String] = []
        for snapshot in snapshots {
            let onAction = DeviceAction(
                accessoryID: snapshot.id,
                accessoryName: snapshot.name,
                characteristic: "on",
                value: 1,
                reason: "Emergency: lights on for safety"
            )
            let brightnessAction = DeviceAction(
                accessoryID: snapshot.id,
                accessoryName: snapshot.name,
                characteristic: "brightness",
                value: 100,
                reason: "Emergency: full brightness"
            )
            do {
                try await homeKit.execute(onAction)
                try await homeKit.execute(brightnessAction)
            } catch {
                failedLights.append(snapshot.name)
                logger.error("Failed to set emergency lighting on \(snapshot.name): \(error.localizedDescription)")
            }
        }
        if !snapshots.isEmpty {
            logger.info("Emergency lighting: \(snapshots.count) light(s) set to full brightness")
        }
        if !failedLights.isEmpty {
            await postMitigationFailureNotification(
                type: "Emergency Lighting",
                failedDevices: failedLights
            )
        }
    }

    private func stopHVAC(homeKit: HomeKitService) async {
        let snapshots = homeKit.allDeviceSnapshots.filter {
            ($0.category == "thermostat" || $0.category == "fan") && $0.isReachable
        }
        var failedHVAC: [String] = []
        for snapshot in snapshots {
            // Thermostats: set targetHeatingCoolingState=0 (Off) to stop the compressor
            // and fan completely. Setting targetTemperature alone keeps air circulating,
            // which spreads smoke/CO — exactly what we must prevent.
            let characteristic = snapshot.category == "fan" ? "active" : "targetHeatingCoolingState"
            let value: Double = 0
            let action = DeviceAction(
                accessoryID: snapshot.id,
                accessoryName: snapshot.name,
                characteristic: characteristic,
                value: value,
                reason: "Emergency: stopping air circulation"
            )
            do {
                try await homeKit.execute(action)
            } catch {
                failedHVAC.append(snapshot.name)
                logger.error("Failed to stop \(snapshot.name): \(error.localizedDescription)")
            }
        }
        if !failedHVAC.isEmpty {
            await postMitigationFailureNotification(
                type: "HVAC Shutdown",
                failedDevices: failedHVAC
            )
        }
    }

    private func startPurifiers(homeKit: HomeKitService) async {
        let snapshots = homeKit.allDeviceSnapshots.filter { $0.category == "purifier" && $0.isReachable }
        var failedPurifiers: [String] = []
        for snapshot in snapshots {
            let action = DeviceAction(
                accessoryID: snapshot.id,
                accessoryName: snapshot.name,
                characteristic: "active",
                value: 1,
                reason: "Emergency: high CO₂ — purifying air"
            )
            do {
                try await homeKit.execute(action)
            } catch {
                failedPurifiers.append(snapshot.name)
                logger.error("Failed to start purifier \(snapshot.name): \(error.localizedDescription)")
            }
        }
        if !failedPurifiers.isEmpty {
            await postMitigationFailureNotification(
                type: "Air Purifier",
                failedDevices: failedPurifiers
            )
        }
    }

    /// Posts a high-priority notification when emergency mitigation actions fail.
    /// This ensures the user is alerted even if their phone is locked — a failed
    /// water valve shutdown during a leak requires immediate manual intervention.
    private func postMitigationFailureNotification(type: String, failedDevices: [String]) async {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Emergency Mitigation Failed"
        content.body = "\(type) failed for: \(failedDevices.joined(separator: ", ")). Manual intervention required."
        content.sound = .defaultCritical
        content.interruptionLevel = .critical

        let request = UNNotificationRequest(
            identifier: "mitigation-failure-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("Failed to post mitigation failure notification: \(error.localizedDescription)")
        }

        // Also push to companions so the user's phone alerts them
        if let cloudSync {
            try? await cloudSync.pushEmergencyAlert(
                type: "mitigationFailure",
                message: "\(type) failed for: \(failedDevices.joined(separator: ", ")). Check immediately.",
                timestamp: Date()
            )
        }
    }

    // MARK: - Alert Resolution

    private func resolveAlert(accessoryID: String, characteristicType: String) {
        guard let alertType = tracker.alertType(for: characteristicType) else { return }
        tracker.resolveAlert(accessoryID: accessoryID, characteristicType: characteristicType)

        if activeAlerts.isEmpty {
            Task {
                await postResolutionNotification(alertType: alertType)
            }
        }
    }

    private func postResolutionNotification(alertType: AlertType) async {
        let content = UNMutableNotificationContent()
        content.title = "Sentio Home — All Clear"
        content.body = "\(alertType.title) has been resolved. All sensors are clear."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "emergency-resolved-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static var emergencyCharacteristicTypes: Set<String> {
        EmergencyAlertTracker.emergencyCharacteristicTypes
    }

    private func findAccessories(
        homeKit: HomeKitService,
        withCharacteristic charType: String,
        category: String? = nil,
        serviceType: String? = nil
    ) -> [(HMAccessory, HMCharacteristic)] {
        var results: [(HMAccessory, HMCharacteristic)] = []
        for home in homeKit.homes {
            for accessory in home.accessories where accessory.isReachable {
                if let category, categoryName(for: accessory) != category { continue }
                for service in accessory.services {
                    if let serviceType, service.serviceType != serviceType { continue }
                    for char in service.characteristics where char.characteristicType == charType {
                        results.append((accessory, char))
                    }
                }
            }
        }
        return results
    }

    private func categoryName(for accessory: HMAccessory) -> String {
        switch accessory.category.categoryType {
        case HMAccessoryCategoryTypeFan:       return "fan"
        case HMAccessoryCategoryTypeSensor:    return "sensor"
        case HMAccessoryCategoryTypeAirPurifier: return "purifier"
        default: return "other"
        }
    }

    // MARK: - Reachability Monitoring

    /// IDs of sensors we've already alerted about being unreachable,
    /// so we don't spam the user every cycle.
    private var unreachableAlerted: Set<String> = []

    /// Check that all emergency sensors are still reachable.
    /// Call periodically from the automation scheduler. Posts a notification
    /// if a safety-critical sensor goes offline.
    func checkSensorReachability() async {
        guard let homeKit else { return }

        for home in homeKit.homes {
            for accessory in home.accessories {
                let hasEmergencyChar = accessory.services.flatMap(\.characteristics).contains {
                    Self.emergencyCharacteristicTypes.contains($0.characteristicType)
                }
                guard hasEmergencyChar else { continue }

                let id = accessory.uniqueIdentifier.uuidString
                if !accessory.isReachable {
                    guard !unreachableAlerted.contains(id) else { continue }
                    unreachableAlerted.insert(id)

                    let room = accessory.room?.name ?? "Unknown room"
                    logger.warning("Emergency sensor unreachable: \(accessory.name) in \(room)")

                    let content = UNMutableNotificationContent()
                    content.title = "Sentio Home — Sensor Offline"
                    content.body = "\(accessory.name) in \(room) is unreachable. Safety monitoring may be compromised."
                    content.sound = .default

                    let request = UNNotificationRequest(
                        identifier: "sensor-offline-\(id)",
                        content: content,
                        trigger: nil
                    )
                    try? await UNUserNotificationCenter.current().add(request)
                } else {
                    unreachableAlerted.remove(id)
                }
            }
        }
    }

    // MARK: - Notification Registration

    static func registerNotificationCategory() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ALERT",
            title: "View Details",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "EMERGENCY_ALERT",
            actions: [viewAction],
            intentIdentifiers: [],
            options: [.allowInCarPlay]
        )

        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            var categories = existing
            categories.insert(category)
            center.setNotificationCategories(categories)
        }
    }
}
