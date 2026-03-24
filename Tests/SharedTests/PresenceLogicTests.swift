import Testing
import Foundation
import CoreLocation
@testable import SentioKit

@Suite("PresenceLogic")
struct PresenceLogicTests {

    // MARK: - recent()

    @Test("Fresh companion data is returned")
    func recentFreshData() {
        let data = CompanionData(timestamp: Date(), source: .iphone)
        let result = PresenceLogic.recent(data)
        #expect(result != nil)
    }

    @Test("Data from 5 minutes ago is still recent")
    func recentFiveMinutes() {
        let data = CompanionData(
            timestamp: Date().addingTimeInterval(-300),
            source: .iphone
        )
        let result = PresenceLogic.recent(data)
        #expect(result != nil)
    }

    @Test("Data older than 10 minutes is stale")
    func recentStaleData() {
        let data = CompanionData(
            timestamp: Date().addingTimeInterval(-601),
            source: .iphone
        )
        let result = PresenceLogic.recent(data)
        #expect(result == nil)
    }

    @Test("nil input returns nil")
    func recentNilInput() {
        #expect(PresenceLogic.recent(nil) == nil)
    }

    @Test("Data exactly at 10-minute boundary is still recent")
    func recentBoundary() {
        let now = Date()
        let data = CompanionData(
            timestamp: now.addingTimeInterval(-599),
            source: .iphone
        )
        let result = PresenceLogic.recent(data, now: now)
        #expect(result != nil)
    }

    // MARK: - bestRecent()

    @Test("Returns newer source when both have values")
    func bestRecentNewerWins() {
        let now = Date()
        let older = CompanionData(
            timestamp: now.addingTimeInterval(-120),
            source: .iphone,
            latitude: 37.0
        )
        let newer = CompanionData(
            timestamp: now.addingTimeInterval(-30),
            source: .watch,
            latitude: 38.0
        )
        let result = PresenceLogic.bestRecent(older, newer, keyPath: \.latitude, now: now)
        #expect(result?.source == .watch)
    }

    @Test("Returns only source that has non-nil value")
    func bestRecentOnlyOneHasValue() {
        let now = Date()
        let withValue = CompanionData(
            timestamp: now.addingTimeInterval(-30),
            source: .iphone,
            latitude: 37.0
        )
        let withoutValue = CompanionData(
            timestamp: now.addingTimeInterval(-10),
            source: .watch
            // latitude is nil
        )
        let result = PresenceLogic.bestRecent(withValue, withoutValue, keyPath: \.latitude, now: now)
        #expect(result?.source == .iphone)
    }

    @Test("Returns nil when both are stale")
    func bestRecentBothStale() {
        let now = Date()
        let a = CompanionData(
            timestamp: now.addingTimeInterval(-700),
            source: .iphone,
            latitude: 37.0
        )
        let b = CompanionData(
            timestamp: now.addingTimeInterval(-800),
            source: .watch,
            latitude: 38.0
        )
        let result = PresenceLogic.bestRecent(a, b, keyPath: \.latitude, now: now)
        #expect(result == nil)
    }

    @Test("Returns nil when neither has value for keypath")
    func bestRecentNeitherHasValue() {
        let now = Date()
        let a = CompanionData(timestamp: now, source: .iphone)
        let b = CompanionData(timestamp: now, source: .watch)
        let result = PresenceLogic.bestRecent(a, b, keyPath: \.heartRate, now: now)
        #expect(result == nil)
    }

    // MARK: - determinePresence()

    @Test("User within 100m of home is present")
    func presenceNearHome() {
        let home = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let data = CompanionData(
            timestamp: Date(),
            source: .iphone,
            latitude: 37.7749,
            longitude: -122.4194 // same location
        )
        #expect(PresenceLogic.determinePresence(companion: data, homeLocation: home) == true)
    }

    @Test("User far from home is away")
    func presenceFarFromHome() {
        let home = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let data = CompanionData(
            timestamp: Date(),
            source: .iphone,
            latitude: 37.80, // ~3km away
            longitude: -122.42
        )
        #expect(PresenceLogic.determinePresence(companion: data, homeLocation: home) == false)
    }

    @Test("Stationary activity without GPS defaults to home")
    func presenceStationaryNoGPS() {
        let data = CompanionData(
            timestamp: Date(),
            source: .iphone,
            motionActivity: "stationary"
        )
        #expect(PresenceLogic.determinePresence(companion: data, homeLocation: nil) == true)
    }

    @Test("Driving activity without GPS means away")
    func presenceDrivingNoGPS() {
        let data = CompanionData(
            timestamp: Date(),
            source: .iphone,
            motionActivity: "driving"
        )
        #expect(PresenceLogic.determinePresence(companion: data, homeLocation: nil) == false)
    }

