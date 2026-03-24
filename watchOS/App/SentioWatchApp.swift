import SwiftUI
import WatchKit
import CoreLocation
import os

@main
struct SentioWatchApp: App {

    @State private var healthService = HealthService()
    @State private var cloudSync = CloudSyncService()
    @State private var locationDelegate = WatchLocationDelegate()
    @State private var locationManager = CLLocationManager()
    @State private var showOnboarding: Bool = {
        if ProcessInfo.processInfo.arguments.contains("--skipOnboarding") { return false }
        if ProcessInfo.processInfo.arguments.contains("--showOnboarding") { return true }
        return !UserDefaults.standard.bool(forKey: "onboardingComplete")
    }()

    var body: some Scene {
        WindowGroup {
            if showOnboarding {
                WatchOnboardingView(isPresented: $showOnboarding)
            } else {
                WatchHomeView(healthService: healthService, cloudSync: cloudSync)
                    .task { await bootstrap() }
            }
        }
    }

    @MainActor
    private func bootstrap() async {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        if !isUITesting {
            await healthService.requestAuthorization()
        }
        healthService.startMonitoring()

        locationManager.delegate = locationDelegate
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }

        await cloudSync.checkAccountStatus()
        await cloudSync.initializeSchemaIfNeeded()

        while !Task.isCancelled {
            await pushData()
            try? await Task.sleep(for: .seconds(120))
        }
    }

    @MainActor
    private func pushData() async {
        let location = locationManager.location

        let data = CompanionData(
            timestamp: Date(),
            source: .watch,
            deviceID: WKInterfaceDevice.current().identifierForVendor?.uuidString,
            motionActivity: healthService.isWorkingOut ? "workout" : nil,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            batteryLevel: nil,
            heartRate: healthService.heartRate,
            heartRateVariability: healthService.heartRateVariability,
            sleepState: healthService.sleepState,
            isWorkingOut: healthService.isWorkingOut,
            wristTemperatureDelta: healthService.wristTemperatureDelta,
            bloodOxygen: healthService.bloodOxygen
        )

        do {
            try await cloudSync.pushCompanionData(data)
        } catch {
            Logger(subsystem: "com.sentio.home.companion.watch", category: "Sync")
                .error("Failed to push companion data: \(error.localizedDescription)")
        }
    }
}

private class WatchLocationDelegate: NSObject, CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}
