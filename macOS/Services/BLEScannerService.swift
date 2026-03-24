import Foundation
import CoreBluetooth
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "BLEScanner")

/// Scans for nearby Bluetooth Low Energy peripherals to help detect guest
/// presence. Maintains a baseline of known household BLE devices and counts
/// unknown peripherals as potential visitors.
///
/// Apartment-safe: uses RSSI thresholds to filter out through-wall signals
/// from neighboring units, and requires sustained visibility to count a device.
@Observable
@MainActor
final class BLEScannerService: NSObject {

    private(set) var unknownPeripheralCount = 0
    private(set) var totalPeripheralCount = 0
    private(set) var bluetoothDenied = false

    /// RSSI threshold: only count devices stronger than this value.
    /// -60 dBm ≈ same room / within ~5 meters. Filters apartment neighbors
    /// whose signals typically arrive at -70 to -90 dBm through walls.
    private let rssiThreshold: Int = -60

    /// A device must be seen in at least this many consecutive scan windows
    /// to be counted. Reduces transient false positives from passersby.
    private let minimumSightings = 2

    /// How long a peripheral stays in the active set without being re-seen.
    private let peripheralTimeoutSeconds: TimeInterval = 180 // 3 minutes

    private let scanDurationSeconds: TimeInterval = 10
    private let scanPauseSeconds: TimeInterval = 50

    private var centralManager: CBCentralManager?
    private var isScanning = false

    private var knownPeripherals: Set<String> = []
    private var trackedPeripherals: [String: TrackedPeripheral] = [:]

    private var scanTimer: DispatchSourceTimer?

    private let storageKey = "knownBLEPeripherals"

    struct TrackedPeripheral {
        var name: String?
        var lastSeen: Date
        var bestRSSI: Int
        var sightings: Int
    }

    override init() {
        super.init()
        loadKnownPeripherals()
    }

    func startScanning() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
        logger.info("BLE scanner initialized (RSSI threshold: \(self.rssiThreshold) dBm)")
    }

    func stopScanning() {
        scanTimer?.cancel()
        scanTimer = nil
        centralManager?.stopScan()
        centralManager = nil
        isScanning = false
        logger.info("BLE scanner stopped")
    }

    // MARK: - Learning

    func learnCurrentPeripherals() {
        let closePeripherals = trackedPeripherals.filter {
            $0.value.bestRSSI >= rssiThreshold && $0.value.sightings >= minimumSightings
        }
        knownPeripherals.formUnion(closePeripherals.keys)
        saveKnownPeripherals()
        recalculate()
        logger.info("Learned \(closePeripherals.count) BLE peripheral(s) as known")
    }

    func resetBaseline() {
        knownPeripherals.removeAll()
        saveKnownPeripherals()
        recalculate()
    }

    // MARK: - Query

    var guestSignalScore: Double {
        switch unknownPeripheralCount {
        case 0:     return 0
        case 1:     return 0.3
        case 2:     return 0.5
        default:    return 0.65
        }
    }

    var signalDetail: String {
        if unknownPeripheralCount == 0 { return "" }
        return "\(unknownPeripheralCount) unknown BLE device(s) nearby (RSSI > \(rssiThreshold) dBm)"
    }

    // MARK: - Scan Cycling

    private func beginScanCycle() {
        guard let central = centralManager, central.state == .poweredOn else { return }

        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        isScanning = true

        scanTimer?.cancel()
        let stopTimer = DispatchSource.makeTimerSource(queue: .main)
        stopTimer.schedule(deadline: .now() + scanDurationSeconds)
        stopTimer.setEventHandler { [weak self] in
            Task { @MainActor in self?.endScanWindow() }
        }
        stopTimer.resume()
        scanTimer = stopTimer
    }

    private func endScanWindow() {
        centralManager?.stopScan()
        isScanning = false

        let now = Date()
        let cutoff = now.addingTimeInterval(-peripheralTimeoutSeconds)
        trackedPeripherals = trackedPeripherals.filter { $0.value.lastSeen > cutoff }
        recalculate()

        let nextTimer = DispatchSource.makeTimerSource(queue: .main)
        nextTimer.schedule(deadline: .now() + scanPauseSeconds)
        nextTimer.setEventHandler { [weak self] in
            Task { @MainActor in self?.beginScanCycle() }
        }
        nextTimer.resume()
        scanTimer = nextTimer
    }

    private func recalculate() {
        let qualified = trackedPeripherals.filter {
            $0.value.bestRSSI >= rssiThreshold && $0.value.sightings >= minimumSightings
        }

        totalPeripheralCount = qualified.count
        let unknown = qualified.filter { !knownPeripherals.contains($0.key) }
        unknownPeripheralCount = unknown.count
    }

    private func loadKnownPeripherals() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            knownPeripherals = Set(saved)
        }
    }

    private func saveKnownPeripherals() {
        UserDefaults.standard.set(Array(knownPeripherals), forKey: storageKey)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEScannerService: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        let authorization = CBManager.authorization
        Task { @MainActor in
            bluetoothDenied = (authorization == .denied || authorization == .restricted)
            switch state {
            case .poweredOn:
                logger.info("Bluetooth powered on — starting scan cycle")
                beginScanCycle()
            case .poweredOff:
                logger.info("Bluetooth powered off")
                isScanning = false
            case .unauthorized:
                bluetoothDenied = true
                logger.warning("Bluetooth unauthorized")
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiValue = RSSI.intValue
        guard rssiValue >= -80 else { return }

        let identifier = peripheral.identifier.uuidString
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String

        Task { @MainActor in
            let now = Date()
            if var existing = trackedPeripherals[identifier] {
                existing.lastSeen = now
                existing.sightings += 1
                existing.bestRSSI = max(existing.bestRSSI, rssiValue)
                if let name { existing.name = name }
                trackedPeripherals[identifier] = existing
            } else {
                trackedPeripherals[identifier] = TrackedPeripheral(
                    name: name,
                    lastSeen: now,
                    bestRSSI: rssiValue,
                    sightings: 1
                )
            }
        }
    }
}
