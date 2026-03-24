import Foundation
import HealthKit
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home.companion.watch", category: "Health")

@Observable
@MainActor
final class HealthService {

    private(set) var heartRate: Double?
    private(set) var heartRateVariability: Double?
    private(set) var sleepState: String?
    private(set) var isWorkingOut = false
    private(set) var wristTemperatureDelta: Double?
    private(set) var bloodOxygen: Double?
    private(set) var isAuthorized = false

    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private var workoutPollingTask: Task<Void, Never>?

    private static let readTypes: Set<HKSampleType> = {
        var types: Set<HKSampleType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.appleSleepingWristTemperature),
        ]
        types.insert(HKSeriesType.workoutType())
        return types
    }()

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.info("HealthKit not available on this device")
            return
        }

        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            isAuthorized = true
            logger.info("HealthKit authorization granted")
        } catch {
            logger.error("HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    func startMonitoring() {
        guard isAuthorized else { return }

        observeHeartRate()
        observeHRV()
        observeSleep()
        observeWorkouts()
        observeBloodOxygen()
        observeWristTemperature()

        Task {
            await fetchLatestHeartRate()
            await fetchLatestHRV()
            await fetchLatestSleepState()
            await fetchLatestBloodOxygen()
            await fetchLatestWristTemperature()
        }

        logger.info("Health monitoring started")
    }

    func stopMonitoring() {
        workoutPollingTask?.cancel()
        workoutPollingTask = nil
        for query in observerQueries {
            store.stop(query)
        }
        observerQueries.removeAll()
        logger.info("Health monitoring stopped")
    }

    // MARK: - Heart Rate

    private func observeHeartRate() {
        let type = HKQuantityType(.heartRate)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
            if let error { logger.warning("HR observer error: \(error.localizedDescription)"); return }
            Task { @MainActor [weak self] in await self?.fetchLatestHeartRate() }
        }
        store.execute(query)
        observerQueries.append(query)
    }

    private func fetchLatestHeartRate() async {
        guard let sample = await fetchMostRecent(type: HKQuantityType(.heartRate), within: .minutes(10)) else {
            heartRate = nil
            return
        }
        heartRate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    // MARK: - Heart Rate Variability

    private func observeHRV() {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
            if let error { logger.warning("HRV observer error: \(error.localizedDescription)"); return }
            Task { @MainActor [weak self] in await self?.fetchLatestHRV() }
        }
        store.execute(query)
        observerQueries.append(query)
    }

    private func fetchLatestHRV() async {
        guard let sample = await fetchMostRecent(type: HKQuantityType(.heartRateVariabilitySDNN), within: .hours(1)) else {
            heartRateVariability = nil
            return
        }
        heartRateVariability = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
    }

    // MARK: - Sleep

    private func observeSleep() {
        let type = HKCategoryType(.sleepAnalysis)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
            if let error { logger.warning("Sleep observer error: \(error.localizedDescription)"); return }
            Task { @MainActor [weak self] in await self?.fetchLatestSleepState() }
        }
        store.execute(query)
        observerQueries.append(query)
    }

    private func fetchLatestSleepState() async {
        let type = HKCategoryType(.sleepAnalysis)
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: now.addingTimeInterval(-3600),
            end: now,
            options: .strictEndDate
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )

        do {
            let results = try await descriptor.result(for: store)
            if let sample = results.first {
                sleepState = sleepStateName(for: sample.value)
            } else {
                sleepState = "awake"
            }
        } catch {
            logger.warning("Sleep fetch failed: \(error.localizedDescription)")
        }
    }

    private func sleepStateName(for value: Int) -> String {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed:                return "inBed"
        case .asleepUnspecified:    return "asleepCore"
        case .asleepCore:           return "asleepCore"
        case .asleepDeep:           return "asleepDeep"
        case .asleepREM:            return "asleepREM"
        case .awake:                return "awake"
        default:                    return "awake"
        }
    }

    // MARK: - Workout

    private func observeWorkouts() {
        let type = HKSeriesType.workoutType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
            if let error { logger.warning("Workout observer error: \(error.localizedDescription)"); return }
            Task { @MainActor [weak self] in await self?.fetchActiveWorkout() }
        }
        store.execute(query)
        observerQueries.append(query)

        // Also poll periodically since workout end may not trigger observer immediately
        workoutPollingTask = Task {
            while !Task.isCancelled {
                await fetchActiveWorkout()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func fetchActiveWorkout() async {
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: now.addingTimeInterval(-7200), // last 2 hours
            end: now,
            options: .strictStartDate
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )

        do {
            let results = try await descriptor.result(for: store)
            if let workout = results.first {
                // If the workout ended less than 60 seconds ago, consider it still active
                isWorkingOut = workout.endDate.timeIntervalSinceNow > -60
            } else {
                isWorkingOut = false
            }
        } catch {
            isWorkingOut = false
        }
    }

    // MARK: - Blood Oxygen

    private func observeBloodOxygen() {
        let type = HKQuantityType(.oxygenSaturation)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
            if let error { logger.warning("SpO2 observer error: \(error.localizedDescription)"); return }
            Task { @MainActor [weak self] in await self?.fetchLatestBloodOxygen() }
        }
        store.execute(query)
        observerQueries.append(query)
    }

    private func fetchLatestBloodOxygen() async {
        guard let sample = await fetchMostRecent(type: HKQuantityType(.oxygenSaturation), within: .hours(1)) else {
            bloodOxygen = nil
            return
        }
        bloodOxygen = sample.quantity.doubleValue(for: .percent())
    }

    // MARK: - Wrist Temperature

    private func observeWristTemperature() {
        let type = HKQuantityType(.appleSleepingWristTemperature)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
            if let error { logger.warning("Wrist temp observer error: \(error.localizedDescription)"); return }
            Task { @MainActor [weak self] in await self?.fetchLatestWristTemperature() }
        }
        store.execute(query)
        observerQueries.append(query)
    }

    private func fetchLatestWristTemperature() async {
        guard let sample = await fetchMostRecent(type: HKQuantityType(.appleSleepingWristTemperature), within: .hours(12)) else {
            wristTemperatureDelta = nil
            return
        }
        wristTemperatureDelta = sample.quantity.doubleValue(for: .degreeCelsius())
    }

    // MARK: - Generic Fetch

    private func fetchMostRecent(type: HKQuantityType, within duration: Duration) async -> HKQuantitySample? {
        let now = Date()
        let start = now.addingTimeInterval(-duration.timeInterval)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictEndDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )

        do {
            return try await descriptor.result(for: store).first
        } catch {
            logger.warning("Fetch \(type.identifier) failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Duration Helper

private extension Duration {
    static func minutes(_ m: Int) -> Duration { .seconds(m * 60) }
    static func hours(_ h: Int) -> Duration { .seconds(h * 3600) }

    var timeInterval: TimeInterval { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
