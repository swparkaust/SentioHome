import AppIntents

struct AskSentioShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskSentioIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Tell \(.applicationName)",
                "Talk to \(.applicationName)"
            ],
            shortTitle: "Ask Sentio",
            systemImageName: "house.fill"
        )
    }
}
