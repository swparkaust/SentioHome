import SwiftUI

struct WatchAskView: View {

    let cloudSync: CloudSyncService

    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var conversationID = UUID().uuidString
    @State private var turns: [WatchConversationTurn] = []
    @State private var inactivityTask: Task<Void, Never>?

    private let quickCommands: [(icon: String, label: String, id: String)] = [
        ("lightbulb.slash", "Turn off all lights", "lightsOff"),
        ("thermometer.medium", "What's the temperature?", "temperature"),
        ("lock.fill", "Lock the front door", "lockDoor"),
        ("fan", "Start the vacuum", "vacuum"),
        ("music.note", "Play relaxing music", "music"),
        ("eye", "Is anyone home?", "anyoneHome"),
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {

                    TextField("Ask Sentio…", text: $inputText)
                        .onSubmit { sendRequest(inputText) }
                        .accessibilityIdentifier("watchAsk.input")

                    if isProcessing {
                        ProgressView("Asking…")
                            .font(.caption2)
                            .accessibilityIdentifier("watchAsk.loading")
                    }

                    ForEach(turns) { turn in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(turn.userMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .accessibilityIdentifier("watchAsk.turn.userMessage")

                            Text(turn.responseMessage)
                                .font(.footnote)
                                .accessibilityIdentifier("watchAsk.turn.response")

                            ForEach(turn.actionsPerformed, id: \.self) { action in
                                Label(action, systemImage: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                    .accessibilityIdentifier("watchAsk.turn.action")
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .id(turn.id)
                        .accessibilityIdentifier("watchAsk.turn.\(turn.id)")
                    }

                    if turns.isEmpty && !isProcessing {
                        Divider()
                            .padding(.vertical, 4)

                        ForEach(quickCommands, id: \.label) { command in
                            Button {
                                sendRequest(command.label)
                            } label: {
                                Label(command.label, systemImage: command.icon)
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(isProcessing)
                            .accessibilityIdentifier("watchAsk.quickCommand.\(command.id)")
                        }
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: turns.count) {
                if let lastID = turns.last?.id {
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
        }
        .navigationTitle("Ask")
    }

    private func sendRequest(_ message: String) {
        let text = message.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isProcessing else { return }

        inputText = ""
        isProcessing = true

        scheduleInactivityClear()

        Task {
            let requestID = UUID().uuidString
            let request = UserRequest(
                id: requestID,
                message: text,
                timestamp: Date(),
                intent: "auto",
                conversationID: conversationID
            )

            do {
                try await cloudSync.pushUserRequest(request)
                let response = await pollForResponse(requestID: requestID, timeout: 20)

                let turn = WatchConversationTurn(
                    userMessage: text,
                    responseMessage: response?.message ?? "No response — is your Mac awake?",
                    actionsPerformed: response?.actionsPerformed ?? []
                )
                turns.append(turn)

                if response?.expectsContinuation != true {
                    startNewConversation()
                }
            } catch {
                let turn = WatchConversationTurn(
                    userMessage: text,
                    responseMessage: "Couldn't reach home.",
                    actionsPerformed: []
                )
                turns.append(turn)
                startNewConversation()
            }

            isProcessing = false
        }
    }

    private func startNewConversation() {
        conversationID = UUID().uuidString
    }

    private func scheduleInactivityClear() {
        inactivityTask?.cancel()
        inactivityTask = Task {
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, !isProcessing else { return }
            withAnimation {
                turns.removeAll()
                startNewConversation()
            }
        }
    }

    private func pollForResponse(requestID: String, timeout: TimeInterval) async -> UserResponse? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let response = await cloudSync.pullUserResponse(requestID: requestID) {
                return response
            }
            try? await Task.sleep(for: .seconds(2))
        }
        return nil
    }
}

struct WatchConversationTurn: Identifiable {
    let id = UUID()
    let userMessage: String
    let responseMessage: String
    let actionsPerformed: [String]
}
