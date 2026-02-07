import Foundation
import Sentry

enum MetricLogLevel {
    case trace
    case debug
    case info
    case warn
    case error
    case fatal
}

enum DAUNavigationKind: String {
    case folder
    case collection
}

enum DAUEntryKind: String {
    case file
    case directory
    case collection
    case mixed
}

enum DAUEntryActionKind: String {
    case openDefault = "open_default"
    case openWithApp = "open_with_app"
    case quickLook = "quick_look"
    case getInfo = "get_info"
    case share
    case performService = "perform_service"
    case revealInFinder = "reveal_in_finder"
    case setDefaultApp = "set_default_app"
    case createFolder = "create_folder"
    case createAlias = "create_alias"
    case copy
    case paste
    case rename
    case move
    case duplicate
    case moveToTrash = "move_to_trash"
    case deleteImmediately = "delete_immediately"
    case putBack = "put_back"
    case emptyTrash = "empty_trash"
    case compress
    case extract
    case setTags = "set_tags"
}

enum VoyagerSentryMetricLogger {
    private static let userIdStore = UserIdStore()

    static func setUserId(_ userId: String?) {
        userIdStore.set(userId)
    }

    static func logMetric(
        _ name: String,
        value: Double,
        tags: [String: String]? = nil,
        level: MetricLogLevel = .info,
    ) {
        var attributes: [String: Any] = [
            "metric.name": name,
            "metric.value": value,
        ]
        if let userId = userIdStore.get() {
            attributes["metric.user_id"] = userId
        }
        if let tags {
            for (key, tagValue) in tags {
                attributes["metric.tag.\(key)"] = tagValue
            }
        }
        switch level {
        case .trace:
            SentrySDK.logger.trace("metric", attributes: attributes)
        case .debug:
            SentrySDK.logger.debug("metric", attributes: attributes)
        case .info:
            SentrySDK.logger.info("metric", attributes: attributes)
        case .warn:
            SentrySDK.logger.warn("metric", attributes: attributes)
        case .error:
            SentrySDK.logger.error("metric", attributes: attributes)
        case .fatal:
            SentrySDK.logger.fatal("metric", attributes: attributes)
        }
    }

    static func logDAUNavigation(kind: DAUNavigationKind) {
        captureDAUEvent(
            name: "dau.navigation",
            tags: ["nav.kind": kind.rawValue],
        )
    }

    static func logDAUEntryAction(
        actionKind: DAUEntryActionKind,
        entryKind: DAUEntryKind,
    ) {
        captureDAUEvent(
            name: "dau.entry_action",
            tags: [
                "action.kind": actionKind.rawValue,
                "entry.kind": entryKind.rawValue,
            ],
        )
    }

    private static func captureDAUEvent(
        name: String,
        tags: [String: String],
    ) {
        let event = Event(level: .info)
        event.message = SentryMessage(formatted: name)
        event.tags = tags
        SentrySDK.capture(event: event)
    }
}

private final class UserIdStore: @unchecked Sendable {
    private nonisolated(unsafe) let lock = NSLock()
    private nonisolated(unsafe) var value: String?

    nonisolated func set(_ value: String?) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    nonisolated func get() -> String? {
        lock.lock()
        let current = value
        lock.unlock()
        return current
    }
}
