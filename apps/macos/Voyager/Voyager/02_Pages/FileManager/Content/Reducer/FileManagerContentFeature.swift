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

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
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

            case let .entryViewLayout(action):
                return routeEntryViewLayoutAction(action, state: &state)

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
              state.entryOperations.loadingContext.isCollectionMode,
              state.isOpenedCollectionDirty
        else {
            return .none
        }

        let trimmedQuery = baseline.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        state.composer.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
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

    private func routeEntryViewLayoutAction(
        _ action: EntryViewLayoutAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .setSelectedIds(ids, lastSelectedId):
            return .send(.entries(.setSelectedIds(ids: ids, lastSelectedId: lastSelectedId)))

        case let .setSelectedIdsFromLasso(ids, lastSelectedId):
            return .send(.entries(.setSelectedIdsFromLasso(ids: ids, lastSelectedId: lastSelectedId)))

        case let .selectNextItem(isShiftPressed):
            return .send(.entries(.selectNextItem(isShiftPressed: isShiftPressed)))

        case let .selectPreviousItem(isShiftPressed):
            return .send(.entries(.selectPreviousItem(isShiftPressed: isShiftPressed)))

        case let .selectByOffset(offset, isShiftPressed):
            return .send(.entries(.selectByOffset(offset: offset, isShiftPressed: isShiftPressed)))

        case let .updateGridColumnCount(count):
            return .send(.entries(.updateGridColumnCount(count)))

        case .resetScrollFlag:
            return .send(.entries(.resetScrollFlag))

        case let .setDropTargeted(isTargeted):
            return .send(.entries(.setDropTargeted(isTargeted)))

        case let .startDrag(paths):
            return .send(.entries(.startDrag(paths: paths)))

        case let .handleDrop(providers, destinationPath):
            return .send(.entries(.handleDrop(providers: providers, destinationPath: destinationPath)))

        case let .dropItems(sourcePaths, destinationPath, isOptionDrag):
            return .send(.entries(.dropItems(
                sourcePaths: sourcePaths,
                destinationPath: destinationPath,
                isOptionDrag: isOptionDrag,
            )))

        case let .startRename(id):
            return .send(.entries(.startRename(id: id)))

        case let .updateRenamingText(text):
            return .send(.entries(.updateRenamingText(text)))

        case .commitRename:
            return .send(.entries(.commitRename))

        case .cancelRename:
            return .send(.entries(.cancelRename))

        case .openSelectedItem:
            return .send(.entries(.openSelectedItem))

        case .toggleShowHiddenFiles:
            state.entryViewLayout.showHiddenFiles.toggle()
            return reloadEntryItemsEffect(state: state)
        }
    }

    private func reloadEntryItemsEffect(state: State) -> Effect<Action> {
        switch state.navigation.navigationState {
        case let .folder(path):
            .send(.entries(.loadItems(path: path)))
        case .recents:
            .send(.entries(.loadRecentItems(showHidden: state.entryViewLayout.showHiddenFiles)))
        case let .tags(tagName):
            .send(.entries(.loadTagItems(
                tagName: tagName,
                showHidden: state.entryViewLayout.showHiddenFiles,
            )))
        case .computer:
            .send(.entries(.loadComputerItems))
        case .collection:
            .none
        }
    }
}
