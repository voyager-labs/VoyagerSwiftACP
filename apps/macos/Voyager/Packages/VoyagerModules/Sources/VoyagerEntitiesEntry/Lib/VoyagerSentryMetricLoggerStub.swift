import Foundation

public enum DAUNavigationKind: String, Sendable {
    case folder
    case collection
}

public enum DAUEntryActionKind: String, Sendable {
    case openDefault
    case openWithApp
    case setDefaultApp
    case quickLook
    case getInfo
    case share
    case performService
    case revealInFinder
    case createFolder
    case createAlias
    case copy
    case paste
    case move
    case duplicate
    case rename
    case moveToTrash
    case deleteImmediately
    case putBack
    case emptyTrash
    case compress
    case extract
    case setTags
}

public enum DAUEntryKind: String, Sendable {
    case file
    case directory
    case collection
    case mixed
}

public enum SentryMetricLevel: String, Sendable {
    case info
    case warn
    case error
}

public enum VoyagerSentryMetricLogger {
    public static func logMetric(
        _: String,
        value _: Double,
        tags _: [String: String] = [:],
        level _: SentryMetricLevel = .info,
    ) {
        // Stub implementation - Sentry not available in package target
    }

    public static func logDAUNavigation(kind _: DAUNavigationKind) {
        // Stub implementation - Sentry not available in package target
    }

    public static func logDAUEntryAction(actionKind _: DAUEntryActionKind, entryKind _: DAUEntryKind) {
        // Stub implementation - Sentry not available in package target
    }
}
