import ComposableArchitecture
import Foundation

public enum DAUNavigationKind: String, Sendable {
    case folder
    case collection
}

public enum DAUEntryKind: String, Sendable {
    case file
    case directory
    case collection
    case mixed
}

public enum DAUEntryActionKind: String, Sendable {
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

public struct MetricsClient: Sendable {
    public var logMetric: @Sendable (_ name: String, _ value: Double, _ tags: [String: String]?) -> Void
    public var logDAUNavigation: @Sendable (DAUNavigationKind) -> Void
    public var logDAUEntryAction: @Sendable (DAUEntryActionKind, DAUEntryKind) -> Void

    public nonisolated init(
        logMetric: @escaping @Sendable (_ name: String, _ value: Double, _ tags: [String: String]?) -> Void,
        logDAUNavigation: @escaping @Sendable (DAUNavigationKind) -> Void,
        logDAUEntryAction: @escaping @Sendable (DAUEntryActionKind, DAUEntryKind) -> Void
    ) {
        self.logMetric = logMetric
        self.logDAUNavigation = logDAUNavigation
        self.logDAUEntryAction = logDAUEntryAction
    }
}

extension MetricsClient: DependencyKey {
    public nonisolated static var liveValue: MetricsClient {
        .init(
            logMetric: { _, _, _ in },
            logDAUNavigation: { _ in },
            logDAUEntryAction: { _, _ in }
        )
    }

    public nonisolated static var testValue: MetricsClient {
        .init(
            logMetric: { _, _, _ in },
            logDAUNavigation: { _ in },
            logDAUEntryAction: { _, _ in }
        )
    }

    public nonisolated static var previewValue: MetricsClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var metricsClient: MetricsClient {
        get { self[MetricsClient.self] }
        set { self[MetricsClient.self] = newValue }
    }
}
