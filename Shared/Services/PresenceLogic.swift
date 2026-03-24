import Foundation
import CoreLocation

/// Pure-logic presence detection functions extracted from ContextEngine
/// for testability. No framework dependencies beyond CoreLocation.
enum PresenceLogic {

    static func recent(_ data: CompanionData?, now: Date = Date()) -> CompanionData? {
        guard let data, now.timeIntervalSince(data.timestamp) < 600 else { return nil }
        return data
    }

    static func bestRecent(
        _ a: CompanionData?,
        _ b: CompanionData?,
        keyPath: KeyPath<CompanionData, Double?>,
        now: Date = Date()
    ) -> CompanionData? {
        let candidates = [recent(a, now: now), recent(b, now: now)]
            .compactMap { $0 }
            .filter { $0[keyPath: keyPath] != nil }
        return candidates.max { $0.timestamp < $1.timestamp }
    }

    static func determinePresence(
        companion: CompanionData?,
        homeLocation: CLLocation?,
        radiusMeters: Double = 100
    ) -> Bool {
        if let companion,
           let lat = companion.latitude,
           let lon = companion.longitude {
            let companionLocation = CLLocation(latitude: lat, longitude: lon)
            if let home = homeLocation {
                return companionLocation.distance(from: home) < radiusMeters
            }
        }

        if let activity = companion?.motionActivity {
            switch activity {
            case "stationary":
                return true
            case "driving":
                return false
            default:
                return true
            }
        }

        return true
    }
}
