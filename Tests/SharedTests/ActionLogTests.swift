import Testing
import Foundation
@testable import SentioKit


@Suite("ActionLog")
@MainActor
struct ActionLogTests {

    @Test("Appending a plan with actions creates an entry")
    func appendWithActions() {
        let log = ActionLog()
        let plan = AutomationPlanV2(
            actions: [
                DeviceAction(
                    accessoryID: "light-1",
                    accessoryName: "Living Room Light",
                    characteristic: "brightness",
                    value: 50,
                    reason: "Dimming for evening"
                )
            ],
            communication: nil,
            music: nil,
            summary: "Evening dimming"
        )

        log.append(plan: plan)

        #expect(log.entries.count == 1)
        #expect(log.entries[0].summary == "Evening dimming")
        #expect(log.entries[0].actions.count == 1)
        #expect(log.entries[0].spokenMessage == nil)
        #expect(log.entries[0].musicQuery == nil)
    }

    @Test("Appending a plan with communication records spoken message")
    func appendWithCommunication() {
        let log = ActionLog()
        let plan = AutomationPlanV2(
            actions: [],
            communication: CommunicationAction(
                message: "Welcome home!",
                route: "auto",
                expectsReply: false,
                            ),
            music: nil,
            summary: "Welcome"
        )

        log.append(plan: plan)

        #expect(log.entries.count == 1)
        #expect(log.entries[0].spokenMessage == "Welcome home!")
    }

    @Test("Appending a plan with music records query")
    func appendWithMusic() {
        let log = ActionLog()
        let plan = AutomationPlanV2(
            actions: [],
            communication: nil,
            music: MusicAction(
                query: "lo-fi chill beats",
                volume: 0.3,
                stop: false
            ),
            summary: "Ambient music"
        )

        log.append(plan: plan)

        #expect(log.entries.count == 1)
        #expect(log.entries[0].musicQuery == "lo-fi chill beats")
    }

    @Test("Music stop action records 'Stopped music'")
    func musicStopRecorded() {
        let log = ActionLog()
        let plan = AutomationPlanV2(
            actions: [],
            communication: nil,
            music: MusicAction(
                query: "",
                volume: 0,
                stop: true
            ),
            summary: "Stop music"
        )

        log.append(plan: plan)

        #expect(log.entries[0].musicQuery == "Stopped music")
    }

    @Test("Empty plan is not appended")
    func emptyPlanIgnored() {
        let log = ActionLog()
        let plan = AutomationPlanV2(
            actions: [],
            communication: nil,
            music: nil,
            summary: "No changes"
        )

        log.append(plan: plan)

        #expect(log.entries.isEmpty)
    }

    @Test("Entries are inserted at the beginning (most recent first)")
    func insertionOrder() {
        let log = ActionLog()

        log.append(plan: AutomationPlanV2(
            actions: [DeviceAction(accessoryID: "1", accessoryName: "A", characteristic: "on", value: 1, reason: "first")],
            communication: nil, music: nil, summary: "First"
        ))

        log.append(plan: AutomationPlanV2(
            actions: [DeviceAction(accessoryID: "2", accessoryName: "B", characteristic: "on", value: 1, reason: "second")],
            communication: nil, music: nil, summary: "Second"
        ))

        #expect(log.entries[0].summary == "Second")
        #expect(log.entries[1].summary == "First")
    }

    @Test("Log caps at 50 entries")
    func maxEntries() {
        let log = ActionLog()

        for i in 0..<60 {
            log.append(plan: AutomationPlanV2(
                actions: [DeviceAction(accessoryID: "\(i)", accessoryName: "D\(i)", characteristic: "on", value: 1, reason: "r")],
                communication: nil, music: nil, summary: "Entry \(i)"
            ))
        }

        #expect(log.entries.count == 50)
        // Most recent should be first
        #expect(log.entries[0].summary == "Entry 59")
    }

    // MARK: - Previous Values & Undo

    @Test("Appending with previousValues stores them in the entry")
    func appendWithPreviousValues() {
        let log = ActionLog()
        let plan = AutomationPlanV2(
            actions: [
                DeviceAction(
                    accessoryID: "light-1",
                    accessoryName: "Lamp",
                    characteristic: "brightness",
                    value: 50,
                    reason: "Dimming"
                )
            ],
            communication: nil,
            music: nil,
            summary: "Dim"
        )

        log.append(plan: plan, previousValues: ["light-1|brightness": 100])

        #expect(log.entries[0].previousValues["light-1|brightness"] == 100)
    }

    @Test("mostRecentUndoableEntry returns entry with non-empty previousValues")
    func undoableEntry() {
        let log = ActionLog()
        let plan = AutomationPlanV2(
            actions: [
                DeviceAction(accessoryID: "l1", accessoryName: "L", characteristic: "on", value: 0, reason: "off")
            ],
            communication: nil,
            music: nil,
            summary: "Turn off"
        )

        log.append(plan: plan, previousValues: ["l1|on": 1])

        #expect(log.mostRecentUndoableEntry != nil)
        #expect(log.mostRecentUndoableEntry?.previousValues["l1|on"] == 1)
    }

    @Test("mostRecentUndoableEntry returns nil when previousValues is empty")
    func noUndoableEntry() {
        let log = ActionLog()
        let plan = AutomationPlanV2(
            actions: [
                DeviceAction(accessoryID: "l1", accessoryName: "L", characteristic: "on", value: 0, reason: "off")
            ],
            communication: nil,
            music: nil,
            summary: "Turn off"
        )

        log.append(plan: plan) // No previousValues

        #expect(log.mostRecentUndoableEntry == nil)
    }

    @Test("mostRecentUndoableEntry skips entries with empty actions")
    func undoableRequiresActions() {
        let log = ActionLog()
        let plan = AutomationPlanV2(
            actions: [],
            communication: CommunicationAction(
                message: "Hello",
                route: "auto",
                expectsReply: false
            ),
            music: nil,
            summary: "Greeting"
        )

        log.append(plan: plan, previousValues: ["something": 1])

        // Has previousValues but no actions — should not be undoable
        #expect(log.mostRecentUndoableEntry == nil)
    }

    @Test("entry(forNotificationID:) finds the correct entry")
    func findByNotificationID() {
        let log = ActionLog()
        let plan = AutomationPlanV2(
            actions: [
                DeviceAction(accessoryID: "l1", accessoryName: "L", characteristic: "on", value: 1, reason: "on")
            ],
            communication: nil,
            music: nil,
            summary: "Lights on"
        )

        log.append(plan: plan)
        let entryID = log.entries[0].id
        let found = log.entry(forNotificationID: "automation-\(entryID)")

        #expect(found != nil)
        #expect(found?.summary == "Lights on")
    }

    @Test("entry(forNotificationID:) returns nil for unknown ID")
    func findByNotificationIDNotFound() {
        let log = ActionLog()
        #expect(log.entry(forNotificationID: "automation-nonexistent") == nil)
    }
}
