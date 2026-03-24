import Foundation
import CoreLocation
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home.companion", category: "Location")

@Observable
@MainActor
final class LocationService: NSObject {

    private(set) var currentLocation: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// True when the user has entered the approach geofence (~1km) but
    /// hasn't entered the home geofence (~100m). Signals "on the way home."
    private(set) var approachingHome = false

    /// The user's home coordinate, inferred from the most frequent overnight
    /// stationary location. Persisted to UserDefaults so it survives restarts.
    private var homeCoordinate: CLLocationCoordinate2D? {
        didSet {
            if let coord = homeCoordinate {
                UserDefaults.standard.set(coord.latitude, forKey: "homeLatitude")
                UserDefaults.standard.set(coord.longitude, forKey: "homeLongitude")
                UserDefaults.standard.set(true, forKey: "homeLocationSet")
            }
        }
    }
    private static let approachRadius: CLLocationDistance = 1000   // 1km
    private static let homeRadius: CLLocationDistance = 100         // 100m
    private nonisolated static let geofenceID = "com.sentio.home.approach"

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.distanceFilter = 50 // meters

        // Restore persisted home location
        if UserDefaults.standard.bool(forKey: "homeLocationSet") {
            let lat = UserDefaults.standard.double(forKey: "homeLatitude")
            let lon = UserDefaults.standard.double(forKey: "homeLongitude")
            homeCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            logger.info("Restored home location: \(lat), \(lon)")
        }
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
        logger.info("Location updates started")
    }

    // MARK: - Geofencing

    func setHomeLocation(_ coordinate: CLLocationCoordinate2D) {
        guard homeCoordinate == nil else {
            logger.debug("Home location already set — ignoring duplicate call")
            return
        }
        homeCoordinate = coordinate

        let region = CLCircularRegion(
            center: coordinate,
            radius: Self.approachRadius,
            identifier: Self.geofenceID
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
        logger.info("Approach geofence set at \(coordinate.latitude), \(coordinate.longitude)")
    }

    private func updateApproachState(location: CLLocation) {
        guard let home = homeCoordinate else { return }
        let homeLocation = CLLocation(latitude: home.latitude, longitude: home.longitude)
        let distance = location.distance(from: homeLocation)

        approachingHome = distance <= Self.approachRadius && distance > Self.homeRadius
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.updateApproachState(location: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == LocationService.geofenceID else { return }
        Task { @MainActor in
            self.approachingHome = true
            logger.info("Entered approach geofence")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == LocationService.geofenceID else { return }
        Task { @MainActor in
            self.approachingHome = false
            logger.info("Exited approach geofence")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.startUpdating()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.warning("Location error: \(error.localizedDescription)")
    }
}
