import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import XCTest

@MainActor
final class RCL001DefineCollectionScopeTests: XCTestCase {
    // MARK: - RCL-001-open_collection_scope_menu

    /// RCL-001-open_collection_scope_menu: scope menu presentation은 app/menu layer 소유
    /// Composer package는 scope editor state open을 검증하고 menu UI trigger 자체는 app-focused로 분리한다.
    /// - 검증 내용: menu presentation boundary 명시
    /// - 사전 조건: `open_collection_filter_composer`가 reducer state open을 검증함
    /// - 기대 결과: menu command-to-action wiring은 app-focused spec-owner suite에서 검증 필요
    func testOpenCollectionScopeMenu_requiresAppMenuFocusedSuite() throws {
        throw XCTSkip(
            "Scope menu presentation is app/menu-layer owned; Composer package verifies scope editor state only.",
        )
    }

    // MARK: - RCL-001-open_collection_filter_composer

    /// RCL-001-open_collection_filter_composer: Composer open은 기존 scope draft를 유지
    /// filter composer를 열 때 committed collection base scope가 scope editor draft로 seed되는지 검증한다.
    /// - 검증 내용: presented 상태, base selection, includeSubfolders, query draft 유지 확인
    /// - 사전 조건: collectionContext에 기존 scope와 query가 있음
    /// - 기대 결과: scope editor가 열리고 기존 scope 의미가 draft로 복원됨
    func testOpenCollectionFilterComposer_withCommittedScope_seedsCurrentDraft() {
        var state = ComposerState()
        state.collectionContext = CollectionContext(
            query: "report",
            scopes: ["/VoyagerFixtures/Documents"],
            excludedScopes: ["/VoyagerFixtures/Documents/Archive"],
            includeSubfolders: false,
            conditions: [],
        )

        reduce(&state, .scopeEditorOpen(editingPath: nil, favorites: [], backHistory: []))

        XCTAssertTrue(state.scopeEditor.isPresented)
        XCTAssertEqual(state.scopeEditor.selection.explicitBases.map(\.path), ["/VoyagerFixtures/Documents"])
        XCTAssertEqual(state.scopeEditor.selection.exceptions.map(\.path), [])
        XCTAssertFalse(state.scopeEditor.includeSubfolders)
        XCTAssertEqual(state.collectionContext?.query, "report")
    }

    // MARK: - RCL-001-collapse_collection_filter_composer

    /// RCL-001-collapse_collection_filter_composer: Composer collapse는 scope draft를 폐기하지 않음
    /// 열린 scope editor를 접어도 선택한 scope draft와 include-subfolders 값이 유지되는지 검증한다.
    /// - 검증 내용: presented만 false로 바뀌고 selection/includeSubfolders가 보존되는지 확인
    /// - 사전 조건: scope editor가 열린 상태에서 명시적 scope와 includeSubfolders=false가 선택됨
    /// - 기대 결과: 다시 열 수 있는 draft 상태가 유지됨
    func testCollapseCollectionFilterComposer_preservesScopeDraft() {
        var state = makeScopeState(
            bases: ["/VoyagerFixtures/Documents"],
            exceptions: [],
            includeSubfolders: false,
        )
        state.scopeEditor.isPresented = true

        reduce(&state, .scopeEditorSetPresented(false))

        XCTAssertFalse(state.scopeEditor.isPresented)
        XCTAssertEqual(state.scopeEditor.selection.explicitBases.map(\.path), ["/VoyagerFixtures/Documents"])
        XCTAssertFalse(state.scopeEditor.includeSubfolders)
    }

    // MARK: - RCL-001-add_directory_to_collection_scope

