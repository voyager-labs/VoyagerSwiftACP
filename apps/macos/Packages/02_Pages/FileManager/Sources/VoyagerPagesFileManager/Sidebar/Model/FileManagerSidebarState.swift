import ComposableArchitecture
import Foundation

@ObservableState
public struct FileManagerSidebarState: Equatable {
    public var sidebarVisible: Bool = true
    var sidebarWidth: CGFloat = 220
    var allFixedLocationItems: [FileManagerFixedLocationItem] = []
    var fixedLocationItems: [FileManagerFixedLocationItem] = []
    var hiddenFixedLocationItemIDs: Set<FileManagerFixedLocationItem.ID> = []
    var shouldShowFixedLocationSection: Bool {
        !fixedLocationItems.isEmpty
    }

    var contentTabSidebarItems: [ContentTabProjection.ContentTabSidebarItem] = ContentTabProjection
        .sidebarItems(from: .withHomeTab())

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

    mutating func setFixedLocationVisibility(id: FileManagerFixedLocationItem.ID, isVisible: Bool) {
        if isVisible {
            hiddenFixedLocationItemIDs.remove(id)
        } else {
            hiddenFixedLocationItemIDs.insert(id)
        }
        applyFixedLocationVisibility()
    }

    mutating func setAllFixedLocationVisibility(_ isVisible: Bool) {
        hiddenFixedLocationItemIDs = isVisible ? [] : Set(allFixedLocationItems.map(\.id))
        applyFixedLocationVisibility()
    }

    func isFixedLocationVisible(_ id: FileManagerFixedLocationItem.ID) -> Bool {
        !hiddenFixedLocationItemIDs.contains(id)
    }

    private mutating func applyFixedLocationVisibility() {
        fixedLocationItems = allFixedLocationItems.filter { !hiddenFixedLocationItemIDs.contains($0.id) }
    }
}
