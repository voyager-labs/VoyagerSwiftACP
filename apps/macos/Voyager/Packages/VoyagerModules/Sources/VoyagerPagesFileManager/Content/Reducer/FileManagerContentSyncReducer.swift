import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

@Reducer
struct FileManagerContentSyncReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .externalFileSystemChanged(paths):
                switch state.navigation.navigationState {
                case .collection:
                    if collectionPathsAffectCurrentContext(paths, state: state) {
                        state.collectionSession.isStale = true
                    }
                    return .none

                case let .folder(path):
                    guard pathsAffectCurrentFolder(paths, currentPath: path) else {
                        return .none
                    }
                    return reloadEntryItemsEffect(
                        navigationState: state.navigation.navigationState,
                        showHidden: state.entryViewLayout.showHiddenFiles,
                    )

                case .recents, .tags, .computer:
                    return reloadEntryItemsEffect(
                        navigationState: state.navigation.navigationState,
                        showHidden: state.entryViewLayout.showHiddenFiles,
                    )
                }

            case .delegate(.discardCollectionChanges):
                guard let baseline = state.collectionSession.baseline,
                      state.isCollectionMode,
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

            default:
                return .none
            }
        }
    }

    private func pathsAffectCurrentFolder(_ paths: [String], currentPath: String) -> Bool {
        let normalizedCurrentPath = URL(fileURLWithPath: currentPath).standardizedFileURL.path

        return paths.contains { path in
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            if normalizedPath == normalizedCurrentPath {
                return true
            }

            let folderPrefix = normalizedCurrentPath == "/" ? "/" : normalizedCurrentPath + "/"
            return normalizedPath.hasPrefix(folderPrefix)
        }
    }

    private func collectionPathsAffectCurrentContext(_ paths: [String], state: State) -> Bool {
        let relevantPaths = paths.filter {
            !isOpenedCollectionDocumentPath($0, openedURL: state.collectionSession.openedURL)
        }
        guard !relevantPaths.isEmpty else {
            return false
        }
        guard let context = state.collectionContext else {
            return true
        }
        return collectionChangeIsRelevant(changedPaths: relevantPaths, scopes: context.scopes)
    }

    private func isOpenedCollectionDocumentPath(_ path: String, openedURL: URL?) -> Bool {
        guard let openedURL else {
            return false
        }

        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedOpenedPath = openedURL.standardizedFileURL.path
        if normalizedPath == normalizedOpenedPath {
            return true
        }

        let packagePrefix = normalizedOpenedPath == "/" ? "/" : normalizedOpenedPath + "/"
        return normalizedPath.hasPrefix(packagePrefix)
    }

    private func reloadEntryItemsEffect(
        navigationState: ContentPageNavigationRoute,
        showHidden: Bool,
    ) -> Effect<Action> {
        switch navigationState {
        case let .folder(path):
            .send(.entryViewLayout(.entryOperations(.loading(.loadItems(path: path, showHidden: showHidden)))))
        case .recents:
            .send(.entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden: showHidden)))))
        case let .tags(tagName):
            .send(.entryViewLayout(.entryOperations(.loading(.loadTagItems(tagName: tagName, showHidden: showHidden)))))
        case .computer:
            .send(.entryViewLayout(.entryOperations(.loading(.loadComputerItems))))
        case .collection:
            .none
        }
    }
}
