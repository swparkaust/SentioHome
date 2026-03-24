import Foundation
import CloudKit
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "CloudSync")

/// Syncs companion data between iOS/watchOS apps and the macOS server via a shared
/// CloudKit private database (iCloud container).
@Observable
@MainActor
final class CloudSyncService {

    /// Shared instance for use by App Intents and other contexts that
    /// can't access the app's view-owned instance.
    static let shared = CloudSyncService()

    // MARK: - State

    private(set) var latestIPhoneData: CompanionData?
    private(set) var latestWatchData: CompanionData?

    private(set) var isSyncing = false

    /// Whether the user is signed into iCloud. When false, all CloudKit
    /// operations will fail and companion data sync is unavailable.
    private(set) var iCloudAvailable = true

    /// Legacy accessor — returns the most recent companion data from either source.
    var latestCompanionData: CompanionData? {
        [latestIPhoneData, latestWatchData]
            .compactMap { $0 }
            .max { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private

    private let container: CKContainer?
    private let database: CKDatabase?

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            container = nil
            database = nil
            iCloudAvailable = false
            logger.info("CloudSyncService initialized in UI testing mode — CloudKit disabled")
            return
        }
        let ckContainer = CKContainer(identifier: "iCloud.com.sentio.home")
        container = ckContainer
        database = ckContainer.privateCloudDatabase

        Task { await checkAccountStatus() }
    }

    func checkAccountStatus() async {
        guard let container else {
            iCloudAvailable = false
            return
        }
        do {
            let status = try await container.accountStatus()
            iCloudAvailable = (status == .available)
            if !iCloudAvailable {
                logger.warning("iCloud account not available (status: \(String(describing: status))). Companion sync disabled.")
            }
        } catch {
            iCloudAvailable = false
            logger.error("Failed to check iCloud account status: \(error.localizedDescription)")
        }
    }

    // MARK: - Schema Initialization

    private static let schemaInitializedKey = "cloudKitSchemaInitialized_v2"

    private(set) var schemaReady = false

