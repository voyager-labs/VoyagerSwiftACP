import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerShared
import XCTest

@MainActor
final class ComposerScopeEditorQueryDismissApplyTests: XCTestCase { // swiftlint:disable:this type_name
    func testScopeEditorDismissSubmitsSearchForQueryOnlyIncludeSubfoldersChange() async {
        let searchRecorder = QueryDismissSearchRecorder()
        let store = makeQueryOnlyStore(recorder: searchRecorder) { state in
            state.scopeEditor.includeSubfolders = false
            recordScopeChangeFeedback(
                state: &state,
                beforeScope: ComposerScopeSnapshot(
                    scopeSelection: .explicit(
                        bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                        exceptions: [],
                    ),
                    includeSubfolders: true,
                ),
                origin: .includeSubfolders,
            )
        }

        await dismissAndExpectSubmit(
            store: store,
            expectedScopes: ["/Users/test/Documents"],
            expectedIncludeSubfolders: false,
        )

        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .delayed)
        let activeSearchRequestID = try XCTUnwrap(store.state.activeSearchRequestID)
        XCTAssertEqual(store.state.lastScopeChangeFeedback?.pendingResultRequest, .search(activeSearchRequestID))

        let recordedRequest = await searchRecorder.last()
        XCTAssertEqual(recordedRequest?.query, "kind:image")
        XCTAssertEqual(recordedRequest?.filters.scopes, ["/Users/test/Documents"])
        XCTAssertEqual(recordedRequest?.filters.includeSubfolders, false)
        XCTAssertTrue(recordedRequest?.filters.conditions.isEmpty ?? false)
    }

    func testScopeEditorDismissSubmitsSearchForQueryOnlyScopeChange() async {
        let searchRecorder = QueryDismissSearchRecorder()
        let store = makeQueryOnlyStore(recorder: searchRecorder) { state in
            state.scopeEditor.selection = .explicit(
                bases: [
                    ComposerScopeBase(path: "/Users/test/Documents"),
                    ComposerScopeBase(path: "/Users/test/Downloads"),
                ],
                exceptions: [],
            )
            state.scopes = ["/Users/test/Documents", "/Users/test/Downloads"]
            recordScopeChangeFeedback(
                state: &state,
                beforeScope: ComposerScopeSnapshot(
                    scopeSelection: .explicit(
                        bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                        exceptions: [],
                    ),
                    includeSubfolders: true,
                ),
                origin: .addBase,
            )
        }

        await dismissAndExpectSubmit(
            store: store,
            expectedScopes: ["/Users/test/Documents", "/Users/test/Downloads"],
            expectedIncludeSubfolders: true,
        )

        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .delayed)
        let activeSearchRequestID = try XCTUnwrap(store.state.activeSearchRequestID)
        XCTAssertEqual(store.state.lastScopeChangeFeedback?.pendingResultRequest, .search(activeSearchRequestID))

        let recordedRequest = await searchRecorder.last()
        XCTAssertEqual(recordedRequest?.query, "kind:image")
        XCTAssertEqual(recordedRequest?.filters.scopes, ["/Users/test/Documents", "/Users/test/Downloads"])
        XCTAssertEqual(recordedRequest?.filters.includeSubfolders, true)
        XCTAssertTrue(recordedRequest?.filters.conditions.isEmpty ?? false)
    }

    func testScopeEditorDismissCanSubmitAcrossRepeatedOpenCloseCycles() async throws {
        let searchRecorder = QueryDismissSearchRecorder()

        var initialState = ComposerState()
        initialState.collectionContext = CollectionContext(
            query: "kind:image",
            scopes: ["/Users/test/Documents"],
            includeSubfolders: true,
            conditions: [],
        )
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopeEditor.committedSelection = initialState.scopeEditor.selection
        initialState.scopeEditor.includeSubfolders = true
        initialState.scopeEditor.committedIncludeSubfolders = true
        initialState.scopes = ["/Users/test/Documents"]

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.search = { request in
                await searchRecorder.record(request)
                try await Task.sleep(for: .seconds(3600))
                return VoyagerShared.SearchResponsePayload(itemCount: 0)
            }
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }
        store.exhaustivity = .off

        try await performRepeatedCycle(on: store)

        let requests = await searchRecorder.allRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.filters.includeSubfolders), [false, false])
        XCTAssertEqual(requests.map(\.query), ["kind:image", "kind:image"])
    }

    private func makeQueryOnlyStore(
        recorder: QueryDismissSearchRecorder,
        mutate: (inout ComposerState) -> Void,
    ) -> TestStore<ComposerState, ComposerAction> {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopeEditor.committedSelection = initialState.scopeEditor.selection
        initialState.scopes = ["/Users/test/Documents"]
        initialState.collectionContext = CollectionContext(
            query: "kind:image",
            scopes: ["/Users/test/Documents"],
            includeSubfolders: true,
            conditions: [],
        )
        mutate(&initialState)

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.search = { request in
                await recorder.record(request)
                try await Task.sleep(for: .seconds(3600))
                return VoyagerShared.SearchResponsePayload(itemCount: 0)
            }
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }
        store.exhaustivity = .off
        return store
    }

    private func dismissAndExpectSubmit(
        store: TestStore<ComposerState, ComposerAction>,
        expectedScopes: [String],
        expectedIncludeSubfolders: Bool,
    ) async {
        await store.send(.scopeEditorSetPresented(false)) {
            $0.scopeEditor.isPresented = false
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.receive(\.view.submit)

        XCTAssertTrue(store.state.hasSubmittedInSession)
        XCTAssertTrue(store.state.isLoadingSearch)
        XCTAssertFalse(store.state.isLoadingFilters)
        XCTAssertEqual(
            store.state.submittedSearchFilters,
            VoyagerShared.SearchFiltersPayload(
                scopes: expectedScopes,
                includeSubfolders: expectedIncludeSubfolders,
                conditions: [],
            ),
        )
        XCTAssertNotNil(store.state.activeSearchRequestID)
        XCTAssertNil(store.state.activeFiltersRequestID)
        XCTAssertNil(store.state.lastAcceptedSearchRequestID)
        XCTAssertNil(store.state.lastAcceptedFiltersRequestID)
        XCTAssertNil(store.state.lastFiltersResponse)
        XCTAssertEqual(store.state.pendingSearchQuery, "kind:image")
        XCTAssertEqual(store.state.text, "")
    }

    // swiftlint:disable:next function_body_length
    private func performRepeatedCycle(on store: TestStore<ComposerState, ComposerAction>) async throws {
        await store.send(.scopeEditorOpen(editingPath: nil, favorites: [], backHistory: [])) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopeEditor.includeSubfolders = true
            $0.scopeEditor.committedSelection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopeEditor.committedIncludeSubfolders = true
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
            $0.scopeEditor.favorites = []
            $0.scopeEditor.backHistory = []
        }

        await store.send(.scopeEditorSetIncludeSubfolders(false)) {
            $0.scopeEditor.includeSubfolders = false
        }

        await dismissAndExpectSubmit(
            store: store,
            expectedScopes: ["/Users/test/Documents"],
            expectedIncludeSubfolders: false,
        )

        await store.send(.scopeEditorOpen(editingPath: nil, favorites: [], backHistory: [])) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopeEditor.includeSubfolders = true
            $0.scopeEditor.committedSelection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopeEditor.committedIncludeSubfolders = true
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
            $0.scopeEditor.favorites = []
            $0.scopeEditor.backHistory = []
        }

        await store.send(.scopeEditorSetIncludeSubfolders(false)) {
            $0.scopeEditor.includeSubfolders = false
        }

        await dismissAndExpectSubmit(
            store: store,
            expectedScopes: ["/Users/test/Documents"],
            expectedIncludeSubfolders: false,
        )
    }
}

private actor QueryDismissSearchRecorder {
    private var requests: [VoyagerShared.SearchRequestPayload] = []

    func record(_ request: VoyagerShared.SearchRequestPayload) {
        requests.append(request)
    }

    func last() -> VoyagerShared.SearchRequestPayload? {
        requests.last
    }

    func allRequests() -> [VoyagerShared.SearchRequestPayload] {
        requests
    }
}
