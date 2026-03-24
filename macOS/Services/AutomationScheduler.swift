import Foundation
@preconcurrency import UserNotifications
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "Scheduler")

/// Runs the automation loop: gather context → ask Intelligence → execute actions.
/// Fires on a repeating timer configurable from Settings.
@Observable
@MainActor
final class AutomationScheduler {

    private(set) var nextRunDate: Date?
    private(set) var isRunning = true
    private(set) var lastError: String?

    private let contextEngine: ContextEngine
    private let intelligenceEngine: IntelligenceEngine
    private let homeKit: HomeKitService
    private let cloudSync: CloudSyncService
    private let actionLog: ActionLog
    private let preferenceMemory: PreferenceMemory
    private let voiceService: VoiceService
    private let musicService: MusicService
    private let calendarService: CalendarService
    private let screenActivity: ScreenActivityService
    private let guestDetection: GuestDetectionService
    private let networkDiscovery: NetworkDiscoveryService
    private let bleScanner: BLEScannerService
    private let voiceThrottler = VoiceThrottler()
    private let overrideTracker: OverrideTracker
    private let conversationManager: ConversationManager

    private var timer: DispatchSourceTimer?
    private var intervalMinutes: Double

    private var activityToken: NSObjectProtocol?
    private var cloudKitObserver: NSObjectProtocol?
    private var intervalRevertTask: Task<Void, Never>?

    var adaptiveScheduling = true

    private var previousUserIsHome: Bool?
    private var previousSleepState: String?
    private var previousApproaching: Bool?

    private var departureSweepDone = false

    private var lastProcessedRequestID: String?
    private var requestPollTask: Task<Void, Never>?

    /// Hard gate — AI must never control locks, garage doors, or security.
    private static let safetyCriticalTypes: Set<String> = [
        "targetLockState", "targetSecuritySystemState", "targetDoorState"
    ]

    private func filterSafetyCritical(_ actions: [DeviceAction]) -> ([DeviceAction], [DeviceAction]) {
        actions.reduce(into: ([DeviceAction](), [DeviceAction]())) { result, action in
            if Self.safetyCriticalTypes.contains(action.characteristic) {
                result.1.append(action)
            } else {
                result.0.append(action)
            }
        }
    }

    init(
        contextEngine: ContextEngine,
        intelligenceEngine: IntelligenceEngine,
        homeKit: HomeKitService,
        cloudSync: CloudSyncService,
        actionLog: ActionLog,
        preferenceMemory: PreferenceMemory,
        voiceService: VoiceService,
        musicService: MusicService,
        calendarService: CalendarService,
        screenActivity: ScreenActivityService,
        guestDetection: GuestDetectionService,
        networkDiscovery: NetworkDiscoveryService,
        bleScanner: BLEScannerService,
        overrideTracker: OverrideTracker,
        conversationManager: ConversationManager,
        intervalMinutes: Double = 5
    ) {
        self.contextEngine = contextEngine
        self.intelligenceEngine = intelligenceEngine
        self.homeKit = homeKit
        self.cloudSync = cloudSync
        self.actionLog = actionLog
        self.preferenceMemory = preferenceMemory
        self.voiceService = voiceService
        self.musicService = musicService
        self.calendarService = calendarService
        self.screenActivity = screenActivity
        self.guestDetection = guestDetection
        self.networkDiscovery = networkDiscovery
        self.bleScanner = bleScanner
        self.overrideTracker = overrideTracker
        self.conversationManager = conversationManager
        self.intervalMinutes = intervalMinutes
    }

    // MARK: - Lifecycle

    func start() {
        logger.info("Scheduler starting with \(self.intervalMinutes)-minute interval")
        isRunning = true

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Home automation server — must remain awake"
        )

        scheduleNext()

        Task {
            await cloudSync.initializeSchemaIfNeeded()
            await cloudSync.subscribeToUpdates()
            await cloudSync.subscribeToUserRequests()
        }
        screenActivity.startMonitoring()
        networkDiscovery.startScanning()
        bleScanner.startScanning()
        Task { await calendarService.requestAccess() }

        Task { await cloudSync.subscribeToUserRequests() }
        startUserRequestPolling()
        conversationManager.startCleanupLoop()

        cloudKitObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitRemoteNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                logger.info("CloudKit push received — triggering immediate pull")
                await self.cloudSync.pullLatestCompanionData()
                await self.checkForUserRequest()
            }
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            await runNow()
        }
    }

    func pause() {
        isRunning = false
        timer?.cancel()
        timer = nil
        requestPollTask?.cancel()
        requestPollTask = nil
        intervalRevertTask?.cancel()
        intervalRevertTask = nil
        conversationManager.stopCleanupLoop()
        nextRunDate = nil
        if let observer = cloudKitObserver {
            NotificationCenter.default.removeObserver(observer)
            cloudKitObserver = nil
        }
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
        logger.info("Scheduler paused")
    }

    func resume() {
        isRunning = true

        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .automaticTerminationDisabled, .suddenTerminationDisabled],
                reason: "Home automation server — must remain awake"
            )
        }

        if cloudKitObserver == nil {
            cloudKitObserver = NotificationCenter.default.addObserver(
                forName: .cloudKitRemoteNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    logger.info("CloudKit push received — triggering immediate pull")
                    await self.cloudSync.pullLatestCompanionData()
                    await self.checkForUserRequest()
                }
            }
        }

        departureSweepDone = false

        startUserRequestPolling()
        conversationManager.startCleanupLoop()

        scheduleNext()
        logger.info("Scheduler resumed")
    }

    func updateInterval(minutes: Double) {
        intervalMinutes = minutes
        if isRunning {
            timer?.cancel()
            scheduleNext()
        }
        logger.info("Interval updated to \(minutes) minutes")
    }

    // MARK: - Execution

    func runNow() async {
        guard homeKit.isReady else {
            logger.info("HomeKit not ready yet, skipping cycle")
            return
        }

        syncThrottlerSettings()
        lastError = nil

        do {
            await cloudSync.pullLatestCompanionData()
            let context = await gatherFreshContext()

            let houseOccupied = context.userIsHome
                || (context.otherOccupantsHome ?? false)
                || (context.guestsLikelyPresent ?? false)

            if context.userIsHome || houseOccupied {
                departureSweepDone = false
            }

            // Away mode: only active when the house is truly empty
            if !context.userIsHome && !houseOccupied && departureSweepDone {
                if let motionRooms = context.activeMotionRooms, !motionRooms.isEmpty {
                    await postAwayMotionAlert(rooms: motionRooms)
                    logger.warning("Motion while away in: \(motionRooms.joined(separator: ", "))")
                }
                if context.approachingHome != true {
                    logger.info("Away mode (house empty) — skipping full LLM cycle")
                    await cloudSync.pruneOldRecords()
                    return
                }
            }

            guard intelligenceEngine.isAvailable else {
                logger.warning("Apple Intelligence model not available — skipping cycle")
                lastError = "Model assets are unavailable. Enable Apple Intelligence in System Settings."
                return
            }

            let plan = try await intelligenceEngine.generatePlan(
                for: context,
                preferenceHistory: preferenceMemory.fullPromptSection,
                activeOverrides: overrideTracker.promptSection
            )

            if !context.userIsHome && !houseOccupied && !departureSweepDone {
                departureSweepDone = true
                logger.info("Departure sweep complete — house is empty, entering away mode")
            }

            // Hard gate: enforce override/safety rules even if the model ignores the prompt
            if !plan.actions.isEmpty {
                let (safeActions, blockedSafety) = filterSafetyCritical(plan.actions)
                if !blockedSafety.isEmpty {
                    let names = blockedSafety.map { "\($0.accessoryName).\($0.characteristic)" }
                    logger.warning("Blocked \(blockedSafety.count) safety-critical action(s): \(names.joined(separator: ", "))")
                }

                let (allowed, blocked) = overrideTracker.filterActions(safeActions)

                if !blocked.isEmpty {
                    let names = blocked.map { "\($0.accessoryName).\($0.characteristic)" }
                    logger.info("Blocked \(blocked.count) action(s) due to active overrides: \(names.joined(separator: ", "))")
                }

                if !allowed.isEmpty {
                    let previousValues = snapshotValues(for: allowed)
                    await homeKit.execute(allowed)
                    actionLog.append(plan: plan, previousValues: previousValues)
                    await postNotification(plan: plan, entryID: actionLog.entries.first?.id)

                    if context.userIsHome {
                        preferenceMemory.watchForOverrides(
                            actions: allowed,
                            context: context,
                            homeKit: homeKit
                        )
                    }
                }
            }

            if let comm = plan.communication {
                let airPodsWorn = context.airPodsInEar ?? false
                let decision = voiceThrottler.evaluate(
                    message: comm.message,
                    expectsReply: comm.expectsReply,
                    route: comm.route,
                    sleepState: context.sleepState,
                    isInEvent: context.isInEvent ?? false,
                    cameraInUse: context.macCameraInUse ?? false,
                    userIsHome: context.userIsHome,
                    houseOccupied: houseOccupied,
                    guestsPresent: context.guestsLikelyPresent ?? false,
                    airPodsConnected: airPodsWorn
                )

                switch decision {
                case .allow:
                    await voiceService.execute(comm, airPodsConnected: airPodsWorn)
                    voiceThrottler.recordAnnouncement(
                        message: comm.message,
                        expectsReply: comm.expectsReply
                    )

                case .forcePrivate(let reason):
                    if airPodsWorn {
                        var privateComm = comm
                        privateComm.route = "airpods"
                        await voiceService.execute(privateComm, airPodsConnected: true)
                        voiceThrottler.recordAnnouncement(
                            message: comm.message,
                            expectsReply: comm.expectsReply
                        )
                        logger.info("Voice forced to AirPods: \(reason)")
                    } else {
                        logger.info("Voice suppressed (AirPods not in ear): \(reason)")
                    }

                case .suppress(let reason):
                    logger.info("Voice suppressed: \(reason) — \"\(comm.message.prefix(60))\"")
                }
            }

            if let music = plan.music, houseOccupied || context.approachingHome == true {
                await musicService.execute(music)
            }

            contextEngine.musicAvailable = musicService.hasSubscription
            contextEngine.musicIsPlaying = musicService.isPlaying
            contextEngine.musicTrackName = musicService.currentTrackName
            contextEngine.musicMood = musicService.currentMood

            if plan.actions.isEmpty && (plan.communication != nil || plan.music != nil) {
                actionLog.append(plan: plan)
            } else if plan.actions.isEmpty && plan.communication == nil && plan.music == nil {
                logger.info("No changes needed")
            }

            await cloudSync.pruneOldRecords()
            preferenceMemory.compressOldOverrides()
            await homeKit.emergencyHandler?.checkSensorReachability()
            intelligenceEngine.resetSession()

            if adaptiveScheduling {
                adaptInterval(context: context)
            }

        } catch {
            lastError = error.localizedDescription
            logger.error("Automation cycle failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Context Refresh

    private func gatherFreshContext() async -> HomeContext {
        calendarService.refreshEvents()
        contextEngine.calendarEvents = calendarService.upcomingEvents
        contextEngine.isInEvent = calendarService.isInEvent
        contextEngine.macDisplayOn = screenActivity.displayIsOn
        contextEngine.macIsIdle = screenActivity.isIdle
        contextEngine.macFrontmostApp = screenActivity.frontmostApp
        contextEngine.macInferredActivity = screenActivity.inferredActivity
        contextEngine.macCameraInUse = screenActivity.cameraInUse

        let occupants = await cloudSync.countRecentOccupants()
        contextEngine.occupantCount = occupants
        contextEngine.otherOccupantsHome = occupants > 1

        guestDetection.evaluate(
            calendarEvents: calendarService.upcomingEvents,
            isInEvent: calendarService.isInEvent,
            userIsHome: contextEngine.occupantCount >= 1,
            userCurrentRoom: homeKit.lastMotionRoom,
            activeMotionRooms: homeKit.activeMotionRooms,
            occupiedRooms: homeKit.occupiedRooms,
            openContacts: homeKit.openContactRooms,
            userActivity: cloudSync.latestIPhoneData?.motionActivity,
            timeOfDay: HomeContext.timeOfDay(from: Date()),
            networkDiscovery: networkDiscovery,
            bleScanner: bleScanner
        )
        contextEngine.guestsLikelyPresent = guestDetection.guestsLikelyPresent
        contextEngine.guestConfidence = guestDetection.confidence
        contextEngine.guestInferenceReason = guestDetection.inferenceReason

        contextEngine.musicAvailable = musicService.hasSubscription
        contextEngine.musicIsPlaying = musicService.isPlaying
        contextEngine.musicTrackName = musicService.currentTrackName
        contextEngine.musicMood = musicService.currentMood

        return await contextEngine.gatherContext()
    }

    // MARK: - Execute Actions (shared pipeline)

    @discardableResult
    private func executeActions(_ actions: [DeviceAction], source: String, summary: String? = nil) async -> [DeviceAction] {
        guard !actions.isEmpty else { return [] }

        let (safeActions, blockedSafety) = filterSafetyCritical(actions)
        if !blockedSafety.isEmpty {
            let names = blockedSafety.map { "\($0.accessoryName).\($0.characteristic)" }
            logger.warning("Blocked \(blockedSafety.count) safety-critical action(s) from \(source): \(names.joined(separator: ", "))")
        }

        let (allowed, blocked) = overrideTracker.filterActions(safeActions)
        if !blocked.isEmpty {
            let names = blocked.map { "\($0.accessoryName).\($0.characteristic)" }
            logger.info("Blocked \(blocked.count) action(s) due to active overrides from \(source): \(names.joined(separator: ", "))")
        }

        if !allowed.isEmpty {
            let previousValues = snapshotValues(for: allowed)
            await homeKit.execute(allowed)
            let logPlan = AutomationPlanV2(
                actions: allowed,
                communication: nil,
                music: nil,
                summary: summary ?? "\(source) — \(allowed.count) action(s)"
            )
            actionLog.append(plan: logPlan, previousValues: previousValues)
        }

        return allowed
    }

    // MARK: - User Request Handling

    func handleLocalRequest(_ message: String) async -> String {
        let conversationID = UUID().uuidString
        let request = UserRequest(
            id: UUID().uuidString,
            message: message,
            timestamp: Date(),
            intent: "auto",
            conversationID: conversationID
        )

        do {
            let context = await gatherFreshContext()

            let (response, actions, music) = try await conversationManager.handleTurn(
                request,
                context: context,
                preferenceHistory: preferenceMemory.fullPromptSection,
                activeOverrides: overrideTracker.promptSection,
                isLocal: true
            )

            await executeActions(actions, source: "local request", summary: response.message)
            if let music {
                await musicService.execute(music)
            }

            if !response.expectsContinuation {
                conversationManager.endConversation(conversationID)
            }

            return response.message
        } catch {
            logger.error("Local request failed: \(error.localizedDescription)")
            return "Something went wrong: \(error.localizedDescription)"
        }
    }

    /// Poll for user requests from the companion app.
    /// Polls every 5 seconds — CloudKit push notifications can also wake this,
    /// but polling ensures we don't miss requests during away mode when the
    /// main automation loop runs infrequently.
    private func startUserRequestPolling() {
        requestPollTask?.cancel()
        requestPollTask = Task {
            while !Task.isCancelled {
                await checkForUserRequest()
                conversationManager.expireStaleConversations()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func checkForUserRequest() async {
        guard let request = await cloudSync.pullLatestUserRequest() else { return }

        guard request.id != lastProcessedRequestID else { return }
        lastProcessedRequestID = request.id

        logger.info("Processing user request: \(request.message.prefix(60))")

        do {
            await cloudSync.pullLatestCompanionData()
            let context = await gatherFreshContext()

            let (response, actions, music) = try await conversationManager.handleTurn(
                request,
                context: context,
                preferenceHistory: preferenceMemory.fullPromptSection,
                activeOverrides: overrideTracker.promptSection
            )

            let executedActions = await executeActions(actions, source: "user request", summary: response.message)
            if let music {
                await musicService.execute(music)
            }

            if !response.expectsContinuation {
                conversationManager.endConversation(request.conversationID)
            }

            var finalResponse = response
            finalResponse.actionsPerformed = executedActions.map {
                "\($0.accessoryName): \($0.characteristic) → \($0.value)"
            }
            try await cloudSync.pushUserResponse(finalResponse)
            logger.info("User request fulfilled: \(response.message.prefix(80))")

        } catch {
            let errorResponse = UserResponse(
                requestID: request.id,
                message: "Sorry, I couldn't process that right now. \(error.localizedDescription)",
                actionsPerformed: [],
                timestamp: Date(),
                expectsContinuation: false,
                conversationID: request.conversationID
            )
            try? await cloudSync.pushUserResponse(errorResponse)
            logger.error("User request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Adaptive Scheduling

    private func adaptInterval(context: HomeContext) {
        let isTransition =
            (previousUserIsHome != nil && previousUserIsHome != context.userIsHome) ||
            (context.approachingHome == true && previousApproaching != true) ||
            (previousSleepState != nil && previousSleepState != context.sleepState)

        previousUserIsHome = context.userIsHome
        previousSleepState = context.sleepState
        previousApproaching = context.approachingHome

        let targetMinutes: Double
        if isTransition {
            targetMinutes = 1
            logger.info("Context transition detected — accelerating to 1-minute interval")
        } else if context.approachingHome == true {
            targetMinutes = 2
        } else if !context.userIsHome && departureSweepDone {
            targetMinutes = 30
        } else if screenActivity.isIdle && !calendarService.isInEvent {
            targetMinutes = 15
        } else {
            targetMinutes = 5
        }

        if targetMinutes != intervalMinutes {
            let previous = intervalMinutes
            intervalMinutes = targetMinutes
            timer?.cancel()
            scheduleNext()
            if isTransition {
                intervalRevertTask?.cancel()
                intervalRevertTask = Task {
                    try? await Task.sleep(for: .seconds(300))  // After 5 minutes, revert
                    guard !Task.isCancelled else { return }
                    if self.intervalMinutes < 5 {
                        self.intervalMinutes = max(previous, 5)
                        self.timer?.cancel()
                        self.scheduleNext()
                        logger.info("Reverted to \(self.intervalMinutes)-minute interval")
                    }
                }
            }
        }
    }

    /// Reads voice throttle settings from UserDefaults (@AppStorage in SettingsView)
    /// and pushes them into the VoiceThrottler instance. Called at the start of each
    /// automation cycle so settings changes take effect without restarting.
    private func syncThrottlerSettings() {
        let defaults = UserDefaults.standard
        voiceThrottler.maxAnnouncementsPerHour = defaults.object(forKey: "maxVoicePerHour") as? Int ?? 6
        voiceThrottler.enforceQuietHours = defaults.object(forKey: "enforceQuietHours") as? Bool ?? true
        voiceThrottler.quietHoursStart = defaults.object(forKey: "quietHoursStart") as? Int ?? 23
        voiceThrottler.quietHoursEnd = defaults.object(forKey: "quietHoursEnd") as? Int ?? 7
    }

    private func scheduleNext() {
        timer?.cancel()
        let interval = intervalMinutes * 60
        nextRunDate = Date().addingTimeInterval(interval)

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + interval, repeating: interval)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.nextRunDate = Date().addingTimeInterval(interval)
                await self.runNow()
            }
        }
        source.resume()
        timer = source
    }

    // MARK: - Notifications

    static let notificationCategoryID = "AUTOMATION_ACTION"
    static let undoActionID = "UNDO_ACTION"
    static let okActionID = "OK_ACTION"

    static func registerNotificationActions() {
        let undoAction = UNNotificationAction(
            identifier: undoActionID,
            title: "Undo",
            options: [.destructive]
        )
        let okAction = UNNotificationAction(
            identifier: okActionID,
            title: "OK",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: notificationCategoryID,
            actions: [undoAction, okAction],
            intentIdentifiers: [],
            options: []
        )
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            var categories = existing
            categories.insert(category)
            center.setNotificationCategories(categories)
        }
    }

    private func snapshotValues(for actions: [DeviceAction]) -> [String: Double] {
        var snapshot: [String: Double] = [:]
        for action in actions {
            let key = "\(action.accessoryID).\(action.characteristic)"
            if let value = homeKit.readValue(accessoryID: action.accessoryID, characteristic: action.characteristic) {
                snapshot[key] = value
            }
        }
        return snapshot
    }

    private func postNotification(plan: AutomationPlanV2, entryID: UUID? = nil) async {
        guard UserDefaults.standard.bool(forKey: "enableNotifications") else { return }

        let content = UNMutableNotificationContent()
        content.title = "Sentio Home"
        content.body = plan.summary
        content.sound = nil
        content.categoryIdentifier = Self.notificationCategoryID

        // Entry ID lets the notification delegate find previousValues for undo
        let notificationID: String
        if let entryID {
            notificationID = "automation-\(entryID)"
        } else {
            notificationID = "automation-\(UUID())"
        }

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private func postAwayMotionAlert(rooms: [String]) async {
        let content = UNMutableNotificationContent()
        content.title = "Sentio Home — Motion While Away"
        content.body = "Motion detected in \(rooms.joined(separator: ", ")) while nobody is home."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "away-motion-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
