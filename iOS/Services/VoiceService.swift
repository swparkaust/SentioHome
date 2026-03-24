import Foundation
import AVFoundation
import AudioToolbox
import MediaPlayer
import Speech
import CloudKit
import Observation
import Synchronization
import os

private let logger = Logger(subsystem: "com.sentio.home.companion", category: "Voice")

/// Handles bidirectional voice communication on iOS:
/// - Speaks messages through AirPods (or iPhone speaker) via AVSpeechSynthesizer
/// - Listens for replies via SFSpeechRecognizer (uses AirPods mic when connected)
/// - Polls CloudKit for voice relay messages from the macOS server
@Observable
@MainActor
final class VoiceService: NSObject {

    private(set) var isSpeaking = false
    private(set) var isListening = false
    private(set) var lastSpokenMessage: String?
    private(set) var lastUserReply: String?
    var onUserReply: ((String) -> Void)?
    private(set) var tapToTalkEnabled = false
    private(set) var lastTapToTalkCommand: String?
    private(set) var lastTapToTalkResponse: String?
    private(set) var activeConversationID: String?
    private(set) var isInDialogue = false

    private let synthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let cloudSync: CloudSyncService

    private var speechDelegate: SpeechDelegate?
    private var pollTask: Task<Void, Never>?
    private var tapToTalkTask: Task<Void, Never>?

    init(cloudSync: CloudSyncService) {
        self.cloudSync = cloudSync
        super.init()
        speechDelegate = SpeechDelegate()
        synthesizer.delegate = speechDelegate
    }

