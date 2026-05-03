import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerShared
import XCTest

@MainActor
final class ComposerScopeEditorEditingTests: XCTestCase {
    func testScopeEditorAddDoesNotReapplyFiltersWhileEditingEvenForReadyCondition() async {
        let applyRecorder = EditingApplyFiltersRecorder()

        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.conditions = [
            Condition(
                propertyKey: "name",
                propertyLabel: "Name",
                propertyType: "string",
                operatorCode: "contains",
                operatorLabel: "Contains",
                operatorValueArity: 1,
                operatorValueUIKind: "text",
                valueType: "string",
                values: ["draft"],
                isActive: true,
            ),
        ]
        initialState.collectionContext = CollectionContext(
            query: "draft",
            scopes: ["/Users/test/Documents"],
            includeSubfolders: true,
            conditions: initialState.conditions,
        )
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopeEditor.committedSelection = initialState.scopeEditor.selection
        initialState.scopes = ["/Users/test/Documents"]

        let store = makeEditingStore(initialState: initialState, recorder: applyRecorder)

        await store.send(.addScope(path: "/Users/test/Downloads")) {
            $0.scopeEditor.selection = .explicit(
                bases: [
                    ComposerScopeBase(path: "/Users/test/Documents"),
                    ComposerScopeBase(path: "/Users/test/Downloads"),
                ],
                exceptions: [],
            )
            $0.scopes = ["/Users/test/Documents", "/Users/test/Downloads"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        let recordedRequest = await applyRecorder.last()
        XCTAssertNil(recordedRequest)
        await store.finish()
    }

    func testScopeEditorOpenInEditModeShowsDirectChildFolders() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let parentURL = temporaryRoot.appendingPathComponent("Parent", isDirectory: true)
        let archiveURL = parentURL.appendingPathComponent("Archive", isDirectory: true)
        let receiptsURL = parentURL.appendingPathComponent("Receipts", isDirectory: true)
        let fileURL = parentURL.appendingPathComponent("note.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: receiptsURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        var initialState = ComposerState()
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: parentURL.path)],
            exceptions: [],
        )
        initialState.scopeEditor.isPresented = true

