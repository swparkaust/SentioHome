import Foundation
import Observation

/// Keeps a rolling log of automation actions for the UI to display
/// and supports undo by storing pre-action device snapshots.
@Observable
@MainActor
final class ActionLog {

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let summary: String
        let actions: [DeviceAction]
        let spokenMessage: String?
        let musicQuery: String?

        let previousValues: [String: Double]
    }

    private(set) var entries: [Entry] = []

    private let maxEntries = 50

    func append(plan: AutomationPlanV2, previousValues: [String: Double] = [:]) {
        guard !plan.actions.isEmpty || plan.communication != nil || plan.music != nil else { return }
        let entry = Entry(
            timestamp: Date(),
            summary: plan.summary,
            actions: plan.actions,
            spokenMessage: plan.communication?.message,
            musicQuery: plan.music?.stop == true ? "Stopped music" : plan.music?.query,
            previousValues: previousValues
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    func entry(forNotificationID id: String) -> Entry? {
        entries.first { "automation-\($0.id)" == id }
    }

    /// Find the most recent undoable entry (within the last 60 seconds).
    var mostRecentUndoableEntry: Entry? {
        entries.first {
            !$0.actions.isEmpty &&
            !$0.previousValues.isEmpty &&
            $0.timestamp.timeIntervalSinceNow > -60
        }
    }
}
