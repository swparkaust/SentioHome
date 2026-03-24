import SwiftUI

struct WatchHomeView: View {

    let healthService: HealthService
    let cloudSync: CloudSyncService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    statusIndicator

                    NavigationLink {
                        WatchAskView(cloudSync: cloudSync)
                    } label: {
                        Label("Ask Sentio", systemImage: "message.fill")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .accessibilityIdentifier("watchHome.askSentio")

                    healthGrid
                }
                .padding(.horizontal)
            }
            .navigationTitle("Sentio")
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "house.and.flag.fill")
                .foregroundStyle(.tint)
            Text(healthService.isAuthorized ? "Sharing" : "Setup Needed")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("watchHome.status.label")
            Spacer()
            Circle()
                .fill(healthService.isAuthorized ? .green : .orange)
                .frame(width: 6, height: 6)
                .accessibilityIdentifier("watchHome.status.indicator")
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("watchHome.status")
    }

    // MARK: - Health Grid

    private var healthGrid: some View {
        VStack(spacing: 8) {
            if let sleep = healthService.sleepState {
                MetricRow(
                    icon: sleepIcon(for: sleep),
                    label: "Sleep",
                    value: sleepLabel(for: sleep),
                    color: .indigo
                )
                .accessibilityIdentifier("watchHome.health.sleep")
            }

            if let hr = healthService.heartRate {
                MetricRow(
                    icon: "heart.fill",
                    label: "Heart Rate",
                    value: "\(Int(hr)) bpm",
                    color: .red
                )
                .accessibilityIdentifier("watchHome.health.heartRate")
            }

            if let hrv = healthService.heartRateVariability {
                MetricRow(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: "\(Int(hrv)) ms",
                    color: .green
                )
                .accessibilityIdentifier("watchHome.health.hrv")
            }

            if healthService.isWorkingOut {
                MetricRow(
                    icon: "figure.run",
                    label: "Activity",
                    value: "Working Out",
                    color: .yellow
                )
                .accessibilityIdentifier("watchHome.health.activity")
            }

            if let temp = healthService.wristTemperatureDelta {
                let sign = temp >= 0 ? "+" : ""
                MetricRow(
                    icon: "thermometer.medium",
                    label: "Wrist Temp",
                    value: "\(sign)\(String(format: "%.1f", temp))°",
                    color: .orange
                )
                .accessibilityIdentifier("watchHome.health.wristTemp")
            }

            if let spo2 = healthService.bloodOxygen {
                MetricRow(
                    icon: "lungs.fill",
                    label: "Blood O₂",
                    value: "\(Int(spo2 * 100))%",
                    color: .cyan
                )
                .accessibilityIdentifier("watchHome.health.bloodOxygen")
            }

            if healthService.heartRate == nil && healthService.sleepState == nil {
                Text("Waiting for health data…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .accessibilityIdentifier("watchHome.health.emptyState")
            }
        }
    }

    // MARK: - Sleep Helpers

    private func sleepIcon(for state: String) -> String {
        switch state {
        case "asleepDeep", "asleepCore", "asleepREM": return "moon.zzz.fill"
        case "inBed": return "bed.double.fill"
        default: return "sun.max.fill"
        }
    }

    private func sleepLabel(for state: String) -> String {
        switch state {
        case "asleepDeep":  return "Deep Sleep"
        case "asleepCore":  return "Core Sleep"
        case "asleepREM":   return "REM Sleep"
        case "inBed":       return "In Bed"
        default:            return "Awake"
        }
    }
}

// MARK: - Metric Row

private struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.footnote.weight(.medium))
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
