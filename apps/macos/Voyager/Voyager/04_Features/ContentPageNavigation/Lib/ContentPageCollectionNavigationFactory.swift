import Foundation
import VoyagerEntitiesCollection

enum ContentPageCollectionNavigationFactory {
    static func makeCollectionNavigation(
        _ payload: CollectionNavigationPresentationPayload,
        sortKey: SortKey,
        sortOrder: SortOrder,
        viewLayout: EntryViewLayoutState.Mode,
    ) -> ContentPageCollectionNavigation {
        let kind: ContentPageCollectionKind = switch payload.kind {
        case .temporary:
            .temporary
        case let .file(url, name):
            .file(url: url, name: name)
        }

        return ContentPageCollectionNavigation(
            kind: kind,
            context: payload.context,
            sortKey: sortKey,
            sortOrder: sortOrder,
            viewLayout: viewLayout,
            compatibility: payload.compatibility,
        )
    }
}