    /// RCL-001-add_directory_to_collection_scope: 첫 명시적 directory 추가는 single explicit scope가 됨
    /// root-only 상태에서 candidate directory를 추가하면 summary가 단일 명시 scope로 전환되는지 검증한다.
    /// - 검증 내용: selection bases, summary primary, undo history, feedback origin 확인
    /// - 사전 조건: root-only scope editor draft
    /// - 기대 결과: 선택 directory가 base scope가 되고 undo 가능한 history가 생성됨
    func testAddDirectoryToCollectionScope_fromRootOnly_createsSingleExplicitScope() {
        var state = ComposerState()

        reduce(&state, .addScope(path: "/VoyagerFixtures/Documents"))

        XCTAssertEqual(state.scopeEditor.selection.explicitBases.map(\.path), ["/VoyagerFixtures/Documents"])
        XCTAssertEqual(state.scopeEditor.summary.primary, .singleExplicit(path: "/VoyagerFixtures/Documents"))
        XCTAssertTrue(state.canUndo)
        XCTAssertEqual(state.lastScopeChangeFeedback?.origin, .addBase)
    }

    /// RCL-001-add_directory_to_collection_scope: 추가 directory는 multi explicit scope로 확장
    /// 이미 명시적 scope가 있을 때 다른 directory를 추가하면 multi scope summary가 되는지 검증한다.
    /// - 검증 내용: 두 개 base scope와 multi summary count 확인
    /// - 사전 조건: `/VoyagerFixtures/Documents`가 이미 선택된 scope editor draft
    /// - 기대 결과: 기존 scope를 유지하면서 새 directory가 추가됨
    func testAddDirectoryToCollectionScope_withExistingBase_expandsToMultiExplicitScope() {
        var state = makeScopeState(bases: ["/VoyagerFixtures/Documents"])

        reduce(&state, .addScope(path: "/VoyagerFixtures/Notes"))

        XCTAssertEqual(
            state.scopeEditor.selection.explicitBases.map(\.path),
            ["/VoyagerFixtures/Documents", "/VoyagerFixtures/Notes"],
        )
        XCTAssertEqual(state.scopeEditor.summary.primary, .multiExplicit(count: 2))
        XCTAssertEqual(state.lastScopeChangeFeedback?.origin, .addBase)
    }

    // MARK: - RCL-001-remove_directory_from_collection_scope

    /// RCL-001-remove_directory_from_collection_scope: 명시적 directory 제거는 남은 scope 의미를 재계산
    /// multi explicit scope에서 하나를 제거하면 나머지 scope와 summary가 유지되는지 검증한다.
    /// - 검증 내용: 제거 대상만 사라지고 남은 scope가 single explicit summary가 되는지 확인
    /// - 사전 조건: 두 개 명시적 scope가 선택된 scope editor draft
    /// - 기대 결과: 제거하지 않은 scope와 feedback origin이 유지됨
    func testRemoveDirectoryFromCollectionScope_fromMultiExplicit_keepsRemainingScope() {
        var state = makeScopeState(bases: ["/VoyagerFixtures/Documents", "/VoyagerFixtures/Notes"])

        reduce(&state, .removeScope(path: "/VoyagerFixtures/Documents"))

        XCTAssertEqual(state.scopeEditor.selection.explicitBases.map(\.path), ["/VoyagerFixtures/Notes"])
        XCTAssertEqual(state.scopeEditor.summary.primary, .singleExplicit(path: "/VoyagerFixtures/Notes"))
        XCTAssertEqual(state.lastScopeChangeFeedback?.origin, .removeBase)
    }

    // MARK: - RCL-001-exclude_directory_from_collection_scope

    /// RCL-001-exclude_directory_from_collection_scope: 기준 scope 하위 directory 제외는 exception 상태가 됨
    /// 선택된 base scope 아래 directory를 제외하면 exception list와 summary badge에 반영되는지 검증한다.
    /// - 검증 내용: excluded scope, summary badge, feedback origin 확인
    /// - 사전 조건: `/VoyagerFixtures/Documents` base scope가 include-subfolders 모드로 선택됨
    /// - 기대 결과: archive directory가 exception으로 추가되고 summary에 1 exception이 표시됨
    func testExcludeDirectoryFromCollectionScope_withDescendant_addsException() {
        var state = makeScopeState(bases: ["/VoyagerFixtures/Documents"])

        reduce(&state, .excludeScope(path: "/VoyagerFixtures/Documents/Archive"))

        XCTAssertEqual(state.scopeEditor.selection.exceptions.map(\.path), ["/VoyagerFixtures/Documents/Archive"])
        XCTAssertEqual(state.scopeEditor.summary.badges, [.exceptionCount(1)])
        XCTAssertEqual(state.lastScopeChangeFeedback?.origin, .exclude)
    }

