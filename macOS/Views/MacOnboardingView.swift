import SwiftUI
import UserNotifications

/// Multi-step onboarding sheet for the macOS server app.
/// Introduces Sentio, explains the architecture, and requests permissions
/// one at a time with context for each.
struct MacOnboardingView: View {

    @Binding var isPresented: Bool

    @State private var currentStep = 0

    private let totalSteps = 7

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                        .accessibilityIdentifier("onboarding.progress.step\(index)")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .accessibilityIdentifier("onboarding.progressIndicator")

            Spacer()

            // Mac Catalyst propagates container accessibilityIdentifier to children,
            // so we set a step-specific identifier here.
            stepContent
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
                .accessibilityIdentifier(stepIdentifiers[currentStep])

            Spacer()

            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.backButton")
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboarding.continueButton")
                } else {
                    Button("Get Started") {
                        UserDefaults.standard.set(true, forKey: "onboardingComplete")
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboarding.getStartedButton")
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 460)
    }

    // MARK: - Steps

    private let stepIdentifiers = [
        "onboarding.step.welcome",
        "onboarding.step.architecture",
        "onboarding.step.homeKit",
        "onboarding.step.calendarMusic",
        "onboarding.step.notifications",
        "onboarding.step.networkBluetooth",
        "onboarding.step.ready",
    ]

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: welcomeStep
        case 1: architectureStep
        case 2: homeKitStep
        case 3: calendarMusicStep
        case 4: notificationsStep
        case 5: networkBluetoothStep
        case 6: readyStep
        default: welcomeStep
        }
    }

    private var welcomeStep: some View {
        OnboardingStepView(
            icon: "house.and.flag.fill",
            iconColor: .accentColor,
            title: "Welcome to Sentio",
            subtitle: "Your home, on autopilot.",
            description: "Sentio uses Apple's on-device intelligence to understand your context — time, weather, activity, health — and adjusts your smart home to create the ideal environment. Everything runs locally on your Mac. Nothing leaves your devices."
        )
    }

    private var architectureStep: some View {
        OnboardingStepView(
            icon: "macbook.and.iphone",
            iconColor: .blue,
            title: "How It Works",
            subtitle: "Your Mac is the brain.",
            description: "This Mac runs the automation engine. Your iPhone shares sensor data (light, motion, location). Your Apple Watch shares health data (heart rate, sleep). Together, they give Sentio the full picture. All communication happens through your private iCloud account."
        )
    }

    private var homeKitStep: some View {
        OnboardingStepView(
            icon: "lightbulb.2.fill",
            iconColor: .yellow,
            title: "HomeKit Access",
            subtitle: "Sentio needs to see and control your devices.",
            description: "When prompted, grant HomeKit access so Sentio can read sensor states (motion, temperature, contact) and adjust lights, thermostat, fans, and other accessories. Sentio will never lock doors or arm security without your explicit confirmation."
        )
    }

    private var calendarMusicStep: some View {
        OnboardingStepView(
            icon: "calendar.badge.clock",
            iconColor: .red,
            title: "Calendar & Music",
            subtitle: "Anticipate your schedule. Set the mood.",
            description: "Calendar access lets Sentio prepare for meetings (suppress voice, ensure good lighting) and events (warm lights before a dinner party). Music access lets Sentio play ambient background music through your speakers to match the moment."
        )
    }

    private var notificationsStep: some View {
        OnboardingStepView(
            icon: "bell.badge.fill",
            iconColor: .orange,
            title: "Notifications",
            subtitle: "Stay informed. Stay safe.",
            description: "Sentio sends quiet notifications when it makes changes, with an undo option. For emergencies — smoke, CO, water leaks — it sends critical alerts that bypass Do Not Disturb. Grant \"Critical Alerts\" when prompted."
        )
    }

    private var networkBluetoothStep: some View {
        OnboardingStepView(
            icon: "antenna.radiowaves.left.and.right",
            iconColor: .purple,
            title: "Network & Bluetooth",
            subtitle: "Detect guests. Respect privacy.",
            description: "Sentio passively scans your local network and Bluetooth for unknown devices to infer when guests are present. When guests are detected, it suppresses personal announcements and switches to a hospitality mode. No guest data is stored or transmitted."
        )
    }

    private var readyStep: some View {
        OnboardingStepView(
            icon: "checkmark.circle.fill",
            iconColor: .green,
            title: "You're All Set",
            subtitle: "Sentio will start learning your preferences.",
            description: "The first few days, Sentio uses sensible defaults. As you manually adjust devices, it learns your preferences and adapts. If it ever gets something wrong, just change it — Sentio will notice and remember. You can always pause automation from the menu bar."
        )
    }
}

// MARK: - Reusable Step View

struct OnboardingStepView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityIdentifier("onboarding.stepView.icon")

            Text(title)
                .font(.title.bold())
                .accessibilityIdentifier("onboarding.stepView.title")

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.stepView.subtitle")

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 400)
                .accessibilityIdentifier("onboarding.stepView.description")
        }
        .padding(.horizontal, 32)
    }
}
