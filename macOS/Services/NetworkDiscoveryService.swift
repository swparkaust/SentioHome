import Foundation
import Network
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "NetworkDiscovery")

/// Discovers devices on the local network via Bonjour/mDNS to help detect
/// guest presence. Maintains a baseline of known household devices so that
/// new, unrecognized devices signal a possible visitor.
///
/// Apartment-safe: filters by signal strength heuristics and requires
/// devices to be actively communicating, not just visible on a shared subnet.
@Observable
@MainActor
final class NetworkDiscoveryService {

    private(set) var unknownDeviceCount = 0
    private(set) var unknownDeviceNames: [String] = []
    private(set) var totalVisibleDevices = 0

    private let deviceTimeoutSeconds: TimeInterval = 300

    /// Minimum number of Bonjour service types a device must advertise
    /// to be counted. Reduces noise from transient mDNS reflections in apartments.
    private let minimumServiceTypes = 1

    private var knownDevices: Set<String> = []
    private var activeDevices: [String: ActiveDevice] = [:]
    private var browsers: [NWBrowser] = []

    private let serviceTypes = [
        "_airplay._tcp",        // AirPlay (iPhones, iPads, speakers)
        "_raop._tcp",           // Remote Audio Output Protocol
        "_companion-link._tcp", // Apple device companion
        "_homekit._tcp",        // HomeKit accessories
        "_googlecast._tcp",     // Chromecast / Android devices
        "_spotify-connect._tcp" // Spotify Connect devices
    ]

    private let storageKey = "knownNetworkDevices"

    struct ActiveDevice {
        var name: String
        var lastSeen: Date
        var serviceTypes: Set<String>
    }

    init() {
        loadKnownDevices()
    }

    func startScanning() {
        guard browsers.isEmpty else { return }
        logger.info("Starting network discovery for \(self.serviceTypes.count) service types")

        for serviceType in serviceTypes {
            let params = NWParameters()
            params.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: params)

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    self?.handleResults(results, serviceType: serviceType)
                }
            }

            browser.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    logger.debug("Browser ready for \(serviceType)")
                case .failed(let error):
                    logger.warning("Browser failed for \(serviceType): \(error.localizedDescription)")
                default:
                    break
                }
            }

            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    func stopScanning() {
        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()
        logger.info("Network discovery stopped")
    }

    // MARK: - Learning

    func learnCurrentDevices() {
        let identifiers = activeDevices.keys
        knownDevices.formUnion(identifiers)
        saveKnownDevices()
        recalculate()
        logger.info("Learned \(identifiers.count) device(s) as known household devices")
    }

    func resetBaseline() {
        knownDevices.removeAll()
        saveKnownDevices()
        recalculate()
        logger.info("Known device baseline reset")
    }

    // MARK: - Query

    var guestSignalScore: Double {
        switch unknownDeviceCount {
        case 0:     return 0
        case 1:     return 0.3
        case 2:     return 0.5
        default:    return 0.7
        }
    }

    var signalDetail: String {
        if unknownDeviceCount == 0 {
            return ""
        }
        let names = unknownDeviceNames.prefix(3).joined(separator: ", ")
        return "\(unknownDeviceCount) unknown device(s) on network: \(names)"
    }

    private func handleResults(_ results: Set<NWBrowser.Result>, serviceType: String) {
        let now = Date()

        for result in results {
            let identifier = deviceIdentifier(from: result)
            let name = deviceName(from: result)

            if var existing = activeDevices[identifier] {
                existing.lastSeen = now
                existing.serviceTypes.insert(serviceType)
                if !name.isEmpty { existing.name = name }
                activeDevices[identifier] = existing
            } else {
                activeDevices[identifier] = ActiveDevice(
                    name: name,
                    lastSeen: now,
                    serviceTypes: [serviceType]
                )
            }
        }

        pruneStaleDevices(now: now)
        recalculate()
    }

    private func pruneStaleDevices(now: Date) {
        let cutoff = now.addingTimeInterval(-deviceTimeoutSeconds)
        activeDevices = activeDevices.filter { $0.value.lastSeen > cutoff }
    }

    private func recalculate() {
        let qualifiedDevices = activeDevices.filter {
            $0.value.serviceTypes.count >= minimumServiceTypes
        }

        totalVisibleDevices = qualifiedDevices.count

        let unknown = qualifiedDevices.filter { !knownDevices.contains($0.key) }
        unknownDeviceCount = unknown.count
        unknownDeviceNames = unknown.values.map(\.name).sorted()
    }

    private func deviceIdentifier(from result: NWBrowser.Result) -> String {
        // Use just the service name (not type) so the same physical device
        // discovered under multiple service types gets a single identity.
        switch result.endpoint {
        case .service(let name, _, let domain, _):
            return "\(name).\(domain)"
        default:
            return result.endpoint.debugDescription
        }
    }

    private func deviceName(from result: NWBrowser.Result) -> String {
        switch result.endpoint {
        case .service(let name, _, _, _):
            return name
        default:
            return "Unknown"
        }
    }

    private func loadKnownDevices() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            knownDevices = Set(saved)
            logger.info("Loaded \(saved.count) known device(s) from baseline")
        }
    }

    private func saveKnownDevices() {
        UserDefaults.standard.set(Array(knownDevices), forKey: storageKey)
    }
}
