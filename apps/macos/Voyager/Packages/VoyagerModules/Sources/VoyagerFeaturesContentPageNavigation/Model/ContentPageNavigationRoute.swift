import Foundation
import VoyagerEntitiesEntry
import VoyagerWidgetsEntryViewLayout

public enum ContentPageNavigationRoute: Equatable, Sendable {
    case folder(String)
    case recents
    case tags(String)
    case computer
    case collection(ContentPageCollectionNavigation)

    public var isCollection: Bool {
        if case .collection = self {
            return true
        }
        return false
    }

    public static func fromPath(_ path: String, computerName: String) -> Self {
        switch path {
        case "Recents":
            .recents
        default:
            if path == computerName {
                .computer
            } else if path.hasPrefix("/") {
                .folder(path)
            } else {
                .tags(path)
            }
        }
    }
}

public enum ContentPageCollectionKind: Equatable, Sendable {
    case temporary
    case file(url: URL, name: String)
}

public struct ContentPageCollectionNavigation: Equatable, Sendable {
    public var kind: ContentPageCollectionKind
    public var context: CollectionContext
    public var sortKey: VoyagerWidgetsEntryViewLayout.SortKey
    public var sortOrder: VoyagerWidgetsEntryViewLayout.SortOrder
    public var viewLayout: EntryViewLayoutState.Mode

    public init(
        kind: ContentPageCollectionKind,
        context: CollectionContext,
        sortKey: VoyagerWidgetsEntryViewLayout.SortKey,
        sortOrder: VoyagerWidgetsEntryViewLayout.SortOrder,
        viewLayout: EntryViewLayoutState.Mode,
    ) {
        self.kind = kind
        self.context = context
        self.sortKey = sortKey
        self.sortOrder = sortOrder
        self.viewLayout = viewLayout
    }
}
