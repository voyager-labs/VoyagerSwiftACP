import ComposableArchitecture
import Foundation

public enum FileManagerProductMetric: Equatable, Sendable {
    case contentBrowsing(
        result: ContentBrowsingResult,
        content: ContentBrowsingKind,
        source: ContentBrowsingSource,
        operationID: UUID,
    )
    case contentTabAction(
        result: ContentTabActionResult,
        identity: ContentTabInteractionIdentity,
        source: ContentTabActionSource,
        operationID: UUID,
    )
    case entryAction(
        result: EntryActionResult,
        action: EntryActionMetricKind,
        source: EntryActionMetricSource,
        operationID: UUID,
        aggregate: EntryActionAggregate,
    )
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
        case .closeContentTab: "close"
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

public enum EntryActionResult: String, Equatable, Sendable {
    case success
    case failure
    case cancelled
    case partial
    case unavailable
}

public enum EntryActionMetricKind: String, Equatable, Sendable {
    case open
    case quickLook = "quick_look"
    case share
    case revealInFinder = "reveal_in_finder"
    case copyPath = "copy_path"
    case create
    case rename
    case move
    case copy
    case trash
    case restore
    case tag
}

public enum EntryActionMetricSource: String, Equatable, Sendable {
    case fileManagerContent = "file_manager_content"
    case contextMenu = "context_menu"
    case toolbar
    case keyboardShortcut = "keyboard_shortcut"
    case menuCommand = "menu_command"
    case dragAndDrop = "drag_and_drop"
}

public struct EntryActionAggregate: Equatable, Sendable {
    public let attempted: Int
    public let succeeded: Int
    public let failed: Int

    public init(attempted: Int, succeeded: Int, failed: Int) {
        self.attempted = max(0, min(attempted, 1000))
        self.succeeded = max(0, min(succeeded, 1000))
        self.failed = max(0, min(failed, 1000))
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
        action: EntryActionMetricKind,
        source: EntryActionMetricSource,
        result: EntryActionResult,
        aggregate: EntryActionAggregate,
    ) -> FileManagerProductMetric {
        .entryAction(
            result: result,
            action: action,
            source: source,
            operationID: operationID,
            aggregate: aggregate,
        )
    }
}
