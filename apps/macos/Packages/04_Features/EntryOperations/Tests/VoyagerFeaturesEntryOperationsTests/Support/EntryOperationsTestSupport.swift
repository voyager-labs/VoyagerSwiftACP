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

private actor OpenWithCommandCompletionGate {
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var started: Set<String> = []

    func wait(_ path: String) async {
        started.insert(path)
        await withCheckedContinuation { waiters[path] = $0 }
    }

    func resume(_ path: String) {
        waiters.removeValue(forKey: path)?.resume()
    }

    func isStarted(_ path: String) -> Bool {
        started.contains(path)
    }
}

struct OpenWithCommandEvidence {
    let openStartedPaths: [String]
    let openFinishedPaths: [String]
    let defaultFinishedPaths: [String]
    let terminals: [EntryActionRecord]
    let setDefaultCallCount: Int
    let reloadCallCount: Int
    let openCallCount: Int
    let batchActionCount: Int
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

    static func runOpenWithCommand(
        files: [EntryModel],
        currentPath: String,
        bundleID: String,
        metadata: EntryCommandMetadata,
        shouldSetAsDefault: Bool = false,
        failingPath: String? = nil,
        completionOrder: [String] = [],
        usesOtherPicker: Bool = false,
        cancelsOtherPicker: Bool = false,
        trashPath: String? = nil,
    ) async -> OpenWithCommandEvidence {
        let gate = OpenWithCommandCompletionGate()
        let actions = LockIsolated<[EntryOperationsAction]>([])
        let (setDefaultCalls, reloadCalls, openCalls) = (LockIsolated(0), LockIsolated(0), LockIsolated(0))
        let store = makeObservedStore(
            observeAction: { action in actions.withValue { $0.append(action) } },
            configure: {
                $0.entryOpenClient.trashDirectoryPath = { trashPath }
                $0.entryOpenClient.setDefaultApp = { _, _ in setDefaultCalls.withValue { $0 += 1 } }
                $0.entryOpenClient.invalidateApplicationsForType = { _ in }
                $0.entryOpenClient.applicationsForType = { _, _ in
                    reloadCalls.withValue { $0 += 1 }
                    return []
                }
                $0.entryOpenClient.defaultApplication = { _ in nil }
                $0.entryOpenClient.open = { url, _ in
                    openCalls.withValue { $0 += 1 }
                    if !completionOrder.isEmpty {
                        await gate.wait(url.path)
                    }
                    if url.path == failingPath {
                        throw FileOpError.system(message: "open denied")
                    }
                }
                if usesOtherPicker {
                    $0.openWithPanelClient.selectApplication = { _, _, _ in
                        if cancelsOtherPicker { return nil }
                        return OpenWithPanelSelection(bundleID: bundleID, setAsDefault: shouldSetAsDefault)
                    }
                }
            },
        )
        // store.exhaustivity = .off: observer와 dependency recorder가 전체 command lifecycle을 검증한다.
        store.exhaustivity = .off

        let command = EntryOperationsNavigationCommand.openWithSelectedItem(
            bundleID: usesOtherPicker ? nil : bundleID,
            shouldSetAsDefault: shouldSetAsDefault,
        )
        let context = EntryOperationsCommandContext(
            selectedIds: Set(files.map(\.id)),
            displayItems: files,
            currentPath: currentPath,
        )
        await store.send(.routing(.executeCommand(command: .navigation(command), context: context, metadata: metadata)))
        await completeOpenWithCommand(store, gate: gate, completionOrder: completionOrder)

        return makeOpenWithEvidence(
            actions: actions.value,
            bundleID: bundleID,
            setDefaultCallCount: setDefaultCalls.value,
            reloadCallCount: reloadCalls.value,
            openCallCount: openCalls.value,
        )
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
            state.loadingContext.directoryPath = "/tmp"
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
            state.loadingContext.acceptedCoreFinishedGeneration = generation
        }
        await store.receive(\.loading.streamFinished, generation) { state in
            state.loadingContext.streamTerminal = true
        }
        await store.receive(\.lifecycle.restorableTrashPathsLoaded)
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

    private static func completeOpenWithCommand(
        _ store: TestStore<EntryOperationsFeature.State, EntryOperationsFeature.Action>,
        gate: OpenWithCommandCompletionGate,
        completionOrder: [String],
    ) async {
        for path in completionOrder {
            while await !gate.isStarted(path) {
                await Task.yield()
            }
        }
        for path in completionOrder {
            await gate.resume(path)
            await Task.yield()
        }
        await store.finish()
        await store.skipReceivedActions()
    }

    private static func makeOpenWithEvidence(
        actions: [EntryOperationsAction],
        bundleID: String,
        setDefaultCallCount: Int,
        reloadCallCount: Int,
        openCallCount: Int,
    ) -> OpenWithCommandEvidence {
        let openStartedPaths = actions.compactMap { action -> String? in
            guard case let .lifecycle(.operationStarted(path, .openWithApp(id))) = action,
                  id == bundleID
            else { return nil }
            return path
        }
        let openFinishedPaths = actions.compactMap { action -> String? in
            guard case let .lifecycle(.operationFinished(path, .openWithApp(id), _)) = action,
                  id == bundleID
            else { return nil }
            return path
        }
        let defaultFinishedPaths = actions.compactMap { action -> String? in
            guard case let .lifecycle(.operationFinished(path, .setDefaultApp(id), .success)) = action,
                  id == bundleID
            else { return nil }
            return path
        }
        let terminals = actions.compactMap { action -> EntryActionRecord? in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return nil }
            return record
        }
        let batchActionCount = actions.reduce(into: 0) { count, action in
            guard case .acceptedCommand(_, .openWith(.openFilesWithAppBundleID)) = action else { return }
            count += 1
        }
        return OpenWithCommandEvidence(
            openStartedPaths: openStartedPaths,
            openFinishedPaths: openFinishedPaths,
            defaultFinishedPaths: defaultFinishedPaths,
            terminals: terminals,
            setDefaultCallCount: setDefaultCallCount,
            reloadCallCount: reloadCallCount,
            openCallCount: openCallCount,
            batchActionCount: batchActionCount,
        )
    }

    private static func makeStaleEntry(_ suffix: String) -> EntryModel {
        EntryModelFixtures.makeFileEntry(
            id: "/tmp/stale-\(suffix).txt",
            name: "stale-\(suffix).txt",
        )
    }
}

func immediateStagedStream(entries: [EntryModel]) -> AsyncThrowingStream<EntryLoadEvent, Error> {
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
