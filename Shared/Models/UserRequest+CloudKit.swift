import Foundation
import CloudKit

extension UserRequest {

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType)
        record["requestID"]      = id as CKRecordValue
        record["message"]        = message as CKRecordValue
        record["timestamp"]      = timestamp as CKRecordValue
        record["intent"]         = intent as CKRecordValue
        record["conversationID"] = conversationID as CKRecordValue
        return record
    }

    static func from(_ record: CKRecord) -> UserRequest? {
        guard let id = record["requestID"] as? String,
              let message = record["message"] as? String,
              let timestamp = record["timestamp"] as? Date,
              let conversationID = record["conversationID"] as? String else { return nil }
        return UserRequest(
            id: id,
            message: message,
            timestamp: timestamp,
            intent: record["intent"] as? String ?? "auto",
            conversationID: conversationID
        )
    }
}

extension UserResponse {

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType)
        record["requestID"]           = requestID as CKRecordValue
        record["message"]             = message as CKRecordValue
        record["actionsPerformed"]    = actionsPerformed as CKRecordValue
        record["timestamp"]           = timestamp as CKRecordValue
        record["expectsContinuation"] = NSNumber(value: expectsContinuation)
        record["conversationID"]      = conversationID as CKRecordValue
        return record
    }

    static func from(_ record: CKRecord) -> UserResponse? {
        guard let requestID = record["requestID"] as? String,
              let message = record["message"] as? String,
              let timestamp = record["timestamp"] as? Date,
              let conversationID = record["conversationID"] as? String else { return nil }
        return UserResponse(
            requestID: requestID,
            message: message,
            actionsPerformed: record["actionsPerformed"] as? [String] ?? [],
            timestamp: timestamp,
            expectsContinuation: (record["expectsContinuation"] as? NSNumber)?.boolValue ?? false,
            conversationID: conversationID
        )
    }
}
