import AppKit
import ComposableArchitecture
import Dependencies
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared

// MARK: - PasteboardClient.noOp

extension PasteboardClient {
    /// No-op pasteboard: all operations succeed silently without touching the system pasteboard.
    static let noOp = PasteboardClient(
        changeCount: { 0 },
        clearContents: {},
        writeObjects: { _ in true },
        readObjects: { _, _ in nil },
        setString: { _, _ in true },
        string: { _ in nil },
    )
}

// MARK: - Test Store Factory

actor EntryOperationsLoadSuspensionGate {
    enum Completion {
        case entries([EntryModel])
        case failure
    }

    private var continuation: CheckedContinuation<Completion, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async throws -> [EntryModel] {
        let completion = await withCheckedContinuation { continuation in
            self.continuation = continuation
            let waiters = self.waiters
            self.waiters.removeAll()
            waiters.forEach { waiter in waiter.resume() }
        }
        switch completion {
        case let .entries(entries):
            return entries
        case .failure:
            throw Failure.expected
        }
    }

    func waitForValue() async -> [EntryModel] {
        await (try? wait()) ?? []
    }

    func waitUntilWaiting() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resume(with completion: Completion) {
        continuation?.resume(returning: completion)
        continuation = nil
    }

    private enum Failure: Error {
        case expected
    }
}

@MainActor
enum EntryOperationsTestSupport {
    enum CancelledLoadScenario {
        case recents
        case tag
        case computerSuccess
        case computerFailure
    }

    /// Creates a `TestStore` with safe baseline dependencies for EntryOperations tests.
    ///
    /// Baseline dependencies:
    /// - `entryFileOpsClient`: `.previewValue` (no side effects)
    /// - `entryOpenClient`: `.previewValue` (no side effects)
    /// - `entryQuickLookClient`: `.previewValue` (no side effects)
    /// - `pasteboardClient`: `.noOp` (silent, no system pasteboard)
    /// - `undoManagerClient`: no-op (registerUndo/undo/redo do nothing)
    /// - `trashMetadataStoreClient`: `.testValue` (in-memory storage)
    ///
    /// Use `configure` to override specific dependencies per test.
    static func makeStore(
        initialState: EntryOperationsFeature.State = .init(),
        configure: (inout DependencyValues) -> Void = { _ in },
    ) -> TestStore<EntryOperationsFeature.State, EntryOperationsFeature.Action> {
        TestStore(initialState: initialState) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.entryOpenClient = .previewValue
            $0.entryQuickLookClient = .previewValue
            $0.pasteboardClient = .noOp
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            )
            $0.trashMetadataStoreClient = .testValue
            configure(&$0)
        }
    }

    static func makeObservedStore(
        initialState: EntryOperationsFeature.State = .init(),
        observeAction: @escaping @Sendable (EntryOperationsFeature.Action) -> Void,
        configure: (inout DependencyValues) -> Void = { _ in },
    ) -> TestStore<EntryOperationsFeature.State, EntryOperationsFeature.Action> {
        TestStore(initialState: initialState) {
            CombineReducers {
                EntryOperationsFeature()
                Reduce { _, action in
                    observeAction(action)
                    return .none
                }
            }
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.entryOpenClient = .previewValue
            $0.entryQuickLookClient = .previewValue
            $0.pasteboardClient = .noOp
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            )
            $0.trashMetadataStoreClient = .testValue
            configure(&$0)
        }
    }

    static func completeReplacementAfterCancellation(
        store: TestStore<EntryOperationsFeature.State, EntryOperationsFeature.Action>,
        gate: EntryOperationsLoadSuspensionGate,
        latestEntry: EntryModel,
        staleCompletion: EntryOperationsLoadSuspensionGate.Completion,
    ) async {
        await gate.waitUntilWaiting()
        await store.send(.loading(.loadItems(path: "/tmp", showHidden: false)))
        await store.receive(\.loading.itemsLoaded, [latestEntry]) { state in
            state.items = [latestEntry]
            state.isLoading = false
            state.isReloading = false
        }
        await gate.resume(with: staleCompletion)
        await store.finish()
    }

    static func cancelledLoadResult(
        action: EntryOperationsFeature.Action,
        latestEntry: EntryModel,
        staleCompletion: EntryOperationsLoadSuspensionGate.Completion,
        configure: (inout DependencyValues, EntryOperationsLoadSuspensionGate) -> Void,
    ) async -> [EntryModel] {
        let gate = EntryOperationsLoadSuspensionGate()
        let store = makeStore { dependencies in
            configure(&dependencies, gate)
            dependencies.entryLoadingClient.loadItems = { _, _ in [latestEntry] }
        }
        await store.send(action) { state in state.isLoading = true }
        await completeReplacementAfterCancellation(
            store: store,
            gate: gate,
            latestEntry: latestEntry,
            staleCompletion: staleCompletion,
        )
        return Array(store.state.items)
    }

    static func cancelledLoadPreservesLatest(_ scenario: CancelledLoadScenario) async -> Bool {
        let latestEntry = EntryModelFixtures.makeFileEntry(id: "/tmp/latest.txt", name: "latest.txt")
        let items: [EntryModel] = switch scenario {
        case .recents:
            await cancelledLoadResult(
                action: .loading(.loadRecentItems(showHidden: false)),
                latestEntry: latestEntry,
                staleCompletion: .entries([makeStaleEntry("recent")]),
            ) { dependencies, gate in
                dependencies.entryLoadingClient.loadRecentItems = { _, _ in await gate.waitForValue() }
            }
        case .tag:
            await cancelledLoadResult(
                action: .loading(.loadTagItems(tagName: "Blue", showHidden: false)),
                latestEntry: latestEntry,
                staleCompletion: .entries([makeStaleEntry("tag")]),
            ) { dependencies, gate in
                dependencies.entryLoadingClient.loadFilesWithTag = { _, _, _ in await gate.waitForValue() }
            }
        case .computerSuccess:
            await cancelledLoadResult(
                action: .loading(.loadComputerItems),
                latestEntry: latestEntry,
                staleCompletion: .entries([makeStaleEntry("computer")]),
            ) { dependencies, gate in
                dependencies.entryLoadingClient.loadComputerItems = { try await gate.wait() }
            }
        case .computerFailure:
            await cancelledLoadResult(
                action: .loading(.loadComputerItems),
                latestEntry: latestEntry,
                staleCompletion: .failure,
            ) { dependencies, gate in
                dependencies.entryLoadingClient.loadComputerItems = { try await gate.wait() }
            }
        }
        return items == [latestEntry]
    }

    private static func makeStaleEntry(_ suffix: String) -> EntryModel {
        EntryModelFixtures.makeFileEntry(
            id: "/tmp/stale-\(suffix).txt",
            name: "stale-\(suffix).txt",
        )
    }
}
