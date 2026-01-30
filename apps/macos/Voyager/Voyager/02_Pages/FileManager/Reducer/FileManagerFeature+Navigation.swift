import ComposableArchitecture
import Foundation

extension FileManagerFeature {
    func performNavigation(
        _ pending: PendingNavigation,
        state: inout State,
    ) -> Effect<Action> {
        switch pending {
        case .back:
            performBackNavigation(state: &state)

        case .forward:
            performForwardNavigation(state: &state)

        case let .history(index, isBackHistory):
            performHistoryNavigation(
                index: index,
                isBackHistory: isBackHistory,
                state: &state,
            )

        case .enclosingDirectory:
            performEnclosingDirectoryNavigation(state: &state)
        }
    }

    func performEnclosingDirectoryNavigation(state: inout State) -> Effect<Action> {
        guard let parentPath = state.enclosingDirectoryPath else { return .none }
        let parentURL = URL(fileURLWithPath: parentPath)
        let childName = URL(fileURLWithPath: state.currentPath).lastPathComponent
        if !childName.isEmpty {
            state.entries.selectAfterLoadFileNames = [childName]
        }
        let previousNavigationState = state.navigationState
        state.navigateToFolder(parentURL.path, sidebarItemName: parentURL.lastPathComponent)
        logDAUNavigationIfNeeded(previous: previousNavigationState, next: state.navigationState)
        state.resetComposer()
        state.resetComposerOnNextDirectoryNavigation = false
        let exitEffect = exitCollectionMode(state: &state)
        return .concatenate(
            exitEffect,
            .send(.entries(.loadItems(path: parentURL.path))),
        )
    }

    func navigateToState(
        _ navigationState: FileManagerNavigationUtils.NavigationState,
        showHidden: Bool = false,
    ) -> Effect<Action> {
        switch navigationState {
        case .recents:
            .send(.entries(.loadRecentItems(showHidden: showHidden)))
        case let .folder(path):
            .send(.entries(.loadItems(path: path)))
        case let .tags(tagName):
            .run { send in
                let taggedItems = await sidebarClient.loadFilesWithTag(
                    tagName,
                    showHidden,
                    entryClient,
                    WorkspaceClient.liveValue,
                )
                await send(.entries(.itemsLoaded(taggedItems)))
            }
        case .computer:
            .send(.entries(.loadComputerItems))
        case let .collection(navigation):
            .send(.navigateToCollection(navigation))
        }
    }

    func logDAUNavigationIfNeeded(
        previous: FileManagerNavigationUtils.NavigationState,
        next: FileManagerNavigationUtils.NavigationState,
    ) {
        guard previous != next else { return }
        guard let kind = dauNavigationKind(for: next) else { return }
        VoyagerSentryMetricLogger.logDAUNavigation(kind: kind)
    }

    func dauNavigationKind(
        for navigationState: FileManagerNavigationUtils.NavigationState,
    ) -> DAUNavigationKind? {
        switch navigationState {
        case .folder:
            .folder
        case .collection:
            .collection
        default:
            nil
        }
    }
}