    // MARK: - RCL-001-restore_directory_to_collection_scope

    /// RCL-001-restore_directory_to_collection_scope: exception restore는 선택한 제외 directory만 복원
    /// exception list에서 하나를 restore하면 해당 path만 excluded scope 목록에서 제거되는지 검증한다.
    /// - 검증 내용: 선택 exception 제거와 다른 exception 유지 여부 확인
    /// - 사전 조건: 두 개 exception이 있는 명시적 scope draft
    /// - 기대 결과: restore 대상만 사라지고 feedback origin은 restore임
    func testRestoreDirectoryToCollectionScope_removesOnlySelectedException() {
        var state = makeScopeState(
            bases: ["/VoyagerFixtures/Documents"],
            exceptions: ["/VoyagerFixtures/Documents/Archive", "/VoyagerFixtures/Documents/Temp"],
        )

        reduce(&state, .restoreScope(path: "/VoyagerFixtures/Documents/Archive"))

        XCTAssertEqual(state.scopeEditor.selection.exceptions.map(\.path), ["/VoyagerFixtures/Documents/Temp"])
        XCTAssertEqual(state.lastScopeChangeFeedback?.origin, .restore)
    }

    // MARK: - RCL-001-toggle_collection_scope_subfolder_inclusion

    /// RCL-001-toggle_collection_scope_subfolder_inclusion: include-subfolders toggle은 summary 보조 문구를 갱신
    /// 하위 폴더 포함 설정을 끄면 exact folder mode summary로 바뀌는지 검증한다.
    /// - 검증 내용: includeSubfolders, effective mode, summary secondary item 확인
    /// - 사전 조건: 단일 explicit scope가 include-subfolders=true로 선택됨
    /// - 기대 결과: includeSubfolders=false가 되고 summary는 only selected folder가 됨
    func testToggleCollectionScopeSubfolderInclusion_toFalse_updatesSummary() {
        var state = makeScopeState(bases: ["/VoyagerFixtures/Documents"], includeSubfolders: true)

        reduce(&state, .scopeEditorSetIncludeSubfolders(false))

        XCTAssertFalse(state.scopeEditor.includeSubfolders)
        XCTAssertTrue(state.scopeEditor.isExactFolderOnlyMode)
        XCTAssertEqual(state.scopeEditor.summary.secondaryItems, [.onlySelectedFolder])
        XCTAssertEqual(state.lastScopeChangeFeedback?.origin, .includeSubfolders)
    }

    // MARK: - RCL-001-search_collection_scope_candidates

    /// RCL-001-search_collection_scope_candidates: candidate 검색 응답은 query와 일치할 때만 목록을 갱신
    /// scope candidate 검색 결과가 현재 query와 일치할 때 search result list로 표시되는지 검증한다.
    /// - 검증 내용: listState, candidateItems, candidate path/name 확인
    /// - 사전 조건: scope editor가 열려 있고 query text가 `doc`으로 설정됨
    /// - 기대 결과: 검색 결과 candidate가 addable item으로 노출됨
    func testSearchCollectionScopeCandidates_withMatchingQuery_updatesCandidateResults() {
        var state = ComposerState()
        state.scopeEditor.isPresented = true
        state.scopeEditor.queryText = "doc"

        reduce(
            &state,
            .internal(.scopeEditorSearchResponse("doc", .success([
                .init(
                    id: "/VoyagerFixtures/Documents",
                    path: "/VoyagerFixtures/Documents",
                    name: "Documents",
                    iconName: "folder",
                ),
            ]))),
        )

        XCTAssertEqual(state.scopeEditor.listState, .searchResults(query: "doc"))
        XCTAssertEqual(state.scopeEditor.candidateItems.map(\.path), ["/VoyagerFixtures/Documents"])
        XCTAssertEqual(state.scopeEditor.candidateItems.first?.name, "Documents")
    }

