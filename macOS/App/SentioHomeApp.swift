import SwiftUI
import UserNotifications
import AVFoundation

// MARK: - App Delegate

/// Prevents the Catalyst app from quitting when the last window is hidden,
/// registers for remote notifications (CloudKit push), and handles lifecycle.
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        return config
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(
            name: .cloudKitRemoteNotification,
            object: nil,
            userInfo: userInfo
        )
        completionHandler(.newData)
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // CloudKit uses its own token management — no action needed here.
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Remote notifications unavailable — CloudKit polling fallback will handle updates.
    }

    /// No-op: don't let discarded scenes trigger termination.
    /// Menu bar apps must survive with zero visible windows.
    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {}
}

extension Notification.Name {
    static let cloudKitRemoteNotification = Notification.Name("com.sentio.home.cloudKitRemoteNotification")
}

@main
struct SentioHomeApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let statusBarBridge = StatusBarBridge()
    @State private var homeKit = HomeKitService()
    @State private var cloudSync = CloudSyncService()
    @State private var actionLog = ActionLog()
    @State private var preferenceMemory = PreferenceMemory()
    @State private var voiceService: VoiceService?
    @State private var musicService = MusicService()
    @State private var calendarService = CalendarService()
    @State private var screenActivity = ScreenActivityService()
    @State private var guestDetection = GuestDetectionService()
    @State private var networkDiscovery = NetworkDiscoveryService()
    @State private var bleScanner = BLEScannerService()
    @State private var overrideTracker = OverrideTracker()
    @State private var emergencyHandler = EmergencyHandler()
    @State private var scheduler: AutomationScheduler?
    @State private var notificationDelegate: NotificationDelegate?
    @State private var showOnboarding: Bool = {
        if ProcessInfo.processInfo.arguments.contains("--skipOnboarding") { return false }
        if ProcessInfo.processInfo.arguments.contains("--showOnboarding") { return true }
        return !UserDefaults.standard.bool(forKey: "onboardingComplete")
    }()
    @State private var showSettings: Bool = ProcessInfo.processInfo.arguments.contains("--showSettings")

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    init() {
        if !ProcessInfo.processInfo.arguments.contains("--uitesting") {
            statusBarBridge.install()
        }
    }

    var body: some Scene {
        WindowGroup {
            if isUITesting {
                uiTestingBody
            } else {
                productionBody
            }
        }
        .defaultSize(width: isUITesting ? 500 : 1, height: isUITesting ? 1200 : 1)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }

    @ViewBuilder
    private var uiTestingBody: some View {
        if showOnboarding {
            MacOnboardingView(isPresented: $showOnboarding)
                .frame(width: 500, height: 600)
        } else if showSettings {
            SettingsView(
                scheduler: scheduler,
                preferenceMemory: preferenceMemory,
                guestDetection: guestDetection,
                networkDiscovery: networkDiscovery,
                bleScanner: bleScanner,
                voiceService: voiceService
            )
            .frame(width: 500, height: 1200)
        } else {
            MenuBarView(
                homeKit: homeKit,
                actionLog: actionLog,
                preferenceMemory: preferenceMemory,
                musicService: musicService,
                calendarService: calendarService,
                screenActivity: screenActivity,
                guestDetection: guestDetection,
                networkDiscovery: networkDiscovery,
                bleScanner: bleScanner,
                scheduler: scheduler
            )
            .frame(width: 360, height: 500)
        }
    }

    @ViewBuilder
    private var productionBody: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(isPresented: $showOnboarding) {
                MacOnboardingView(isPresented: $showOnboarding)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    scheduler: scheduler,
                    preferenceMemory: preferenceMemory,
                    guestDetection: guestDetection,
                    networkDiscovery: networkDiscovery,
                    bleScanner: bleScanner,
                    voiceService: voiceService
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                showHostWindow()
                showSettings = true
            }
            .onChange(of: showSettings) {
                if !showSettings {
                    hideHostWindow()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                scheduler?.pause()
                screenActivity.stopMonitoring()
            }
            .task {
                guard !isUITesting else { return }
                configureTitleBar()

                while showOnboarding {
                    try? await Task.sleep(for: .milliseconds(200))
                }

                hideHostWindow()
                await bootstrap()
            }
    }

    // MARK: - Bootstrap

    @MainActor
    private func bootstrap() async {
        guard scheduler == nil else { return }

        let voice = VoiceService(cloudSync: cloudSync, homeKit: homeKit)
        voiceService = voice

        homeKit.overrideTracker = overrideTracker
        homeKit.emergencyHandler = emergencyHandler
        emergencyHandler.configure(homeKit: homeKit, cloudSync: cloudSync, voiceService: voice)

        screenActivity.statusBarBridge = statusBarBridge

        await musicService.requestAuthorization()

        let contextEngine = ContextEngine(homeKit: homeKit, cloudSync: cloudSync)
        let intelligenceEngine = IntelligenceEngine()
        let conversationManager = ConversationManager(intelligenceEngine: intelligenceEngine)
        let interval = UserDefaults.standard.double(forKey: "automationIntervalMinutes")

        let newScheduler = AutomationScheduler(
            contextEngine: contextEngine,
            intelligenceEngine: intelligenceEngine,
            homeKit: homeKit,
            cloudSync: cloudSync,
            actionLog: actionLog,
            preferenceMemory: preferenceMemory,
            voiceService: voice,
            musicService: musicService,
            calendarService: calendarService,
            screenActivity: screenActivity,
            guestDetection: guestDetection,
            networkDiscovery: networkDiscovery,
            bleScanner: bleScanner,
            overrideTracker: overrideTracker,
            conversationManager: conversationManager,
            intervalMinutes: interval > 0 ? interval : 5
        )
        scheduler = newScheduler
        newScheduler.start()

        pushMenuBarState()
        startMenuBarRefreshLoop()

        let delegate = NotificationDelegate(actionLog: actionLog, homeKit: homeKit)
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate

        _ = try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .criticalAlert]
        )
        AutomationScheduler.registerNotificationActions()
        EmergencyHandler.registerNotificationCategory()
    }

    // MARK: - Menu Bar State

    @MainActor
    private func pushMenuBarState(quickAskResponse: String? = nil) {
        let nextEvent: String? = {
            guard let event = calendarService.upcomingEvents.first else { return nil }
            return "\(event.title) at \(event.startDate.formatted(date: .omitted, time: .shortened))"
        }()

        statusBarBridge.pushState(
            deviceCount: homeKit.allDeviceSnapshots.count,
            homeCount: homeKit.homes.count,
            preferencesLearned: preferenceMemory.overrides.count,
            isRunning: scheduler?.isRunning ?? true,
            nowPlaying: musicService.isPlaying ? musicService.currentTrackName : nil,
            inMeeting: calendarService.isInEvent,
            nextEvent: nextEvent,
            screenActivity: screenActivity.inferredActivity,
            motionRooms: homeKit.activeMotionRooms.isEmpty ? nil : homeKit.activeMotionRooms.joined(separator: ", "),
            openContacts: homeKit.openContactRooms.isEmpty ? nil : homeKit.openContactRooms.joined(separator: ", "),
            guestsDetected: guestDetection.guestsLikelyPresent ? "Guests detected (\(Int(guestDetection.confidence * 100))%)" : nil,
            unknownNetworkDevices: networkDiscovery.unknownDeviceCount,
            unknownBLEDevices: bleScanner.unknownPeripheralCount,
            pendingWatches: preferenceMemory.pendingWatches,
            nextCheckDate: scheduler?.nextRunDate,
            recentActions: actionLog.entries.prefix(5).map { (summary: $0.summary, timestamp: $0.timestamp) },
            quickAskResponse: quickAskResponse
        )
    }

    @MainActor
    private func startMenuBarRefreshLoop() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.sentio.home.toggleAutomation"),
            object: nil, queue: .main
        ) { [self] _ in
            Task { @MainActor in
                if scheduler?.isRunning == true { scheduler?.pause() } else { scheduler?.resume() }
                pushMenuBarState()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.sentio.home.runNow"),
            object: nil, queue: .main
        ) { [self] _ in
            Task { @MainActor in
                await scheduler?.runNow()
                pushMenuBarState()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.sentio.home.quickAsk"),
            object: nil, queue: .main
        ) { [self] notification in
            guard let message = notification.userInfo?["message"] as? String else { return }
            Task { @MainActor in
                let response = await scheduler?.handleLocalRequest(message)
                pushMenuBarState(quickAskResponse: response)
            }
        }

        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                pushMenuBarState()
            }
        }
    }

    // MARK: - Catalyst Window Management

    private func configureTitleBar() {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  let titlebar = windowScene.titlebar else { continue }
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
            windowScene.activationConditions.canActivateForTargetContentIdentifierPredicate = NSPredicate(value: false)
        }
        #endif
    }

    private func hideHostWindow() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 1, height: 1)
            windowScene.sizeRestrictions?.maximumSize = CGSize(width: 1, height: 1)
            for window in windowScene.windows {
                window.isHidden = true
            }
        }
    }

    private func showHostWindow() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 1, height: 1)
            windowScene.sizeRestrictions?.maximumSize = CGSize(width: 600, height: 800)
            for window in windowScene.windows {
                window.isHidden = false
            }
        }
    }
}
