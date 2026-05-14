import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

@Reducer
struct FileManagerContentFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.fileManagerClient)
    private var fileManagerClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .collection(.saveCompleted(result)) = action else {
                return .none
            }
            return handleCollectionSaveCompleted(result: result, state: &state)
        }

        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.collection, action: \.collection) {
            CollectionFeature()
        }

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
        }

        FileManagerContentComposerReducer()

        FileManagerContentNavigationBridgeReducer()

        FileManagerContentEntryOperationsBridgeReducer()

        FileManagerContentKeyCommandReducer()

        FileManagerContentSyncReducer()

        Reduce { state, action in
            if let effect = handleCollectionOwnerAction(action, state: &state) {
                return effect
            }

            switch action {
            case .internal(.clearCollectionMode), .internal(.exitCollectionMode):
                return handleCollectionModeAction(
                    action,
                    state: &state,
                    computerName: fileManagerClient.displayName("/"),
                )

            default:
                return .none
            }
        }
    }
}
