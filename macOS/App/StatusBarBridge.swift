import UIKit
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "StatusBarBridge")

@MainActor
final class StatusBarBridge {

    private var plugin: AnyObject?

    func install() {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else {
            logger.error("Built-in plugins URL not found")
            return
        }

        let bundleURL = pluginsURL.appendingPathComponent("StatusBarPlugin.bundle")
        guard let bundle = Bundle(url: bundleURL), bundle.load() else {
            logger.error("Failed to load StatusBarPlugin.bundle")
            return
        }

        guard let pluginClass = NSClassFromString("StatusBarPlugin.StatusBarPlugin") as? NSObject.Type else {
            logger.error("StatusBarPlugin class not found in loaded bundle")
            return
        }

        let pluginInstance = pluginClass.init()
        self.plugin = pluginInstance
        _ = pluginInstance.perform(NSSelectorFromString("showStatusItem:"), with: NSNull())
    }

    /// Push current state from the Catalyst services to the AppKit plugin.
    func pushState(
        deviceCount: Int,
        homeCount: Int,
        preferencesLearned: Int,
        isRunning: Bool,
        nowPlaying: String?,
        inMeeting: Bool,
        nextEvent: String?,
        screenActivity: String?,
        motionRooms: String?,
        openContacts: String?,
        guestsDetected: String?,
        unknownNetworkDevices: Int,
        unknownBLEDevices: Int,
        pendingWatches: Int,
        nextCheckDate: Date?,
        recentActions: [(summary: String, timestamp: Date)],
        quickAskResponse: String? = nil
    ) {
        guard let plugin else { return }
        let sel = NSSelectorFromString("updateState:")
        guard plugin.responds(to: sel) else { return }

        let dict: NSMutableDictionary = [
            "deviceCount": deviceCount,
            "homeCount": homeCount,
            "preferencesLearned": preferencesLearned,
            "isRunning": isRunning,
            "inMeeting": inMeeting,
            "unknownNetworkDevices": unknownNetworkDevices,
            "unknownBLEDevices": unknownBLEDevices,
            "pendingWatches": pendingWatches,
        ]

        if let nowPlaying { dict["nowPlaying"] = nowPlaying }
        if let nextEvent { dict["nextEvent"] = nextEvent }
        if let screenActivity { dict["screenActivity"] = screenActivity }
        if let motionRooms { dict["motionRooms"] = motionRooms }
        if let openContacts { dict["openContacts"] = openContacts }
        if let guestsDetected { dict["guestsDetected"] = guestsDetected }
        if let nextCheckDate { dict["nextCheckDate"] = nextCheckDate }
        if let quickAskResponse { dict["quickAskResponse"] = quickAskResponse }

        let actions = recentActions.map { entry -> NSDictionary in
            ["summary": entry.summary, "timestamp": entry.timestamp]
        }
        dict["recentActions"] = actions

        _ = plugin.perform(sel, with: dict)
    }

    // MARK: - Plugin Queries

    func frontmostAppBundleID() -> String? {
        guard let plugin else { return nil }
        let sel = NSSelectorFromString("frontmostAppBundleID")
        guard plugin.responds(to: sel) else { return nil }
        let result = plugin.perform(sel)
        return result?.takeUnretainedValue() as? String
    }

    func frontmostAppName() -> String? {
        guard let plugin else { return nil }
        let sel = NSSelectorFromString("frontmostAppName")
        guard plugin.responds(to: sel) else { return nil }
        let result = plugin.perform(sel)
        return result?.takeUnretainedValue() as? String
    }

    func isDisplayAsleep() -> Bool {
        guard let plugin else { return false }
        let sel = NSSelectorFromString("isDisplayAsleep")
        guard plugin.responds(to: sel) else { return false }
        let result = plugin.perform(sel)
        return (result?.takeUnretainedValue() as? NSNumber)?.boolValue ?? false
    }

    func systemIdleTime() -> TimeInterval {
        guard let plugin else { return 0 }
        let sel = NSSelectorFromString("systemIdleTime")
        guard plugin.responds(to: sel) else { return 0 }
        let result = plugin.perform(sel)
        return (result?.takeUnretainedValue() as? NSNumber)?.doubleValue ?? 0
    }

    func isCameraActive() -> Bool {
        guard let plugin else { return false }
        let sel = NSSelectorFromString("isCameraActive")
        guard plugin.responds(to: sel) else { return false }
        let result = plugin.perform(sel)
        return (result?.takeUnretainedValue() as? NSNumber)?.boolValue ?? false
    }

}
