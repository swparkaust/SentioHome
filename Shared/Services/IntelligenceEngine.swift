import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "Intelligence")

#if canImport(FoundationModels)
/// Uses Apple Intelligence's on-device Foundation Model to decide how to
/// adjust HomeKit devices based on the current context.
@MainActor
final class IntelligenceEngine {

    private static let systemInstructions = """
    You are Sentio, an intelligent home automation assistant running on-device. \
    Analyze the provided context and produce an automation plan. \
    Prioritize comfort, energy efficiency, and subtlety — changes should feel natural. \
    Only act when there's a clear reason. Never lock doors, open garage doors, or arm security. \
    Keep the summary brief and friendly. Don't reference raw data in your reasons.
    """

    private var session: LanguageModelSession

    init() {
        session = LanguageModelSession(instructions: Self.systemInstructions)
    }

    func resetSession() {
        session = LanguageModelSession(instructions: Self.systemInstructions)
    }

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func generatePlan(for context: HomeContext, preferenceHistory: String?, activeOverrides: String? = nil) async throws -> AutomationPlanV2 {
        let prompt = buildPrompt(from: context, preferenceHistory: preferenceHistory, activeOverrides: activeOverrides, automationGuidance: true)
        logger.debug("Prompt:\n\(prompt)")

        let response = try await session.respond(
            to: prompt,
            generating: AutomationPlanV2.self
        ).content

        let hasComm = response.communication != nil
        logger.info("Plan: \(response.summary) — \(response.actions.count) action(s), communication: \(hasComm)")
        return response
    }

    // MARK: - Dialogue

    private static let dialogueInstructions = """
    You are Sentio, a home automation assistant. You are in a multi-turn voice conversation. \
    Keep responses to one or two sentences — the user is listening via AirPods or a speaker.

    You return device actions and optional music actions that execute immediately. \
    Never lock doors or arm security systems. Respect any active manual overrides listed in the context.

    Set conversationComplete=true when you've fulfilled the request. \
    Set conversationComplete=false only when YOU asked a clarifying question that needs an answer. \
    Do not ask "anything else?" — end naturally.

    You can handle casual conversation with an empty actions array. Not every interaction needs a device action.
    """

    func createDialogueSession(
        isLocal: Bool = false,
        userIsHome: Bool = true
    ) -> LanguageModelSession {
        let locationNote: String
        if isLocal {
            locationNote = "The user is at home, communicating via the Mac. Be concise."
        } else if userIsHome {
            locationNote = "The user is at home, communicating via iPhone. Be concise."
        } else {
            locationNote = "The user is AWAY from home, using the companion app. Reference device states."
        }

        let instructions = """
        \(Self.dialogueInstructions)
        \(locationNote)
        """

        logger.info("Created dialogue session (isLocal=\(isLocal), userIsHome=\(userIsHome))")
        return LanguageModelSession(instructions: instructions)
    }

    func processDialogueTurn(
        session: LanguageModelSession,
        userMessage: String,
        contextPrompt: String?,
        isFirstTurn: Bool
    ) async throws -> DialogueTurnResponse {
        let prompt: String
        if isFirstTurn, let contextPrompt {
            prompt = """
            \(contextPrompt)

            ## User Request
            The user said: "\(sanitizeForPrompt(userMessage))"
            """
        } else {
            prompt = sanitizeForPrompt(userMessage)
        }

        let response = try await session.respond(
            to: prompt,
            generating: DialogueTurnResponse.self
        ).content

        logger.info("Dialogue turn: \(response.actions.count) action(s), complete=\(response.conversationComplete)")
        return response
    }

    private func buildPrompt(from context: HomeContext, preferenceHistory: String?, activeOverrides: String? = nil, automationGuidance: Bool = false) -> String {
        PromptBuilder.buildPrompt(from: context, preferenceHistory: preferenceHistory, activeOverrides: activeOverrides, automationGuidance: automationGuidance)
    }
}
#endif
