import ComposableArchitecture
import Foundation
import VoyagerEntitiesTag

@CasePathable
public enum FileManagerSidebarAction: CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)

    @CasePathable
    public enum View: CasePathable, Sendable {
        case setSidebarVisible(Bool)
        case toggleFavoritesSection
        case toggleLocationsSection
        case toggleTagsSection
        case setSidebarWidth(CGFloat)
        case setContextMenuTarget(id: String?, wasSelected: Bool)
    }

    // NSItemProvider가 Sendable을 준수하지 않아 @unchecked 필요. 드래그앤드롭은 @MainActor에서만 수행됨.
    @CasePathable
    public enum Delegate: CasePathable, @unchecked Sendable {
        case openFavorite(SidebarItems.FavoriteItem)
        case openLocation(SidebarItems.LocationItem)
        case showTag(String)
        case showRecents
        case showComputer
        case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
        case dropItemsToTag(providers: [NSItemProvider], tagName: String)
    }

    // insertFavoriteFromDrop의 NSItemProvider 때문에 @unchecked 필요. 드래그앤드롭은 @MainActor에서만 수행됨.
    @CasePathable
    public enum Internal: CasePathable, @unchecked Sendable {
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
