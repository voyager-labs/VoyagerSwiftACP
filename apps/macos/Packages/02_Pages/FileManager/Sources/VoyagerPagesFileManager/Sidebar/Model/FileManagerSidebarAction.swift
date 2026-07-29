@preconcurrency import AppKit
import ComposableArchitecture
import Foundation

@CasePathable
public enum FileManagerSidebarAction: CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)

    @CasePathable
    public enum View: CasePathable, Sendable {
        case setSidebarVisible(Bool)
        case setSidebarWidth(CGFloat)
        case setFixedLocationVisibility(FileManagerFixedLocationItem.ID, Bool)
        case setAllFixedLocationVisibility(Bool)
        case toggleContentTabSelection(ContentTabID)
        case selectContentTabRange(to: ContentTabID)
        case collapseContentTabSelectionToActive
        case entryDropRequested(FileManagerSidebarEntryDropRequest)
        case contentTabReorderRequested(
            sourceID: ContentTabID,
            targetID: ContentTabID,
            placement: ContentTabReorderPlacement,
        )
    }

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case selectFixedLocation(FileManagerFixedLocationItem.ID)
        case selectContentTab(ContentTabID)
        case toggleContentTabSelection(ContentTabID)
        case selectContentTabRange(to: ContentTabID)
        case collapseContentTabSelectionToActive
        case closeContentTab(ContentTabID)
        case closeSelectedContentTabs
        case pinContentTab(ContentTabID)
        case unpinContentTab(ContentTabID)
        case setSelectedContentTabsPinned(target: SelectedContentTabPinMutationTargetState)
        case openContentTab
        case duplicateContentTab(ContentTabID)
        case duplicateSelectedContentTabs
        case entryDropRequested(FileManagerSidebarEntryDropRequest)
        case contentTabReorderRequested(
            sourceID: ContentTabID,
            targetID: ContentTabID,
            placement: ContentTabReorderPlacement,
        )
    }

    @CasePathable
    public enum Internal: CasePathable, Sendable {
        case syncContentTabSidebarItems([ContentTabProjection.ContentTabSidebarItem])
    }
}

public enum FileManagerSidebarEntryDropTarget: Equatable, Sendable {
    case fixedLocation(String)
    case contentTab(ContentTabID)
}

public struct FileManagerSidebarEntryDropRequest: @unchecked Sendable {
    public let target: FileManagerSidebarEntryDropTarget
    public let providers: [NSItemProvider]
    public let isOptionDrag: Bool

    public init(
        target: FileManagerSidebarEntryDropTarget,
        providers: [NSItemProvider],
        isOptionDrag: Bool,
    ) {
        self.target = target
        self.providers = providers
        self.isOptionDrag = isOptionDrag
    }
}
