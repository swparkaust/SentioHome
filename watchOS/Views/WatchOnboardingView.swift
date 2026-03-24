import SwiftUI

/// Compact onboarding flow for watchOS.
/// Explains the Watch's role and requests HealthKit + Location.
struct WatchOnboardingView: View {

    @Binding var isPresented: Bool

    @State private var currentStep: Int = {
        if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "--onboardingStep"),
           idx + 1 < ProcessInfo.processInfo.arguments.count,
           let step = Int(ProcessInfo.processInfo.arguments[idx + 1]) {
            return step
        }
        return 0
    }()

    private let steps = 3

    var body: some View {
        TabView(selection: $currentStep) {
            welcomeStep.tag(0)
            healthStep.tag(1)
            readyStep.tag(2)
        }
        .tabViewStyle(.verticalPage)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "house.and.flag.fill")
                    .font(.title)
                    .foregroundStyle(.tint)

                Text("Sentio Watch")
                    .font(.headline)
                    .accessibilityIdentifier("watchOnboarding.welcome.title")

                Text("Your Watch shares health data with Sentio so your home adapts to how you feel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("watchOnboarding.welcome.description")

                Text("Swipe up to continue")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .accessibilityIdentifier("watchOnboarding.welcome.hint")
            }
            .padding(.horizontal)
        }
        .accessibilityIdentifier("watchOnboarding.welcome")
    }

    private var healthStep: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "heart.text.clipboard")
                    .font(.title)
                    .foregroundStyle(.red)

                Text("Health & Location")
                    .font(.headline)
                    .accessibilityIdentifier("watchOnboarding.health.title")

                Text("Heart rate, sleep state, and wrist temperature help Sentio dim lights when you doze off or adjust the thermostat when you're warm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("watchOnboarding.health.description")

                Text("Location helps detect when you've left home even if your iPhone stays behind.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("watchOnboarding.health.locationDescription")
            }
            .padding(.horizontal)
        }
        .accessibilityIdentifier("watchOnboarding.health")
    }

    private var readyStep: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)

                Text("All Set")
                    .font(.headline)
                    .accessibilityIdentifier("watchOnboarding.ready.title")

                Text("Data syncs automatically every 2 minutes. Use \"Ask Sentio\" to talk to your home from your wrist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("watchOnboarding.ready.description")

                Button("Get Started") {
                    UserDefaults.standard.set(true, forKey: "onboardingComplete")
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
                .accessibilityIdentifier("watchOnboarding.getStarted")
            }
            .padding(.horizontal)
        }
        .accessibilityIdentifier("watchOnboarding.ready")
    }
}
