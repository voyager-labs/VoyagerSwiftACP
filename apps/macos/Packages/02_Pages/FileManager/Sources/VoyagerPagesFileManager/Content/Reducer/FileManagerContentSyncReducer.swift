import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements

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
                    let normalizedPaths = paths.map(normalizedPath(for:))
                    let normalizedCurrentPath = normalizedPath(for: path)
                    let expandedHasFolder = !state.entryViewLayout.hierarchy.expandedFolderIDs.isEmpty
                    let coarseRefreshNeeded = normalizedPaths.count == 1
                        && expandedHasFolder
                        && isProperAncestor(
                            normalizedPaths[0],
                            of: normalizedCurrentPath,
                        )
                    if coarseRefreshNeeded {
                        return .concatenate(
                            .send(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                                affectedPaths: normalizedPaths.map(parentPath(for:)),
                                removedPrefixes: [],
                            )))),
                            FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state),
                        )
                    }
                    return .concatenate(
                        .send(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                            affectedPaths: normalizedPaths.map(parentPath(for:)),
                            removedPrefixes: [],
                        )))),
                        FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state),
                    )

                case .recents, .tags, .computer:
                    return FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state)

                case .home, .aiChat, .aiChatSessions:
                    return .none
                }

            default:
                return .none
            }
        }
    }

    private func pathsAffectCurrentFolder(_ paths: [String], currentPath: String) -> Bool {
        let normalizedCurrentPath = normalizedPath(for: currentPath)

        return paths.contains { path in
            let candidatePath = normalizedPath(for: path)
            if candidatePath == normalizedCurrentPath {
                return true
            }

            return isSameOrDescendant(path: candidatePath, of: normalizedCurrentPath)
        }
    }

    private func isSameOrDescendant(path: String, of ancestor: String) -> Bool {
        let pathComponents = URL(fileURLWithPath: path).pathComponents
        let ancestorComponents = URL(fileURLWithPath: ancestor).pathComponents
        return pathComponents.starts(with: ancestorComponents)
    }

    private func isProperAncestor(_ candidate: String, of path: String) -> Bool {
        let candidateComponents = URL(fileURLWithPath: candidate).pathComponents
        let pathComponents = URL(fileURLWithPath: path).pathComponents
        return candidateComponents.count < pathComponents.count
            && pathComponents.starts(with: candidateComponents)
    }

    private func parentPath(for path: String) -> String {
        URL(fileURLWithPath: normalizedPath(for: path)).deletingLastPathComponent().path
    }

    private func normalizedPath(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func collectionPathsAffectCurrentContext(_ paths: [String], state: State) -> Bool {
        let relevantPaths = paths.filter {
            !isOpenedCollectionDocumentPath($0, openedURL: state.openedCollectionURL)
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

        let lexicalPath = URL(fileURLWithPath: path).path
        let lexicalOpenedPath = openedURL.path
        let lexicalPackagePrefix = lexicalOpenedPath == "/" ? "/" : lexicalOpenedPath + "/"
        if lexicalPath == lexicalOpenedPath || lexicalPath.hasPrefix(lexicalPackagePrefix) {
            return true
        }

        let candidatePath = normalizedPath(for: path)
        let normalizedOpenedPath = normalizedPath(for: openedURL.path)
        if candidatePath == normalizedOpenedPath {
            return true
        }

        let packagePrefix = normalizedOpenedPath == "/" ? "/" : normalizedOpenedPath + "/"
        return candidatePath.hasPrefix(packagePrefix)
    }
}
