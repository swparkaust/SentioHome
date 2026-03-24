import Foundation
import HomeKit
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "HomeKit")

/// Discovers and controls HomeKit accessories across all homes.
@Observable
@MainActor
final class HomeKitService: NSObject, DeviceSnapshotProvider {

    // MARK: - Published State

    private(set) var homes: [HMHome] = []
    private(set) var isReady = false

    /// Whether HomeKit access has been denied or restricted by the user.
    /// When true, the app should surface a prompt to enable HomeKit in Settings.
    private(set) var authorizationDenied = false

    /// Optional override tracker — when set, the service forwards real-time
    /// characteristic value changes so manual adjustments can be detected.
    var overrideTracker: (any OverrideTracking)?

    /// Optional emergency handler — when set, safety-critical sensor changes
    /// (smoke, CO, water leak) are forwarded for instant response.
    var emergencyHandler: (any EmergencyHandling)?

    private let manager: HMHomeManager?

    override init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            manager = nil
            super.init()
            logger.info("HomeKitService initialized in UI testing mode — HomeKit disabled")
            return
        }
        let mgr = HMHomeManager()
        manager = mgr
        super.init()
        mgr.delegate = self
    }

    var allRoomNames: [String] {
        homes.flatMap(\.rooms).map(\.name).sorted()
    }

    // MARK: - Snapshots

    var allDeviceSnapshots: [DeviceSnapshot] {
        homes.flatMap { home in
            home.accessories.map { accessory in
                snapshot(for: accessory, in: home)
            }
        }
    }

    private func snapshot(for accessory: HMAccessory, in home: HMHome) -> DeviceSnapshot {
        let characteristics = accessory.services.flatMap(\.characteristics).compactMap { char -> DeviceSnapshot.CharacteristicValue? in
            guard let type = shortType(for: char),
                  let value = char.value as? NSNumber else { return nil }
            return DeviceSnapshot.CharacteristicValue(
                type: type,
                value: value.doubleValue,
                label: char.localizedDescription
            )
        }

        return DeviceSnapshot(
            id: accessory.uniqueIdentifier.uuidString,
            name: accessory.name,
            roomName: accessory.room?.name,
            category: categoryName(for: accessory),
            characteristics: characteristics,
            isReachable: accessory.isReachable
        )
    }

    // MARK: - Control

    func execute(_ action: DeviceAction) async throws {
        guard let accessory = findAccessory(id: action.accessoryID) else {
            logger.warning("Accessory not found: \(action.accessoryID)")
            return
        }

        guard let characteristic = findCharacteristic(named: action.characteristic, in: accessory) else {
            logger.warning("Characteristic '\(action.characteristic)' not found on \(accessory.name)")
            return
        }

        let targetValue = coerce(action.value, for: characteristic)
        try await characteristic.writeValue(targetValue)

        // Register after success so delegate can distinguish AI writes from manual.
        overrideTracker?.registerAIWrite(
            accessoryID: action.accessoryID,
            characteristic: action.characteristic,
            value: action.value
        )

        logger.info("Set \(accessory.name).\(action.characteristic) → \(action.value) (\(action.reason))")
    }

    @discardableResult
    func execute(_ actions: [DeviceAction]) async -> [DeviceAction] {
        logger.info("Executing \(actions.count) action(s)")
        var failed: [DeviceAction] = []
        for action in actions {
            do {
                try await execute(action)
            } catch {
                failed.append(action)
                logger.error("Failed to execute action on \(action.accessoryName): \(error.localizedDescription)")
            }
        }
        return failed
    }

    // MARK: - Room Presence

    private var _lastMotionRoom: String?
    private var _lastMotionDate: Date?

    var lastMotionRoom: String? { _lastMotionRoom }

    fileprivate func recordMotion(room: String) {
        _lastMotionRoom = room
        _lastMotionDate = Date()
    }

    var activeMotionRooms: [String] {
        var rooms: Set<String> = []
        for home in homes {
            for accessory in home.accessories where accessory.isReachable {
                guard let room = accessory.room?.name else { continue }
                for service in accessory.services {
                    for char in service.characteristics where char.characteristicType == HMCharacteristicTypeMotionDetected {
                        if let motionDetected = char.value as? Bool, motionDetected {
                            rooms.insert(room)
                        }
                    }
                }
            }
        }
        return Array(rooms).sorted()
    }

    // MARK: - Energy Tracking

    var powerReadings: [PowerReading] {
        homes.flatMap { home in
            home.accessories.compactMap { accessory -> PowerReading? in
                guard accessory.isReachable else { return nil }
                for service in accessory.services {
                    for char in service.characteristics {
                        if char.characteristicType == "000000B8-0000-1000-8000-0026BB765291", // kCurrentPowerConsumption
                           let value = char.value as? NSNumber {
                            return PowerReading(
                                accessoryID: accessory.uniqueIdentifier.uuidString,
                                accessoryName: accessory.name,
                                roomName: accessory.room?.name,
                                watts: value.doubleValue
                            )
                        }
                    }
                }
                return nil
            }
        }
    }

    var totalPowerWatts: Double {
        powerReadings.reduce(0) { $0 + $1.watts }
    }

    // MARK: - Occupancy Sensors

    var occupiedRooms: [String] {
        var rooms: Set<String> = []
        for home in homes {
            for accessory in home.accessories where accessory.isReachable {
                guard let room = accessory.room?.name else { continue }
                for service in accessory.services {
                    for char in service.characteristics where char.characteristicType == HMCharacteristicTypeOccupancyDetected {
                        if let detected = (char.value as? NSNumber)?.boolValue, detected {
                            rooms.insert(room)
                        }
                    }
                }
            }
        }
        return Array(rooms).sorted()
    }

    // MARK: - Contact Sensors

    var openContactRooms: [String] {
        var rooms: [String] = []
        for home in homes {
            for accessory in home.accessories where accessory.isReachable {
                guard let room = accessory.room?.name else { continue }
                for service in accessory.services {
                    for char in service.characteristics where char.characteristicType == HMCharacteristicTypeContactState {
                        // ContactState: 0 = detected (closed), 1 = not detected (open)
                        if let value = char.value as? Int, value == 1 {
                            rooms.append("\(accessory.name) (\(room))")
                        }
                    }
                }
            }
        }
        return rooms
    }

    // MARK: - Lookup Helpers

    func readValue(accessoryID: String, characteristic: String) -> Double? {
        guard let accessory = findAccessory(id: accessoryID),
              let char = findCharacteristic(named: characteristic, in: accessory) else {
            return nil
        }
        if let boolVal = char.value as? Bool {
            return boolVal ? 1 : 0
        }
        if let numVal = char.value as? NSNumber {
            return numVal.doubleValue
        }
        return nil
    }

    private func findAccessory(id: String) -> HMAccessory? {
        var cleanID = id.trimmingCharacters(in: .whitespaces)
        // The model may output "[UUID] Name" — extract just the UUID from brackets.
        if let open = cleanID.firstIndex(of: "["),
           let close = cleanID.firstIndex(of: "]") {
            cleanID = String(cleanID[cleanID.index(after: open)..<close])
        }
        cleanID = cleanID.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        for home in homes {
            if let accessory = home.accessories.first(where: { $0.uniqueIdentifier.uuidString == cleanID }) {
                return accessory
            }
        }
        return nil
    }

    private static let characteristicAliases: [String: String] = [
        "powerstate": "on",
        "power": "on",
        "switch": "on",
        "colortemperature": "colortemperature",
        "color temperature": "colortemperature",
        "volume": "volume",
    ]

    private func findCharacteristic(named type: String, in accessory: HMAccessory) -> HMCharacteristic? {
        let lowered = type.lowercased()
        let resolved = Self.characteristicAliases[lowered] ?? lowered
        for service in accessory.services {
            for char in service.characteristics {
                if shortType(for: char)?.lowercased() == resolved {
                    return char
                }
            }
        }
        return nil
    }

    private func coerce(_ value: Double, for characteristic: HMCharacteristic) -> Any {
        let metadata = characteristic.metadata

        guard value.isFinite else {
            logger.warning("Rejecting non-finite value \(value) for characteristic, defaulting to 0")
            return 0
        }

        var clamped = value
        if let minVal = metadata?.minimumValue as? NSNumber {
            clamped = max(clamped, minVal.doubleValue)
        }
        if let maxVal = metadata?.maximumValue as? NSNumber {
            clamped = min(clamped, maxVal.doubleValue)
        }

        if let format = metadata?.format {
            switch format {
            case HMCharacteristicMetadataFormatBool:
                return clamped >= 1
            case HMCharacteristicMetadataFormatInt,
                 HMCharacteristicMetadataFormatUInt8,
                 HMCharacteristicMetadataFormatUInt16,
                 HMCharacteristicMetadataFormatUInt32,
                 HMCharacteristicMetadataFormatUInt64:
                return Int(clamped)
            default:
                break
            }
        }
        return clamped
    }

    // MARK: - Mapping

    private func shortType(for char: HMCharacteristic) -> String? {
        let mapping: [String: String] = [
            HMCharacteristicTypePowerState:                 "on",
            HMCharacteristicTypeBrightness:                 "brightness",
            HMCharacteristicTypeHue:                        "hue",
            HMCharacteristicTypeSaturation:                 "saturation",
            HMCharacteristicTypeTargetTemperature:          "targetTemperature",
            HMCharacteristicTypeTargetHeatingCooling:       "targetHeatingCoolingState",
            HMCharacteristicTypeCurrentTemperature:         "currentTemperature",
            HMCharacteristicTypeTargetDoorState:            "targetDoorState",
            HMCharacteristicTypeCurrentDoorState:           "currentDoorState",
            HMCharacteristicTypeTargetLockMechanismState:   "targetLockState",
            HMCharacteristicTypeMotionDetected:             "motionDetected",
            HMCharacteristicTypeColorTemperature:           "colorTemperature",
            HMCharacteristicTypeActive:                     "active",
            HMCharacteristicTypeRotationSpeed:              "rotationSpeed",
            HMCharacteristicTypeTargetFanState:             "targetFanState",
            HMCharacteristicTypeCurrentRelativeHumidity:    "currentHumidity",
            HMCharacteristicTypeContactState:               "contactState",
            HMCharacteristicTypeOccupancyDetected:          "occupancyDetected",
            HMCharacteristicTypeSmokeDetected:              "smokeDetected",
            HMCharacteristicTypeCarbonMonoxideDetected:     "carbonMonoxideDetected",
            HMCharacteristicTypeCarbonDioxideDetected:      "carbonDioxideDetected",
            "00000070-0000-1000-8000-0026BB765291":         "leakDetected",
        ]
        return mapping[char.characteristicType]
    }

    private func categoryName(for accessory: HMAccessory) -> String {
        switch accessory.category.categoryType {
        case HMAccessoryCategoryTypeLightbulb:      return "lightbulb"
        case HMAccessoryCategoryTypeThermostat:      return "thermostat"
        case HMAccessoryCategoryTypeDoor:            return "door"
        case HMAccessoryCategoryTypeDoorLock:        return "lock"
        case HMAccessoryCategoryTypeGarageDoorOpener:return "garage"
        case HMAccessoryCategoryTypeFan:             return "fan"
        case HMAccessoryCategoryTypeSwitch:          return "switch"
        case HMAccessoryCategoryTypeOutlet:          return "outlet"
        case HMAccessoryCategoryTypeWindowCovering:  return "blinds"
        case HMAccessoryCategoryTypeSensor:          return "sensor"
        case HMAccessoryCategoryTypeAirPurifier:     return "purifier"
        case HMAccessoryCategoryTypeSprinkler:       return "sprinkler"
        case HMAccessoryCategoryTypeSpeaker:         return "speaker"
        case HMAccessoryCategoryTypeAudioReceiver:   return "speaker"
        case HMAccessoryCategoryTypeBridge:          return "bridge"
        case HMAccessoryCategoryTypeAirPort:         return "airport"
        case HMAccessoryCategoryTypeTelevision:      return "television"
        default:                                     return "other"
        }
    }
}

