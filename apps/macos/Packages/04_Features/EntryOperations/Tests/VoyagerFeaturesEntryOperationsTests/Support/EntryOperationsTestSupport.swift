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

func makeFailingDeleteClient(error: FileOpError) -> EntryFileOpsClient {
    let live = EntryFileOpsClient.liveValue
    return EntryFileOpsClient(
        createFolder: { parentURL, folderName in try await live.createFolder(parentURL, folderName) },
        pasteFile: { sourceURL, destinationURL in try await live.pasteFile(sourceURL, destinationURL) },
        moveFile: { sourceURL, destinationURL in try await live.moveFile(sourceURL, destinationURL) },
        renameFile: { sourceURL, destinationURL in try await live.renameFile(sourceURL, destinationURL) },
        createAlias: { sourceURL, aliasURL in try await live.createAlias(sourceURL, aliasURL) },
        moveToTrashAndReturnURL: { url in try await live.moveToTrashAndReturnURL(url) },
        deleteImmediately: { _ in throw error },
        putBackFromTrash: { trashURL, originalPath in try await live.putBackFromTrash(trashURL, originalPath) },
        compressItems: { urls in try await live.compressItems(urls) },
        extractCompressedFile: { url in try await live.extractCompressedFile(url) },
        getTags: { url in try await live.getTags(url) },
        setTags: { url, tags in try await live.setTags(url, tags) },
        toggleTag: { url, tag in try await live.toggleTag(url, tag) },
        fileExists: { path in live.fileExists(path) },
        saveDragPaths: { _ in },
        loadDragPaths: { [] },
        saveDragWithOption: { _ in },
        loadDragWithOption: { false },
        clipboardChangeCount: { 0 },
        loadClipboardCutSessionId: { nil },
        saveClipboardCutSessionId: { _ in },
        loadClipboardPaths: { ([], .copy) },
        postFileSystemChanged: { _ in },
    )
}

func makeFailingTrashClient(recorder: FileOpsRecorder) -> EntryFileOpsClient {
    let live = EntryFileOpsClient.liveValue
    return EntryFileOpsClient(
        createFolder: { parentURL, folderName in try await live.createFolder(parentURL, folderName) },
        pasteFile: { sourceURL, destinationURL in try await live.pasteFile(sourceURL, destinationURL) },
        moveFile: { sourceURL, destinationURL in try await live.moveFile(sourceURL, destinationURL) },
        renameFile: { sourceURL, destinationURL in try await live.renameFile(sourceURL, destinationURL) },
        createAlias: { sourceURL, aliasURL in try await live.createAlias(sourceURL, aliasURL) },
        moveToTrashAndReturnURL: { _ in throw FileOpError.system(message: "trash unavailable") },
        deleteImmediately: { url in
            try await live.deleteImmediately(url)
            recorder.recordDelete(path: url)
        },
        putBackFromTrash: { trashURL, originalPath in try await live.putBackFromTrash(trashURL, originalPath) },
        compressItems: { urls in try await live.compressItems(urls) },
        extractCompressedFile: { url in try await live.extractCompressedFile(url) },
        getTags: { url in try await live.getTags(url) },
        setTags: { url, tags in try await live.setTags(url, tags) },
        toggleTag: { url, tag in try await live.toggleTag(url, tag) },
        fileExists: { path in live.fileExists(path) },
        saveDragPaths: { _ in },
        loadDragPaths: { [] },
        saveDragWithOption: { _ in },
        loadDragWithOption: { false },
        clipboardChangeCount: { 0 },
        loadClipboardCutSessionId: { nil },
        saveClipboardCutSessionId: { _ in },
        loadClipboardPaths: { ([], .copy) },
        postFileSystemChanged: { _ in },
    )
}

func prepareTrashRecord(sourceURL: URL, trashRoot: URL) throws -> EntryActionRecord {
    try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
    let trashURL = trashRoot.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: trashURL)
    return EntryActionRecord(
        operationKind: .moveToTrash,
        targets: [.init(beforePath: sourceURL.path, afterPath: trashURL.path)],
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
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
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
        let generation = store.state.loadingContext.generation + 1
        await store.send(.loading(.loadItems(path: "/tmp", showHidden: false))) { state in
            state.isLoading = true
            state.loadingContext.generation = generation
            state.loadingContext.expectedCoreBatchIndex = 0
            state.loadingContext.coreFinished = false
            state.loadingContext.streamTerminal = false
            state.loadingContext.isIncomplete = false
            state.loadingContext.sourceKind = .directory
        }
        await store.receive(\.loading.streamEvent, .init(
            generation: generation,
            event: .coreBatch(items: [latestEntry], batchIndex: 0),
        )) { state in
            state.items = [latestEntry]
            state.isLoading = false
            state.isReloading = false
            state.loadingContext.generation = generation
            state.loadingContext.expectedCoreBatchIndex = 1
            state.loadingContext.sourceKind = .directory
        }
        await store.receive(\.loading.streamEvent, .init(
            generation: generation,
            event: .coreFinished(batchCount: 1),
        )) { state in
            state.loadingContext.coreFinished = true
        }
        await store.receive(\.loading.streamFinished, generation) { state in
            state.loadingContext.streamTerminal = true
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
            dependencies.entryLoadingClient.stagedLoadItems = { _, _, _ in
                immediateStagedStream(entries: [latestEntry])
            }
        }
        await store.send(action) { state in
            state.isLoading = true
            switch action {
            case .loading(.loadRecentItems):
                state.loadingContext.generation = 1
                state.loadingContext.sourceKind = .recents
            case .loading(.loadTagItems):
                state.loadingContext.generation = 1
                state.loadingContext.sourceKind = .tags
            case .loading(.loadComputerItems):
                state.loadingContext.generation = 1
            default:
                break
            }
        }
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
                dependencies.entryLoadingClient.stagedLoadRecentItems = { _, _ in
                    delayedStagedStream(gate: gate)
                }
            }
        case .tag:
            await cancelledLoadResult(
                action: .loading(.loadTagItems(tagName: "Blue", showHidden: false)),
                latestEntry: latestEntry,
                staleCompletion: .entries([makeStaleEntry("tag")]),
            ) { dependencies, gate in
                dependencies.entryLoadingClient.stagedLoadFilesWithTag = { _, _, _ in
                    delayedStagedStream(gate: gate)
                }
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

private func immediateStagedStream(entries: [EntryModel]) -> AsyncThrowingStream<EntryLoadEvent, Error> {
    AsyncThrowingStream { continuation in
        if !entries.isEmpty {
            continuation.yield(.coreBatch(items: entries, batchIndex: 0))
        }
        continuation.yield(.coreFinished(batchCount: entries.isEmpty ? 0 : 1))
        continuation.finish()
    }
}

private func delayedStagedStream(
    gate: EntryOperationsLoadSuspensionGate,
) -> AsyncThrowingStream<EntryLoadEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            let entries = await gate.waitForValue()
            if !entries.isEmpty {
                continuation.yield(.coreBatch(items: entries, batchIndex: 0))
            }
            continuation.yield(.coreFinished(batchCount: entries.isEmpty ? 0 : 1))
            continuation.finish()
        }
    }
}
