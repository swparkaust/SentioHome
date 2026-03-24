import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "Preferences")

/// Detects when users override AI-driven actions and persists those overrides
/// as a preference signal. The Intelligence Engine reads these to avoid
/// repeating unwanted automations.
///
/// Detection works by snapshot comparison: after the AI executes actions,
/// we record what was set, wait a short window, then re-read the device state.
/// If the value changed, the user (or another automation) corrected it.
@Observable
@MainActor
final class PreferenceMemory {

    private(set) var overrides: [UserOverride] = []
    private(set) var pendingWatches: Int = 0

    let detectionWindowSeconds: TimeInterval = 300
    let maxOverrides = 200

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("SentioHome", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("overrides.json")
        if appSupport == FileManager.default.temporaryDirectory {
            logger.warning("Application Support directory unavailable — using temporary directory for preference storage")
        }
        load()
        loadSeasonalSummaries()
    }

    // MARK: - Override Detection

    func watchForOverrides(
        actions: [DeviceAction],
        context: HomeContext,
        homeKit: any DeviceSnapshotProvider
    ) {
        guard !actions.isEmpty else { return }

        let watchList = actions.map { action in
            PendingWatch(
                accessoryID: action.accessoryID,
                accessoryName: action.accessoryName,
                characteristic: action.characteristic,
                aiSetValue: action.value,
                aiReason: action.reason,
                context: context
            )
        }

        pendingWatches += watchList.count
        logger.info("Watching \(watchList.count) device(s) for overrides over \(self.detectionWindowSeconds)s")

        Task {
            try? await Task.sleep(for: .seconds(detectionWindowSeconds))
            await detectOverrides(watches: watchList, homeKit: homeKit)
            pendingWatches -= watchList.count
        }
    }

    private func detectOverrides(
        watches: [PendingWatch],
        homeKit: any DeviceSnapshotProvider
    ) async {
        let currentSnapshots = homeKit.allDeviceSnapshots
        var detected: [UserOverride] = []

        for watch in watches {
            guard let snapshot = currentSnapshots.first(where: { $0.id == watch.accessoryID }),
                  let characteristic = snapshot.characteristics.first(where: { $0.type == watch.characteristic }),
                  let currentValue = characteristic.value else {
                continue
            }

            let delta = abs(currentValue - watch.aiSetValue)
            let isOverride: Bool

            switch watch.characteristic {
            case "on":
                isOverride = (watch.aiSetValue >= 1) != (currentValue >= 1)
            case "brightness", "saturation":
                isOverride = delta > 5
            case "hue":
                isOverride = delta > 10
            case "targetTemperature":
                isOverride = delta > 0.5
            default:
                isOverride = delta > 1
            }

            if isOverride {
                let override = UserOverride(
                    id: UUID(),
                    timestamp: Date(),
                    accessoryID: watch.accessoryID,
                    accessoryName: watch.accessoryName,
                    roomName: snapshot.roomName,
                    characteristic: watch.characteristic,
                    aiSetValue: watch.aiSetValue,
                    aiReason: watch.aiReason,
                    userSetValue: currentValue,
                    timeOfDay: watch.context.timeOfDay,
                    dayOfWeek: watch.context.dayOfWeek,
                    isWeekend: watch.context.isWeekend,
                    weatherCondition: watch.context.weatherCondition,
                    userWasHome: watch.context.userIsHome
                )
                detected.append(override)
                logger.info("Override detected: \(watch.accessoryName).\(watch.characteristic) — AI set \(watch.aiSetValue), user changed to \(currentValue)")
            }
        }

        if !detected.isEmpty {
            overrides.append(contentsOf: detected)
            pruneIfNeeded()
            save()
            logger.info("\(detected.count) override(s) recorded. Total: \(self.overrides.count)")
        }
    }

    // MARK: - Query

