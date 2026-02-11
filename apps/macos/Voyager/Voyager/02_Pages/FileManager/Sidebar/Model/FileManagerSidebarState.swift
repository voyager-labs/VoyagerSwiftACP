import ComposableArchitecture
import Foundation

@ObservableState
struct FileManagerSidebarState: Equatable {
    var sidebarVisible: Bool = true
    var sidebarWidth: CGFloat = 220
    var selectedSidebarItem: String?
    var favorites: [SidebarItems.FavoriteItem] = []
    var locations: [SidebarItems.LocationItem] = []
    var tags: [SidebarItems.TagItem] = []
    var isFavoritesCollapsed: Bool = false
    var isLocationsCollapsed: Bool = false
    var isTagsCollapsed: Bool = false
    var pendingSidebarSelectionRestore: String?
}