    // MARK: - RCL-001-show_collection_scope_candidate_disambiguation

    /// RCL-001-show_collection_scope_candidate_disambiguation: 동일 이름 candidate는 위치 식별자를 보존
    /// 검색 결과의 locationIdentifier가 candidate item에 유지되어 disambiguation에 사용할 수 있는지 검증한다.
    /// - 검증 내용: candidate item의 locationIdentifier 보존 확인
    /// - 사전 조건: 동일 이름 directory 후보가 서로 다른 locationIdentifier로 반환됨
    /// - 기대 결과: 두 candidate가 같은 이름이어도 위치 식별자를 잃지 않음
    func testShowCollectionScopeCandidateDisambiguation_preservesLocationIdentifier() {
        var state = ComposerState()
        state.scopeEditor.isPresented = true
        state.scopeEditor.queryText = "Reports"

        reduce(
            &state,
            .internal(.scopeEditorSearchResponse("Reports", .success([
                .init(id: "1", path: "/A/Reports", name: "Reports", iconName: "folder", locationIdentifier: "A"),
                .init(id: "2", path: "/B/Reports", name: "Reports", iconName: "folder", locationIdentifier: "B"),
            ]))),
        )

        XCTAssertEqual(state.scopeEditor.candidateItems.map(\.name), ["Reports", "Reports"])
        XCTAssertEqual(state.scopeEditor.candidateItems.map(\.locationIdentifier), ["A", "B"])
    }

    // MARK: - RCL-001-show_collection_scope_change_feedback

    /// RCL-001-show_collection_scope_change_feedback: scope 변경 직후 feedback snapshot이 기록됨
    /// scope 변경 feedback이 before/after scope 의미와 history depth를 함께 보존하는지 검증한다.
    /// - 검증 내용: feedback before/after, phase, history depth 확인
    /// - 사전 조건: root-only 상태에서 scope를 추가함
    /// - 기대 결과: visible feedback이 생성되고 undo 가능한 history depth와 일치함
    func testShowCollectionScopeChangeFeedback_afterScopeChange_recordsBeforeAndAfter() {
        var state = ComposerState()

        reduce(&state, .addScope(path: "/VoyagerFixtures/Documents"))

        XCTAssertEqual(state.lastScopeChangeFeedback?.phase, .visible)
        XCTAssertEqual(state.lastScopeChangeFeedback?.beforeScope.scopeSelection, .rootOnly)
        XCTAssertEqual(
            state.lastScopeChangeFeedback?.afterScope.scopeSelection.explicitBases.map(\.path),
            ["/VoyagerFixtures/Documents"],
        )
        XCTAssertEqual(state.lastScopeChangeFeedback?.historyDepthAfterCommit, state.history.count)
    }

    // MARK: - RCL-001-show_collection_scope_exceptions

    /// RCL-001-show_collection_scope_exceptions: exception list는 owning base와 함께 노출됨
    /// scope editor sections가 excluded directory를 exception row로 표시하는지 검증한다.
    /// - 검증 내용: sections 안의 exceptionScope item과 owningBasePath 확인
    /// - 사전 조건: base scope 아래 exception이 있는 scope editor draft
    /// - 기대 결과: exception row가 생성되고 owning base path가 보존됨
    func testShowCollectionScopeExceptions_sectionsExposeExceptionRows() throws {
        let state = makeScopeState(
            bases: ["/VoyagerFixtures/Documents"],
            exceptions: ["/VoyagerFixtures/Documents/Archive"],
        )

        let exceptionItem = try XCTUnwrap(state.scopeEditor.sections().flatMap(\.items).compactMap { item in
            if case let .exceptionScope(exception) = item { return exception }
            return nil
        }.first)

        XCTAssertEqual(exceptionItem.path, "/VoyagerFixtures/Documents/Archive")
        XCTAssertEqual(exceptionItem.owningBasePath, "/VoyagerFixtures/Documents")
    }

    // MARK: - RCL-001-show_collection_scope_summary

