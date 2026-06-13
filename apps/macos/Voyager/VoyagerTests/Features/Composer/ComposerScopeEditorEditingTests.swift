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

        XCTAssertEqual(store.state.scopeEditor.selection.explicitBases.map(\.path), ["/Users/test/Documents"])
        XCTAssertEqual(store.state.scopeEditor.selection.exceptions.map(\.path), ["/Users/test/Documents/Receipts"])

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

        XCTAssertEqual(store.state.scopeEditor.selection.explicitBases.map(\.path), ["/Users/test/Documents"])
        XCTAssertFalse(store.state.scopeEditor.hasExceptions)
        XCTAssertFalse(
            store.state.scopeEditor.sections()
                .flatMap(\.items)
                .contains { if case .exceptionScope = $0 { true } else { false } },
        )

        await store.finish()
    }
}

@MainActor
extension ComposerScopeEditorEditingTests {
    func testScopeEditorExcludeNoOpsForDirectExcludedPathAndPreservesPresentedContext() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [ComposerScopeException(path: "/Users/test/Documents/Receipts")],
        )
        initialState.scopeEditor.committedSelection = initialState.scopeEditor.selection
        initialState.scopeEditor.includeSubfolders = true
        initialState.scopeEditor.committedIncludeSubfolders = true
        initialState.scopeEditor.editingPath = "/Users/test/Documents"
        initialState.scopeEditor.entryMode = .edit
        initialState.scopeEditor.queryText = "receipts"
        initialState.scopeEditor.listState = .searchResults(query: "receipts")
        initialState.scopeEditor.candidateItems = [
            ComposerScopeEditorCandidateItem(
                path: "/Users/test/Documents/Receipts",
                name: "Receipts",
                iconName: "folder",
            ),
        ]
        initialState.scopes = ["/Users/test/Documents"]
        let store = makePassiveStore(initialState: initialState)

        await store.send(.exceptionScope(.exclude(path: "/Users/test/Documents/Receipts")))

        XCTAssertEqual(store.state.scopeEditor.selection, initialState.scopeEditor.selection)
        XCTAssertEqual(store.state.scopeEditor.committedSelection, initialState.scopeEditor.committedSelection)
        XCTAssertEqual(store.state.scopeEditor.queryText, "receipts")
        XCTAssertEqual(store.state.scopeEditor.listState, .searchResults(query: "receipts"))
        XCTAssertEqual(store.state.scopeEditor.candidateItems, initialState.scopeEditor.candidateItems)
        XCTAssertTrue(store.state.scopeEditor.isPresented)
        XCTAssertEqual(store.state.scopeEditor.editingPath, "/Users/test/Documents")
        XCTAssertEqual(store.state.scopeEditor.entryMode, .edit)
        XCTAssertEqual(store.state.scopes, ["/Users/test/Documents"])
        await store.finish()
    }

    func testScopeEditorExcludeNoOpsWithoutOwningBaseAndSettlesEditorState() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopeEditor.committedSelection = initialState.scopeEditor.selection
        initialState.scopeEditor.includeSubfolders = true
        initialState.scopeEditor.committedIncludeSubfolders = true
        initialState.scopeEditor.editingPath = "/Users/test/Documents"
        initialState.scopeEditor.entryMode = .edit
        initialState.scopeEditor.queryText = ""
        initialState.scopeEditor.listState = .searchResults(query: "stale")
        initialState.scopeEditor.candidateItems = [
            ComposerScopeEditorCandidateItem(path: "/Users/test/Desktop", name: "Desktop", iconName: "folder"),
        ]
        initialState.scopes = ["/Users/test/Documents"]
        let store = makePassiveStore(initialState: initialState)

        await store.send(.exceptionScope(.exclude(path: "/Users/test/Desktop"))) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = "/Users/test/Documents"
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.listState = .childFolders(parentPath: "/Users/test/Documents")
            $0.scopeEditor.candidateItems = []
        }

        XCTAssertEqual(store.state.scopeEditor.selection, initialState.scopeEditor.selection)
        XCTAssertEqual(store.state.scopeEditor.committedSelection, initialState.scopeEditor.committedSelection)
        XCTAssertEqual(store.state.scopeEditor.queryText, "")
        XCTAssertTrue(store.state.scopeEditor.isPresented)
        XCTAssertEqual(store.state.scopeEditor.editingPath, "/Users/test/Documents")
        XCTAssertEqual(store.state.scopeEditor.entryMode, .edit)
        XCTAssertEqual(store.state.scopes, ["/Users/test/Documents"])
        await store.finish()
    }

    func testScopeEditorRestoreNoOpsForUnavailablePathAndSettlesEditorState() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [ComposerScopeException(path: "/Users/test/Documents/Receipts")],
        )
        initialState.scopeEditor.committedSelection = initialState.scopeEditor.selection
        initialState.scopeEditor.includeSubfolders = true
        initialState.scopeEditor.committedIncludeSubfolders = true
        initialState.scopeEditor.editingPath = "/Users/test/Documents"
        initialState.scopeEditor.entryMode = .edit
        initialState.scopeEditor.queryText = ""
        initialState.scopeEditor.listState = .searchResults(query: "stale")
        initialState.scopeEditor.candidateItems = [
            ComposerScopeEditorCandidateItem(path: "/Users/test/Desktop", name: "Desktop", iconName: "folder"),
        ]
        initialState.scopes = ["/Users/test/Documents"]
        let store = makePassiveStore(initialState: initialState)

        await store.send(.exceptionScope(.restore(path: "/Users/test/Desktop"))) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = "/Users/test/Documents"
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.listState = .childFolders(parentPath: "/Users/test/Documents")
            $0.scopeEditor.candidateItems = []
        }

        XCTAssertEqual(store.state.scopeEditor.selection, initialState.scopeEditor.selection)
        XCTAssertEqual(store.state.scopeEditor.committedSelection, initialState.scopeEditor.committedSelection)
        XCTAssertEqual(store.state.scopeEditor.queryText, "")
        XCTAssertTrue(store.state.scopeEditor.isPresented)
        XCTAssertEqual(store.state.scopeEditor.editingPath, "/Users/test/Documents")
        XCTAssertEqual(store.state.scopeEditor.entryMode, .edit)
        XCTAssertEqual(store.state.scopes, ["/Users/test/Documents"])
        await store.finish()
    }
}

@MainActor
private func makePassiveStore(initialState: ComposerState) -> TestStore<ComposerState, ComposerAction> {
    TestStore(initialState: initialState) {
        ComposerFeature()
    } withDependencies: {
        $0.searchClient = .testValue
        $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
    }
}

@MainActor
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
