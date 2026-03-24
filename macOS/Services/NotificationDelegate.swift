import Foundation
import UserNotifications
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "NotificationDelegate")

/// Handles notification action responses (Undo, OK, View Details).
/// Must be set as the UNUserNotificationCenter delegate at startup.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    private let actionLog: ActionLog
    private let homeKit: HomeKitService

    init(actionLog: ActionLog, homeKit: HomeKitService) {
        self.actionLog = actionLog
        self.homeKit = homeKit
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let notificationID = response.notification.request.identifier

        // Call completionHandler synchronously to satisfy the delegate contract,
        // then perform async work in a detached task to avoid Swift 6 sendability issues.
        completionHandler()

        Task { @MainActor in
            switch actionIdentifier {
            case AutomationScheduler.undoActionID:
                await self.handleUndo(notificationID: notificationID)

            case AutomationScheduler.okActionID,
                 UNNotificationDefaultActionIdentifier:
                break

            case "VIEW_ALERT":
                logger.info("User viewed emergency alert")

            case UNNotificationDismissActionIdentifier:
                break

            default:
                logger.debug("Unhandled notification action: \(actionIdentifier)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func handleUndo(notificationID: String) async {
        guard let entry = actionLog.entry(forNotificationID: notificationID) else {
            logger.warning("No ActionLog entry found for notification \(notificationID)")
            return
        }

        guard entry.timestamp.timeIntervalSinceNow > -60 else {
            logger.info("Undo expired — entry is older than 60 seconds")
            return
        }

        guard !entry.previousValues.isEmpty else {
            logger.warning("No previous values to restore for entry \(entry.id)")
            return
        }

        logger.info("Undoing \(entry.actions.count) action(s) from '\(entry.summary)'")

        for action in entry.actions {
            let key = "\(action.accessoryID).\(action.characteristic)"
            guard let previousValue = entry.previousValues[key] else { continue }

            let reverseAction = DeviceAction(
                accessoryID: action.accessoryID,
                accessoryName: action.accessoryName,
                characteristic: action.characteristic,
                value: previousValue,
                reason: "Undo: restoring previous value"
            )

            do {
                try await homeKit.execute(reverseAction)
            } catch {
                logger.error("Failed to undo \(action.accessoryName).\(action.characteristic): \(error.localizedDescription)")
            }
        }

        logger.info("Undo complete for '\(entry.summary)'")
    }
}
