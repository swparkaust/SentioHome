import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@Generable
#endif
struct CommunicationAction: Codable {

    #if canImport(FoundationModels)
    @Guide(description: """
        The message to speak to the user. Keep it brief, warm, and conversational — \
        like a thoughtful roommate, not a robot. One sentence is ideal. Two max. \
        Examples: "Goodnight, dimming the lights.", "Welcome home, warming things up.", \
        "It's getting late, want me to start winding down?"
        """)
    #endif
    var message: String

    #if canImport(FoundationModels)
    @Guide(description: """
        Where to deliver this message. Use one of: \
        "airpods" (private, through connected AirPods — best for personal or sleep-related messages), \
        "auto" (let the system choose based on what's connected).
        """)
    #endif
    var route: String

    #if canImport(FoundationModels)
    @Guide(description: """
        Whether this message expects a verbal response from the user. \
        Set to true only when you're asking a question that requires confirmation \
        (e.g. "Want me to lock up?"). Set to false for announcements and status updates. \
        When true, the system will listen for a response via AirPods mic.
        """)
    #endif
    var expectsReply: Bool
}

#if canImport(FoundationModels)
@Generable
#endif
struct AutomationPlanV2: Codable {

    #if canImport(FoundationModels)
    @Guide(description: "List of device actions to execute. Return an empty array if no changes are needed.")
    #endif
    var actions: [DeviceAction]

    #if canImport(FoundationModels)
    @Guide(description: """
        Optional spoken message to the user. Only include when there is something genuinely worth saying — \
        do not narrate every action. Good reasons to speak: welcoming the user home, saying goodnight, \
        asking for confirmation on something unusual, or noting something important (e.g. "Left the \
        garage open"). Most automation cycles should NOT include a message. Return nil when silent.
        """)
    #endif
    var communication: CommunicationAction?

    #if canImport(FoundationModels)
    @Guide(description: """
        Optional music playback action. Use this to set ambient music that matches the context — \
        e.g. calm acoustic in the evening, upbeat in the morning, silence at bedtime. \
        Only include when a change in music is appropriate. Do NOT start music every cycle. \
        Use stop=true to silence currently playing music when the context calls for quiet. \
        Return nil to leave music unchanged.
        """)
    #endif
    var music: MusicAction?

    #if canImport(FoundationModels)
    @Guide(description: "A one-sentence summary of the overall plan, e.g. 'Setting a warm evening ambiance'.")
    #endif
    var summary: String
}
