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
    }

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case selectContentTab(ContentTabID)
        case closeContentTab(ContentTabID)
        case pinContentTab(ContentTabID)
        case unpinContentTab(ContentTabID)
        case openContentTab
    }

    @CasePathable
    public enum Internal: CasePathable, Sendable {
        case syncContentTabSidebarItems([ContentTabProjection.ContentTabSidebarItem])
    }
}