    func requestPermissions() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable _ in
                continuation.resume()
            }
        }

        if await AVAudioApplication.requestRecordPermission() {
            logger.info("Microphone permission granted")
        }

        logger.info("Voice permissions configured")
    }

    // MARK: - Relay Polling

    func startListeningForRelays() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await checkForRelay()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        logger.info("Started polling for voice relays")
    }

    func stopListeningForRelays() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func checkForRelay() async {
        guard let relay = await cloudSync.pullLatestVoiceRelay() else { return }

        // Only process relays from the last 30 seconds to avoid replaying old messages
        guard relay.timestamp.timeIntervalSinceNow > -30 else { return }

        await speak(relay.message, requirePrivateRoute: true)

        if relay.expectsReply {
            let reply = await listenForReply(timeout: 10)
            if let reply {
                lastUserReply = reply
                onUserReply?(reply)
                try? await cloudSync.pushVoiceReply(reply)
            }
        }
    }

    private func isAirPodsCurrentRoute() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let airPodsKeywords = ["airpods", "beats fit", "beats solo", "beats studio", "powerbeats"]
        return outputs.contains { output in
            let isBluetoothOutput = output.portType == .bluetoothA2DP
                || output.portType == .bluetoothHFP
            let name = output.portName.lowercased()
            let isAppleHeadphones = airPodsKeywords.contains { name.contains($0) }
            return isBluetoothOutput && isAppleHeadphones
        }
    }

    // MARK: - AirPods Tap-to-Talk

    /// Enable tap-to-talk: when the user double-taps or long-presses the
    /// AirPods stem (triggering the play/pause remote command), Sentio listens
    /// for a voice command, sends it to the macOS server, and speaks the response.
    func enableTapToTalk() {
        guard !tapToTalkEnabled else { return }
        tapToTalkEnabled = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try? session.setActive(true)

        UIApplication.shared.beginReceivingRemoteControlEvents()

        let commandCenter = MPRemoteCommandCenter.shared()

        // AirPods stem press fires the play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                await self?.handleTapToTalk()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in .success }

        var nowPlaying = [String: Any]()
        nowPlaying[MPMediaItemPropertyTitle] = "Sentio Home"
        nowPlaying[MPMediaItemPropertyArtist] = "Listening"
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying

        logger.info("Tap-to-talk enabled — AirPods stem press will trigger voice input")
    }

    func disableTapToTalk() {
        tapToTalkEnabled = false
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        UIApplication.shared.endReceivingRemoteControlEvents()
        logger.info("Tap-to-talk disabled")
    }

    /// Phrases that signal the user wants to end the conversation.
    private static let endPhrases: Set<String> = [
        "thanks", "thank you", "that's all", "thats all", "goodbye",
        "bye", "nevermind", "never mind", "stop", "done", "nothing"
    ]

    private func handleTapToTalk() async {
        guard !isListening, !isSpeaking else { return }
        guard isAirPodsCurrentRoute() else {
            logger.info("Tap-to-talk ignored — AirPods not the current route")
            return
        }

        let conversationID = UUID().uuidString
        activeConversationID = conversationID
        isInDialogue = true
        defer {
            activeConversationID = nil
            isInDialogue = false
        }

        AudioServicesPlaySystemSound(1113)  // "Tink" — subtle tap sound

        logger.info("Tap-to-talk: listening for command…")
        guard let command = await listenForReply(timeout: 8) else {
            logger.info("Tap-to-talk: no speech detected")
            return
        }

        lastTapToTalkCommand = command
        var currentMessage = command

        while true {
            let requestID = UUID().uuidString
            let request = UserRequest(
                id: requestID,
                message: currentMessage,
                timestamp: Date(),
                intent: "auto",
                conversationID: conversationID
            )

            do {
                try await cloudSync.pushUserRequest(request)
            } catch {
                await speak("Couldn't reach your home.", requirePrivateRoute: true)
                return
            }

            guard let response = await pollForTapResponse(requestID: requestID, timeout: 20) else {
                await speak("I didn't get a response.", requirePrivateRoute: true)
                return
            }

            lastTapToTalkResponse = response.message
            await speak(response.message, requirePrivateRoute: true)

            guard response.expectsContinuation else {
                logger.info("Tap-to-talk dialogue complete after server signal")
                return
            }

            try? await Task.sleep(for: .milliseconds(300))

            guard let reply = await listenForReply(timeout: 8) else {
                logger.info("Tap-to-talk dialogue ended — no reply (silence)")
                return
            }

            let normalized = reply.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.endPhrases.contains(normalized) {
                logger.info("Tap-to-talk dialogue ended by user phrase: \(normalized)")
                return
            }

            lastTapToTalkCommand = reply
            currentMessage = reply
        }
    }

    private func pollForTapResponse(requestID: String, timeout: TimeInterval) async -> UserResponse? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let response = await cloudSync.pullUserResponse(requestID: requestID) {
                return response
            }
            try? await Task.sleep(for: .seconds(2))
        }
        return nil
    }

    // MARK: - Speech Output

    func speak(_ message: String, requirePrivateRoute: Bool = false) async {
        if requirePrivateRoute && !isAirPodsCurrentRoute() {
            logger.info("Private route required but AirPods not active — dropping message")
            return
        }

        isSpeaking = true
        lastSpokenMessage = message

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .allowBluetoothA2DP])
        try? session.setActive(true)

        // Double-check route after activating session (activation can change routing)
        if requirePrivateRoute && !isAirPodsCurrentRoute() {
            isSpeaking = false
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            logger.info("Route changed after session activation — dropping message")
            return
        }

        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        utterance.preUtteranceDelay = 0.3
        utterance.postUtteranceDelay = 0.2

        // Set handler before speak() so delegate can't fire before it's assigned.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            speechDelegate?.onFinish = {
                continuation.resume()
            }
            synthesizer.speak(utterance)
        }

        isSpeaking = false

        if tapToTalkEnabled {
            try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
        }

        logger.info("Spoke: \"\(message)\"")
    }

    // MARK: - Speech Input (Listening)

    func listenForReply(timeout: TimeInterval) async -> String? {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            logger.warning("Speech recognizer not available")
            return nil
        }

        isListening = true
        defer { isListening = false }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try? session.setActive(true)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return nil }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true  // Privacy: all on-device

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        logger.info("Listening for reply (timeout: \(timeout)s)...")

        // Mutex prevents double-resume across timeout task vs. speech recognition callback
        let request = recognitionRequest
        let result: String? = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let guard_ = Mutex(false)
            let lastResult = Mutex<String?>(nil)
            nonisolated(unsafe) var silenceTask: Task<Void, Never>?

            let resumeOnce: @Sendable () -> Void = {
                let alreadyResumed = guard_.withLock { resumed in
                    if resumed { return true }
                    resumed = true
                    return false
                }
                if !alreadyResumed {
                    let value = lastResult.withLock { $0 }
                    continuation.resume(returning: value)
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(timeout))
                resumeOnce()
            }

            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if let result {
                    lastResult.withLock { $0 = result.bestTranscription.formattedString }

                    silenceTask?.cancel()
                    silenceTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        resumeOnce()
                    }
                }

                if error != nil || (result?.isFinal ?? false) {
                    silenceTask?.cancel()
                    resumeOnce()
                }
            }
        }

        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        self.recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        self.recognitionRequest = nil
        recognitionTask = nil

        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        if let result {
            logger.info("User replied: \"\(result)\"")
        } else {
            logger.info("No reply received within timeout")
        }

        return result
    }
}

// MARK: - Speech Delegate

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    nonisolated(unsafe) var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let handler = onFinish
        onFinish = nil
        handler?()
    }
}