        var entryLoadingClient = EntryLoadingClient.testValue
        entryLoadingClient.contentsOfDirectory = { url, keys, options in
            try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: options,
            )
        }
        entryLoadingClient.displayName = { ($0 as NSString).lastPathComponent }
        entryLoadingClient.homeDirectory = { temporaryRoot.path }

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = entryLoadingClient
        }

        await store.send(.scopeEditorOpen(editingPath: parentURL.path, favorites: [], backHistory: [])) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = parentURL.path
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .childFolders(parentPath: parentURL.path)
            $0.scopeEditor.candidateItems = [
                ComposerScopeEditorCandidateItem(
                    path: archiveURL.path,
                    name: "Archive",
                    iconName: "folder",
                    locationIdentifier: parentURL.path,
                ),
                ComposerScopeEditorCandidateItem(
                    path: receiptsURL.path,
                    name: "Receipts",
                    iconName: "folder",
                    locationIdentifier: parentURL.path,
                ),
            ]
            $0.scopeEditor.favorites = []
            $0.scopeEditor.backHistory = []
        }

        XCTAssertEqual(
            store.state.scopeEditor.candidateSelectionIntent(for: receiptsURL.path),
            .exclude(path: receiptsURL.path),
        )
        await store.finish()
    }

    func testScopeEditorRetappingEditingTargetReturnsToAddMode() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.editingPath = "/Users/test/Documents"
        initialState.scopeEditor.entryMode = .edit
        initialState.scopeEditor.queryText = "docs"
        initialState.scopeEditor.listState = .searchResults(query: "docs")

        let store = makePassiveStore(initialState: initialState)

        await store.send(.scopeEditorOpen(editingPath: nil, favorites: [], backHistory: [])) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    // swiftlint:disable:next function_body_length
    func testScopeEditorOpenPreservesPendingScopeRuleWhenAlreadyPresented() async {
        var initialState = ComposerState()
        initialState.collectionContext = CollectionContext(
            query: "",
            scopes: ["/Users/test/Documents"],
            includeSubfolders: true,
            conditions: [],
        )
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [
                ComposerScopeBase(path: "/Users/test/Documents"),
                ComposerScopeBase(path: "/Users/test/Downloads"),
            ],
            exceptions: [],
        )
        initialState.scopeEditor.committedSelection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopeEditor.includeSubfolders = false
        initialState.scopeEditor.committedIncludeSubfolders = true
        initialState.scopeEditor.editingPath = nil
        initialState.scopeEditor.entryMode = .add
        initialState.scopeEditor.queryText = "down"
        initialState.scopeEditor.listState = .searchResults(query: "down")
        initialState.scopes = ["/Users/test/Documents", "/Users/test/Downloads"]

        let store = makePassiveStore(initialState: initialState)

        await store.send(
            .scopeEditorOpen(editingPath: "/Users/test/Downloads", favorites: [], backHistory: []),
        ) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = "/Users/test/Downloads"
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.selection = .explicit(
                bases: [
                    ComposerScopeBase(path: "/Users/test/Documents"),
                    ComposerScopeBase(path: "/Users/test/Downloads"),
                ],
                exceptions: [],
            )
            $0.scopeEditor.committedSelection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopeEditor.includeSubfolders = false
            $0.scopeEditor.committedIncludeSubfolders = true
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .childFolders(parentPath: "/Users/test/Downloads")
            $0.scopeEditor.candidateItems = []
            $0.scopeEditor.favorites = []
            $0.scopeEditor.backHistory = []
        }

        await store.finish()
    }

    func testScopeEditorAddFromRootOnlyCreatesExplicitScopeAndKeepsPopoverOpen() async {
        var initialState = ComposerState()
        initialState.collectionContext = CollectionContext(
            query: "",
            scopes: [ComposerScopeUtils.rootScopePath],
            includeSubfolders: true,
            conditions: [],
        )
        initialState.scopeEditor.selection = .rootOnly
        initialState.scopeEditor.committedSelection = .rootOnly
        initialState.scopes = [ComposerScopeUtils.rootScopePath]
        initialState.scopeEditor.isPresented = true

        let store = makePassiveStore(initialState: initialState)

        await store.send(.addScope(path: "/Users/test/Documents")) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopes = ["/Users/test/Documents"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorRemoveKeepsPopoverOpenAndEditMode() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [
                ComposerScopeBase(path: "/Users/test/Documents"),
                ComposerScopeBase(path: "/Users/test/Downloads"),
            ],
            exceptions: [],
        )
        initialState.scopeEditor.editingPath = "/Users/test/Documents"
        initialState.scopeEditor.entryMode = .edit
        initialState.scopes = ["/Users/test/Documents", "/Users/test/Downloads"]

        let store = makePassiveStore(initialState: initialState)

        await store.send(.removeScope(path: "/Users/test/Downloads")) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopes = ["/Users/test/Documents"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = "/Users/test/Documents"
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.listState = .childFolders(parentPath: "/Users/test/Documents")
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorReplaceContinuesEditingTargetWithNewPath() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopeEditor.editingPath = "/Users/test/Documents"
        initialState.scopeEditor.entryMode = .edit
        initialState.scopes = ["/Users/test/Documents"]

        let store = makePassiveStore(initialState: initialState)

        await store.send(.updateScope(oldPath: "/Users/test/Documents", newPath: "/Users/test/Desktop")) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Desktop")],
                exceptions: [],
            )
            $0.scopes = ["/Users/test/Desktop"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = "/Users/test/Desktop"
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.listState = .childFolders(parentPath: "/Users/test/Desktop")
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorReplacePreservesNestedExplicitScopes() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [
                ComposerScopeBase(path: "/Users/test/Documents"),
                ComposerScopeBase(path: "/Users/test/Downloads"),
            ],
            exceptions: [],
        )
        initialState.scopeEditor.editingPath = "/Users/test/Downloads"
        initialState.scopeEditor.entryMode = .edit
        initialState.scopes = ["/Users/test/Documents", "/Users/test/Downloads"]

        let store = makePassiveStore(initialState: initialState)

        await store.send(.updateScope(oldPath: "/Users/test/Downloads", newPath: "/Users/test/Documents/Receipts")) {
            $0.scopeEditor.selection = .explicit(
                bases: [
                    ComposerScopeBase(path: "/Users/test/Documents"),
                    ComposerScopeBase(path: "/Users/test/Documents/Receipts"),
                ],
                exceptions: [],
            )
            $0.scopes = ["/Users/test/Documents", "/Users/test/Documents/Receipts"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = "/Users/test/Documents/Receipts"
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.listState = .childFolders(parentPath: "/Users/test/Documents/Receipts")
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorExcludeAddsExceptionWithoutDroppingBase() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopeEditor.committedSelection = initialState.scopeEditor.selection
        initialState.scopeEditor.includeSubfolders = true
        initialState.scopeEditor.committedIncludeSubfolders = true
        initialState.scopes = ["/Users/test/Documents"]

        let store = makePassiveStore(initialState: initialState)

        await store.send(.exceptionScope(.exclude(path: "/Users/test/Documents/Receipts"))) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [ComposerScopeException(path: "/Users/test/Documents/Receipts")],
            )
            $0.scopes = ["/Users/test/Documents"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorRestoreRemovesExceptionWithoutDroppingBase() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [ComposerScopeException(path: "/Users/test/Documents/Receipts")],
        )
        initialState.scopeEditor.committedSelection = initialState.scopeEditor.selection
        initialState.scopeEditor.includeSubfolders = true
        initialState.scopeEditor.committedIncludeSubfolders = true
        initialState.scopes = ["/Users/test/Documents"]

        let store = makePassiveStore(initialState: initialState)

        await store.send(.exceptionScope(.restore(path: "/Users/test/Documents/Receipts"))) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopes = ["/Users/test/Documents"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }
}

private func makePassiveStore(initialState: ComposerState) -> TestStore<ComposerState, ComposerAction> {
    TestStore(initialState: initialState) {
        ComposerFeature()
    } withDependencies: {
        $0.searchClient = .testValue
        $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
    }
}

private func makeEditingStore(
    initialState: ComposerState,
    recorder: EditingApplyFiltersRecorder,
) -> TestStore<ComposerState, ComposerAction> {
    TestStore(initialState: initialState) {
        ComposerFeature()
    } withDependencies: {
        $0.searchClient.applyFilters = { request in
            await recorder.record(request)
            return VoyagerShared.SearchResponsePayload(itemCount: 0)
        }
        $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
    }
}

private actor EditingApplyFiltersRecorder {
    private var requests: [VoyagerShared.FiltersOnlyRequestPayload] = []

    func record(_ request: VoyagerShared.FiltersOnlyRequestPayload) {
        requests.append(request)
    }

    func last() -> VoyagerShared.FiltersOnlyRequestPayload? {
        requests.last
    }
}
