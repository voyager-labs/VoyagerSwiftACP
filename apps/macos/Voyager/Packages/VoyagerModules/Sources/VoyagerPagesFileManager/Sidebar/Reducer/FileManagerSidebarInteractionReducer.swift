import AppKit
import ComposableArchitecture

@Reducer
struct FileManagerSidebarInteractionReducer {
    enum CancelID {
        static let systemNotifications = "FileManagerSidebarInteraction.systemNotifications"
    }

    @Dependency(\.notificationCenterClient) private var notificationCenterClient

    var body: some Reducer<FileManagerSidebarState, FileManagerSidebarAction> {
        Reduce { state, action in
            switch action {
            case let .view(.setContextMenuTarget(id, wasSelected)):
                state.contextMenuTargetId = id
                state.contextMenuTargetWasSelected = wasSelected
                return .none

            case .internal(.restoreSidebarSelection):
                if let restoreSelection = state.pendingSidebarSelectionRestore {
                    state.selectedSidebarItem = restoreSelection
                }
                state.pendingSidebarSelectionRestore = nil
                return .none

            case .internal(.startObservingSystemNotifications):
                let notificationCenterClient = notificationCenterClient
                return .run { send in
                    for await _ in await notificationCenterClient.notifications(
                        NSMenu.didEndTrackingNotification,
                        nil,
                    ) {
                        await send(.internal(.systemMenuDidEndTracking))
                    }
                }
                .cancellable(id: CancelID.systemNotifications, cancelInFlight: true)

            case .internal(.stopObservingSystemNotifications):
                return .cancel(id: CancelID.systemNotifications)

            case .internal(.systemMenuDidEndTracking):
                state.contextMenuTargetId = nil
                state.contextMenuTargetWasSelected = false
                return .none

            default:
                return .none
            }
        }
    }
}
