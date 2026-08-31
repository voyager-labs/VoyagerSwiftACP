import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

public enum FileManagerProductMetric: Equatable, Sendable {
    case contentBrowsing(
        result: ContentBrowsingResult,
        content: ContentBrowsingKind,
        identity: ContentPageNavigationInteractionIdentity,
        source: ContentBrowsingSource,
        operationID: UUID,
    )
    case contentTabAction(
        result: ContentTabActionResult,
        identity: ContentTabInteractionIdentity,
        source: ContentTabActionSource,
        operationID: UUID,
    )
    case entryAction(EntryActionProductMetric)
}

public struct EntryActionProductMetric: Equatable, Sendable {
    public let result: EntryActionResult
    public let identity: EntryInteractionIdentity
    public let source: EntryCommandSource
    public let operationID: UUID
    public let aggregate: EntryActionAggregate

    public init(
        result: EntryActionResult,
        identity: EntryInteractionIdentity,
        source: EntryCommandSource,
        operationID: UUID,
        aggregate: EntryActionAggregate,
    ) {
        self.result = result
        self.identity = identity
        self.source = source
        self.operationID = operationID
        self.aggregate = aggregate
    }
}

public extension FileManagerProductMetric {
    static func entryAction(
        result: EntryActionResult,
        identity: EntryInteractionIdentity,
        source: EntryCommandSource,
        operationID: UUID,
        aggregate: EntryActionAggregate,
    ) -> Self {
        .entryAction(.init(
            result: result,
            identity: identity,
            source: source,
            operationID: operationID,
            aggregate: aggregate,
        ))
    }
}

public enum ContentBrowsingResult: String, Equatable, Sendable {
    case success
    case empty
    case failure
    case unavailable
}

public enum ContentBrowsingFailure: Equatable, Sendable {
    case permissionDenied
    case unavailable
}

public enum ContentBrowsingKind: String, Equatable, Sendable {
    case folder
    case collection
}

public enum ContentBrowsingSource: String, Equatable, Sendable {
    case fileManagerSidebar = "file_manager_sidebar"
    case fileManagerContent = "file_manager_content"
}

public enum ContentTabActionResult: String, Equatable, Sendable {
    case success
    case failure
    case cancelled
    case unavailable
}

/// Content Tab 터미널의 유한한 정규 interaction identity.
/// action_type 단독으로는 registry interaction을 특정할 수 없으므로(예: inter-window 이동과
/// 같은 창 재배치가 모두 move로 보고될 수 있음) 생산자가 수용된 interaction의 정확한
/// identity를 전달하고 앱 어댑터가 이를 implemented voy_691_* canonical key로 사상한다.
public enum ContentTabInteractionIdentity: Equatable, Sendable {
    case openNewContentTab
    case closeContentTab
    case closeSelectedContentTabs
    case duplicateContentTab
    case duplicateSelectedContentTabs
    case restoreLastClosedTab
    case reorderContentTab
    case reorderSelectedContentTabs
    case moveContentTabToAnotherWindow
    case moveSelectedContentTabsToAnotherWindow
    case pinContentTabs
    case unpinContentTabs

    /// registry property_value_allowlist와 일치하는 action_type 값.
    public var actionType: String {
        switch self {
        case .openNewContentTab: "open"
        case .closeContentTab, .closeSelectedContentTabs: "close"
        case .duplicateContentTab, .duplicateSelectedContentTabs: "duplicate"
        case .restoreLastClosedTab: "restore"
        case .reorderContentTab, .reorderSelectedContentTabs: "reorder"
        case .moveContentTabToAnotherWindow, .moveSelectedContentTabsToAnotherWindow:
            "move"
        case .pinContentTabs: "pin"
        case .unpinContentTabs: "unpin"
        }
    }
}

public enum ContentTabActionSource: String, Equatable, Sendable {
    case contentTabBar = "content_tab_bar"
    case fileManagerContent = "file_manager_content"
    case contextMenu = "context_menu"
    case toolbar
    case keyboardShortcut = "keyboard_shortcut"
    case menuCommand = "menu_command"
    case dragAndDrop = "drag_and_drop"
}

public struct ProductContentTabActionMetricContext: Equatable, Sendable {
    public let operationID: UUID
    public let source: ContentTabActionSource

    public init(operationID: UUID, source: ContentTabActionSource) {
        self.operationID = operationID
        self.source = source
    }
}

