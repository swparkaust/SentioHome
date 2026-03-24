import SwiftUI

struct CompanionHomeView: View {

    let homeKit: HomeKitService
    let sensorService: SensorService
    let locationService: LocationService
    let cloudSync: CloudSyncService
    let voiceService: VoiceService?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    contextCard
                    voiceCard
                    devicesCard
                }
                .padding()
            }
            .navigationTitle("Sentio")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RemoteChatView(cloudSync: cloudSync)
                    } label: {
                        Image(systemName: "message")
                    }
                    .accessibilityIdentifier("companionHome.toolbar.remoteChatLink")
                }
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: cloudSync.isSyncing)
                .accessibilityIdentifier("companionHome.status.syncIcon")

            Text("Sharing Context")
                .font(.headline)
                .accessibilityIdentifier("companionHome.status.title")

            Text("Sentio is using your iPhone's sensors to help your Mac make smarter home decisions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .accessibilityIdentifier("companionHome.status.card")
    }

    // MARK: - Context Card

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Context", systemImage: "sensor")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ContextRow(
                icon: "sun.max",
                label: "Ambient Light",
                value: sensorService.ambientLightLux.map { "\(Int($0)) lux" } ?? "—"
            )
            .accessibilityIdentifier("companionHome.context.ambientLight")
            ContextRow(
                icon: "figure.walk",
                label: "Activity",
                value: sensorService.currentActivity.capitalized
            )
            .accessibilityIdentifier("companionHome.context.activity")
            ContextRow(
                icon: "location",
                label: "Location",
                value: locationService.approachingHome ? "Approaching Home" : locationService.currentLocation != nil ? "Tracking" : "Unavailable"
            )
            .accessibilityIdentifier("companionHome.context.location")
            if let focus = sensorService.focusMode {
                ContextRow(
                    icon: "moon.circle",
                    label: "Focus",
                    value: focus.capitalized
                )
                .accessibilityIdentifier("companionHome.context.focus")
            }
            ContextRow(
                icon: "sun.max.trianglebadge.exclamationmark",
                label: "Screen Brightness",
                value: "\(Int(((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.brightness ?? 0) * 100))%"
            )
            .accessibilityIdentifier("companionHome.context.screenBrightness")
            if sensorService.airPodsConnected {
                ContextRow(
                    icon: "airpodspro",
                    label: "AirPods Posture",
                    value: sensorService.headPosture?.capitalized ?? "Detecting…"
                )
                .accessibilityIdentifier("companionHome.context.airPodsPosture")
            }
            ContextRow(
                icon: "arrow.triangle.2.circlepath",
                label: "Last Sync",
                value: cloudSync.latestCompanionData?.timestamp.formatted(date: .omitted, time: .shortened) ?? "Never"
            )
            .accessibilityIdentifier("companionHome.context.lastSync")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .accessibilityIdentifier("companionHome.context.card")
    }

    // MARK: - Voice Card

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Voice", systemImage: "waveform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let voice = voiceService {
                ContextRow(
                    icon: "speaker.wave.2",
                    label: "Status",
                    value: voice.isSpeaking ? "Speaking…" : voice.isListening ? "Listening…" : "Idle"
                )
                .accessibilityIdentifier("companionHome.voice.status")

                HStack {
                    Label(
                        voice.tapToTalkEnabled ? "AirPods: tap stem to talk" : "AirPods: tap-to-talk off",
                        systemImage: voice.tapToTalkEnabled ? "airpodspro" : "airpodspro"
                    )
                    .font(.caption)
                    .foregroundStyle(voice.tapToTalkEnabled ? .primary : .secondary)
                    .accessibilityIdentifier("companionHome.voice.tapToTalkLabel")

                    Spacer()

                    Button {
                        if voice.tapToTalkEnabled {
                            voice.disableTapToTalk()
                        } else {
                            voice.enableTapToTalk()
                        }
                    } label: {
                        Text(voice.tapToTalkEnabled ? "Disable" : "Enable")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityIdentifier("companionHome.voice.tapToTalkToggle")
                }

                if let command = voice.lastTapToTalkCommand {
                    ContextRow(
                        icon: "mic.fill",
                        label: "You said",
                        value: command
                    )
                    .accessibilityIdentifier("companionHome.voice.lastCommand")
                }
                if let response = voice.lastTapToTalkResponse {
                    ContextRow(
                        icon: "text.bubble",
                        label: "Sentio said",
                        value: response
                    )
                    .accessibilityIdentifier("companionHome.voice.lastResponse")
                }

                if let last = voice.lastSpokenMessage {
                    ContextRow(
                        icon: "text.bubble",
                        label: "Last Relay",
                        value: last
                    )
                    .accessibilityIdentifier("companionHome.voice.lastRelay")
                }
                if let reply = voice.lastUserReply {
                    ContextRow(
                        icon: "person.wave.2",
                        label: "Your Reply",
                        value: reply
                    )
                    .accessibilityIdentifier("companionHome.voice.lastReply")
                }
            } else {
                Text("Voice service starting…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("companionHome.voice.loading")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .accessibilityIdentifier("companionHome.voice.card")
    }

    // MARK: - Devices Card

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(homeKit.allDeviceSnapshots.count) Devices", systemImage: "lightbulb.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("companionHome.devices.countLabel")

            if homeKit.allDeviceSnapshots.isEmpty {
                Text("No HomeKit devices found.\nMake sure you have a Home set up.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("companionHome.devices.emptyState")
            } else {
                ForEach(homeKit.allDeviceSnapshots.prefix(10)) { device in
                    DeviceRow(device: device)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .accessibilityIdentifier("companionHome.devices.card")
    }
}

// MARK: - Supporting Views

private struct ContextRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DeviceRow: View {
    let device: DeviceSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .frame(width: 24)
                .foregroundStyle(device.isReachable ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline)
                if let room = device.roomName {
                    Text(room)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !device.isReachable {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var iconName: String {
        switch device.category {
        case "lightbulb":   return "lightbulb.fill"
        case "thermostat":  return "thermometer.medium"
        case "door":        return "door.left.hand.open"
        case "lock":        return "lock.fill"
        case "fan":         return "fan.fill"
        case "switch":      return "switch.2"
        case "outlet":      return "poweroutlet.type.b"
        case "blinds":      return "blinds.vertical.open"
        case "sensor":      return "sensor"
        case "purifier":    return "air.purifier.fill"
        case "sprinkler":   return "sprinkler.and.droplets.fill"
        case "other":       return "gearshape"
        default:            return "questionmark.circle"
        }
    }
}
