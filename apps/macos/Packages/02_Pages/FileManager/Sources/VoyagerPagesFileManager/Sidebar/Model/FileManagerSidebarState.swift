import ComposableArchitecture
import Foundation
import VoyagerEntitiesTag

@ObservableState
public struct FileManagerSidebarState: Equatable {
    public var sidebarVisible: Bool = true
    var sidebarWidth: CGFloat = 220
    var selectedSidebarItem: String?
    var favorites: [SidebarItems.FavoriteItem] = []
    var locations: [SidebarItems.LocationItem] = []
    var tags: [Tag] = []
    var isFavoritesCollapsed: Bool = false
    var isLocationsCollapsed: Bool = false
    var isTagsCollapsed: Bool = false
    var pendingSidebarSelectionRestore: String?
    var contextMenuTargetId: String?
    var contextMenuTargetWasSelected: Bool = false
}
