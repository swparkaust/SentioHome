import Testing
@testable import SentioKit

@Suite("AppClassifier")
struct AppClassifierTests {

    // MARK: - Video Call Classification

    @Test("Zoom classified as video call when camera active")
    func zoomWithCamera() {
        #expect(AppClassifier.classify(bundleID: "us.zoom.xos", name: "zoom.us", cameraInUse: true) == "video call")
    }

    @Test("FaceTime classified as video call when camera active")
    func faceTimeWithCamera() {
        #expect(AppClassifier.classify(bundleID: "com.apple.FaceTime", name: "FaceTime", cameraInUse: true) == "video call")
    }

    @Test("Teams classified as video call when camera active")
    func teamsWithCamera() {
        #expect(AppClassifier.classify(bundleID: "com.microsoft.teams2", name: "Microsoft Teams", cameraInUse: true) == "video call")
    }

    @Test("Video call app returns nil when camera inactive")
    func videoCallNoCameraReturnsNil() {
        #expect(AppClassifier.classify(bundleID: "us.zoom.xos", name: "zoom.us", cameraInUse: false) == nil)
    }

    // MARK: - Camera-Required Apps

    @Test("Slack classified as video call only with camera")
    func slackRequiresCamera() {
        #expect(AppClassifier.classify(bundleID: "com.slack.Slack", name: "Slack", cameraInUse: true) == "video call")
    }

    @Test("Slack returns nil without camera")
    func slackNoCameraReturnsNil() {
        #expect(AppClassifier.classify(bundleID: "com.slack.Slack", name: "Slack", cameraInUse: false) == nil)
    }

    @Test("Chrome classified as video call only with camera")
    func chromeRequiresCamera() {
        #expect(AppClassifier.classify(bundleID: "com.google.Chrome", name: "Google Chrome", cameraInUse: true) == "video call")
    }

    @Test("Chrome returns nil without camera")
    func chromeNoCameraReturnsNil() {
        #expect(AppClassifier.classify(bundleID: "com.google.Chrome", name: "Google Chrome", cameraInUse: false) == nil)
    }

    // MARK: - Media Classification

    @Test("Apple TV classified as watching media")
    func appleTVMedia() {
        #expect(AppClassifier.classify(bundleID: "com.apple.TV", name: "TV", cameraInUse: false) == "watching media")
    }

    @Test("Spotify classified as watching media")
    func spotifyMedia() {
        #expect(AppClassifier.classify(bundleID: "com.spotify.client", name: "Spotify", cameraInUse: false) == "watching media")
    }

    @Test("Plex classified as watching media")
    func plexMedia() {
        #expect(AppClassifier.classify(bundleID: "tv.plex.desktop", name: "Plex", cameraInUse: false) == "watching media")
    }

    // MARK: - Coding Classification

    @Test("Xcode classified as coding")
    func xcodeCoding() {
        #expect(AppClassifier.classify(bundleID: "com.apple.dt.Xcode", name: "Xcode", cameraInUse: false) == "coding")
    }

    @Test("VS Code classified as coding")
    func vscodeCoding() {
        #expect(AppClassifier.classify(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", cameraInUse: false) == "coding")
    }

    @Test("Terminal classified as coding")
    func terminalCoding() {
        #expect(AppClassifier.classify(bundleID: "com.apple.Terminal", name: "Terminal", cameraInUse: false) == "coding")
    }

    // MARK: - Writing Classification

    @Test("Pages classified as writing")
    func pagesWriting() {
        #expect(AppClassifier.classify(bundleID: "com.apple.iWork.Pages", name: "Pages", cameraInUse: false) == "writing")
    }

    @Test("Word classified as writing")
    func wordWriting() {
        #expect(AppClassifier.classify(bundleID: "com.microsoft.Word", name: "Microsoft Word", cameraInUse: false) == "writing")
    }

    // MARK: - Gaming Classification

    @Test("Steam classified as gaming")
    func steamGaming() {
        #expect(AppClassifier.classify(bundleID: "com.valvesoftware.steam", name: "Steam", cameraInUse: false) == "gaming")
    }

    // MARK: - Name-Based Fallback

    @Test("Unknown bundle ID falls back to name-based classification")
    func nameFallbackCoding() {
        #expect(AppClassifier.classify(bundleID: "com.unknown.app", name: "Sublime Text", cameraInUse: false) == "coding")
    }

    @Test("Netflix by name classified as watching media")
    func netflixByName() {
        #expect(AppClassifier.classify(bundleID: "com.netflix.unknown", name: "Netflix", cameraInUse: false) == "watching media")
    }

    @Test("Meeting app by name requires camera")
    func meetingByNameRequiresCamera() {
        #expect(AppClassifier.classify(bundleID: "com.unknown", name: "zoom meeting", cameraInUse: false) == nil)
    }

    @Test("Meeting app by name with camera classified")
    func meetingByNameWithCamera() {
        #expect(AppClassifier.classify(bundleID: "com.unknown", name: "zoom meeting", cameraInUse: true) == "video call")
    }

    // MARK: - Nil / Unknown

    @Test("Unknown app returns nil")
    func unknownAppReturnsNil() {
        #expect(AppClassifier.classify(bundleID: "com.random.app", name: "Random App", cameraInUse: false) == nil)
    }

    @Test("Nil bundle ID and name returns nil")
    func nilEverythingReturnsNil() {
        #expect(AppClassifier.classify(bundleID: nil, name: nil, cameraInUse: false) == nil)
    }

    @Test("Nil bundle ID with known name classified")
    func nilBundleIDKnownName() {
        #expect(AppClassifier.classify(bundleID: nil, name: "Xcode", cameraInUse: false) == "coding")
    }
}
