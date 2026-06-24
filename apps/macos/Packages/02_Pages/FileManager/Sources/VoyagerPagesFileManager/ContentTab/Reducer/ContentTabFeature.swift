import ComposableArchitecture
import Foundation

@Reducer
public struct ContentTabFeature {
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
        guard state.tabs.count < ContentTabConstants.maxTabs else { return .none }

        let item = ContentTabItem(
            id: ContentTabID(),
            page: page(for: anchor),
            anchor: anchor,
            isPinned: false,
            title: nil,
            iconName: nil,
        )
        state.tabs.append(item)
        state.activeTabID = item.id
        return .none
    }

    private func setCurrent(id: ContentTabID, state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard state.tabs[id: id] != nil else { return .none }
        state.activeTabID = id
        return .none
    }

    private func close(id: ContentTabID, state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard let tab = state.tabs[id: id] else { return .none }

        if tab.isPinned {
            state.tabs[id: id]?.isPinned = false
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
            state.activeTabID = state.tabs.last?.id
        }

        return .none
    }

    private func restore(state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard let snapshot = state.recentlyClosed else { return .none }
        guard state.tabs.count < ContentTabConstants.maxTabs else { return .none }

        let item = ContentTabItem(
            id: ContentTabID(),
            page: snapshot.page,
            anchor: snapshot.anchor,
            isPinned: false,
            title: nil,
            iconName: nil,
        )
        state.tabs.append(item)
        state.activeTabID = item.id
        state.recentlyClosed = nil
        return .none
    }

    private func pin(id: ContentTabID, state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard let tab = state.tabs[id: id], !tab.isPinned else { return .none }
        state.tabs[id: id]?.isPinned = true
        return .none
    }

    private func unpin(id: ContentTabID, state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard let tab = state.tabs[id: id], tab.isPinned else { return .none }
        state.tabs[id: id]?.isPinned = false
        return .none
    }

    private func updateActivePageAnchor(id: ContentTabID, newAnchor: ContentTabPageAnchor,
                                        state: inout ContentTabState) -> Effect<ContentTabAction>
    {
        guard state.tabs[id: id] != nil else { return .none }
        state.tabs[id: id]?.anchor = newAnchor
        state.tabs[id: id]?.page = page(for: newAnchor)
        return .none
    }
}

extension ContentTabFeature {
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
