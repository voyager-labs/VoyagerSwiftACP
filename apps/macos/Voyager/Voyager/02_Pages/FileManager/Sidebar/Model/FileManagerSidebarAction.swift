import ComposableArchitecture
import Foundation

@CasePathable
enum FileManagerSidebarAction: CasePathable {
    case setSidebarVisible(Bool)
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
    case toggleFavoritesSection
    case toggleLocationsSection
    case toggleTagsSection
    case setSidebarWidth(CGFloat)
    case openFavorite(SidebarItems.FavoriteItem)
    case openLocation(SidebarItems.LocationItem)
    case showTag(Tag)
    case showRecents
    case showComputer
    case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
    case dropItemsToTag(providers: [NSItemProvider], tagName: String)

    case startObservingSystemNotifications
    case stopObservingSystemNotifications
    case systemMenuDidEndTracking
    case setContextMenuTarget(id: String?, wasSelected: Bool)
}
