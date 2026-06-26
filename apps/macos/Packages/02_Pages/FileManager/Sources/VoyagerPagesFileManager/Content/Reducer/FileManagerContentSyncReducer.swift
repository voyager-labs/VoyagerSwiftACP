import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation

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
                    let affectsCollection = collectionPathsAffectCurrentContext(paths, state: state)
                    guard affectsCollection else {
                        return .none
                    }
                    return .send(.collection(.externalPathsChanged(paths)))

                case let .folder(path):
                    guard pathsAffectCurrentFolder(paths, currentPath: path) else {
                        return .none
                    }
                    return FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state)

                case .recents, .tags, .computer:
                    return FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state)

                case .home:
                    return .none
                }

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
            !isOpenedCollectionDocumentPath($0, openedURL: state.collection.collectionSession.document?.url)
        }
        guard !relevantPaths.isEmpty else {
            return false
        }
        guard let context = state.collection.collectionContext else {
            return true
        }
        return collectionChangeIsRelevant(
            changedPaths: relevantPaths,
            scopes: context.scopes,
            excludedScopes: context.excludedScopes,
            includeSubfolders: context.includeSubfolders,
        )
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
}