    /// RCL-001-show_collection_scope_summary: scope summary는 base count와 exception badge를 표시
    /// multi explicit scope와 exception이 있을 때 summary payload가 현재 scope 의미를 반영하는지 검증한다.
    /// - 검증 내용: primary, secondary, badge text/accessibility text 확인
    /// - 사전 조건: 두 개 base scope와 하나의 exception이 있는 scope draft
    /// - 기대 결과: 2 scopes, include subfolders, 1 exception summary가 계산됨
    func testShowCollectionScopeSummary_withMultiScopeAndException_describesCurrentScope() {
        let state = makeScopeState(
            bases: ["/VoyagerFixtures/Documents", "/VoyagerFixtures/Notes"],
            exceptions: ["/VoyagerFixtures/Documents/Archive"],
        )

        XCTAssertEqual(state.scopeEditor.summary.primary, .multiExplicit(count: 2))
        XCTAssertEqual(state.scopeEditor.summary.secondaryItems, [.includeSubfolders])
        XCTAssertEqual(state.scopeEditor.summary.badgeText, "1 exception")
        XCTAssertEqual(state.scopeEditor.summary.accessibilityText, "2 Scopes, Include subfolders, 1 exception")
    }

    // MARK: - RCL-001-undo_collection_filter_changes

    /// RCL-001-undo_collection_filter_changes: undo는 직전 scope 변경 1건만 되돌림
    /// directory 추가 직후 undo하면 root-only scope로 복원되고 redo history가 생기는지 검증한다.
    /// - 검증 내용: selection, history, redoHistory 확인
    /// - 사전 조건: scope 추가로 history가 1건 생성된 상태
    /// - 기대 결과: root-only로 복원되고 redo 가능한 snapshot이 남음
    func testUndoCollectionFilterChanges_afterAddScope_restoresPreviousScope() {
        var state = ComposerState()
        reduce(&state, .addScope(path: "/VoyagerFixtures/Documents"))

        reduce(&state, .undo)

        XCTAssertEqual(state.scopeEditor.selection, .rootOnly)
        XCTAssertFalse(state.canUndo)
        XCTAssertTrue(state.canRedo)
    }

    // MARK: - RCL-001-redo_collection_filter_changes

    /// RCL-001-redo_collection_filter_changes: redo는 가장 최근 undo 1건을 재적용
    /// undo 이후 redo하면 추가했던 scope가 다시 current scope가 되는지 검증한다.
    /// - 검증 내용: redo 후 selection과 redo history 소진 확인
    /// - 사전 조건: scope 추가 후 undo가 실행되어 redoHistory가 존재함
    /// - 기대 결과: 추가했던 directory가 다시 base scope가 되고 redoHistory는 비워짐
    func testRedoCollectionFilterChanges_afterUndo_reappliesScopeChange() {
        var state = ComposerState()
        reduce(&state, .addScope(path: "/VoyagerFixtures/Documents"))
        reduce(&state, .undo)

        reduce(&state, .redo)

        XCTAssertEqual(state.scopeEditor.selection.explicitBases.map(\.path), ["/VoyagerFixtures/Documents"])
        XCTAssertTrue(state.canUndo)
        XCTAssertFalse(state.canRedo)
    }

    private func makeScopeState(
        bases: [String],
        exceptions: [String] = [],
        includeSubfolders: Bool = true,
    ) -> ComposerState {
        var state = ComposerState()
        state.scopeEditor.selection = ComposerScopeSelection.fromCanonicalScopes(
            bases: bases,
            exceptions: exceptions,
            includeSubfolders: includeSubfolders,
        )
        state.scopeEditor.includeSubfolders = includeSubfolders
        state.scopeEditor.committedSelection = state.scopeEditor.selection
        state.scopeEditor.committedIncludeSubfolders = includeSubfolders
        return state
    }

    private func reduce(_ state: inout ComposerState, _ action: ComposerAction) {
        withDependencies {
            $0.entryLoadingClient = .testValue
            $0.searchClient = .testValue
            $0.registryClient = .testValue
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: action)
        }
    }
}