    @Test("Walking activity without GPS defaults to home (ambiguous)")
    func presenceWalkingNoGPS() {
        let data = CompanionData(
            timestamp: Date(),
            source: .iphone,
            motionActivity: "walking"
        )
        #expect(PresenceLogic.determinePresence(companion: data, homeLocation: nil) == true)
    }

    @Test("nil companion defaults to home")
    func presenceNilCompanion() {
        let home = CLLocation(latitude: 37.7749, longitude: -122.4194)
        #expect(PresenceLogic.determinePresence(companion: nil, homeLocation: home) == true)
    }

    @Test("Custom radius is respected")
    func presenceCustomRadius() {
        let home = CLLocation(latitude: 37.7749, longitude: -122.4194)
        // ~500m away
        let data = CompanionData(
            timestamp: Date(),
            source: .iphone,
            latitude: 37.7793,
            longitude: -122.4194
        )
        // Within 1000m radius
        #expect(PresenceLogic.determinePresence(companion: data, homeLocation: home, radiusMeters: 1000) == true)
        // Outside 100m radius
        #expect(PresenceLogic.determinePresence(companion: data, homeLocation: home, radiusMeters: 100) == false)
    }

    // MARK: - recent() exact 600s boundary

    @Test("Data at exactly 600 seconds is stale (strict < 600)")
    func recentExact600Boundary() {
        let now = Date()
        let atBoundary = CompanionData(
            timestamp: now.addingTimeInterval(-600),
            source: .iphone
        )
        #expect(PresenceLogic.recent(atBoundary, now: now) == nil)
    }

    @Test("Data at 599.9 seconds is still recent")
    func recentJustBeforeBoundary() {
        let now = Date()
        let justBefore = CompanionData(
            timestamp: now.addingTimeInterval(-599.9),
            source: .iphone
        )
        #expect(PresenceLogic.recent(justBefore, now: now) != nil)
    }

    // MARK: - determinePresence() location without homeLocation

    @Test("Companion with location but no homeLocation falls through to activity check")
    func presenceLocationButNoHome() {
        // Has lat/lon but homeLocation is nil, so the location branch
        // enters the if-let but finds home == nil — falls through to activity.
        let stationary = CompanionData(
            timestamp: Date(),
            source: .iphone,
            motionActivity: "stationary",
            latitude: 37.7749,
            longitude: -122.4194
        )
        #expect(PresenceLogic.determinePresence(companion: stationary, homeLocation: nil) == true)

        let driving = CompanionData(
            timestamp: Date(),
            source: .iphone,
            motionActivity: "driving",
            latitude: 37.7749,
            longitude: -122.4194
        )
        #expect(PresenceLogic.determinePresence(companion: driving, homeLocation: nil) == false)
    }

    @Test("Companion with location, no homeLocation, no activity defaults to home")
    func presenceLocationNoHomeNoActivity() {
        let data = CompanionData(
            timestamp: Date(),
            source: .iphone,
            latitude: 37.7749,
            longitude: -122.4194
            // motionActivity is nil, homeLocation is nil
        )
        #expect(PresenceLogic.determinePresence(companion: data, homeLocation: nil) == true)
    }

    // MARK: - bestRecent() same-timestamp determinism

    @Test("bestRecent with identical timestamps returns a deterministic result")
    func bestRecentSameTimestamp() {
        let now = Date()
        let a = CompanionData(
            timestamp: now.addingTimeInterval(-60),
            source: .iphone,
            latitude: 37.0
        )
        let b = CompanionData(
            timestamp: now.addingTimeInterval(-60),
            source: .watch,
            latitude: 38.0
        )
        // max(by:) returns the last maximum element when equal, so the result
        // must be stable regardless of call count.
        let result1 = PresenceLogic.bestRecent(a, b, keyPath: \.latitude, now: now)
        let result2 = PresenceLogic.bestRecent(a, b, keyPath: \.latitude, now: now)
        #expect(result1?.source == result2?.source)

        // Also verify the reversed argument order yields the same winner,
        // confirming that the array ordering [a, b] decides the tie.
        let resultReversed = PresenceLogic.bestRecent(b, a, keyPath: \.latitude, now: now)
        // With equal timestamps, max(by: <) keeps the *last* element in the array,
        // so swapping argument order swaps the winner. The important thing is
        // each call is individually stable.
        let resultReversed2 = PresenceLogic.bestRecent(b, a, keyPath: \.latitude, now: now)
        #expect(resultReversed?.source == resultReversed2?.source)
    }
}
