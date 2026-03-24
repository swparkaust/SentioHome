import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The AI's response during a multi-turn conversation.
/// Unlike `AutomationPlanV2` (used for periodic automation), this struct is
/// designed for interactive dialogue where actions execute immediately per turn.
#if canImport(FoundationModels)
@Generable
#endif
struct DialogueTurnResponse: Codable {

    #if canImport(FoundationModels)
    @Guide(description: """
        Your conversational reply to the user. Be concise and natural — \
        they may be listening through AirPods or a speaker. One or two sentences is ideal.
        """)
    #endif
    var responseText: String

    #if canImport(FoundationModels)
    @Guide(description: "Device actions for this turn. These execute immediately.")
    #endif
    var actions: [DeviceAction]

    #if canImport(FoundationModels)
    @Guide(description: "Optional music action for this turn.")
    #endif
    var music: MusicAction?

    #if canImport(FoundationModels)
    @Guide(description: """
        True when you've fulfilled the request and have no question to ask. \
        False only when YOU asked a clarifying question that needs an answer. \
        Do not append 'anything else?' — end the conversation naturally.
        """)
    #endif
    var conversationComplete: Bool
}
