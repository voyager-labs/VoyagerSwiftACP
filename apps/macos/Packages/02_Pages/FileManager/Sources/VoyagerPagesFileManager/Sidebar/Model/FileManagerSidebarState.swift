import ComposableArchitecture
import Foundation

@ObservableState
public struct FileManagerSidebarState: Equatable {
    public var sidebarVisible: Bool = true
    var sidebarWidth: CGFloat = 220
    var allFixedLocationItems: [FileManagerFixedLocationItem] = []
    var fixedLocationItems: [FileManagerFixedLocationItem] = []
    var hiddenFixedLocationItemIDs: Set<FileManagerFixedLocationItem.ID> = []
    private var orderedTopNavigationItems: [FileManagerSidebarTopNavigationItem] = []
    var topNavigationItems: [FileManagerSidebarTopNavigationItem] = []
    var unpinnedContentTabItems: [ContentTabProjection.ContentTabSidebarItem] = ContentTabProjection
        .sidebarItems(from: .withHomeTab())
    var contentTabSidebarItems: [ContentTabProjection.ContentTabSidebarItem] = ContentTabProjection
        .sidebarItems(from: .withHomeTab())
    var topNavigationArrangementPresentation: FileManagerTopNavigationArrangementPresentation?
    public var currentWindowID: UUID?
    public var contentTabMoveTargets: [ContentTabMoveTarget] = []
    public var pendingContentTabMoveRequest: ContentTabMoveRequest?

    var showsTopNavigationDivider: Bool {
        !topNavigationItems.isEmpty
    }

    var fixedLocationVisibilityMenuItems: [FileManagerFixedLocationItem] {
        let discoveredLocationIDs = Set(allFixedLocationItems.map(\.id))

        return orderedTopNavigationItems.compactMap { item in
            guard case let .location(location) = item,
                  discoveredLocationIDs.contains(location.id)
            else {
                return nil
            }
            return location
        }
    }

    mutating func setFixedLocationItems(
        _ items: [FileManagerFixedLocationItem],
        hiddenIDs: Set<FileManagerFixedLocationItem.ID>? = nil,
    ) {
        if let hiddenIDs {
            hiddenFixedLocationItemIDs = hiddenIDs
        }
        allFixedLocationItems = items
        applyFixedLocationVisibility()
    }

    mutating func setOrderedTopNavigationItems(_ items: [FileManagerSidebarTopNavigationItem]) {
        orderedTopNavigationItems = items
        applyTopNavigationVisibility()
    }

    mutating func setFixedLocationVisibility(id: FileManagerFixedLocationItem.ID, isVisible: Bool) {
        if isVisible {
            hiddenFixedLocationItemIDs.remove(id)
        } else {
            hiddenFixedLocationItemIDs.insert(id)
        }
        applyFixedLocationVisibility()
        applyTopNavigationVisibility()
    }

    mutating func setAllFixedLocationVisibility(_ isVisible: Bool) {
        hiddenFixedLocationItemIDs = isVisible ? [] : Set(allFixedLocationItems.map(\.id))
        applyFixedLocationVisibility()
        applyTopNavigationVisibility()
    }

    func isFixedLocationVisible(_ id: FileManagerFixedLocationItem.ID) -> Bool {
        !hiddenFixedLocationItemIDs.contains(id)
    }

    private mutating func applyFixedLocationVisibility() {
        fixedLocationItems = allFixedLocationItems.filter { !hiddenFixedLocationItemIDs.contains($0.id) }
    }

    private mutating func applyTopNavigationVisibility() {
        topNavigationItems = orderedTopNavigationItems.filter { item in
            guard case let .location(location) = item else { return true }
            return !hiddenFixedLocationItemIDs.contains(location.id)
        }
    }
}
