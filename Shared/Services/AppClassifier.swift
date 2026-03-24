import Foundation

enum AppClassifier {

    static let bundleIDClassification: [String: String] = [
        "us.zoom.xos": "video call",
        "com.microsoft.teams": "video call",
        "com.microsoft.teams2": "video call",
        "com.apple.FaceTime": "video call",
        "com.webex.meetingmanager": "video call",
        "com.cisco.webexmeetings": "video call",
        "com.slack.Slack": "video call",
        "com.google.Chrome": "video call",

        "com.apple.TV": "watching media",
        "com.apple.Music": "watching media",
        "com.spotify.client": "watching media",
        "com.apple.QuickTimePlayerX": "watching media",
        "tv.plex.desktop": "watching media",
        "com.plexapp.plexmediaserver": "watching media",

        "com.apple.dt.Xcode": "coding",
        "com.microsoft.VSCode": "coding",
        "com.sublimetext.4": "coding",
        "dev.zed.Zed": "coding",
        "com.jetbrains.intellij": "coding",
        "com.jetbrains.CLion": "coding",
        "com.jetbrains.pycharm": "coding",
        "com.googlecode.iterm2": "coding",
        "com.apple.Terminal": "coding",

        "com.apple.iWork.Pages": "writing",
        "com.microsoft.Word": "writing",
        "com.apple.Notes": "writing",
        "pro.writer.mac": "writing",

        "com.valvesoftware.steam": "gaming",
        "com.apple.GameCenter": "gaming",
    ]

    static let cameraRequiredForClassification: Set<String> = [
        "com.slack.Slack",
        "com.google.Chrome",
    ]

    static func classify(bundleID: String?, name: String?, cameraInUse: Bool) -> String? {
        if let bundleID,
           let activity = bundleIDClassification[bundleID] {
            if cameraRequiredForClassification.contains(bundleID) && !cameraInUse {
                return nil
            }
            if activity == "video call" && !cameraInUse {
                return nil
            }
            return activity
        }

        return classifyByName(name, cameraInUse: cameraInUse)
    }

    private static func classifyByName(_ appName: String?, cameraInUse: Bool) -> String? {
        guard let name = appName?.lowercased() else { return nil }

        let meetingApps = ["zoom", "microsoft teams", "facetime", "webex", "slack"]
        if meetingApps.contains(where: { name.contains($0) }) && cameraInUse {
            return "video call"
        }

        let mediaApps = ["tv", "music", "spotify", "netflix", "disney", "plex", "quicktime"]
        if name == "tv" || mediaApps.dropFirst().contains(where: { name.contains($0) }) {
            return "watching media"
        }

        let codeApps = ["xcode", "visual studio code", "code", "sublime text", "zed", "intellij", "terminal", "iterm"]
        if codeApps.contains(where: { name.contains($0) }) {
            return "coding"
        }

        let writingApps = ["pages", "word", "notes", "ia writer", "google docs"]
        if writingApps.contains(where: { name.contains($0) }) {
            return "writing"
        }

        let gameApps = ["game center", "steam"]
        if gameApps.contains(where: { name.contains($0) }) {
            return "gaming"
        }

        return nil
    }
}
