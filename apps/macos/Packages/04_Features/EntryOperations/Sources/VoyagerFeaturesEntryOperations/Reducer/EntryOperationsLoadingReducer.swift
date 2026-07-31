import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

public struct EntryOperationsLoadingCancelID: Hashable, Sendable {
    public let windowID: UUID?
    public let ownerID: UUID

    public static func loadItems(windowID: UUID?, ownerID: UUID) -> Self {
        Self(windowID: windowID, ownerID: ownerID)
    }
}

@Reducer
public struct EntryOperationsLoadingReducer {
    public typealias State = EntryOperationsState
    public typealias Action = EntryOperationsAction

    public init() {}

    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .loading(.loadItems(path, showHidden, priority)):
                let generation = state.loadingContext.begin(
                    sourceKind: .directory,
                    preservesSnapshot: state.isReloading,
                )
                state.isLoading = true
                return .run { [entryLoadingClient] send in
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    do {
                        for try await event in entryLoadingClient.loadItems(url, showHidden, priority) {
                            await send(.loading(.streamEvent(.init(generation: generation, event: event))))
                        }
                        await send(.loading(.streamFinished(generation: generation)))
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.loading(.streamFailed(generation: generation)))
                    }
                }
                .cancellable(
                    id: EntryOperationsLoadingCancelID.loadItems(
                        windowID: state.windowID,
                        ownerID: state.loadingCancellationOwnerID,
                    ),
                    cancelInFlight: true,
                )

            case let .loading(.loadRecentItems(showHidden, priority)):
                let generation = state.loadingContext.begin(
                    sourceKind: .recents,
                    preservesSnapshot: state.isReloading,
                )
                state.isLoading = true
                return .run { [entryLoadingClient] send in
                    do {
                        for try await event in entryLoadingClient.loadRecentItems(showHidden, priority) {
                            await send(.loading(.streamEvent(.init(generation: generation, event: event))))
                        }
                        await send(.loading(.streamFinished(generation: generation)))
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.loading(.streamFailed(generation: generation)))
                    }
                }
                .cancellable(
                    id: EntryOperationsLoadingCancelID.loadItems(
                        windowID: state.windowID,
                        ownerID: state.loadingCancellationOwnerID,
                    ),
                    cancelInFlight: true,
                )

            case let .loading(.loadTagItems(tagName, showHidden, priority)):
                let generation = state.loadingContext.begin(
                    sourceKind: .tags,
                    preservesSnapshot: state.isReloading,
                )
                state.isLoading = true
                return .run { [entryLoadingClient] send in
                    do {
                        for try await event in entryLoadingClient.loadFilesWithTag(tagName, showHidden, priority) {
                            await send(.loading(.streamEvent(.init(generation: generation, event: event))))
                        }
                        await send(.loading(.streamFinished(generation: generation)))
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.loading(.streamFailed(generation: generation)))
                    }
                }
                .cancellable(
                    id: EntryOperationsLoadingCancelID.loadItems(
                        windowID: state.windowID,
                        ownerID: state.loadingCancellationOwnerID,
                    ),
                    cancelInFlight: true,
                )

            case .loading(.loadComputerItems):
                state.loadingContext.invalidate()
                state.isLoading = true
                return .run { [entryLoadingClient] send in
                    do {
                        let computerItems = try await entryLoadingClient.loadComputerItems()
                        try Task.checkCancellation()
                        await send(.loading(.itemsLoaded(computerItems)))
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.loading(.itemsLoaded([])))
                    }
                }
                .cancellable(
                    id: EntryOperationsLoadingCancelID.loadItems(
                        windowID: state.windowID,
                        ownerID: state.loadingCancellationOwnerID,
                    ),
                    cancelInFlight: true,
                )

            case .loading(.cancelAndClearItems):
                state.loadingContext.invalidate()
                state.loadingContext.items = []
                state.isLoading = false
                state.isReloading = false
                state.renamingItemId = nil
                state.renamingText = ""
                state.renamingItem = nil
                return .cancel(
                    id: EntryOperationsLoadingCancelID.loadItems(
                        windowID: state.windowID,
                        ownerID: state.loadingCancellationOwnerID,
                    ),
                )

            case let .loading(.itemsLoaded(items)):
                state.loadingContext.items = IdentifiedArray(uniqueElements: items)
                state.isLoading = false
                state.isReloading = false
                return .none

            case let .loading(.streamEvent(streamEvent)):
                guard streamEvent.generation == state.loadingContext.generation,
                      !state.loadingContext.streamTerminal
                else {
                    return .none
                }
                switch streamEvent.event {
                case let .coreBatch(items, batchIndex):
                    guard !state.loadingContext.coreFinished,
                          batchIndex == state.loadingContext.expectedCoreBatchIndex
                    else {
                        return .none
                    }
                    if batchIndex == 0, state.isReloading {
                        state.loadingContext.items = []
                    }
                    let existingIDs = Set(state.loadingContext.items.map(\.id))
                    state.loadingContext.items.append(contentsOf: items.filter { !existingIDs.contains($0.id) })
                    state.loadingContext.expectedCoreBatchIndex += 1
                    state.isLoading = false
                    state.isReloading = false
                    return .none

                case let .coreFinished(batchCount):
                    guard !state.loadingContext.coreFinished,
                          batchCount == state.loadingContext.expectedCoreBatchIndex
                    else {
                        return .none
                    }
                    if batchCount == 0 {
                        state.loadingContext.items = []
                    }
                    state.loadingContext.coreFinished = true
                    state.isLoading = false
                    state.isReloading = false
                    return .none

                case let .metadataPatches(patches):
                    guard state.loadingContext.coreFinished else { return .none }
                    for patch in patches {
                        guard let current = state.loadingContext.items[id: patch.entryID] else { continue }
                        state.loadingContext.items[id: current.id] = current.applying(patch)
                    }
                    return .none
                }

            case let .loading(.streamFinished(generation)):
                guard generation == state.loadingContext.generation,
                      state.loadingContext.coreFinished,
                      !state.loadingContext.streamTerminal
                else {
                    return .none
                }
                state.loadingContext.streamTerminal = true
                return .none

            case let .loading(.streamFailed(generation)):
                guard generation == state.loadingContext.generation,
                      !state.loadingContext.streamTerminal
                else {
                    return .none
                }
                let emittedCoreBatch = state.loadingContext.expectedCoreBatchIndex > 0
                state.loadingContext.streamTerminal = true
                state.loadingContext.isIncomplete = true
                state.isLoading = false
                state.isReloading = false
                guard emittedCoreBatch else {
                    state.loadingContext.items = []
                    state.renamingItemId = nil
                    state.renamingText = ""
                    state.renamingItem = nil
                    return .none
                }
                return .none

            case .loading(.itemsLoadFailed):
                state.loadingContext.items = []
                state.isLoading = false
                state.isReloading = false
                state.renamingItemId = nil
                state.renamingText = ""
                state.renamingItem = nil
                return .none

            default:
                return .none
            }
        }
    }
}

private extension EntryMetadataPatch {
    var entryID: EntryModel.ID {
        switch self {
        case let .spotlight(id, _, _, _),
             let .tags(id, _),
             let .supplementaryMetadata(id, _):
            id
        }
    }
}
