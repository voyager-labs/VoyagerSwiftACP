import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

enum ContentPageCollectionNavigationFactory {
    static func makeCollectionNavigation(
        _ payload: CollectionNavigationPresentationPayload,
        sortKey: VoyagerShared.SortKey,
        sortOrder: VoyagerShared.SortOrder,
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
            viewLayout: contentPageNavigationViewLayout(from: viewLayout),
            compatibility: payload.compatibility,
        )
    }
}

func contentPageNavigationViewLayout(
    from mode: EntryViewLayoutState.Mode,
) -> ContentPageNavigationViewLayout {
    switch mode {
    case .list:
        .list
    case .grid:
        .grid
    }
}
