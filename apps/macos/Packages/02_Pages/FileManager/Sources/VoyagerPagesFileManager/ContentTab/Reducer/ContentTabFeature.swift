import ComposableArchitecture
import Foundation

@Reducer
public struct ContentTabFeature {
    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
    @Dependency(\.fileManagerIconClient)
    var fileManagerIconClient

    public typealias State = ContentTabState
    public typealias Action = ContentTabAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .open(anchor):
                open(anchor: anchor, state: &state)

            case let .setCurrent(id):
                setCurrent(id: id, state: &state)

            case let .close(id):
                close(id: id, state: &state)

            case .restore:
                restore(state: &state)

            case let .pin(id):
                pin(id: id, state: &state)

            case let .unpin(id):
                unpin(id: id, state: &state)

            case let .updateActivePageAnchor(id, newAnchor):
                updateActivePageAnchor(id: id, newAnchor: newAnchor, state: &state)
            }
        }
    }
}

extension ContentTabFeature {
    private func open(anchor: ContentTabPageAnchor, state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard state.tabs.count < ContentTabConstants.maxTabs else {
            state.previousActiveTabID = nil
            return .none
        }

        let previousActiveTabID = state.activeTabID
        let item = ContentTabItem(
            id: ContentTabID(),
            page: page(for: anchor),
            anchor: anchor,
            isPinned: false,
            title: title(for: anchor),
            iconName: iconName(for: anchor),
        )
        state.tabs.append(item)
        state.previousActiveTabID = previousActiveTabID
        state.activeTabID = item.id
        return .none
    }

    private func setCurrent(id: ContentTabID, state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard state.tabs[id: id] != nil, state.activeTabID != id else {
            state.previousActiveTabID = nil
            return .none
        }
        state.previousActiveTabID = state.activeTabID
        state.activeTabID = id
        return .none
    }

    private func close(id: ContentTabID, state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard let tab = state.tabs[id: id] else {
            state.previousActiveTabID = nil
            return .none
        }

        if tab.isPinned {
            state.previousActiveTabID = nil
            state.tabs[id: id]?.isPinned = false
            return .none
        }

        // 마지막 tab close 시 Home tab으로 reset (blank pane 방지)
        if state.tabs.count == 1 {
            state.previousActiveTabID = id
            state.tabs[id: id]?.page = .home
            state.tabs[id: id]?.anchor = .homeDefault
            state.tabs[id: id]?.title = "Home"
            state.tabs[id: id]?.iconName = "house"
            state.activeTabID = id
            return .none
        }

        let snapshot = ClosedContentTabSnapshot(
            page: tab.page,
            anchor: tab.anchor,
            wasPinned: tab.isPinned,
            closedAt: Date(),
        )
        state.recentlyClosed = snapshot

        let wasActive = state.activeTabID == id
        state.tabs.remove(id: id)

        if wasActive {
            state.previousActiveTabID = id
            state.activeTabID = state.tabs.last?.id
        } else {
            state.previousActiveTabID = nil
        }

        return .none
    }

    private func restore(state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard let snapshot = state.recentlyClosed else {
            state.previousActiveTabID = nil
            return .none
        }
        guard state.tabs.count < ContentTabConstants.maxTabs else {
            state.previousActiveTabID = nil
            return .none
        }

        let item = ContentTabItem(
            id: ContentTabID(),
            page: snapshot.page,
            anchor: snapshot.anchor,
            isPinned: false,
            title: title(for: snapshot.anchor),
            iconName: iconName(for: snapshot.anchor),
        )
        state.tabs.append(item)
        state.previousActiveTabID = state.activeTabID
        state.activeTabID = item.id
        state.recentlyClosed = nil
        return .none
    }

    private func pin(id: ContentTabID, state: inout ContentTabState) -> Effect<ContentTabAction> {
        state.previousActiveTabID = nil
        guard let tab = state.tabs[id: id], !tab.isPinned else { return .none }
        state.tabs[id: id]?.isPinned = true
        return .none
    }

    private func unpin(id: ContentTabID, state: inout ContentTabState) -> Effect<ContentTabAction> {
        state.previousActiveTabID = nil
        guard let tab = state.tabs[id: id], tab.isPinned else { return .none }
        state.tabs[id: id]?.isPinned = false
        return .none
    }

    private func updateActivePageAnchor(id: ContentTabID, newAnchor: ContentTabPageAnchor,
                                        state: inout ContentTabState) -> Effect<ContentTabAction>
    {
        state.previousActiveTabID = nil
        guard state.tabs[id: id] != nil else { return .none }
        state.tabs[id: id]?.anchor = newAnchor
        state.tabs[id: id]?.page = page(for: newAnchor)
        state.tabs[id: id]?.title = title(for: newAnchor)
        state.tabs[id: id]?.iconName = iconName(for: newAnchor)
        return .none
    }
}

extension ContentTabFeature {
    private func title(for anchor: ContentTabPageAnchor) -> String {
        switch anchor {
        case .homeDefault:
            "Home"
        case let .directory(path):
            URL(fileURLWithPath: path).lastPathComponent.nonEmpty ?? path
        case let .collectionFile(url):
            url.deletingPathExtension().lastPathComponent.nonEmpty ?? url.lastPathComponent
        case let .virtualCollection(id):
            id
        case .aiChat:
            "AI Chat"
        }
    }

    private func iconName(for anchor: ContentTabPageAnchor) -> String {
        switch anchor {
        case .homeDefault:
            "house"
        case let .directory(path):
            fileManagerIconClient.iconNameForURL(URL(fileURLWithPath: path), true, entryLoadingClient)
        case .collectionFile:
            "rectangle.stack"
        case let .virtualCollection(id):
            id == "Recents" ? "clock" : "folder"
        case .aiChat:
            "sparkles"
        }
    }

    private func page(for anchor: ContentTabPageAnchor) -> ContentTabPage {
        switch anchor {
        case .homeDefault:
            .home
        case .directory:
            .directory
        case .collectionFile, .virtualCollection:
            .collection
        case .aiChat:
            .aiChat
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