    func initializeSchemaIfNeeded() async {
        guard iCloudAvailable, let database else { return }

        if UserDefaults.standard.bool(forKey: Self.schemaInitializedKey) {
            schemaReady = true
            return
        }

        do {
            let records = [
                (CompanionData.recordType, ["source": "iphone" as CKRecordValue]),
                (UserRequest.recordType, ["requestID": "schema-init" as CKRecordValue]),
                (UserResponse.recordType, ["requestID": "schema-init" as CKRecordValue]),
                (Self.voiceRelayRecordType, ["message": "schema-init" as CKRecordValue]),
            ]

            for (type, fields) in records {
                let record = CKRecord(recordType: type)
                for (key, value) in fields { record[key] = value }
                let saved = try await database.save(record)
                try await database.deleteRecord(withID: saved.recordID)
            }

            UserDefaults.standard.set(true, forKey: Self.schemaInitializedKey)
            schemaReady = true
            logger.info("CloudKit schema initialized successfully")
        } catch {
            logger.warning("CloudKit schema initialization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sending (iOS/watchOS → Cloud)

    func pushCompanionData(_ data: CompanionData) async throws {
        guard iCloudAvailable, let database else {
            logger.debug("Skipping push — iCloud unavailable")
            return
        }
        let record = data.toCKRecord()
        _ = try await database.save(record)
        logger.info("Pushed \(data.source.rawValue) companion data at \(data.timestamp)")
    }

    // MARK: - Receiving (Cloud → macOS)

    func pullLatestCompanionData() async {
        guard iCloudAvailable, database != nil else {
            logger.debug("Skipping pull — iCloud unavailable")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        async let iPhoneResult = pullLatest(source: .iphone)
        async let watchResult = pullLatest(source: .watch)

        let (iPhone, watch) = await (iPhoneResult, watchResult)

        if let iPhone {
            latestIPhoneData = iPhone
            logger.info("Pulled iPhone data from \(iPhone.timestamp)")
        }
        if let watch {
            latestWatchData = watch
            logger.info("Pulled Watch data from \(watch.timestamp)")
        }
    }

    private func pullLatest(source: CompanionData.Source) async -> CompanionData? {
        guard let database, schemaReady else { return nil }
        let predicate = NSPredicate(format: "source == %@", source.rawValue)
        let query = CKQuery(recordType: CompanionData.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 1)
            if let (_, result) = results.first {
                let record = try result.get()
                return CompanionData.from(record)
            }
        } catch {
            logger.debug("Failed to pull \(source.rawValue) data: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Subscription (macOS — live updates)

    func subscribeToUpdates() async {
        guard iCloudAvailable, let database else { return }
        let subscription = CKQuerySubscription(
            recordType: CompanionData.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: "companion-data-updates",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        do {
            _ = try await database.save(subscription)
            logger.info("Subscribed to companion data updates")
        } catch {
            logger.debug("Subscription setup: \(error.localizedDescription)")
        }
    }

    // MARK: - Voice Relay (macOS → iOS)

    private static let voiceRelayRecordType = "VoiceRelay"
    private static let voiceReplyRecordType = "VoiceReply"

    func pushVoiceRelay(_ relay: VoiceRelay) async throws {
        guard iCloudAvailable, let database, schemaReady else { return }
        let record = CKRecord(recordType: Self.voiceRelayRecordType)
        record["message"]       = relay.message as CKRecordValue
        record["expectsReply"]  = NSNumber(value: relay.expectsReply) as CKRecordValue
        record["timestamp"]     = relay.timestamp as CKRecordValue
        _ = try await database.save(record)
    }

    func pullLatestVoiceRelay() async -> VoiceRelay? {
        guard iCloudAvailable, let database, schemaReady else { return nil }
        let query = CKQuery(
            recordType: Self.voiceRelayRecordType,
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 1)
            if let (_, result) = results.first {
                let record = try result.get()
                guard let message = record["message"] as? String,
                      let timestamp = record["timestamp"] as? Date else { return nil }
                let expectsReply = (record["expectsReply"] as? NSNumber)?.boolValue ?? false
                return VoiceRelay(message: message, expectsReply: expectsReply, timestamp: timestamp)
            }
        } catch {
            logger.debug("Failed to pull voice relay: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Voice Reply (iOS → macOS)

    func pushVoiceReply(_ reply: String) async throws {
        guard iCloudAvailable, let database else { return }
        let record = CKRecord(recordType: Self.voiceReplyRecordType)
        record["reply"]     = reply as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue
        _ = try await database.save(record)
    }

    func pullLatestVoiceReply() async -> String? {
        guard iCloudAvailable, let database else { return nil }
        let query = CKQuery(
            recordType: Self.voiceReplyRecordType,
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 1)
            if let (_, result) = results.first {
                let record = try result.get()
                guard let reply = record["reply"] as? String,
                      let timestamp = record["timestamp"] as? Date,
                      timestamp.timeIntervalSinceNow > -60 else { return nil }
                return reply
            }
        } catch {
            logger.debug("Failed to pull voice reply: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Multi-Occupant

    /// Returns the number of unique companion devices that have pushed data recently.
    ///
    /// **Limitation:** This app uses CloudKit's **private** database, where all records
    /// belong to the same iCloud account. `creatorUserRecordID` is identical for all
    /// records, so this method cannot distinguish household members. It instead counts
    /// distinct device identifiers (from the `deviceID` field) to detect multiple
    /// iPhones on the same iCloud account (e.g., a family sharing scenario).
    ///
    /// For true multi-user occupancy, use `GuestDetectionService` (network/BLE scanning)
    /// which detects unknown devices regardless of iCloud account.
    func countRecentOccupants() async -> Int {
        guard iCloudAvailable, let database else { return 1 }
        let cutoff = Date().addingTimeInterval(-600) // 10 minutes
        let predicate = NSPredicate(format: "timestamp > %@ AND source == %@", cutoff as NSDate, "iphone")
        let query = CKQuery(recordType: CompanionData.recordType, predicate: predicate)

        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 20)
            var uniqueDevices = Set<String>()
            for (_, result) in results {
                if let record = try? result.get(),
                   let deviceID = record["deviceID"] as? String {
                    uniqueDevices.insert(deviceID)
                }
            }
            // Fall back to 1 if no deviceID fields found (older records)
            return max(uniqueDevices.count, 1)
        } catch {
            logger.debug("Occupant count failed: \(error.localizedDescription)")
            return 1
        }
    }

    // MARK: - User Requests (iOS → macOS)

    func pushUserRequest(_ request: UserRequest) async throws {
        guard iCloudAvailable, let database else { return }
        let record = request.toCKRecord()
        _ = try await database.save(record)
        logger.info("Pushed user request: \(request.message.prefix(60))")
    }

    func pullLatestUserRequest() async -> UserRequest? {
        guard iCloudAvailable, let database, schemaReady else { return nil }
        let cutoff = Date().addingTimeInterval(-120)
        let predicate = NSPredicate(format: "timestamp > %@", cutoff as NSDate)
        let query = CKQuery(recordType: UserRequest.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 1)
            if let (_, result) = results.first {
                let record = try result.get()
                return UserRequest.from(record)
            }
        } catch {
            logger.debug("Failed to pull user request: \(error.localizedDescription)")
        }
        return nil
    }

    func subscribeToUserRequests() async {
        guard iCloudAvailable, let database else { return }
        let subscription = CKQuerySubscription(
            recordType: UserRequest.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: "user-request-updates",
            options: [.firesOnRecordCreation]
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        do {
            _ = try await database.save(subscription)
            logger.info("Subscribed to user request notifications")
        } catch {
            logger.debug("User request subscription: \(error.localizedDescription)")
        }
    }

    // MARK: - User Responses (macOS → iOS)

    func pushUserResponse(_ response: UserResponse) async throws {
        guard iCloudAvailable, let database else { return }
        let record = response.toCKRecord()
        _ = try await database.save(record)
        logger.info("Pushed response for request \(response.requestID)")
    }

    func pullUserResponse(requestID: String) async -> UserResponse? {
        guard iCloudAvailable, let database else { return nil }
        let predicate = NSPredicate(format: "requestID == %@", requestID)
        let query = CKQuery(recordType: UserResponse.recordType, predicate: predicate)

        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 1)
            if let (_, result) = results.first {
                let record = try result.get()
                return UserResponse.from(record)
            }
        } catch {
            logger.debug("Failed to pull user response: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Emergency Alerts (macOS → all companions)

    private static let emergencyAlertRecordType = "EmergencyAlert"

    /// Uses a visible push (not silent) so companions show an immediate alert
    /// even when backgrounded.
    func pushEmergencyAlert(type: String, message: String, timestamp: Date) async throws {
        guard iCloudAvailable, let database else {
            logger.error("Cannot push emergency alert — iCloud unavailable")
            throw CKError(.networkUnavailable)
        }
        let record = CKRecord(recordType: Self.emergencyAlertRecordType)
        record["alertType"] = type as CKRecordValue
        record["message"]   = message as CKRecordValue
        record["timestamp"] = timestamp as CKRecordValue
        _ = try await database.save(record)
        logger.info("Emergency alert pushed: \(type)")
    }

    func pullLatestEmergencyAlert() async -> (type: String, message: String, timestamp: Date)? {
        guard iCloudAvailable, let database else { return nil }
        let cutoff = Date().addingTimeInterval(-300)
        let predicate = NSPredicate(format: "timestamp > %@", cutoff as NSDate)
        let query = CKQuery(recordType: Self.emergencyAlertRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 1)
            if let (_, result) = results.first {
                let record = try result.get()
                guard let type = record["alertType"] as? String,
                      let message = record["message"] as? String,
                      let timestamp = record["timestamp"] as? Date else { return nil }
                return (type, message, timestamp)
            }
        } catch {
            logger.debug("Failed to pull emergency alert: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Cleanup

    func pruneOldRecords() async {
        guard iCloudAvailable, let database else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        let predicate = NSPredicate(format: "timestamp < %@", cutoff as NSDate)
        let query = CKQuery(recordType: CompanionData.recordType, predicate: predicate)

        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 50)
            let ids = results.map(\.0)
            for id in ids {
                _ = try? await database.deleteRecord(withID: id)
            }
            if !ids.isEmpty {
                logger.info("Pruned \(ids.count) old companion record(s)")
            }
        } catch {
            logger.debug("Prune failed: \(error.localizedDescription)")
        }
    }
}
