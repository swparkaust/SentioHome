import SwiftUI
import UserNotifications
import os

@main
struct SentioCompanionApp: App {

    @State private var homeKit = HomeKitService()
    @State private var cloudSync = CloudSyncService.shared
    @State private var sensorService = SensorService()
    @State private var locationService = LocationService()
    @State private var voiceService: VoiceService?
    @State private var showOnboarding: Bool = {
        if ProcessInfo.processInfo.arguments.contains("--skipOnboarding") { return false }
        if ProcessInfo.processInfo.arguments.contains("--showOnboarding") { return true }
        return !UserDefaults.standard.bool(forKey: "onboardingComplete")
    }()

    var body: some Scene {
        WindowGroup {
            CompanionHomeView(
                homeKit: homeKit,
                sensorService: sensorService,
                locationService: locationService,
                cloudSync: cloudSync,
                voiceService: voiceService
            )
            .fullScreenCover(isPresented: $showOnboarding) {
                CompanionOnboardingView(isPresented: $showOnboarding)
            }
            .task {
                while showOnboarding {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                await bootstrap()
            }
        }
    }

    @MainActor
    private func bootstrap() async {
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }

        locationService.requestPermission()
        UIDevice.current.isBatteryMonitoringEnabled = true

        let notificationCenter = UNUserNotificationCenter.current()
        try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])

        sensorService.startMonitoring()

        let voice = VoiceService(cloudSync: cloudSync)
        voiceService = voice
        await voice.requestPermissions()
        voice.startListeningForRelays()
        voice.enableTapToTalk()

        while !Task.isCancelled {
            // Only infer home location during overnight hours (10pm–6am) when
            // stationary — the user is very likely at home sleeping. Prevents
            // permanently setting the wrong location if the app is first opened
            // while stationary at work, a coffee shop, etc.
            if let location = locationService.currentLocation,
               sensorService.currentActivity == "stationary" {
                let hour = Calendar.current.component(.hour, from: Date())
                if hour >= 22 || hour < 6 {
                    locationService.setHomeLocation(location.coordinate)
                }
            }

            await pushData()
            try? await Task.sleep(for: .seconds(120))
        }
    }

    @MainActor
    private func pushData() async {
        let data = CompanionData(
            timestamp: Date(),
            source: .iphone,
            deviceID: UIDevice.current.identifierForVendor?.uuidString,
            motionActivity: sensorService.currentActivity,
            latitude: locationService.currentLocation?.coordinate.latitude,
            longitude: locationService.currentLocation?.coordinate.longitude,
            batteryLevel: UIDevice.current.batteryLevel >= 0 ? Double(UIDevice.current.batteryLevel) : nil,
            ambientLightLux: sensorService.ambientLightLux,
            screenBrightness: Double((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.brightness ?? 0),
            airPodsConnected: sensorService.airPodsConnected,
            airPodsInEar: sensorService.airPodsInEar,
            headPosture: sensorService.headPosture,
            focusMode: sensorService.focusMode,
            approachingHome: locationService.approachingHome
        )

        do {
            try await cloudSync.pushCompanionData(data)
        } catch {
            Logger(subsystem: "com.sentio.home.companion", category: "Sync")
                .error("Failed to push companion data: \(error.localizedDescription)")
        }
    }
}