public struct ProductContentTabCloseMetric: Equatable, Sendable {
    public let tabID: ContentTabID
    public let context: ProductContentTabActionMetricContext

    public init(tabID: ContentTabID, context: ProductContentTabActionMetricContext) {
        self.tabID = tabID
        self.context = context
    }
}

public enum EntryActionResult: String, Equatable, Sendable {
    case success
    case failure
    case cancelled
    case partial
    case unavailable
}

public struct EntryActionAggregate: Equatable, Sendable {
    public let attempted: Int
    public let succeeded: Int
    public let failed: Int
    public let cancelled: Int

    public init(attempted: Int, succeeded: Int, failed: Int) {
        self.attempted = max(0, min(attempted, 1000))
        self.succeeded = max(0, min(succeeded, 1000))
        self.failed = max(0, min(failed, 1000))
        cancelled = 0
    }

    public init(attempted: Int, succeeded: Int, failed: Int, cancelled: Int) {
        self.attempted = max(0, min(attempted, 1000))
        self.succeeded = max(0, min(succeeded, 1000))
        self.failed = max(0, min(failed, 1000))
        self.cancelled = max(0, min(cancelled, 1000))
    }
}

public struct FileManagerProductMetricsClient: Sendable {
    public var record: @Sendable (FileManagerProductMetric) -> Void
    public var makeOperationID: @Sendable () -> UUID

    public init(
        record: @escaping @Sendable (FileManagerProductMetric) -> Void,
        makeOperationID: @escaping @Sendable () -> UUID = UUID.init,
    ) {
        self.record = record
        self.makeOperationID = makeOperationID
    }
}

extension FileManagerProductMetricsClient: DependencyKey {
    public static let liveValue = Self(record: { _ in })
    public static let testValue = Self(record: { _ in }, makeOperationID: UUID.init)
    public static let previewValue = testValue
}

public extension DependencyValues {
    var fileManagerProductMetricsClient: FileManagerProductMetricsClient {
        get { self[FileManagerProductMetricsClient.self] }
        set { self[FileManagerProductMetricsClient.self] = newValue }
    }
}

public enum FileManagerProductMetricsProducer {
    public static func browsingTerminal(
        operationID: UUID,
        content: ContentBrowsingKind,
        identity: ContentPageNavigationInteractionIdentity,
        source: ContentBrowsingSource,
        entryCount: Int?,
        failure: ContentBrowsingResult?,
    ) -> FileManagerProductMetric? {
        guard let result = failure ?? entryCount.map({ $0 == 0 ? .empty : .success }) else {
            return nil
        }
        return .contentBrowsing(
            result: result,
            content: content,
            identity: identity,
            source: source,
            operationID: operationID,
        )
    }

    public static func browsingFailure(_ failure: ContentBrowsingFailure) -> ContentBrowsingResult {
        switch failure {
        case .permissionDenied: .failure
        case .unavailable: .unavailable
        }
    }

    public static func contentTabTerminal(
        operationID: UUID,
        identity: ContentTabInteractionIdentity,
        source: ContentTabActionSource,
        result: ContentTabActionResult,
    ) -> FileManagerProductMetric {
        .contentTabAction(result: result, identity: identity, source: source, operationID: operationID)
    }

    public static func entryTerminal(
        operationID: UUID,
        identity: EntryInteractionIdentity,
        source: EntryCommandSource,
        result: EntryActionResult,
        aggregate: EntryActionAggregate,
    ) -> FileManagerProductMetric {
        .entryAction(
            result: result,
            identity: identity,
            source: source,
            operationID: operationID,
            aggregate: aggregate,
        )
    }

    static func entryTerminal(for record: EntryActionRecord) -> FileManagerProductMetric? {
        guard let command = record.command else { return nil }
        let succeeded = record.succeededCount
        let failed = record.failedCount
        let cancelled = record.cancelledCount
        return entryTerminal(
            operationID: command.id,
            identity: command.interaction,
            source: command.source,
            result: entryResult(succeeded: succeeded, failed: failed, cancelled: cancelled),
            aggregate: .init(
                attempted: record.attemptedCount,
                succeeded: succeeded,
                failed: failed,
                cancelled: cancelled,
            ),
        )
    }

    private static func entryResult(
        succeeded: Int,
        failed: Int,
        cancelled: Int,
    ) -> EntryActionResult {
        if succeeded > 0 { return failed + cancelled > 0 ? .partial : .success }
        if failed > 0 { return .failure }
        return cancelled > 0 ? .cancelled : .success
    }
}
