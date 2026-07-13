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
    }

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case selectFixedLocation(FileManagerFixedLocationItem.ID)
        case selectContentTab(ContentTabID)
        case closeContentTab(ContentTabID)
        case pinContentTab(ContentTabID)
        case unpinContentTab(ContentTabID)
        case openContentTab
        case duplicateContentTab(ContentTabID)
    }

    @CasePathable
    public enum Internal: CasePathable, Sendable {
        case syncContentTabSidebarItems([ContentTabProjection.ContentTabSidebarItem])
    }
}
