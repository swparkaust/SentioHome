import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@Generable
#endif
struct MusicAction: Codable {

    #if canImport(FoundationModels)
    @Guide(description: """
        A natural-language search query for Apple Music, such as "lo-fi chill beats", \
        "jazz piano", "classical focus", "soft acoustic morning". Be descriptive enough \
        for MusicKit to find a good match. Prefer genre/mood descriptions over specific \
        artist or track names unless the context strongly suggests one.
        """)
    #endif
    var query: String

    #if canImport(FoundationModels)
    @Guide(description: """
        Volume level from 0.0 (silent) to 1.0 (full). Prefer moderate levels: \
        0.2–0.3 for background ambiance, 0.4–0.5 for casual listening, \
        0.6+ only when the user is likely actively listening (e.g. working out, cooking). \
        Consider time of day and activity — quieter at night, louder during the day.
        """)
    #endif
    var volume: Double

    #if canImport(FoundationModels)
    @Guide(description: """
        Whether to stop any currently playing music instead of starting new playback. \
        Set to true when the context calls for silence (e.g. user falling asleep, \
        leaving the house, starting a phone call). When true, query is ignored.
        """)
    #endif
    var stop: Bool
}
