import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "OverrideTracker")

/// Tracks devices that were recently adjusted manually (not by the AI).
/// While a cooldown is active, the device+characteristic pair is marked as
/// "hands off" — the scheduler strips those actions from the AI plan and
/// the prompt tells the LLM to leave them alone.
///
/// This prevents the frustrating loop where a user manually sets a light
/// to 80% and the AI dims it back to 40% on the next cycle.
@Observable
@MainActor
final class OverrideTracker: OverrideTracking {

    struct ActiveOverride: Sendable {
        let accessoryID: String
        let accessoryName: String
        let roomName: String?
        let characteristic: String
        let userValue: Double
        let detectedAt: Date
        let expiresAt: Date
    }

    private(set) var activeCooldowns: [String: ActiveOverride] = [:]

    var cooldownSeconds: TimeInterval = 1800

    /// Populated before HomeKitService.execute() and cleared as the delegate
    /// fires, so we can distinguish AI writes from manual ones.
    private var pendingAIWrites: [String: PendingWrite] = [:]

    private struct PendingWrite {
        let value: Double
        let timestamp: Date
    }

    func registerAIWrite(accessoryID: String, characteristic: String, value: Double) {
        let key = "\(accessoryID)|\(characteristic)"
        pendingAIWrites[key] = PendingWrite(value: value, timestamp: Date())
    }

    func clearStalePendingWrites() {
        let cutoff = Date().addingTimeInterval(-10)
        pendingAIWrites = pendingAIWrites.filter { $0.value.timestamp > cutoff }
    }

    @discardableResult
    func handleValueChange(
        accessoryID: String,
        accessoryName: String,
        roomName: String?,
        characteristic: String,
        newValue: Double
    ) -> Bool {
        let key = "\(accessoryID)|\(characteristic)"

        if let pending = pendingAIWrites[key] {
            // Tolerance for floating-point coercion differences across HAP types
            let delta = abs(pending.value - newValue)
            let isAIWrite: Bool
            switch characteristic {
            case "on":
                isAIWrite = (pending.value >= 1) == (newValue >= 1)
            case "brightness", "saturation":
                isAIWrite = delta <= 2
            case "targetTemperature":
                isAIWrite = delta <= 0.3
            default:
                isAIWrite = delta <= 1
            }

            if isAIWrite {
                pendingAIWrites.removeValue(forKey: key)
                return false
            }
        }

        let now = Date()
        let override = ActiveOverride(
            accessoryID: accessoryID,
            accessoryName: accessoryName,
            roomName: roomName,
            characteristic: characteristic,
            userValue: newValue,
            detectedAt: now,
            expiresAt: now.addingTimeInterval(cooldownSeconds)
        )
        activeCooldowns[key] = override

        logger.info("Manual override: \(accessoryName).\(characteristic) → \(newValue) — hands off for \(Int(self.cooldownSeconds / 60))min")
        return true
    }

    var activeOverrides: [ActiveOverride] {
        pruneExpired()
        return Array(activeCooldowns.values)
    }

    func isOverridden(accessoryID: String, characteristic: String) -> Bool {
        let key = "\(accessoryID)|\(characteristic)"
        guard let entry = activeCooldowns[key] else { return false }
        if Date() > entry.expiresAt {
            activeCooldowns.removeValue(forKey: key)
            return false
        }
        return true
    }

    func filterActions(_ actions: [DeviceAction]) -> (allowed: [DeviceAction], blocked: [DeviceAction]) {
        pruneExpired()
        var allowed: [DeviceAction] = []
        var blocked: [DeviceAction] = []
        for action in actions {
            if isOverridden(accessoryID: action.accessoryID, characteristic: action.characteristic) {
                blocked.append(action)
            } else {
                allowed.append(action)
            }
        }
        return (allowed, blocked)
    }

    var promptSection: String? {
        let active = activeOverrides
        guard !active.isEmpty else { return nil }

        let lines = active.map { override in
            let room = override.roomName.map { " in \(sanitizeForPrompt($0))" } ?? ""
            let remaining = Int(override.expiresAt.timeIntervalSinceNow / 60)
            return "- \(sanitizeForPrompt(override.accessoryName))\(room): \(sanitizeForPrompt(override.characteristic)) " +
                   "(user set to \(formatted(override.userValue, characteristic: override.characteristic)), " +
                   "hands off for ~\(max(remaining, 1)) min)"
        }

        return """
        ## Active Manual Overrides (DO NOT TOUCH)
        The user recently adjusted these devices manually. Do NOT change \
        these specific characteristics until the cooldown expires. \
        Respect the user's explicit choice.

        \(lines.joined(separator: "\n"))
        """
    }

    private func pruneExpired() {
        let now = Date()
        let expired = activeCooldowns.filter { now > $0.value.expiresAt }
        for key in expired.keys {
            activeCooldowns.removeValue(forKey: key)
            logger.info("Override expired: \(key)")
        }
    }

    private func formatted(_ value: Double, characteristic: String) -> String {
        switch characteristic {
        case "on":
            return value >= 1 ? "on" : "off"
        case "brightness", "saturation":
            return "\(Int(value))%"
        case "hue":
            return "\(Int(value))°"
        case "targetTemperature":
            return String(format: "%.1f°C", value)
        default:
            return String(format: "%.1f", value)
        }
    }
}
