import ComposableArchitecture
import Foundation
import VoyagerEntitiesTag

@CasePathable
enum FileManagerSidebarAction: CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)

    @CasePathable
    enum View: CasePathable, Sendable {
        case setSidebarVisible(Bool)
        case toggleFavoritesSection
        case toggleLocationsSection
        case toggleTagsSection
        case setSidebarWidth(CGFloat)
        case setContextMenuTarget(id: String?, wasSelected: Bool)
    }

    @CasePathable
    enum Delegate: CasePathable, Sendable {
        case openFavorite(SidebarItems.FavoriteItem)
        case openLocation(SidebarItems.LocationItem)
        case showTag(String)
        case showRecents
        case showComputer
        case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
        case dropItemsToTag(providers: [NSItemProvider], tagName: String)
    }

    @CasePathable
    enum Internal: CasePathable, Sendable {
        case restoreSidebarSelection
        case loadFavorites
        case favoritesLoaded([SidebarItems.FavoriteItem])
        case insertFavoriteFromDrop(providers: [NSItemProvider], at: Int)
        case insertFavorite(url: URL, at: Int)
        case removeFavorite(SidebarItems.FavoriteItem)
        case reorderFavorites(from: IndexSet, to: Int)
        case loadLocations
        case locationsLoaded([SidebarItems.LocationItem])
        case loadTags
        case tagsLoaded([Tag])
        case startObservingSystemNotifications
        case stopObservingSystemNotifications
        case systemMenuDidEndTracking
    }
}
