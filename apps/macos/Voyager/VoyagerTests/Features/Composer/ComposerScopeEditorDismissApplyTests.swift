import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerShared
import XCTest

@MainActor
final class ComposerScopeEditorDismissApplyTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testScopeEditorDismissReappliesFiltersWhenIncludeSubfoldersChanged() async {
        let applyRecorder = DismissApplyFiltersRecorder()

        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopes = ["/Users/test/Documents"]
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
        initialState.scopeEditor.includeSubfolders = false

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                await applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(
                    itemCount: 0,
                    appliedFilters: VoyagerShared.AppliedFiltersPayload(
                        scopes: request.filters.scopes,
                        includeSubfolders: request.filters.includeSubfolders,
                        conditions: request.filters.conditions,
                    ),
                    items: nil,
                    error: nil,
                )
            }
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }
        store.exhaustivity = .off

        await store.send(.scopeEditorSetPresented(false)) {
            $0.scopeEditor.isPresented = false
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.receive(\.view.applyFilters) {
            $0.isLoadingFilters = true
            $0.isFilteringInFlight = true
            $0.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(
                scopes: ["/Users/test/Documents"],
                includeSubfolders: false,
                conditions: [
                    VoyagerShared.SearchConditionPayload(
                        propertyKey: "name",
                        operator: "contains",
                        value: .string("draft"),
                    ),
                ],
            )
        }

        let recordedRequest = await applyRecorder.last()
        XCTAssertEqual(recordedRequest?.filters.scopes, ["/Users/test/Documents"])
        XCTAssertEqual(recordedRequest?.filters.includeSubfolders, false)
        XCTAssertEqual(recordedRequest?.filters.conditions.count, 1)
    }

    // swiftlint:disable:next function_body_length
    func testScopeEditorDismissReappliesFiltersWhenScopeChanged() async {
        let applyRecorder = DismissApplyFiltersRecorder()

        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopeEditor.committedSelection = initialState.scopeEditor.selection
        initialState.scopes = ["/Users/test/Documents"]
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
            bases: [
                ComposerScopeBase(path: "/Users/test/Documents"),
                ComposerScopeBase(path: "/Users/test/Downloads"),
            ],
            exceptions: [],
        )
        initialState.scopes = ["/Users/test/Documents", "/Users/test/Downloads"]

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                await applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(
                    itemCount: 0,
                    appliedFilters: VoyagerShared.AppliedFiltersPayload(
                        scopes: request.filters.scopes,
                        includeSubfolders: request.filters.includeSubfolders,
                        conditions: request.filters.conditions,
                    ),
                    items: nil,
                    error: nil,
                )
            }
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }
        store.exhaustivity = .off

        await store.send(.scopeEditorSetPresented(false)) {
            $0.scopeEditor.isPresented = false
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.receive(\.view.applyFilters) {
            $0.isLoadingFilters = true
            $0.isFilteringInFlight = true
            $0.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(
                scopes: ["/Users/test/Documents", "/Users/test/Downloads"],
                includeSubfolders: true,
                conditions: [
                    VoyagerShared.SearchConditionPayload(
                        propertyKey: "name",
                        operator: "contains",
                        value: .string("draft"),
                    ),
                ],
            )
        }

        let recordedRequest = await applyRecorder.last()
        XCTAssertEqual(recordedRequest?.filters.scopes, ["/Users/test/Documents", "/Users/test/Downloads"])
        XCTAssertEqual(recordedRequest?.filters.includeSubfolders, true)
        XCTAssertEqual(recordedRequest?.filters.conditions.count, 1)
    }
}

private actor DismissApplyFiltersRecorder {
    private var requests: [VoyagerShared.FiltersOnlyRequestPayload] = []

    func record(_ request: VoyagerShared.FiltersOnlyRequestPayload) {
        requests.append(request)
    }

    func last() -> VoyagerShared.FiltersOnlyRequestPayload? {
        requests.last
    }
}
