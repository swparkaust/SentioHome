import SwiftUI

struct SettingsView: View {

    let scheduler: AutomationScheduler?
    let preferenceMemory: PreferenceMemory?
    let guestDetection: GuestDetectionService?
    let networkDiscovery: NetworkDiscoveryService?
    let bleScanner: BLEScannerService?
    let voiceService: VoiceService?

    @AppStorage("automationIntervalMinutes") private var intervalMinutes: Double = 5
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("enableCompanion") private var enableCompanion = true

    @AppStorage("maxVoicePerHour") private var maxVoicePerHour = 6
    @AppStorage("enforceQuietHours") private var enforceQuietHours = true
    @AppStorage("quietHoursStart") private var quietStart = 23
    @AppStorage("quietHoursEnd") private var quietEnd = 7

    @Environment(\.dismiss) private var dismiss
    @State private var showingResetConfirmation = false
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("settings.doneButton")
            }
            .padding(.bottom, 4)

            Section("Automation") {
                HStack {
                    Text("Check interval")
                    Spacer()
                    Picker("", selection: $intervalMinutes) {
                        Text("1 min").tag(1.0)
                        Text("2 min").tag(2.0)
                        Text("5 min").tag(5.0)
                        Text("10 min").tag(10.0)
                        Text("15 min").tag(15.0)
                        Text("30 min").tag(30.0)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    .accessibilityIdentifier("settings.automation.interval")
                }
            }

            Section("Learned Preferences") {
                if let memory = preferenceMemory {
                    LabeledContent("Overrides recorded", value: "\(memory.overrides.count)")
                        .accessibilityIdentifier("settings.preferences.overridesCount")
                    if let latest = memory.recentOverrides.first {
                        LabeledContent("Most recent", value: latest.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .accessibilityIdentifier("settings.preferences.mostRecent")
                    }
                    if memory.pendingWatches > 0 {
                        LabeledContent("Watching for changes", value: "\(memory.pendingWatches) device(s)")
                            .accessibilityIdentifier("settings.preferences.pendingWatches")
                    }
                }

                Text("Sentio learns from your manual adjustments. When you change a device shortly after Sentio sets it, that's recorded as a preference and used to make better decisions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset All Preferences", role: .destructive) {
                    showingResetConfirmation = true
                }
                .accessibilityIdentifier("settings.preferences.resetButton")
                .confirmationDialog(
                    "Reset all learned preferences?",
                    isPresented: $showingResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive) {
                        preferenceMemory?.resetAll()
                    }
                    .accessibilityIdentifier("settings.preferences.resetConfirmButton")
                } message: {
                    Text("Sentio will forget everything it has learned about your preferences and start fresh. This cannot be undone.")
                }
            }

            Section("Guest Detection") {
                if let guest = guestDetection {
                    Toggle("Apartment mode (require correlated signals)", isOn: Binding(
                        get: { guest.apartmentMode },
                        set: { guest.apartmentMode = $0 }
                    ))
                    .accessibilityIdentifier("settings.guestDetection.apartmentMode")
                    Text("In apartments, single signals like motion or network devices may come from neighbors. Apartment mode requires at least two independent signals before reporting guests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let network = networkDiscovery {
                    LabeledContent("Known network devices", value: "\(network.totalVisibleDevices - network.unknownDeviceCount)")
                        .accessibilityIdentifier("settings.guestDetection.knownNetworkDevices")
                    LabeledContent("Unknown network devices", value: "\(network.unknownDeviceCount)")
                        .accessibilityIdentifier("settings.guestDetection.unknownNetworkDevices")
                    Button("Learn Current Network Devices") {
                        network.learnCurrentDevices()
                    }
                    .help("Mark all currently visible network devices as known household devices")
                    .accessibilityIdentifier("settings.guestDetection.learnNetworkButton")
                }

                if let ble = bleScanner {
                    LabeledContent("Known BLE peripherals", value: "\(ble.totalPeripheralCount - ble.unknownPeripheralCount)")
                        .accessibilityIdentifier("settings.guestDetection.knownBLEDevices")
                    LabeledContent("Unknown BLE peripherals", value: "\(ble.unknownPeripheralCount)")
                        .accessibilityIdentifier("settings.guestDetection.unknownBLEDevices")
                    Button("Learn Current BLE Devices") {
                        ble.learnCurrentPeripherals()
                    }
                    .help("Mark all nearby Bluetooth devices as known household devices")
                    .accessibilityIdentifier("settings.guestDetection.learnBLEButton")
                }

                Button("Reset Device Baselines", role: .destructive) {
                    networkDiscovery?.resetBaseline()
                    bleScanner?.resetBaseline()
                }
                .accessibilityIdentifier("settings.guestDetection.resetBaselinesButton")
            }

            Section("Voice Announcements") {
                Text("Sentio only speaks when something genuinely warrants it — welcoming you home, alerting about an open door, or asking a quick question. Routine device adjustments are always silent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Max per hour", value: "\(maxVoicePerHour)")
                    .accessibilityIdentifier("settings.voice.maxPerHourLabel")
                Stepper("", value: $maxVoicePerHour, in: 0...20)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.voice.maxPerHourStepper")

                Toggle("Quiet hours", isOn: $enforceQuietHours)
                    .accessibilityIdentifier("settings.voice.quietHoursToggle")
                if enforceQuietHours {
                    HStack {
                        Text("Silent from")
                        Picker("", selection: $quietStart) {
                            ForEach(0..<24, id: \.self) { h in
                                Text("\(h):00").tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                        .accessibilityIdentifier("settings.voice.quietHoursStart")
                        Text("to")
                        Picker("", selection: $quietEnd) {
                            ForEach(0..<24, id: \.self) { h in
                                Text("\(h):00").tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                        .accessibilityIdentifier("settings.voice.quietHoursEnd")
                    }
                }
            }

            Section("Notifications") {
                Toggle("Show notification when actions are taken", isOn: $enableNotifications)
                    .accessibilityIdentifier("settings.notifications.enableToggle")
            }

            Section("Companion") {
                Toggle("Accept data from iOS companion", isOn: $enableCompanion)
                    .accessibilityIdentifier("settings.companion.enableToggle")
                Text("The companion app shares sensor data like ambient light and activity to help Sentio make better decisions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                // ServiceManagement (launch-at-login) is not available in Mac Catalyst.
                // Users can add SentioHome to Login Items via System Settings > General > Login Items.
                Text("To launch Sentio at login, add it via System Settings → General → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: "1.0")
                    .accessibilityIdentifier("settings.about.version")
                LabeledContent("Engine", value: "Apple Intelligence (on-device)")
                    .accessibilityIdentifier("settings.about.engine")
            }
        }
        .formStyle(.grouped)
        .onChange(of: intervalMinutes) {
            scheduler?.updateInterval(minutes: intervalMinutes)
        }
    }
}