// MARK: - Power Reading

struct PowerReading: Sendable {
    var accessoryID: String
    var accessoryName: String
    var roomName: String?
    var watts: Double
}

// MARK: - HMHomeManagerDelegate

extension HomeKitService: HMHomeManagerDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status.contains(.determined) && !status.contains(.authorized) {
                self.authorizationDenied = true
                self.isReady = false
                logger.error("HomeKit authorization denied — enable in System Settings → Privacy & Security → HomeKit")
                return
            }
            self.authorizationDenied = false

            self.homes = manager.homes
            self.isReady = true

            for home in manager.homes {
                for accessory in home.accessories {
                    accessory.delegate = self
                }
            }

            logger.info("HomeKit ready — \(manager.homes.count) home(s), \(self.allDeviceSnapshots.count) accessory(ies)")
        }
    }
}

// MARK: - HMAccessoryDelegate

extension HomeKitService: HMAccessoryDelegate {
    nonisolated func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        Task { @MainActor in
            if characteristic.characteristicType == HMCharacteristicTypeMotionDetected,
               let detected = characteristic.value as? Bool, detected,
               let room = accessory.room?.name {
                self.recordMotion(room: room)
            }

            if let handler = self.emergencyHandler,
               type(of: handler).emergencyCharacteristicTypes.contains(characteristic.characteristicType) {
                if let boolValue = characteristic.value as? Bool {
                    handler.handleSensorUpdate(
                        characteristicType: characteristic.characteristicType,
                        value: boolValue,
                        accessoryID: accessory.uniqueIdentifier.uuidString,
                        accessoryName: accessory.name,
                        roomName: accessory.room?.name
                    )
                }
                return  // Emergency sensors don't need override tracking
            }

            guard let tracker = self.overrideTracker else { return }
            guard let type = self.shortType(for: characteristic) else { return }
            guard let value = characteristic.value as? NSNumber else { return }

            tracker.clearStalePendingWrites()
            tracker.handleValueChange(
                accessoryID: accessory.uniqueIdentifier.uuidString,
                accessoryName: accessory.name,
                roomName: accessory.room?.name,
                characteristic: type,
                newValue: value.doubleValue
            )
        }
    }
}
