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
        case dismissTopNavigationPresentation
        case duplicateContentTab(ContentTabID)
        case duplicateSelectedContentTabs
        case closeContentTab(ContentTabID)
        case closeContentTabFromTrailingControl(ContentTabID)
        case closeSelectedContentTabs
        case pinContentTab(ContentTabID)
        case unpinContentTab(ContentTabID)
        case setSelectedContentTabsPinned(target: SelectedContentTabPinMutationTargetState)
        case entryDropRequested(FileManagerSidebarEntryDropRequest)
        case fileManagerTopNavigationReorderRequested(
            sourceID: FileManagerTopNavigationItemID,
            anchorID: FileManagerTopNavigationItemID,
            placement: FileManagerTopNavigationReorderPlacement,
        )
        case contentTabDomainTransitionRequested(ContentTabDomainTransitionRequest)
        case moveContentTab(tabID: ContentTabID, targetWindowID: UUID)
        case moveSelectedContentTabs(
            initiatingTabID: ContentTabID,
            orderedTabIDs: [ContentTabID],
            targetWindowID: UUID,
        )
        case moveContentTabs(
            payload: ContentTabDragPayload,
            targetWindowID: UUID,
            targetDomain: ContentTabDomain? = nil,
            placement: ContentTabPlacement? = nil,
        )
        case prepareContentTabDrag(initiatingTabID: ContentTabID, selectedTabIDs: Set<ContentTabID>)
        case beginContentTabDrag(ContentTabDragPayload)
        case contentTabDragTerminal(operationID: UUID)
        case teardownContentTabDragSource
        case receiveContentTabDrag(ContentTabDragPayload)
        /// 외부 창 explicit same/opposite-domain 경계 drop이 transport한 정확한 target domain/placement 의도.
        /// preserve-domain transfer(`receiveContentTabDrag`)과 동일한 canonical `ContentTabMoveRequest` lifecycle으로 합쳐진다.
        case receiveContentTabExplicitDomainDrag(
            payload: ContentTabDragPayload,
            targetDomain: ContentTabDomain,
            placement: ContentTabPlacement,
        )
    }

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case selectFixedLocation(FileManagerFixedLocationItem.ID)
        case selectContentTab(ContentTabID)
        case returnContentTabToPinnedLocation(ContentTabID)
        case toggleContentTabSelection(ContentTabID)
        case selectContentTabRange(to: ContentTabID)
        case collapseContentTabSelectionToActive
        case dismissTopNavigationPresentation
        case closeContentTab(ContentTabID)
        case closeContentTabFromTrailingControl(ContentTabID)
        case closeSelectedContentTabs
        case pinContentTab(ContentTabID)
        case unpinContentTab(ContentTabID)
        case setSelectedContentTabsPinned(target: SelectedContentTabPinMutationTargetState)
        case openContentTab
        case duplicateContentTab(ContentTabID)
        case duplicateSelectedContentTabs
        case entryDropRequested(FileManagerSidebarEntryDropRequest)
        case fileManagerTopNavigationReorderRequested(
            sourceID: FileManagerTopNavigationItemID,
            anchorID: FileManagerTopNavigationItemID,
            placement: FileManagerTopNavigationReorderPlacement,
        )
        case contentTabDomainTransitionRequested(ContentTabDomainTransitionRequest)
        case requestContentTabMove(ContentTabMoveRequest)
        case receiveContentTabDrag(ContentTabDragPayload)
        /// 외부 창 explicit domain 경계 drop 의도를 window 계층으로 그대로 전달한다.
        /// window manager가 source 창의 `moveContentTabs`로 route해 canonical request를 구성한다.
        case receiveContentTabExplicitDomainDrag(
            payload: ContentTabDragPayload,
            targetDomain: ContentTabDomain,
            placement: ContentTabPlacement,
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
