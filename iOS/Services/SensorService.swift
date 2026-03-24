import Foundation
import AVFoundation
import CoreMotion
@preconcurrency import Intents
import Observation
import UIKit
import os

private let logger = Logger(subsystem: "com.sentio.home.companion", category: "Sensors")

/// Gathers ambient light, motion activity, and AirPods head motion data
/// from the iPhone's sensors and connected accessories.
@Observable
@MainActor
final class SensorService {

    private(set) var ambientLightLux: Double?
    private(set) var currentActivity: String = "unknown"
    private(set) var isMonitoring = false

    // Focus mode — INFocusStatus only exposes whether ANY Focus is active,
    // not which one (Sleep, Work, DND, etc.). Reports "active" or nil.
    private(set) var focusMode: String?

    // AirPods head motion
    private(set) var airPodsConnected = false
    private(set) var airPodsInEar = false
    private(set) var headPitch: Double?         // radians: negative = looking down, positive = looking up
    private(set) var headYaw: Double?           // radians: head rotation left/right
    private(set) var headPosture: String?       // "upright", "reclined", "lookingDown", "nodding"

    private let activityManager = CMMotionActivityManager()
    private let motionManager = CMMotionManager()
    private let headphoneMotion = CMHeadphoneMotionManager()
    private var lightTimer: Timer?
    private var postureTimer: Timer?

    // Smoothing buffer for posture detection
    private var pitchHistory: [Double] = []
    private let pitchHistorySize = 10
    private var focusTimer: Timer?

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        startActivityUpdates()
        startProximityLightEstimation()
        startHeadphoneMotion()
        startFocusMonitoring()
        startAudioRouteMonitoring()

        logger.info("Sensor monitoring started")
    }

    func stopMonitoring() {
        activityManager.stopActivityUpdates()
        motionManager.stopDeviceMotionUpdates()
        headphoneMotion.stopDeviceMotionUpdates()
        lightTimer?.invalidate()
        postureTimer?.invalidate()
        focusTimer?.invalidate()
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        isMonitoring = false
        airPodsConnected = false
        logger.info("Sensor monitoring stopped")
    }

    private func startActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            logger.info("Activity recognition not available")
            return
        }

        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor [weak self] in
                self?.currentActivity = Self.classify(activity)
            }
        }
    }

    private static func classify(_ activity: CMMotionActivity) -> String {
        if activity.automotive { return "driving" }
        if activity.running    { return "running" }
        if activity.cycling    { return "cycling" }
        if activity.walking    { return "walking" }
        if activity.stationary { return "stationary" }
        return "unknown"
    }

    // MARK: - Ambient Light Estimation

    private func startProximityLightEstimation() {
        lightTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let brightness = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.brightness ?? 0
                self.ambientLightLux = Self.estimateLux(fromBrightness: brightness)
            }
        }
    }

    private static func estimateLux(fromBrightness brightness: Double) -> Double {
        let minLux = 1.0
        let maxLux = 10000.0
        return minLux * pow(maxLux / minLux, brightness)
    }

    // MARK: - AirPods Head Motion

    private func startHeadphoneMotion() {
        guard headphoneMotion.isDeviceMotionAvailable else {
            logger.info("Headphone motion not available (no AirPods connected)")
            return
        }

        headphoneMotion.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    self.airPodsConnected = false
                    self.headPitch = nil
                    self.headYaw = nil
                    self.headPosture = nil
                }
                logger.debug("Headphone motion error: \(error.localizedDescription)")
                return
            }

            guard let motion else { return }

            Task { @MainActor in
                self.airPodsConnected = true
                self.headPitch = motion.attitude.pitch
                self.headYaw = motion.attitude.yaw
                self.updatePitchHistory(motion.attitude.pitch)
            }
        }

        postureTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.classifyPosture()
            }
        }

        logger.info("Headphone motion tracking started")
    }

    // MARK: - Audio Route / AirPods In-Ear Detection

    private var routeChangeObserver: NSObjectProtocol?

    private func startAudioRouteMonitoring() {
        updateAirPodsInEarState()

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAirPodsInEarState()
            }
        }
    }

    private func updateAirPodsInEarState() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let airPodsKeywords = ["airpods", "beats fit", "beats solo", "beats studio", "powerbeats"]

        let isRouted = outputs.contains { output in
            let isBluetooth = output.portType == .bluetoothA2DP
                || output.portType == .bluetoothHFP
            let name = output.portName.lowercased()
            return isBluetooth && airPodsKeywords.contains { name.contains($0) }
        }

        let wasInEar = airPodsInEar
        airPodsInEar = isRouted && airPodsConnected

        if airPodsInEar != wasInEar {
            logger.info("AirPods in-ear state: \(self.airPodsInEar)")
        }
    }

    // MARK: - Focus Mode

    private var focusAuthorized = false

    private func startFocusMonitoring() {
        let center = INFocusStatusCenter.default
        center.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    self.focusMode = nil
                    return
                }
                self.focusAuthorized = true
                self.refreshFocusMode()
                self.focusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshFocusMode()
                    }
                }
            }
        }
    }

    private func refreshFocusMode() {
        guard focusAuthorized else { return }
        let center = INFocusStatusCenter.default
        let focusStatus = center.focusStatus
        if focusStatus.isFocused ?? false {
            focusMode = "active"
        } else {
            focusMode = nil
        }
    }

    // MARK: - Posture Classification

    private func updatePitchHistory(_ pitch: Double) {
        pitchHistory.append(pitch)
        if pitchHistory.count > pitchHistorySize {
            pitchHistory.removeFirst()
        }
    }

    private func classifyPosture() {
        guard pitchHistory.count >= 5 else { return }

        let avgPitch = pitchHistory.reduce(0, +) / Double(pitchHistory.count)

        // Detect nodding: significant variance in recent samples
        let variance = pitchHistory.map { ($0 - avgPitch) * ($0 - avgPitch) }.reduce(0, +) / Double(pitchHistory.count)
        let isNodding = variance > 0.02 // threshold for head bobbing

        if isNodding {
            headPosture = "nodding"
        } else if avgPitch < -0.3 {
            headPosture = "lookingDown"
        } else if avgPitch > 0.2 {
            headPosture = "reclined"
        } else {
            headPosture = "upright"
        }
    }
}
