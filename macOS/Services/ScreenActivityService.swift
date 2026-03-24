import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "ScreenActivity")

/// Monitors the Mac's display state, frontmost app, and camera/mic usage
/// to provide additional context for the Intelligence Engine.
///
/// Routes native macOS API calls (CoreGraphics, IOKit) through the
/// StatusBarPlugin bridge since these aren't available in Mac Catalyst.
@Observable
@MainActor
final class ScreenActivityService {

    private(set) var displayIsOn = true
    private(set) var frontmostApp: String?
    private(set) var frontmostAppBundleIdentifier: String?
    private(set) var isIdle = false
    private(set) var inferredActivity: String?
    private(set) var cameraInUse = false

    private var timer: DispatchSourceTimer?

    var statusBarBridge: StatusBarBridge?

    func startMonitoring() {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: 10)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        source.resume()
        timer = source
        logger.info("Screen activity monitoring started")
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }

    private func refresh() {
        displayIsOn = !(statusBarBridge?.isDisplayAsleep() ?? false)
        let idleSeconds = statusBarBridge?.systemIdleTime() ?? 0
        isIdle = idleSeconds > 300

        let (appName, bundleID) = detectFrontmostApp()
        frontmostApp = appName
        frontmostAppBundleIdentifier = bundleID
        cameraInUse = checkCameraUsage(bundleID: bundleID, appName: appName)
        inferredActivity = classifyApp(bundleID: bundleID, name: appName)
    }

    // MARK: - Frontmost App Detection

    private func detectFrontmostApp() -> (name: String?, bundleID: String?) {
        if let bridge = statusBarBridge {
            let bundleID = bridge.frontmostAppBundleID()
            let name = bridge.frontmostAppName()
            if bundleID != nil || name != nil {
                return (name, bundleID)
            }
        }
        return (nil, nil)
    }

    // MARK: - App Classification

    private func classifyApp(bundleID: String?, name: String?) -> String? {
        AppClassifier.classify(bundleID: bundleID, name: name, cameraInUse: cameraInUse)
    }

    // MARK: - Camera Detection

    private func checkCameraUsage(bundleID: String?, appName: String?) -> Bool {
        if let bridge = statusBarBridge {
            return bridge.isCameraActive()
        }

        // Fallback: infer from dedicated video apps only.
        let dedicatedVideoApps: Set<String> = [
            "us.zoom.xos",
            "com.apple.FaceTime",
        ]

        if let bundleID, dedicatedVideoApps.contains(bundleID) {
            return true
        }

        return false
    }

}
