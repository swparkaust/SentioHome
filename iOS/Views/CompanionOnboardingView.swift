import SwiftUI

struct CompanionOnboardingView: View {

    @Binding var isPresented: Bool

    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<Self.stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                        .accessibilityIdentifier("onboarding.progressIndicator.\(index)")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .accessibilityIdentifier("onboarding.progressBar")

            Spacer()

            stepContent
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                .animation(.easeInOut(duration: 0.3), value: currentStep)

            Spacer()

            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.backButton")
                }

                Spacer()

                if currentStep < Self.stepCount - 1 {
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
    }

    private static let stepCount = 7

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: welcomeStep
        case 1: roleStep
        case 2: locationStep
        case 3: sensorsStep
        case 4: voiceStep
        case 5: siriStep
        case 6: readyStep
        default: welcomeStep
        }
    }

    private var welcomeStep: some View {
        CompanionStepView(
            icon: "house.and.flag.fill",
            iconColor: .accentColor,
            title: "Sentio Companion",
            subtitle: "Your iPhone is the eyes and ears.",
            description: "This app shares your iPhone's sensors with your Mac so Sentio can make smarter home decisions. It also lets you talk to Sentio remotely — from anywhere."
        )
        .accessibilityIdentifier("onboarding.step.welcome")
    }

    private var roleStep: some View {
        CompanionStepView(
            icon: "iphone.radiowaves.left.and.right",
            iconColor: .blue,
            title: "What This App Does",
            subtitle: "Sensors in. Commands out.",
            description: "Your iPhone measures ambient light, motion activity, screen brightness, and location. This data syncs to your Mac via iCloud every 2 minutes. You can also ask Sentio questions, give commands, use AirPods tap-to-talk, or say \"Hey Siri, Ask Sentio\" on any device."
        )
        .accessibilityIdentifier("onboarding.step.role")
    }

    private var locationStep: some View {
        CompanionStepView(
            icon: "location.fill",
            iconColor: .blue,
            title: "Location (Always)",
            subtitle: "Know when you're home, away, or approaching.",
            description: "\"Always\" access lets Sentio detect when you're approaching home to pre-warm lights and adjust temperature — even when the app is closed. Your location never leaves your iCloud account."
        )
        .accessibilityIdentifier("onboarding.step.location")
    }

    private var sensorsStep: some View {
        CompanionStepView(
            icon: "sensor.fill",
            iconColor: .green,
            title: "Motion & Focus",
            subtitle: "Understand what you're doing.",
            description: "Motion data tells Sentio if you're walking, stationary, or driving. AirPods head motion detects if you're reclining or nodding off. Focus mode tells Sentio when to minimize disruptions. All processed on-device."
        )
        .accessibilityIdentifier("onboarding.step.sensors")
    }

    private var voiceStep: some View {
        CompanionStepView(
            icon: "waveform",
            iconColor: .purple,
            title: "Microphone & Speech",
            subtitle: "Talk to Sentio through AirPods.",
            description: "When Sentio speaks to you through AirPods and expects a reply, it listens briefly using on-device speech recognition. You can also tap your AirPods stem to have a back-and-forth conversation — Sentio will keep listening for follow-ups when clarification is needed. All recognition happens on-device — nothing is sent to the cloud."
        )
        .accessibilityIdentifier("onboarding.step.voice")
    }

    private var siriStep: some View {
        CompanionStepView(
            icon: "mic.circle.fill",
            iconColor: .orange,
            title: "Siri Integration",
            subtitle: "\"Hey Siri, Ask Sentio…\"",
            description: "Talk to Sentio from any Siri-enabled device — HomePod, iPhone, Apple Watch, AirPods, or CarPlay. Just say \"Hey Siri, Ask Sentio\" followed by your request. Sentio responds on the same device you spoke to. No setup needed — Siri learns the phrases automatically. For HomePod, make sure Personal Requests is enabled in your Home settings."
        )
        .accessibilityIdentifier("onboarding.step.siri")
    }

    private var readyStep: some View {
        CompanionStepView(
            icon: "checkmark.circle.fill",
            iconColor: .green,
            title: "Ready to Go",
            subtitle: "Leave this app running in the background.",
            description: "The companion works best when it can run in the background. You don't need to open it — sensor data syncs automatically. Use the chat or AirPods tap-to-talk when you want to interact with Sentio."
        )
        .accessibilityIdentifier("onboarding.step.ready")
    }
}

// MARK: - Reusable Step View

private struct CompanionStepView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityIdentifier("onboarding.stepIcon")

            Text(title)
                .font(.largeTitle.bold())
                .accessibilityIdentifier("onboarding.stepTitle")

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.stepSubtitle")

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
                .accessibilityIdentifier("onboarding.stepDescription")
        }
    }
}
