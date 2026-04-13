import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

@ObservableState
public struct FileManagerSidebarState: Equatable {
    public var sidebarVisible: Bool = true
    public var sidebarWidth: CGFloat = 220
    public var selectedSidebarItem: String?
    public var favorites: [SidebarItems.FavoriteItem] = []
    public var locations: [SidebarItems.LocationItem] = []
    public var tags: [Tag] = []
    public var isFavoritesCollapsed: Bool = false
    public var isLocationsCollapsed: Bool = false
    public var isTagsCollapsed: Bool = false
    public var pendingSidebarSelectionRestore: String?
    public var contextMenuTargetId: String?
    public var contextMenuTargetWasSelected: Bool = false
}
