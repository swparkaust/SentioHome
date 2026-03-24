import Testing
import Foundation
@testable import SentioKit

@Suite("MusicAction")
struct MusicActionTests {

    // MARK: - Codable

    @Test("MusicAction round-trips through JSON")
    func codableRoundTrip() throws {
        let action = MusicAction(query: "lo-fi chill beats", volume: 0.3, stop: false)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(MusicAction.self, from: data)
        #expect(decoded.query == "lo-fi chill beats")
        #expect(decoded.volume == 0.3)
        #expect(decoded.stop == false)
    }

    @Test("Stop action round-trips correctly")
    func stopActionRoundTrip() throws {
        let action = MusicAction(query: "", volume: 0, stop: true)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(MusicAction.self, from: data)
        #expect(decoded.stop == true)
    }

    // MARK: - Volume Range

    @Test("Volume at boundaries encodes correctly")
    func volumeBoundaries() throws {
        let silent = MusicAction(query: "ambient", volume: 0.0, stop: false)
        let full = MusicAction(query: "ambient", volume: 1.0, stop: false)

        let silentData = try JSONEncoder().encode(silent)
        let fullData = try JSONEncoder().encode(full)

        let decodedSilent = try JSONDecoder().decode(MusicAction.self, from: silentData)
        let decodedFull = try JSONDecoder().decode(MusicAction.self, from: fullData)

        #expect(decodedSilent.volume == 0.0)
        #expect(decodedFull.volume == 1.0)
    }

    // MARK: - Empty Fields

    @Test("Empty query is valid")
    func emptyQuery() throws {
        let action = MusicAction(query: "", volume: 0.5, stop: false)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(MusicAction.self, from: data)
        #expect(decoded.query.isEmpty)
    }
}
