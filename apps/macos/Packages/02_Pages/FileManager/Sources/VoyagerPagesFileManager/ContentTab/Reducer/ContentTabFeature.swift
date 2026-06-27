import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection

@Reducer
public struct ContentTabFeature {
    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
    @Dependency(\.fileManagerIconClient)
    var fileManagerIconClient
    @Dependency(\.contentTabPinnedRecordClient)
    var contentTabPinnedRecordClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.date)
    var date

    public typealias State = ContentTabState
    public typealias Action = ContentTabAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .open(anchor):
                return open(anchor: anchor, state: &state)

            case let .setCurrent(id):
                return setCurrent(id: id, state: &state)

            case let .close(id):
                return close(id: id, state: &state)

            case .restore:
                return restore(state: &state)

            case let .pin(id):
                return pin(id: id, state: &state)

            case let .unpin(id):
                return unpin(id: id, state: &state)

            case let .updateActivePageAnchor(id, newAnchor):
                return updateActivePageAnchor(id: id, newAnchor: newAnchor, state: &state)

            case .pinnedRecordSaveSucceeded:
                state.previousActiveTabID = nil
                state.pinnedRecordPersistenceError = nil
                return .none

            case let .pinnedRecordSaveFailed(tabID, previousIsPinned, previousPinnedRecord):
                state.previousActiveTabID = nil
                state.tabs[id: tabID]?.isPinned = previousIsPinned
                if let record = previousPinnedRecord {
                    state.pinnedRecords[tabID] = record
                } else {
                    state.pinnedRecords.removeValue(forKey: tabID)
                }
                state.pinnedRecordPersistenceError = "pinned_record_save_failed"
                return .none
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
            return unpin(id: id, state: &state)
        }

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
        let fallbackTabID: ContentTabID? = {
            guard let closingIndex = state.tabs.firstIndex(where: { $0.id == id }) else { return nil }

            if let previousID = state.previousActiveTabID,
               previousID != id,
               state.tabs[id: previousID] != nil
            {
                return previousID
            }

            if closingIndex + 1 < state.tabs.endIndex {
                return state.tabs[closingIndex + 1].id
            }

            if closingIndex > state.tabs.startIndex {
                return state.tabs[state.tabs.index(before: closingIndex)].id
            }

            return state.tabs.first?.id
        }()

        state.tabs.remove(id: id)

        if wasActive {
            state.previousActiveTabID = id
            state.activeTabID = fallbackTabID
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
        state.pinnedRecords[id] = ContentTabPinnedRecord(
            id: id.rawValue,
            page: tab.page,
            anchor: tab.anchor,
            title: tab.title,
            iconName: tab.iconName,
            pinnedAt: date(),
        )
        state.pinnedRecordPersistenceError = nil

        let store = derivePinnedRecordStore(from: state)
        let currentWindowRecordIDs = currentWindowRecordIDs(from: state)
        let client = contentTabPinnedRecordClient
        let defaults = userDefaultsClient
        return .run { send in
            do {
                let existingStore = try client.loadStore(defaults)
                let mergedStore = mergePinnedRecordStore(
                    existingStore,
                    currentWindowStore: store,
                    currentWindowRecordIDs: currentWindowRecordIDs,
                )
                try client.saveStore(mergedStore, defaults)
                await send(.pinnedRecordSaveSucceeded)
            } catch {
                await send(.pinnedRecordSaveFailed(tabID: id, previousIsPinned: false, previousPinnedRecord: nil))
            }
        }
    }

    private func unpin(id: ContentTabID, state: inout ContentTabState) -> Effect<ContentTabAction> {
        state.previousActiveTabID = nil
        guard let tab = state.tabs[id: id], tab.isPinned else { return .none }

        let previousPinnedRecord = state.pinnedRecords[id]

        state.tabs[id: id]?.isPinned = false
        state.pinnedRecords.removeValue(forKey: id)
        state.pinnedRecordPersistenceError = nil

        let store = derivePinnedRecordStore(from: state)
        let currentWindowRecordIDs = currentWindowRecordIDs(from: state)
        let client = contentTabPinnedRecordClient
        let defaults = userDefaultsClient
        return .run { send in
            do {
                let existingStore = try client.loadStore(defaults)
                let mergedStore = mergePinnedRecordStore(
                    existingStore,
                    currentWindowStore: store,
                    currentWindowRecordIDs: currentWindowRecordIDs,
                )
                try client.saveStore(mergedStore, defaults)
                await send(.pinnedRecordSaveSucceeded)
            } catch {
                await send(.pinnedRecordSaveFailed(
                    tabID: id,
                    previousIsPinned: true,
                    previousPinnedRecord: previousPinnedRecord,
                ))
            }
        }
    }

    private func derivePinnedRecordStore(from state: ContentTabState) -> ContentTabPinnedRecordStore {
        let records = state.tabs.filter(\.isPinned).map { tab -> ContentTabPinnedRecord in
            state.pinnedRecords[tab.id] ?? ContentTabPinnedRecord(
                id: tab.id.rawValue,
                page: tab.page,
                anchor: tab.anchor,
                title: tab.title,
                iconName: tab.iconName,
                pinnedAt: date(),
            )
        }
        return ContentTabPinnedRecordStore(records: records)
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
            entryLoadingClient.displayName(path).nonEmpty ?? URL(fileURLWithPath: path).lastPathComponent
                .nonEmpty ?? path
        case let .collectionFile(url):
            CollectionFileUtils.displayName(url, fallback: url.lastPathComponent)
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

private func currentWindowRecordIDs(from state: ContentTabState) -> Set<String> {
    Set(state.tabs.map(\.id.rawValue))
}

private func mergePinnedRecordStore(
    _ existingStore: ContentTabPinnedRecordStore,
    currentWindowStore: ContentTabPinnedRecordStore,
    currentWindowRecordIDs: Set<String>,
) -> ContentTabPinnedRecordStore {
    let retainedRecords = existingStore.records.filter { !currentWindowRecordIDs.contains($0.id) }
    return ContentTabPinnedRecordStore(
        schemaVersion: existingStore.schemaVersion,
        records: retainedRecords + currentWindowStore.records,
    )
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
