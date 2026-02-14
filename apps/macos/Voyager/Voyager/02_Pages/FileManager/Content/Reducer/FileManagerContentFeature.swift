import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct FileManagerContentFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.fileManagerWindowClient)
    var fileManagerWindowClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    var body: some Reducer<State, Action> {
        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.entries, action: \.entries) {
            EntryFeature()
        }

        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsFeature()
        }

        Scope(state: \.self, action: \.entryArrangements) {
            EntryArrangementsFeature()
        }
        FileManagerContentEntryFeature()
        FileManagerContentEntryAppearanceFeature()
        FileManagerContentEntryOperationsFeature()
        FileManagerContentEntryThumbnailFeature()
        FileManagerContentComposerFeature()

        Reduce { (state: inout State, action: Action) in
            switch action {
            case let .handleKeyCommand(command):
                return FileManagerContentKeyCommandHandler.effect(for: command, state: state)

            case let .openPathInNewWindow(path):
                return .run { [fileManagerWindowClient] _ in
                    await fileManagerWindowClient.openPathInNewWindow(path)
                }

            case .entries:
                return .none

            case .entryOperations:
                return .none

            case .entryArrangements:
                return .none

            case .composer:
                return .none

            case .discardCollectionChanges:
                return restoreCollectionDraft(state: &state)

            case .performPendingNavigation:
                return .none

            case .emptyTrashCompleted:
                return .send(.closeWindow)

            case .closeWindow:
                return .none

            case let .changeLayout(layout):
                state.viewLayout = layout
                state.syncComposerCollectionState()
                userDefaultsClient.setString(layout.rawValue, SettingsKeys.viewLayout)
                return .none

            case let .saveScrollOffset(offset, forPath: path):
                state.navigation.scrollPositions[path] = offset
                return .none

            case let .dropItemsToSidebarFolder(providers, targetURL):
                return .send(.entries(.handleDrop(
                    providers: providers,
                    destinationPath: targetURL.path,
                )))

            case let .dropItemsToTag(providers, tagName):
                return .send(.entries(.handleDropToTag(
                    providers: providers,
                    tagName: tagName,
                )))
            }
        }
    }

    private func restoreCollectionDraft(state: inout State) -> Effect<Action> {
        guard let baseline = state.collectionSession.baseline,
              state.entries.isCollectionMode,
              state.isOpenedCollectionDirty
        else {
            return .none
        }

        let trimmedQuery = baseline.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        state.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
        state.collectionContext = baseline.context
        state.syncComposerCollectionState()

        if state.collectionSession.openedURL == nil {
            state.composer.text = baseline.context.query
        } else {
            state.composer.text = ""
        }
        state.composer.scopes = baseline.context.scopes
        state.composer.conditions = baseline.context.conditions
        state.composer.propertyPicker = ConditionPropertyPickerFeature.State()
        state.composer.operatorPicker = OperatorPickerFeature.State()
        state.composer.valuePicker = ValuePickerFeature.State()
        state.composer.clearHistory()

        return .none
    }
}
