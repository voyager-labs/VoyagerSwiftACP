import AppKit
import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation

@Reducer
struct FileManagerWindowRoutingReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .sidebar(.delegate(.dropItemsToSidebarFolder(providers, targetURL))):
                return .send(.content(.delegate(.dropItemsToSidebarFolder(
                    providers: providers,
                    targetURL: targetURL,
                ))))

            case let .sidebar(.delegate(.dropItemsToTag(providers, tagName))):
                return .send(.content(.delegate(.dropItemsToTag(
                    providers: providers,
                    tagName: tagName,
                ))))

            case let .sidebar(.delegate(.selectContentTab(tabID))):
                return .send(.contentTabs(.setCurrent(tabID)))

            case .content(.delegate(.closeWindow)):
                return .send(.closeWindow)

            case .closeWindow:
                return .run { _ in
                    await MainActor.run {
                        NSApp.keyWindow?.close()
                    }
                }

            case .contentTabs(.setCurrent):
                let shouldResyncContentNavigation = state.contentTabs.previousActiveTabID != nil
                    || state.activeTabContentStateMissing
                if shouldResyncContentNavigation {
                    state.saveCurrentContentStateForPreviousActiveTab()
                    state.restoreContentStateForActiveTab()
                }
                state.syncContentTabSidebarItems()
                syncSidebarSelectionForActiveContentTab(state: &state)
                return shouldResyncContentNavigation
                    ? resyncContentNavigationEffect(state: state)
                    : .none

            case .contentTabs(.open):
                state.saveCurrentContentStateForPreviousActiveTab()
                if state.activeTabContentStateMissing {
                    let activeAnchor = state.contentTabs.activeTabID.flatMap { state.contentTabs.tabs[id: $0]?.anchor }
                    state.content = contentState(for: activeAnchor)
                    state.syncActiveTabContentState()
                }
                state.syncContentTabSidebarItems()
                syncSidebarSelectionForActiveContentTab(state: &state)
                return .none

            case let .contentTabs(.close(tabID)):
                if state.contentTabs.tabs[id: tabID] == nil {
                    state.removeContentState(for: tabID)
                    if state.contentTabs.previousActiveTabID == tabID {
                        state.restoreContentStateForActiveTab()
                    }
                } else if state.contentTabs.previousActiveTabID == tabID,
                          state.contentTabs.activeTabID == tabID
                {
                    state.content = contentState(for: state.contentTabs.tabs[id: tabID]?.anchor)
                    state.syncActiveTabContentState()
                }
                state.syncContentTabSidebarItems()
                syncSidebarSelectionForActiveContentTab(state: &state)
                return .none

            case .contentTabs(.restore):
                if state.contentTabs.previousActiveTabID != nil || state.activeTabContentStateMissing {
                    state.saveCurrentContentStateForPreviousActiveTab()
                    state.restoreContentStateForActiveTab()
                }
                state.syncContentTabSidebarItems()
                syncSidebarSelectionForActiveContentTab(state: &state)
                return .none

            case .contentTabs:
                state.syncContentTabSidebarItems()
                return .none

            default:
                return .none
            }
        }
    }
}

private func resyncContentNavigationEffect(state: FileManagerWindowState) -> Effect<FileManagerWindowAction> {
    guard let navigationState = resyncNavigationStateForActiveContentTab(state: state) else {
        return .none
    }
    return .send(.content(.internal(.applyNavigationState(navigationState))))
}

private func resyncNavigationStateForActiveContentTab(
    state: FileManagerWindowState,
) -> ContentPageNavigationRoute? {
    guard let activeTabID = state.contentTabs.activeTabID,
          let activeAnchor = state.contentTabs.tabs[id: activeTabID]?.anchor
    else { return nil }

    switch activeAnchor {
    case .homeDefault, .aiChat:
        return .home
    case let .directory(path):
        return .folder(path)
    case .collectionFile:
        if case let .collection(navigation) = state.content.navigation.navigationState {
            return .collection(navigation)
        }
        return nil
    case .virtualCollection:
        switch state.content.navigation.navigationState {
        case .recents,
             .tags,
             .computer:
            return state.content.navigation.navigationState
        default:
            return nil
        }
    }
}

private func syncSidebarSelectionForActiveContentTab(state: inout FileManagerWindowState) {
    guard let activeTabID = state.contentTabs.activeTabID,
          let activeAnchor = state.contentTabs.tabs[id: activeTabID]?.anchor
    else {
        state.sidebar.selectedSidebarItem = nil
        return
    }

    switch activeAnchor {
    case .homeDefault, .aiChat:
        state.sidebar.selectedSidebarItem = nil
    case .directory, .collectionFile, .virtualCollection:
        let computerName = state.sidebar.locations.first(where: \.isComputer)?.name
        syncSidebarSelection(state: &state, computerName: computerName)
    }
}

private func contentState(for anchor: ContentTabPageAnchor?) -> FileManagerContentFeature.State {
    var content = FileManagerContentFeature.State()

    switch anchor {
    case let .directory(path):
        content.navigation.seedInitialFolderPath(path)
    case .homeDefault,
         .collectionFile,
         .virtualCollection,
         .aiChat,
         .none:
        break
    }

    return content
}
