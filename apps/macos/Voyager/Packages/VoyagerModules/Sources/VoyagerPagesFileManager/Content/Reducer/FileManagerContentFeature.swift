import AppKit
import ComposableArchitecture
import Foundation
import VoyagerShared

import VoyagerEntitiesEntry
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

@Reducer
public struct FileManagerContentFeature {
    public typealias State = FileManagerContentState
    public typealias Action = FileManagerContentAction

    private let systemNotificationsCancellationID = "FileManagerContent.systemNotifications"

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.notificationCenterClient)
    private var notificationCenterClient

    public var body: some Reducer<State, Action> {
        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
        }

        FileManagerContentEntryOperationsBridgeReducer()
        FileManagerContentNavigationBridgeReducer()
        FileManagerContentComposerReducer()
        FileManagerContentKeyCommandReducer()

        Reduce { state, action in
            switch action {
            case .view(.selectAllEntries):
                return .send(.entryViewLayout(.internal(.applySelectAll(
                    orderedItemIds: state.entryViewLayout.entries.map(\.id),
                ))))

            case .delegate(.openPathInNewWindow),
                 .delegate(.openPathInNewTab),
                 .delegate(.closeWindow):
                return .none

            case let .view(.changeLayout(layout)):
                let currentMode = state.entryViewLayout.mode
                let isModeChanging = currentMode != layout
                let hasActiveRename = state.entryViewLayout.entryOperations.renamingItemId != nil

                state.entryViewLayout.mode = layout
                state.syncComposerCollectionState()
                userDefaultsClient.setString(layout.rawValue, SettingsKeys.viewLayout)

                if isModeChanging, hasActiveRename {
                    return .send(.entryViewLayout(.entryOperations(.edit(.cancelRename))))
                }
                return .none

            case let .internal(.saveScrollOffset(offset, forPath: path)):
                state.navigation.scrollPositions[path] = offset
                if path == state.navigation.currentPath {
                    state.entryViewLayout.savedScrollOffset = offset
                }
                return .none

            case .internal(.startObservingSystemNotifications):
                let capturedNotificationCenter = notificationCenterClient
                return .run { send in
                    for await _ in await capturedNotificationCenter.notifications(
                        NSApplication.didBecomeActiveNotification,
                        nil,
                    ) {
                        await send(.internal(.systemAppDidBecomeActive))
                    }
                }
                .cancellable(id: systemNotificationsCancellationID, cancelInFlight: true)

            case .internal(.stopObservingSystemNotifications):
                return .cancel(id: systemNotificationsCancellationID)

            default:
                return .none
            }
        }
    }
}
