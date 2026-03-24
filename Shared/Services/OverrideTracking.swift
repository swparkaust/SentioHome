import Foundation

/// Provides device snapshot access for override detection.
@MainActor
protocol DeviceSnapshotProvider: AnyObject {
    var allDeviceSnapshots: [DeviceSnapshot] { get }
}

/// Tracks AI-initiated writes and detects manual overrides.
@MainActor
protocol OverrideTracking: AnyObject {
    func registerAIWrite(accessoryID: String, characteristic: String, value: Double)
    func clearStalePendingWrites()
    @discardableResult
    func handleValueChange(
        accessoryID: String,
        accessoryName: String,
        roomName: String?,
        characteristic: String,
        newValue: Double
    ) -> Bool
}

/// Handles emergency sensor updates (smoke, leak, CO).
@MainActor
protocol EmergencyHandling: AnyObject {
    static var emergencyCharacteristicTypes: Set<String> { get }
    func handleSensorUpdate(
        characteristicType: String,
        value: Bool,
        accessoryID: String,
        accessoryName: String,
        roomName: String?
    )
    func checkSensorReachability() async
}
