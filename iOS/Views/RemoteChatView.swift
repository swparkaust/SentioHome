import SwiftUI

struct RemoteChatView: View {

    let cloudSync: CloudSyncService

    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isWaiting = false
    @State private var conversationID = UUID().uuidString

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            emptyState
                        }
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                                .accessibilityIdentifier("remoteChat.message.\(message.id)")
                        }
                        if isWaiting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            .id("waiting")
                            .accessibilityIdentifier("remoteChat.waitingIndicator")
                        }
                    }
                    .accessibilityIdentifier("remoteChat.messageList")
                    .padding()
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        if let lastID = messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Ask or command…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .onSubmit { sendMessage() }
                    .accessibilityIdentifier("remoteChat.input")

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .accentColor)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isWaiting)
                .accessibilityIdentifier("remoteChat.sendButton")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle("Remote")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)

            Text("Talk to your home")
                .font(.headline)
                .accessibilityIdentifier("remoteChat.emptyState.title")

            VStack(alignment: .leading, spacing: 6) {
                Label("\"What's the temperature inside?\"", systemImage: "thermometer")
                Label("\"Turn off all the lights\"", systemImage: "lightbulb.slash")
                Label("\"Is the front door locked?\"", systemImage: "lock")
                Label("\"Start the robot vacuum\"", systemImage: "fan")
                Label("\"Play jazz in the living room\"", systemImage: "music.note")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .accessibilityIdentifier("remoteChat.emptyState")
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, text: text)
        messages.append(userMessage)
        inputText = ""
        isWaiting = true

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

                let response = await pollForResponse(requestID: requestID, timeout: 30)

                let aiMessage = ChatMessage(
                    role: .assistant,
                    text: response?.message ?? "No response — your Mac may be offline or asleep.",
                    actions: response?.actionsPerformed ?? []
                )
                messages.append(aiMessage)

                if response?.expectsContinuation != true {
                    conversationID = UUID().uuidString
                }
            } catch {
                messages.append(ChatMessage(
                    role: .assistant,
                    text: "Couldn't reach your home. Make sure your Mac is running."
                ))
                conversationID = UUID().uuidString
            }

            isWaiting = false
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

// MARK: - Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    var actions: [String] = []
    let timestamp = Date()

    enum Role {
        case user, assistant
    }
}

// MARK: - Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? Color.accentColor : Color(.systemGray5))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("remoteChat.bubble.text")

                if !message.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(message.actions, id: \.self) { action in
                            Label(action, systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .accessibilityIdentifier("remoteChat.bubble.action")
                        }
                    }
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("remoteChat.bubble.actionsList")
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("remoteChat.bubble.timestamp")
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