    var recentOverrides: [UserOverride] {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        return overrides
            .filter { $0.timestamp > cutoff }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var promptSection: String? {
        let recent = recentOverrides
        guard !recent.isEmpty else { return nil }

        let lines = recent.prefix(20).map(\.promptDescription)
        return """
        ## User Override History (last 30 days, most recent first)
        The user has manually corrected the following AI actions. \
        Analyze these patterns to understand the user's preferences. \
        Avoid repeating actions the user has consistently overridden in similar contexts. \
        If the user repeatedly sets a device to a specific value in a given context, \
        prefer that value in the future.

        \(lines.joined(separator: "\n"))
        """
    }

    // MARK: - Seasonal Summaries

    /// Compressed long-term preference patterns that persist beyond the 30-day override window.
    /// Generated periodically by summarizing old overrides before they age out.
    private(set) var seasonalSummaries: [SeasonalSummary] = []

    var fullPromptSection: String? {
        var sections: [String] = []

        if let recent = promptSection {
            sections.append(recent)
        }

        if !seasonalSummaries.isEmpty {
            let lines = seasonalSummaries.map(\.promptDescription)
            sections.append("""
            ## Seasonal Preferences (long-term patterns)
            These are compressed patterns from the user's history that span multiple months. \
            Use these as baseline preferences, but recent overrides take priority.

            \(lines.joined(separator: "\n"))
            """)
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    /// Call periodically (e.g. once per day) to compress old overrides before they age out.
    func compressOldOverrides() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let oldOverrides = overrides.filter { $0.timestamp <= cutoff }
        guard oldOverrides.count >= 5 else { return } // Need enough data to find patterns

        var patterns: [String: [UserOverride]] = [:]
        for override in oldOverrides {
            let key = "\(override.accessoryName)|\(override.characteristic)|\(override.isWeekend ? "weekend" : "weekday")"
            patterns[key, default: []].append(override)
        }

        var newSummaries: [SeasonalSummary] = []
        for (_, group) in patterns where group.count >= 2 {
            guard let first = group.first else { continue }
            let avgValue = group.map(\.userSetValue).reduce(0, +) / Double(group.count)
            let months = Set(group.map { Calendar.current.component(.month, from: $0.timestamp) })
                .filter { $0 >= 1 && $0 <= 12 }
                .sorted()
            let monthNames = months.map { Calendar.current.monthSymbols[$0 - 1] }

            newSummaries.append(SeasonalSummary(
                accessoryName: first.accessoryName,
                characteristic: first.characteristic,
                preferredValue: avgValue,
                context: first.isWeekend ? "weekends" : "weekdays",
                months: monthNames,
                sampleCount: group.count,
                lastUpdated: Date()
            ))
        }

        if !newSummaries.isEmpty {
            for newSummary in newSummaries {
                if let idx = seasonalSummaries.firstIndex(where: {
                    $0.accessoryName == newSummary.accessoryName &&
                    $0.characteristic == newSummary.characteristic &&
                    $0.context == newSummary.context
                }) {
                    seasonalSummaries[idx] = newSummary
                } else {
                    seasonalSummaries.append(newSummary)
                }
            }

            overrides.removeAll { $0.timestamp <= cutoff }
            save()
            saveSeasonalSummaries()
            logger.info("Compressed \(oldOverrides.count) old overrides into \(newSummaries.count) seasonal summaries")
        }
    }

    // MARK: - Seasonal Persistence

    private var seasonalStorageURL: URL {
        storageURL.deletingLastPathComponent().appendingPathComponent("seasonal.json")
    }

    private func saveSeasonalSummaries() {
        do {
            let data = try JSONEncoder().encode(seasonalSummaries)
            try data.write(to: seasonalStorageURL, options: .atomic)
        } catch {
            logger.error("Failed to save seasonal summaries: \(error.localizedDescription)")
        }
    }

    private func loadSeasonalSummaries() {
        guard FileManager.default.fileExists(atPath: seasonalStorageURL.path) else { return }
        do {
            let data = try Data(contentsOf: seasonalStorageURL)
            seasonalSummaries = try JSONDecoder().decode([SeasonalSummary].self, from: data)
            logger.info("Loaded \(self.seasonalSummaries.count) seasonal summary(ies)")
        } catch {
            logger.error("Failed to load seasonal summaries: \(error.localizedDescription)")
        }
    }

    // MARK: - Reset

    func resetAll() {
        seasonalSummaries.removeAll()
        saveSeasonalSummaries()
        overrides.removeAll()
        save()
        logger.info("All preference overrides cleared")
    }

    // MARK: - Test Support

    /// Injects test data directly. Only for use in unit tests.
    func injectTestOverrides(_ newOverrides: [UserOverride]) {
        overrides.append(contentsOf: newOverrides)
    }

    /// Injects test data directly. Only for use in unit tests.
    func injectTestSummaries(_ summaries: [SeasonalSummary]) {
        seasonalSummaries = summaries
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(overrides)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            logger.error("Failed to save overrides: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            overrides = try JSONDecoder().decode([UserOverride].self, from: data)
            logger.info("Loaded \(self.overrides.count) override(s) from disk")
        } catch {
            logger.error("Failed to load overrides: \(error.localizedDescription)")
        }
    }

    private func pruneIfNeeded() {
        if overrides.count > maxOverrides {
            overrides = Array(overrides.suffix(maxOverrides))
        }
    }
}

// MARK: - Pending Watch

private struct PendingWatch {
    let accessoryID: String
    let accessoryName: String
    let characteristic: String
    let aiSetValue: Double
    let aiReason: String
    let context: HomeContext
}
