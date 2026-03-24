import Foundation
import CloudKit

extension CompanionData {

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType)
        record["timestamp"]                 = timestamp as CKRecordValue
        record["source"]                    = source.rawValue as CKRecordValue
        record["deviceID"]                  = deviceID as CKRecordValue?

        record["motionActivity"]            = motionActivity as CKRecordValue?
        record["latitude"]                  = latitude as CKRecordValue?
        record["longitude"]                 = longitude as CKRecordValue?
        record["batteryLevel"]              = batteryLevel as CKRecordValue?

        record["ambientLightLux"]           = ambientLightLux as CKRecordValue?
        record["screenBrightness"]          = screenBrightness as CKRecordValue?

        record["airPodsConnected"]          = airPodsConnected.map { NSNumber(value: $0) } as CKRecordValue?
        record["airPodsInEar"]              = airPodsInEar.map { NSNumber(value: $0) } as CKRecordValue?
        record["headPosture"]               = headPosture as CKRecordValue?

        record["focusMode"]                 = focusMode as CKRecordValue?
        record["approachingHome"]           = approachingHome.map { NSNumber(value: $0) } as CKRecordValue?

        record["heartRate"]                 = heartRate as CKRecordValue?
        record["heartRateVariability"]      = heartRateVariability as CKRecordValue?
        record["sleepState"]                = sleepState as CKRecordValue?
        record["isWorkingOut"]              = isWorkingOut.map { NSNumber(value: $0) } as CKRecordValue?
        record["wristTemperatureDelta"]     = wristTemperatureDelta as CKRecordValue?
        record["bloodOxygen"]               = bloodOxygen as CKRecordValue?

        return record
    }

    static func from(_ record: CKRecord) -> CompanionData? {
        guard let timestamp = record["timestamp"] as? Date,
              let sourceRaw = record["source"] as? String,
              let source = Source(rawValue: sourceRaw) else {
            guard let timestamp = record["timestamp"] as? Date else { return nil }
            let fallbackSource: Source = {
                if record["heartRate"] != nil || record["sleepState"] != nil || record["isWorkingOut"] != nil {
                    return .watch
                }
                return .iphone
            }()
            return CompanionData(
                timestamp:                  timestamp,
                source:                     fallbackSource,
                deviceID:                   record["deviceID"] as? String,
                motionActivity:             record["motionActivity"] as? String,
                latitude:                   record["latitude"] as? Double,
                longitude:                  record["longitude"] as? Double,
                batteryLevel:               record["batteryLevel"] as? Double,
                ambientLightLux:            record["ambientLightLux"] as? Double,
                screenBrightness:           record["screenBrightness"] as? Double,
                airPodsConnected:           (record["airPodsConnected"] as? NSNumber)?.boolValue,
                airPodsInEar:               (record["airPodsInEar"] as? NSNumber)?.boolValue,
                headPosture:                record["headPosture"] as? String,
                focusMode:                  record["focusMode"] as? String,
                approachingHome:            (record["approachingHome"] as? NSNumber)?.boolValue,
                heartRate:                  record["heartRate"] as? Double,
                heartRateVariability:       record["heartRateVariability"] as? Double,
                sleepState:                 record["sleepState"] as? String,
                isWorkingOut:               (record["isWorkingOut"] as? NSNumber)?.boolValue,
                wristTemperatureDelta:      record["wristTemperatureDelta"] as? Double,
                bloodOxygen:                record["bloodOxygen"] as? Double
            )
        }

        return CompanionData(
            timestamp:                  timestamp,
            source:                     source,
            deviceID:                   record["deviceID"] as? String,
            motionActivity:             record["motionActivity"] as? String,
            latitude:                   record["latitude"] as? Double,
            longitude:                  record["longitude"] as? Double,
            batteryLevel:               record["batteryLevel"] as? Double,
            ambientLightLux:            record["ambientLightLux"] as? Double,
            screenBrightness:           record["screenBrightness"] as? Double,
            airPodsConnected:           (record["airPodsConnected"] as? NSNumber)?.boolValue,
            airPodsInEar:               (record["airPodsInEar"] as? NSNumber)?.boolValue,
            headPosture:                record["headPosture"] as? String,
            focusMode:                  record["focusMode"] as? String,
            approachingHome:            (record["approachingHome"] as? NSNumber)?.boolValue,
            heartRate:                  record["heartRate"] as? Double,
            heartRateVariability:       record["heartRateVariability"] as? Double,
            sleepState:                 record["sleepState"] as? String,
            isWorkingOut:               (record["isWorkingOut"] as? NSNumber)?.boolValue,
            wristTemperatureDelta:      record["wristTemperatureDelta"] as? Double,
            bloodOxygen:                record["bloodOxygen"] as? Double
        )
    }
}
