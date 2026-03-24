import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("com.sentio.home.openSettings")
}

struct MenuBarView: View {

    let homeKit: HomeKitService
    let actionLog: ActionLog
    let preferenceMemory: PreferenceMemory
    let musicService: MusicService
    let calendarService: CalendarService
    let screenActivity: ScreenActivityService
    let guestDetection: GuestDetectionService
    let networkDiscovery: NetworkDiscoveryService
    let bleScanner: BLEScannerService
    let scheduler: AutomationScheduler?

    @State private var quickInput = ""
    @State private var aiResponse: String?
    @State private var isProcessing = false

    private var schedulerIsRunning: Bool { scheduler?.isRunning ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            header
            Divider()

            askSection
            Divider()

            statusSection
            Divider()

            activitySection

            Divider()

            controlsSection
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "house.and.flag.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sentio Home")
                    .font(.headline)
                Text(schedulerIsRunning ? "Automating" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("menuBar.header.statusText")
            }
            Spacer()
            Circle()
                .fill(schedulerIsRunning ? .green : .orange)
                .frame(width: 8, height: 8)
                .accessibilityIdentifier("menuBar.header.statusIndicator")
        }
        .padding(12)
    }

    // MARK: - Quick Ask

    private var askSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Ask or command…", text: $quickInput)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit { submitQuickAsk() }
                    .accessibilityIdentifier("menuBar.quickAsk.input")

                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityIdentifier("menuBar.quickAsk.processingIndicator")
                } else {
                    Button {
                        submitQuickAsk()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(quickInput.isEmpty ? .gray : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(quickInput.isEmpty)
                    .accessibilityIdentifier("menuBar.quickAsk.sendButton")
                }
            }

            if let response = aiResponse {
                Text(response)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .transition(.opacity)
                    .accessibilityIdentifier("menuBar.quickAsk.response")
            }
        }
        .padding(12)
    }

    private func submitQuickAsk() {
        let text = quickInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isProcessing else { return }

        quickInput = ""
        isProcessing = true
        aiResponse = nil

        Task {
            let response = await scheduler?.handleLocalRequest(text)
            withAnimation {
                aiResponse = response
            }
            isProcessing = false

            Task {
                try? await Task.sleep(for: .seconds(10))
                withAnimation {
                    if aiResponse == response {
                        aiResponse = nil
                    }
                }
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(homeKit.allDeviceSnapshots.count) devices", systemImage: "lightbulb.2")
                .accessibilityIdentifier("menuBar.status.deviceCount")
            Label("\(homeKit.homes.count) home(s)", systemImage: "house")
                .accessibilityIdentifier("menuBar.status.homeCount")
            if preferenceMemory.overrides.count > 0 {
                Label("\(preferenceMemory.overrides.count) preferences learned", systemImage: "brain")
                    .accessibilityIdentifier("menuBar.status.preferencesLearned")
            }
            if musicService.isPlaying, let track = musicService.currentTrackName {
                Label(track, systemImage: "music.note")
                    .accessibilityIdentifier("menuBar.status.nowPlaying")
            }
            if calendarService.isInEvent {
                Label("In a meeting", systemImage: "calendar.badge.clock")
                    .accessibilityIdentifier("menuBar.status.inMeeting")
            } else if let next = calendarService.upcomingEvents.first {
                Label("Next: \(next.title) at \(next.startDate.formatted(date: .omitted, time: .shortened))", systemImage: "calendar")
                    .accessibilityIdentifier("menuBar.status.nextEvent")
            }
            if let activity = screenActivity.inferredActivity {
                Label(activity.capitalized, systemImage: "desktopcomputer")
                    .accessibilityIdentifier("menuBar.status.screenActivity")
            }
            if !homeKit.activeMotionRooms.isEmpty {
                Label("Motion: \(homeKit.activeMotionRooms.joined(separator: ", "))", systemImage: "figure.walk")
                    .accessibilityIdentifier("menuBar.status.activeMotion")
            }
            if !homeKit.openContactRooms.isEmpty {
                Label("Open: \(homeKit.openContactRooms.joined(separator: ", "))", systemImage: "door.left.hand.open")
                    .accessibilityIdentifier("menuBar.status.openContacts")
            }
            if guestDetection.guestsLikelyPresent {
                Label("Guests detected (\(Int(guestDetection.confidence * 100))%)", systemImage: "person.2")
                    .accessibilityIdentifier("menuBar.status.guestsDetected")
            }
            if networkDiscovery.unknownDeviceCount > 0 {
                Label("\(networkDiscovery.unknownDeviceCount) unknown network device(s)", systemImage: "wifi")
                    .accessibilityIdentifier("menuBar.status.unknownNetworkDevices")
            }
            if bleScanner.unknownPeripheralCount > 0 {
                Label("\(bleScanner.unknownPeripheralCount) unknown BLE device(s)", systemImage: "antenna.radiowaves.left.and.right")
                    .accessibilityIdentifier("menuBar.status.unknownBLEDevices")
            }
            if preferenceMemory.pendingWatches > 0 {
                Label("Watching \(preferenceMemory.pendingWatches) device(s)", systemImage: "eye")
                    .accessibilityIdentifier("menuBar.status.pendingWatches")
            }
            if let next = scheduler?.nextRunDate {
                Label("Next check: \(next, style: .relative)", systemImage: "clock")
                    .accessibilityIdentifier("menuBar.status.nextCheck")
            } else {
                Label("Next check: —", systemImage: "clock")
                    .accessibilityIdentifier("menuBar.status.nextCheck")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            if actionLog.entries.isEmpty {
                Text("No actions taken yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("menuBar.activity.emptyState")
            } else {
                ForEach(actionLog.entries.prefix(5)) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.summary)
                                .font(.caption)
                            Text(entry.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 4) {
            Button {
                if schedulerIsRunning {
                    scheduler?.pause()
                } else {
                    scheduler?.resume()
                }
            } label: {
                Label(
                    schedulerIsRunning ? "Pause Automation" : "Resume Automation",
                    systemImage: schedulerIsRunning ? "pause.circle" : "play.circle"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menuBar.controls.pauseResume")

            Divider()

            Button {
                Task { await scheduler?.runNow() }
            } label: {
                Label("Run Now", systemImage: "bolt.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menuBar.controls.runNow")

            Divider()

            Button {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menuBar.controls.settings")

            Divider()

            Button(role: .destructive) {
                UIApplication.shared.perform(NSSelectorFromString("terminate:"))
            } label: {
                Label("Quit Sentio Home", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menuBar.controls.quit")
        }
        .padding(8)
    }
}
