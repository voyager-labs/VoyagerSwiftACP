import ComposableArchitecture
import Foundation

@ObservableState
public struct FileManagerSidebarState: Equatable {
    public var sidebarVisible: Bool = true
    var sidebarWidth: CGFloat = 220
    var contentTabSidebarItems: [ContentTabProjection.ContentTabSidebarItem] = ContentTabProjection
        .sidebarItems(from: .withHomeTab())
}
