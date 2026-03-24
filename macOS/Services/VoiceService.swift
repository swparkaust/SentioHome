import Foundation
import AVFoundation
import HomeKit
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "Voice")

@Observable
@MainActor
final class VoiceService {

    private(set) var isSpeaking = false
    private(set) var lastSpokenMessage: String?

    private let synthesizer = AVSpeechSynthesizer()
    private let cloudSync: CloudSyncService
    let homeKit: HomeKitService
    private var delegate: SpeechDelegate?

    init(cloudSync: CloudSyncService, homeKit: HomeKitService) {
        self.cloudSync = cloudSync
        self.homeKit = homeKit
        self.delegate = SpeechDelegate()
        synthesizer.delegate = delegate

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt)
    }

    // MARK: - Speak

    func execute(_ action: CommunicationAction, airPodsConnected: Bool) async {
        if airPodsConnected {
            await relayToCompanion(action)
        } else {
            await speak(action.message)
        }
    }

    // MARK: - Speech Synthesis

    private func speak(_ message: String) async {
        isSpeaking = true
        lastSpokenMessage = message

        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = Self.bestAvailableVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8

        await speakViaDefaultOutput(utterance)

        isSpeaking = false
        logger.info("Spoke: \"\(message)\"")
    }

    private func speakViaDefaultOutput(_ utterance: AVSpeechUtterance) async {
        synthesizer.speak(utterance)
        let timeout = DispatchSource.makeTimerSource(queue: .main)
        defer { timeout.cancel() }
        timeout.schedule(deadline: .now() + 30)
        timeout.setEventHandler { [weak self] in
            self?.synthesizer.stopSpeaking(at: .immediate)
        }
        timeout.resume()
        await withCheckedContinuation { continuation in
            delegate?.onFinish = {
                continuation.resume()
            }
        }
        delegate?.onFinish = nil
    }

    private static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        if let premium = englishVoices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = englishVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - Emergency Broadcast

    func speakEverywhere(_ message: String) async {
        logger.critical("Emergency broadcast: \"\(message)\"")

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.speak(message)
            }
            group.addTask {
                let relay = VoiceRelay(
                    message: message,
                    expectsReply: false,
                    timestamp: Date()
                )
                try? await self.cloudSync.pushVoiceRelay(relay)
            }
        }
    }

    // MARK: - Relay to iOS Companion

    private func relayToCompanion(_ action: CommunicationAction) async {
        let record = VoiceRelay(
            message: action.message,
            expectsReply: action.expectsReply,
            timestamp: Date()
        )

        do {
            try await cloudSync.pushVoiceRelay(record)
            logger.info("Relayed voice message to iOS companion: \"\(action.message)\"")
        } catch {
            logger.error("Failed to relay voice message: \(error.localizedDescription)")
        }
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
