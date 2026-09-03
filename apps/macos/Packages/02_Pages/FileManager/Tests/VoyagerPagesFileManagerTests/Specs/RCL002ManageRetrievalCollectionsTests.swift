@_spi(Internals) import ComposableArchitecture
import Foundation
@_spi(Testing)
@testable import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

private actor CollectionFileLoadSuspensionGate {
    enum Completion {
        case success(CollectionFileLoadResult)
        case failure
    }

    private var continuation: CheckedContinuation<Completion, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async throws -> CollectionFileLoadResult {
        let completion = await withCheckedContinuation { continuation in
            self.continuation = continuation
            let waiters = waiters
            self.waiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        switch completion {
        case let .success(result):
            return result
        case .failure:
            throw Failure.expected
        }
    }

    func waitUntilWaiting() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resume(with completion: Completion) {
        continuation?.resume(returning: completion)
        continuation = nil
    }

    private enum Failure: Error {
        case expected
    }
}

private enum CollectionOpenCharacterizationFailure {
    case malformed
    case unsupportedSchema
    case invalidDefinition
    case access
    case unknown

    var error: any Error {
        switch self {
        case .malformed:
            CollectionFileCompatibilityError.invalidPropertyListPayload
        case .unsupportedSchema:
            CollectionFileCompatibilityError.unsupportedFutureSchemaVersion(
                found: SchemaVersion(major: 99, minor: 0),
                current: CollectionFileSchemaVersion.current,
            )
        case .invalidDefinition:
            CollectionFileCompatibilityError.invalidDefinitionPayload
        case .access:
            CocoaError(.fileReadNoPermission)
        case .unknown:
            NSError(domain: "CollectionOpenUnknown", code: 1)
        }
    }
}

private struct CollectionOpenMetricRecord: Equatable {
    let name: String
    let value: Double
    let tags: [String: String]?
}

@MainActor
final class RCL002ManageRetrievalCollectionsTests: XCTestCase {
    // MARK: - RCL-002-save_collection_filter_changes

    /// RCL-002-save_collection_filter_changes: empty Collection의 no-op query edit은 draft owner를 동기화한다.
    /// query search는 filter preview만 반환하므로 실제 filter 검색 없이 Composer와 Collection context가 함께 갱신된다.
    /// - 검증 내용: trimmed query submit, canonical context, dirty/canSave, request cardinality
    /// - 사전 조건: file-backed semantic-empty Collection과 새 query text
    /// - 기대 결과: query search 1회, filter search 0회, 저장 가능한 dirty draft
    func testEditEmptyCollection_queryNoOpSynchronizesCollectionDraft() async {
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/query-edit.voycoll")
        let requests = LockIsolated<[String]>([])
        let store = makeCollectionEditStore(
            targetURL: targetURL,
            requests: requests,
        )

        await store.send(.composer(.setText("  invoice  ")))
        await store.skipReceivedActions(strict: false)
        await store.send(.composer(.submit))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        let expectedContext = CollectionContext(query: "invoice", scopes: [], conditions: [])
        XCTAssertEqual(requests.value, ["submit"])
        XCTAssertEqual(store.state.collection.collectionContext, expectedContext)
        XCTAssertEqual(store.state.composer.collectionContext, expectedContext)
        XCTAssertTrue(store.state.collection.isDirty)
        XCTAssertTrue(store.state.collection.canSave(isCollectionMode: true))
        XCTAssertEqual(store.state.collection.collectionSession.document?.url, targetURL)
    }

    /// RCL-002-save_collection_filter_changes: execution-ready condition edit은 기존 filter 검색을 유지한다.
    /// scope-only request-free branch가 실행 가능한 condition의 applyFilters 경로를 가로채지 않는지 characterization 한다.
    /// - 검증 내용: execution-ready condition은 SearchClient.applyFilters만 정확히 한 번 호출한다.
    /// - 사전 조건: file-backed semantic-empty Collection에 값까지 완성된 condition이 있음
    /// - 기대 결과: filter search 1회, query search 0회로 기존 실행 경계가 유지됨
    func testEditEmptyCollection_executionReadyConditionStillRequestsOnce() async {
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/condition-edit.voycoll")
        let requests = LockIsolated<[String]>([])
        var state = makeFileBackedEmptyCollectionContentState(targetURL: targetURL)
        state.composer.conditionEditors = [
            ConditionEditorState(
                id: UUID(950),
                condition: makeEditCondition(values: ["pdf"]),
            ),
        ]
        let store = makeCollectionEditStore(
            initialState: state,
            requests: requests,
        )

        await store.send(.composer(.applyFilters))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertEqual(requests.value, ["applyFilters"])
        XCTAssertEqual(store.state.collection.collectionSession.document?.url, targetURL)
    }

    /// RCL-002-save_collection_filter_changes: condition-only edit은 Collection owner를 즉시 동기화한다.
    /// incomplete condition도 file-backed draft의 dirty/save 판정에 포함되어야 하며 retrieval은 실행하지 않는다.
    func testEditEmptyCollection_conditionOnlySynchronizesCollectionDraft() async {
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/condition-only-edit.voycoll")
        let requests = LockIsolated<[String]>([])
        let store = makeCollectionEditStore(
            targetURL: targetURL,
            requests: requests,
        )

        await store.send(.composer(.view(.addCondition(propertyKey: "kind"))))
        await store.finish()

        let expectedCondition = store.state.composer.conditions[0]
        XCTAssertEqual(store.state.collection.collectionContext?.conditions, [expectedCondition])
        XCTAssertEqual(store.state.composer.collectionContext?.conditions, [expectedCondition])
        XCTAssertTrue(store.state.collection.isDirty)
        XCTAssertTrue(store.state.collection.canSave(isCollectionMode: true))
        XCTAssertTrue(requests.value.isEmpty)
    }

    /// RCL-002-save_collection_filter_changes: file-backed query draft는 입력과 삭제를 모두 owner에 동기화한다.
    /// query를 아직 submit하지 않아도 dirty/save 판정과 close 시 query 삭제가 canonical 상태에 반영되는지 검증한다.
    func testEditFileBackedCollection_queryDraftSynchronizesIncludingClear() async {
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/query-draft-edit.voycoll")
        let baseline = CollectionContext(query: "baseline", scopes: ["/tmp"], conditions: [])
        let requests = LockIsolated<[String]>([])
        var state = makeFileBackedEmptyCollectionContentState(targetURL: targetURL)
        state.collection.collectionContext = baseline
        state.collection.collectionSession.metadata.baseline = .init(context: baseline)
        state.composer.collectionContext = baseline
        state.composer.scopes = baseline.scopes
        state.composer.text = baseline.query
        let store = makeCollectionEditStore(initialState: state, requests: requests)

        await store.send(.composer(.setText(" invoice ")))
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(store.state.collection.collectionContext?.query, "invoice")
        XCTAssertTrue(store.state.collection.isDirty)
        XCTAssertTrue(store.state.collection.canSave(isCollectionMode: true))

        await store.send(.composer(.setText("")))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertEqual(store.state.collection.collectionContext?.query, "")
        XCTAssertEqual(store.state.composer.collectionContext?.query, "")
        XCTAssertTrue(store.state.collection.isDirty)
        XCTAssertTrue(requests.value.isEmpty)
    }

    /// RCL-002-save_collection_filter_changes: 첫 scope-only edit은 retrieval 없이 Collection draft를 dirty로 만든다.
    /// Composer child가 scope editor를 닫은 뒤 FileManager가 현재 scope rule을 Collection ownership에 동기화한다.
    /// - 검증 내용: scope/exclusion context, committed scope, dirty, URL, accepted response, request cardinality
    /// - 사전 조건: copied semantic-empty package의 file-backed Collection과 첫 scope editor transaction
    /// - 기대 결과: pending scope change가 해제되고 원본 URL을 유지한 dirty request-free draft가 됨
    func testEditEmptyCollection_scopeOnlyDraftBecomesDirtyWithoutSearch() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingDirectory(
            from: "fixtures/fixtures/collections/empty_definition_collection.voycoll",
        )
        defer { sandbox.cleanup() }
        let sourcePayload = try Data(contentsOf: sandbox.originalFixture.appendingPathComponent("collection.plist"))
        let requests = LockIsolated<[String]>([])
        let acceptedRequestID = UUID(951)
        let acceptedResponse = SearchResponsePayload(itemCount: 0, items: [])
        var state = makeFileBackedEmptyCollectionContentState(targetURL: sandbox.fileURL)
        state.composer.lastAcceptedFiltersRequestID = acceptedRequestID
        state.composer.lastFiltersResponse = acceptedResponse
        let store = makeCollectionEditStore(initialState: state, requests: requests)

        await store.send(.composer(.scopeEditorSetPresented(true)))
        await store.send(.composer(.candidateScope(.add(path: "/VoyagerFixtures/Documents"))))
        await store.send(.composer(.exceptionScope(.exclude(path: "/VoyagerFixtures/Documents/Archive"))))
        XCTAssertTrue(store.state.composer.scopeEditor.hasPendingScopeRuleChanges)
        await store.send(.composer(.scopeEditorSetPresented(false)))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        let expectedContext = CollectionContext(
            query: "",
            scopes: ["/VoyagerFixtures/Documents"],
            excludedScopes: ["/VoyagerFixtures/Documents/Archive"],
            includeSubfolders: true,
            includeDirectories: false,
            conditions: [],
        )
        XCTAssertEqual(store.state.collection.collectionContext, expectedContext)
        XCTAssertEqual(store.state.composer.collectionContext, expectedContext)
        XCTAssertFalse(store.state.composer.scopeEditor.hasPendingScopeRuleChanges)
        XCTAssertTrue(store.state.collection.isDirty)
        XCTAssertEqual(store.state.collection.collectionSession.document?.url, sandbox.fileURL)
        XCTAssertEqual(store.state.composer.openedCollectionURL, sandbox.fileURL)
        XCTAssertEqual(store.state.composer.lastAcceptedFiltersRequestID, acceptedRequestID)
        XCTAssertEqual(store.state.composer.lastFiltersResponse, acceptedResponse)
        XCTAssertTrue(requests.value.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: sandbox.originalFixture.appendingPathComponent("collection.plist")),
            sourcePayload,
        )
    }

    /// RCL-002-save_collection_filter_changes: copied empty package는 scope edit 후 같은 URL에 저장하고 clean reopen된다.
    /// FileManager open/edit/Composer save/open chain을 live Collection file client로 구동하는 data-surface QA다.
    /// - 검증 내용: exact scope persistence, same-file URL, clean reopened baseline, source bytes, retrieval cardinality
    /// - 사전 조건: canonical semantic-empty package의 isolated directory copy
    /// - 기대 결과: copied package만 변경되고 scope-only journey 전체에서 retrieval 요청이 발생하지 않음
    func testEditEmptyCollection_copiedPackageScopeSaveReopenRestoresCleanDraft() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingDirectory(
            from: "fixtures/fixtures/collections/empty_definition_collection.voycoll",
        )
        defer { sandbox.cleanup() }
        let sourcePayloadURL = sandbox.originalFixture.appendingPathComponent("collection.plist")
        let sourcePayload = try Data(contentsOf: sourcePayloadURL)
        let requests = LockIsolated<[String]>([])
        let store = TestStore(initialState: FileManagerWindowState()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient = .liveValue
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = makeRegistryClient()
            $0.searchClient.search = { _ in
                requests.withValue { $0.append("submit") }
                return .init(itemCount: 0)
            }
            $0.searchClient.applyFilters = { _ in
                requests.withValue { $0.append("applyFilters") }
                return .init(itemCount: 0)
            }
            $0.entryLoadingClient = .testValue
            $0.userDefaultsClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: cross-package journey는 child action 열거보다 persisted terminal state를 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.openCollectionFile(sandbox.fileURL))))
        await store.skipReceivedActions(strict: false)
        XCTAssertFalse(store.state.content.collection.isDirty)

        await store.send(.content(.composer(.scopeEditorSetPresented(true))))
        await store.send(.content(.composer(.candidateScope(.add(path: "/VoyagerFixtures/Documents")))))
        await store.send(.content(.composer(.scopeEditorSetIncludeSubfolders(false))))
        await store.send(.content(.composer(.scopeEditorSetPresented(false))))
        XCTAssertTrue(store.state.content.collection.isDirty)

        await store.send(.content(.composer(.saveCollection)))
        await store.skipReceivedActions(strict: false)
        XCTAssertFalse(store.state.content.collection.isDirty)
        XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, sandbox.fileURL)

        await store.send(.navigation(.view(.openCollectionFile(sandbox.fileURL))))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        let expectedContext = CollectionContext(
            query: "",
            scopes: ["/VoyagerFixtures/Documents"],
            excludedScopes: [],
            includeSubfolders: false,
            includeDirectories: false,
            conditions: [],
        )
        XCTAssertEqual(store.state.content.collection.collectionContext, expectedContext)
        XCTAssertEqual(store.state.content.collection.collectionSession.metadata.baseline?.context, expectedContext)
        XCTAssertFalse(store.state.content.collection.isDirty)
        XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, sandbox.fileURL)
        XCTAssertEqual(store.state.content.composer.openedCollectionURL, sandbox.fileURL)
        XCTAssertTrue(requests.value.isEmpty)
        XCTAssertEqual(try Data(contentsOf: sourcePayloadURL), sourcePayload)
    }

    /// RCL-002-save_collection_filter_changes: repeated scope dismissal preserves add/remove/include semantics.
    /// scope-only transaction을 두 번 닫아 committed draft가 다음 transaction의 baseline으로 사용되는지 검증한다.
    /// - 검증 내용: exact-folder includeSubfolders false 반영과 이후 scope 제거 동기화
    /// - 사전 조건: file-backed semantic-empty Collection에서 add 후 remove를 별도 transaction으로 수행
    /// - 기대 결과: 첫 dismissal은 exact-folder context, 두 번째는 Composer의 root-only scope context가 됨
    func testEditEmptyCollection_scopeDraftSynchronizationCoversRemoveAndIncludeRule() async {
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/repeated-scope-edit.voycoll")
        let requests = LockIsolated<[String]>([])
        let store = makeCollectionEditStore(targetURL: targetURL, requests: requests)

        await store.send(.composer(.scopeEditorSetPresented(true)))
        await store.send(.composer(.candidateScope(.add(path: "/VoyagerFixtures/Documents"))))
        await store.send(.composer(.scopeEditorSetIncludeSubfolders(false)))
        await store.send(.composer(.scopeEditorSetPresented(false)))
        XCTAssertEqual(store.state.collection.collectionContext?.scopes, ["/VoyagerFixtures/Documents"])
        XCTAssertEqual(store.state.collection.collectionContext?.includeSubfolders, false)
        XCTAssertFalse(store.state.composer.scopeEditor.hasPendingScopeRuleChanges)

        await store.send(.composer(.scopeEditorSetPresented(true)))
        await store.send(.composer(.currentScope(.remove(path: "/VoyagerFixtures/Documents"))))
        await store.send(.composer(.scopeEditorSetPresented(false)))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertEqual(
            store.state.collection.collectionContext,
            CollectionContext(query: "", scopes: ["/"], conditions: []),
        )
        XCTAssertTrue(store.state.collection.isDirty)
        XCTAssertFalse(store.state.composer.scopeEditor.hasPendingScopeRuleChanges)
        XCTAssertTrue(requests.value.isEmpty)
    }

    /// RCL-002-save_collection_filter_changes: incomplete condition은 request-free이고 기존 save validation에 차단된다.
    /// scope-only branch 추가가 incomplete condition을 execution-ready 또는 saveable condition으로 승격하지 않는지 검증한다.
    /// - 검증 내용: search/filter/save client 무호출과 incompleteCondition feedback
    /// - 사전 조건: file-backed semantic-empty Collection에 operation/value가 없는 available condition이 있음
    /// - 기대 결과: retrieval 없이 save가 차단되고 document URL과 dirty draft가 유지됨
    func testEditEmptyCollection_incompleteConditionRemainsRequestFreeAndSaveBlocked() async {
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/incomplete-edit.voycoll")
        let requests = LockIsolated<[String]>([])
        let saveURLs = LockIsolated<[URL]>([])
        let incompleteCondition = makeEditCondition(values: nil)
        let incompleteContext = CollectionContext(
            query: "",
            scopes: [],
            conditions: [incompleteCondition],
        )
        var state = makeFileBackedEmptyCollectionContentState(targetURL: targetURL)
        state.composer.conditionEditors = [
            ConditionEditorState(id: UUID(952), condition: incompleteCondition),
        ]
        state.composer.collectionContext = incompleteContext
        state.collection.collectionContext = incompleteContext
        let store = makeCollectionEditStore(
            initialState: state,
            requests: requests,
            saveURLs: saveURLs,
        )

        await store.send(.composer(.applyFilters))
        await store.skipReceivedActions(strict: false)
        await store.send(.collection(.saveToExisting(
            makeEditSavePayload(context: incompleteContext),
            targetURL,
        )))
        await store.receive(\.collection.delegate.saveFeedback)
        XCTAssertEqual(store.state.composer.transientFeedback?.category, .saveBlocked)
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertTrue(requests.value.isEmpty)
        XCTAssertTrue(saveURLs.value.isEmpty)
        XCTAssertTrue(store.state.collection.isDirty)
        XCTAssertEqual(store.state.collection.collectionSession.document?.url, targetURL)
        XCTAssertEqual(store.state.composer.openedCollectionURL, targetURL)
    }

    /// RCL-002-save_collection_filter_changes: save_ready 상태에서 Save 시 .voycoll 갱신 및 dirty baseline 갱신
    /// 임시 collection을 저장하면 file-backed collection으로 승격되고 unsaved/stale indicator가 해제되는지 검증.
    /// - 검증 내용: saveCompleted(.success) 전송 시 writeBackCompleted, writeBackNavigationPrepared, requestNavigation,
    /// syncCollectionState 수신 및 baseline 갱신
    /// - 사전 조건: temporary collection, isOpenedCollectionDirty == true, phase.isStale == true
    /// - 기대 결과: savedURL로 navigation 전환, baseline 갱신, isOpenedCollectionDirty == false, showsUnsavedIndicator == false
    func testSaveSuccessPromotesTemporaryCollectionAndClearsUnsavedIndicator() async {
        let savedURL = URL(fileURLWithPath: "/tmp/voyager/saved.voycoll")
        let savedContext = CollectionContext(query: "draft", scopes: ["/tmp/voyager"], conditions: [])
        let completion = makeSaveCompletion(url: savedURL, savedContext: savedContext)
        var initialState = makeWriteBackState()
        initialState.collection.collectionContext = savedContext
        initialState.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .none,
        )

        XCTAssertTrue(initialState.isOpenedCollectionDirty)
        XCTAssertTrue(initialState.collection.collectionSession.phase.isStale)

        let store = makeStore(initialState: initialState)

        await store.send(.collection(.saveCompleted(.success(completion))))

        await store.receive(\.collection.writeBackCompleted)

        await store.receive(\.collection.delegate.writeBackNavigationPrepared) {
            $0.navigation.navigationState = .collection(.init(
                kind: .file(url: savedURL, name: "saved"),
                context: savedContext,
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
                compatibility: self.makeAllowedCompatibility(),
            ))
        }

        await store.receive(\.internal.requestNavigation)

        await store.receive(\.composer.internal.syncCollectionState) {
            $0.composer.collectionContext = savedContext
            $0.composer.openedCollectionURL = savedURL
            $0.composer.openedCollectionCompatibility = self.makeAllowedCompatibility()
            $0.composer.isCollectionMode = true
        }

        await store.finish()

        XCTAssertEqual(store.state.collection.collectionSession.document?.url, savedURL)
        XCTAssertEqual(store.state.collection.collectionSession.document?.name, "saved")
        XCTAssertEqual(store.state.collection.collectionContext, savedContext)
        XCTAssertEqual(
            store.state.collection.collectionSession.metadata.baseline,
            CollectionBaseline(context: savedContext),
        )
        XCTAssertFalse(store.state.isOpenedCollectionDirty)
        XCTAssertFalse(store.state.collection.collectionSession.phase.isStale)
        let collectionStatus = ToolbarCollectionStatusViewState(
            isCollectionMode: store.state.isCollectionMode,
            openedCollectionURLExists: store.state.openedCollectionURLExists,
            isOpenedCollectionDirty: store.state.isOpenedCollectionDirty,
            isOpenedCollectionStale: store.state.collection.collectionSession.phase.isStale,
            refreshBlockingReason: nil,
        )
        XCTAssertFalse(collectionStatus.showsUnsavedIndicator)
        XCTAssertFalse(collectionStatus.showsStaleIndicator)
        XCTAssertEqual(store.state.navigation.currentPath, "saved")
    }

    /// RCL-002-save_collection_filter_changes: 저장 실패 시 save_failed 피드백과 dirty change 유지
    /// 컴포저가 닫혀 있을 때 저장 실패 피드백이 컴포저를 열고 error 상태를 표시하는지 검증.
    /// - 검증 내용: saveFeedback(.saveFailed) 전송 시 composer.isPresented = true, transientFeedback에 error/saveFailed 설정
    /// - 사전 조건: composer.isPresented == false, saveFailed feedback
    /// - 기대 결과: composer 열림, transientFeedback.stage == .save, category == .saveFailed
    func testSaveFeedbackPresentsComposerWhenClosed() async {
        var initialState = makeWriteBackState()
        initialState.composer.isPresented = false
        let feedback = CollectionSaveFeedback(
            stage: .saveFailed,
            category: .saveFailed,
            title: "Unable to Save Collection",
            message: "Permission denied",
            recoveryHint: "Check the file location or try again.",
            isRetryable: true,
        )

        let store = makeStore(initialState: initialState)

        await store.send(.collection(.delegate(.saveFeedback(feedback)))) {
            $0.composer.isPresented = true
            $0.composer.transientFeedback = ComposerTransientFeedback(
                id: $0.composer.transientFeedback?.id ?? UUID(),
                kind: .error,
                message: "Unable to Save Collection\nPermission denied",
                stage: .save,
                category: .saveFailed,
                recoveryHint: "Check the file location or try again.",
            )
        }

        XCTAssertTrue(store.state.composer.isPresented)
        XCTAssertEqual(store.state.composer.transientFeedback?.stage, .save)
        XCTAssertEqual(store.state.composer.transientFeedback?.category, .saveFailed)
        await store.finish()
    }

    /// RCL-002-save_collection_filter_changes: file-backed navigation이 opened collection 상태로 파생 (session document lag
    /// 허용)
    /// session document가 없어도 file-backed collection navigation이 opened collection URL과 dirty 상태를 올바르게 파생하는지 검증.
    /// - 검증 내용: collectionSession.document == nil이어도 navigationState의 file URL로 openedCollectionURL,
    /// openedCollectionURLExists 파생
    /// - 사전 조건: navigationState == .collection(.file), collectionSession.document == nil, baseline 설정됨
    /// - 기대 결과: openedCollectionURL == savedURL, openedCollectionURLExists == true, isOpenedCollectionDirty == false,
    /// showsUnsavedIndicator == false
    func testFileBackedNavigationCountsAsOpenedCollectionWhenSessionDocumentLags() {
        let savedURL = URL(fileURLWithPath: "/tmp/voyager/test.voycoll")
        let savedContext = CollectionContext(query: "test", scopes: ["/tmp/voyager"], conditions: [])
        var state = makeWriteBackState()
        state.navigation.navigationState = .collection(.init(
            kind: .file(url: savedURL, name: "test"),
            context: savedContext,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
            compatibility: makeAllowedCompatibility(),
        ))
        state.collection.collectionSession.document = nil
        state.collection.collectionContext = savedContext
        state.collection.collectionSession.metadata.baseline = .init(context: savedContext)

        XCTAssertEqual(state.openedCollectionURL, savedURL)
        XCTAssertTrue(state.openedCollectionURLExists)
        XCTAssertFalse(state.isOpenedCollectionDirty)

        let collectionStatus = ToolbarCollectionStatusViewState(
            isCollectionMode: state.isCollectionMode,
            openedCollectionURLExists: state.openedCollectionURLExists,
            isOpenedCollectionDirty: state.isOpenedCollectionDirty,
            isOpenedCollectionStale: state.collection.collectionSession.phase.isStale,
            refreshBlockingReason: nil,
        )
        XCTAssertFalse(collectionStatus.showsUnsavedIndicator)
    }

    // MARK: - RCL-002-save_current_filter_as_new_collection

    /// RCL-002-save_current_filter_as_new_collection: Tags route의 현재 filter context seed 생성
    /// Tags virtual route를 새 collection으로 저장 가능한 현재 filter context로 변환하는지 검증.
    /// - 검증 내용: tags route에서 tag_names 조건과 registry 기반 label/operator metadata 생성
    /// - 사전 조건: navigation route == .tags("Work"), registryClient가 tag_names metadata 제공
    /// - 기대 결과: query/scopes는 비어 있고 tag_names any Work 조건이 active 상태로 생성됨
    func testTagsRouteMapsToRegistryDerivedTagCondition() throws {
        let context = try XCTUnwrap(
            FileManagerVirtualCollectionContextFactory.collectionContext(
                for: .tags("Work"),
                registryClient: makeRegistryClient(),
            ),
        )

        XCTAssertEqual(context.query, "")
        XCTAssertEqual(context.scopes, [])
        XCTAssertEqual(context.excludedScopes, [])
        XCTAssertTrue(context.includeSubfolders)
        XCTAssertTrue(context.includeDirectories)
        let condition = try XCTUnwrap(context.conditions.first)
        XCTAssertEqual(condition.property.key, "tag_names")
        XCTAssertEqual(condition.property.label, "Registry Tag Label")
        XCTAssertEqual(condition.property.type.rawValue, "categorical")
        XCTAssertEqual(condition.operation?.code, "any")
        XCTAssertEqual(condition.operation?.label, "Registry Any Label")
        XCTAssertEqual(condition.operation?.valueContract, .init(shape: .list, count: .multiple, input: .listText))
        XCTAssertEqual(condition.values, ["Work"])
        XCTAssertTrue(condition.isExecutionReady)
    }

    /// RCL-002-save_current_filter_as_new_collection: Recents route의 현재 filter context seed 생성
    /// Recents virtual route를 새 collection으로 저장 가능한 현재 filter context로 변환하는지 검증.
    /// - 검증 내용: recents route에서 last_used_date 조건과 folder 제외 조건 생성
    /// - 사전 조건: navigation route == .recents, registryClient가 date/content_type_tree metadata 제공
    /// - 기대 결과: includeDirectories == false이고 last_used_date, content_type_tree 조건이 active 상태로 생성됨
    func testRecentsRouteMapsToRegistryDerivedRecentCondition() throws {
        let context = try XCTUnwrap(
            FileManagerVirtualCollectionContextFactory.collectionContext(
                for: .recents,
                registryClient: makeRegistryClient(),
            ),
        )

        XCTAssertEqual(context.query, "")
        XCTAssertEqual(context.scopes, [])
        XCTAssertEqual(context.excludedScopes, [])
        XCTAssertTrue(context.includeSubfolders)
        XCTAssertFalse(context.includeDirectories)
        XCTAssertEqual(context.conditions.count, 2)
        let recentCondition = try XCTUnwrap(context.conditions.first { $0.property.key == "last_used_date" })
        XCTAssertEqual(recentCondition.property.label, "Registry Last Used Label")
        XCTAssertEqual(recentCondition.property.type.rawValue, "date")
        XCTAssertEqual(recentCondition.operation?.code, "gt")
        XCTAssertEqual(recentCondition.operation?.label, "Registry Greater Than Label")
        XCTAssertEqual(
            recentCondition.operation?.valueContract,
            .init(shape: .single, count: .fixed(1), input: .singleDate),
        )
        XCTAssertEqual(
            recentCondition.values,
            [FileManagerVirtualCollectionContextFactory.recentsSinceAnyOpenedLiteral],
        )
        XCTAssertTrue(recentCondition.isExecutionReady)

        let directoryExclusion = try XCTUnwrap(context.conditions.first { $0.property.key == "content_type_tree" })
        XCTAssertEqual(directoryExclusion.property.label, "Registry Content Type Tree Label")
        XCTAssertEqual(directoryExclusion.property.type.rawValue, "string")
        XCTAssertEqual(directoryExclusion.operation?.code, "neq")
        XCTAssertEqual(directoryExclusion.operation?.label, "Registry Not Equal Label")
        XCTAssertEqual(
            directoryExclusion.operation?.valueContract,
            .init(shape: .single, count: .fixed(1), input: .singleText),
        )
        XCTAssertEqual(directoryExclusion.values, ["public.folder"])
        XCTAssertTrue(directoryExclusion.isExecutionReady)
    }

    /// RCL-002-save_current_filter_as_new_collection: built-in Recents가 virtual Recents 정의를 재사용
    /// built-in Recents 저장 정의와 기존 virtual route가 동일한 condition SSOT를 사용하는지 검증.
    /// - 검증 내용: built-in Recents context와 virtual Recents context의 전체 값 및 exact condition literal
    /// - 사전 조건: 동일한 registryClient로 built-in/virtual Recents context 생성
    /// - 기대 결과: 두 context가 같고 조건은 두 개이며 recents literal은 `$time.today(-1000000)`임
    func testBuiltInRecentsContextMatchesVirtualRecentsDefinition() throws {
        let registryClient = makeRegistryClient()
        let virtualContext = try XCTUnwrap(
            FileManagerVirtualCollectionContextFactory.collectionContext(
                for: .recents,
                registryClient: registryClient,
            ),
        )
        let builtInContext = FileManagerVirtualCollectionContextFactory.recentsCollectionContext(
            registryClient: registryClient,
        )

        XCTAssertEqual(builtInContext, virtualContext)
        XCTAssertEqual(builtInContext.query, "")
        XCTAssertEqual(builtInContext.scopes, [])
        XCTAssertEqual(builtInContext.excludedScopes, [])
        XCTAssertTrue(builtInContext.includeSubfolders)
        XCTAssertFalse(builtInContext.includeDirectories)
        XCTAssertEqual(builtInContext.conditions.count, 2)
        XCTAssertEqual(
            builtInContext.conditions.first { $0.property.key == "last_used_date" }?.values,
            ["$time.today(-1000000)"],
        )
    }

    /// RCL-002-save_current_filter_as_new_collection: built-in All Tags가 정규화된 names를 단일 조건으로 생성
    /// Finder tag names의 순서와 중복에 관계없이 저장 가능한 deterministic All Tags context를 만드는지 검증.
    /// - 검증 내용: trim, empty 제거, exact dedupe, literal sort 이후 단일 tag_names any condition 생성
    /// - 사전 조건: tag names가 [" Work ", "", "Personal", "Work", " work "]임
    /// - 기대 결과: values가 ["Personal", "Work", "work"]이고 includeDirectories가 true임
    func testBuiltInAllTagsContextNormalizesNamesIntoSingleAnyCondition() throws {
        let context = FileManagerVirtualCollectionContextFactory.allTagsCollectionContext(
            tagNames: [" Work ", "", "Personal", "Work", " work "],
            registryClient: makeRegistryClient(),
        )

        XCTAssertEqual(context.query, "")
        XCTAssertEqual(context.scopes, [])
        XCTAssertEqual(context.excludedScopes, [])
        XCTAssertTrue(context.includeSubfolders)
        XCTAssertTrue(context.includeDirectories)
        XCTAssertEqual(context.conditions.count, 1)

        let condition = try XCTUnwrap(context.conditions.first)
        XCTAssertEqual(condition.property.key, "tag_names")
        XCTAssertEqual(condition.operation?.code, "any")
        XCTAssertNotEqual(condition.operation?.code, "contains")
        XCTAssertEqual(condition.values, ["Personal", "Work", "work"])
    }

    /// RCL-002-save_current_filter_as_new_collection: tag normalization이 공백과 정확 중복만 제거
    /// locale folding 없이 대소문자 변형을 별도 값으로 보존하는 pure normalization contract를 검증.
    /// - 검증 내용: whitespace-only 제거, exact duplicate 제거, case variant 보존, literal lexical sort
    /// - 사전 조건: 공백-only, Work exact duplicate, work case variant가 섞인 names 입력
    /// - 기대 결과: ["Work", "work"] 순서로 정규화됨
    func testTagNameNormalizationRemovesWhitespaceAndExactDuplicatesOnly() {
        XCTAssertEqual(
            FileManagerVirtualCollectionContextFactory.normalizeTagNames([
                " ", "\t\n", "Work", "Work", " work ", "work",
            ]),
            ["Work", "work"],
        )
    }

    /// RCL-002-save_current_filter_as_new_collection: Recents virtual route seed 조건 인식
    /// Recents route에서 자동 생성한 조건 묶음을 Voyager 기본 virtual route seed로 인식하는지 검증.
    /// - 검증 내용: recents collection context의 conditions를 isVirtualRouteSeedConditionSet으로 판정
    /// - 사전 조건: navigation route == .recents
    /// - 기대 결과: Recents 기본 조건 묶음은 virtual route seed로 판정됨
    func testRecognizesRecentsVirtualRouteSeedConditionSet() throws {
        let context = try XCTUnwrap(
            FileManagerVirtualCollectionContextFactory.collectionContext(
                for: .recents,
                registryClient: makeRegistryClient(),
            ),
        )

        XCTAssertTrue(FileManagerVirtualCollectionContextFactory.isVirtualRouteSeedConditionSet(context.conditions))
    }

    /// RCL-002-save_current_filter_as_new_collection: Tags virtual route seed 조건 인식
    /// Tags route에서 자동 생성한 조건 묶음을 Voyager 기본 virtual route seed로 인식하는지 검증.
    /// - 검증 내용: tags collection context의 conditions를 isVirtualRouteSeedConditionSet으로 판정
    /// - 사전 조건: navigation route == .tags("Work")
    /// - 기대 결과: Tags 기본 조건 묶음은 virtual route seed로 판정됨
    func testRecognizesTagVirtualRouteSeedConditionSet() throws {
        let context = try XCTUnwrap(
            FileManagerVirtualCollectionContextFactory.collectionContext(
                for: .tags("Work"),
                registryClient: makeRegistryClient(),
            ),
        )

        XCTAssertTrue(FileManagerVirtualCollectionContextFactory.isVirtualRouteSeedConditionSet(context.conditions))
    }

    /// RCL-002-save_current_filter_as_new_collection: 사용자가 수정한 조건 묶음은 virtual route seed에서 제외
    /// Recents route 기본 조건이 편집되면 더 이상 Voyager 기본 seed로 취급하지 않는지 검증.
    /// - 검증 내용: recents seed condition의 operatorCode 변경 후 isVirtualRouteSeedConditionSet 판정
    /// - 사전 조건: Recents 기본 context 생성 후 첫 조건 operatorCode를 eq로 변경
    /// - 기대 결과: 편집된 조건 묶음은 virtual route seed가 아님
    func testRejectsEditedVirtualRouteSeedConditionSet() throws {
        let context = try XCTUnwrap(
            FileManagerVirtualCollectionContextFactory.collectionContext(
                for: .recents,
                registryClient: makeRegistryClient(),
            ),
        )
        let conditions = context.conditions.map { condition in
            Condition(
                property: condition.property,
                operation: .init(
                    code: "eq",
                    label: "Equals",
                    valueContract: .init(shape: .single, count: .fixed(1), input: .singleDate),
                ),
                values: condition.values,
                availability: condition.availability,
                opaqueSource: condition.opaqueSource,
            )
        }

        XCTAssertFalse(FileManagerVirtualCollectionContextFactory.isVirtualRouteSeedConditionSet(conditions))
    }

    /// RCL-002-save_current_filter_as_new_collection: non-virtual route는 current filter context seed를 생성하지 않음
    /// 일반 folder, Computer, 저장된 Collection route는 Recents/Tags 전용 virtual seed context를 만들지 않는지 검증.
    /// - 검증 내용: folder/computer/collection route별 collectionContext 반환값
    /// - 사전 조건: route == .folder, .computer, .collection
    /// - 기대 결과: 세 route 모두 nil 반환
    func testFolderComputerAndCollectionRoutesDoNotSeedVirtualContext() {
        let registryClient = makeRegistryClient()
        XCTAssertNil(FileManagerVirtualCollectionContextFactory.collectionContext(
            for: .folder("/tmp"),
            registryClient: registryClient,
        ))
        XCTAssertNil(FileManagerVirtualCollectionContextFactory.collectionContext(
            for: .computer,
            registryClient: registryClient,
        ))
        XCTAssertNil(FileManagerVirtualCollectionContextFactory.collectionContext(
            for: .collection(.init(
                kind: .temporary,
                context: .init(),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            )),
            registryClient: registryClient,
        ))
    }

    private func makeStore(
        initialState: FileManagerContentState,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.collectionAlertClient = .init(
                showUnsavedNavigationAlert: { .save },
                showCollectionOpenErrorAlert: { _, _ in },
            )
            $0.collectionFileClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.searchClient = .testValue
            $0.userDefaultsClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off
        return store
    }

    private func makeWriteBackState() -> FileManagerContentState {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true
        state.navigation.navigationState = .collection(.init(
            kind: .temporary,
            context: makeReportContext(),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        state.collection.collectionContext = makeReportContext()
        state.collection.collectionSession.metadata.baseline = .init(context: makeReportContext())
        return state
    }

    private func makeReportContext() -> CollectionContext {
        .init(query: "report", scopes: ["/tmp/voyager"], conditions: [])
    }

    private func makeRegistryClient() -> RegistryClient {
        RegistryClient(
            allProperties: { [] },
            labelForKey: Self.registryLabel(for:),
            propertyTypeString: Self.registryType(for:),
            propertyUnitSpec: { _ in nil },
            operatorCodes: { _ in ["any", "gt", "neq"] },
            operatorDefinition: Self.registryOperatorDefinition(for:),
            resolvePropertyKey: { .canonical($0) },
            resolveCondition: { propertyKey, operatorCode, values, sourcePayload in
                if propertyKey == "removed_property" {
                    return RegistryClient.opaqueCondition(
                        key: propertyKey,
                        source: sourcePayload ?? .init(
                            propertyKey: propertyKey,
                            operatorCode: operatorCode ?? "",
                        ),
                        availability: .unsupportedProperty,
                    )
                }
                let type = SystemPropertyTypeKey(rawType: Self.registryType(for: propertyKey))
                let input: Condition.ValueInputKind = switch (propertyKey, operatorCode) {
                case ("tag_names", "any"): .listText
                case ("last_used_date", "gt"): .singleDate
                default: .singleText
                }
                let contract = Condition.ValueContract(
                    shape: input == .listText ? .list : .single,
                    count: input == .listText ? .multiple : .fixed(1),
                    input: input,
                )
                let label = Self.registryOperatorDefinition(for: operatorCode ?? "").uiLabel ?? (operatorCode ?? "")
                return Condition(
                    property: .init(
                        key: propertyKey,
                        label: Self.registryLabel(for: propertyKey),
                        type: type,
                        unitContract: nil,
                        operatorOptions: operatorCode.map { [.init(code: $0, label: label)] } ?? [],
                    ),
                    operation: operatorCode.map { .init(code: $0, label: label, valueContract: contract) },
                    values: values,
                    availability: .available,
                    opaqueSource: sourcePayload,
                )
            },
        )
    }

    nonisolated private static func registryLabel(for key: String) -> String {
        switch key {
        case "tag_names": "Registry Tag Label"
        case "last_used_date": "Registry Last Used Label"
        case "content_type_tree": "Registry Content Type Tree Label"
        default: key
        }
    }

    nonisolated private static func registryType(for key: String) -> String {
        switch key {
        case "tag_names": "categorical"
        case "last_used_date": "date"
        case "content_type_tree": "string"
        default: "unknown"
        }
    }

    nonisolated private static func registryOperatorDefinition(for code: String) -> OperatorDefinition {
        switch code {
        case "any":
            OperatorDefinition(
                uiLabel: "Registry Any Label",
                uiValueKind: ["categorical": "listText"],
            )
        case "gt":
            OperatorDefinition(
                uiLabel: "Registry Greater Than Label",
                uiValueKind: ["date": "singleDate"],
            )
        case "neq":
            OperatorDefinition(
                uiLabel: "Registry Not Equal Label",
                uiValueKind: ["string": "singleText"],
            )
        default:
            OperatorDefinition(uiLabel: code, uiValueKind: ["unknown": "singleText"])
        }
    }

    private func makeAllowedCompatibility() -> CollectionFileCompatibilityMetadata {
        .init(
            sourceSchemaVersion: SchemaVersion(legacyInt: 2),
            migrationPath: [.currentSchemaV2],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: true,
            writeBackReason: .allowed,
        )
    }

    private func makeSaveCompletion(
        url: URL,
        savedContext: CollectionContext,
    ) -> CollectionSaveCompletion {
        .init(
            url: url,
            file: VoyagerCollectionFile(
                schemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
                id: "test-id",
                name: "saved",
                createdAt: .distantPast,
                updatedAt: .distantFuture,
                query: savedContext.query,
                scopes: savedContext.scopes,
                conditions: [],
                snapshot: nil,
                snapshotMeta: nil,
                appVersion: nil,
            ),
            savedContext: savedContext,
        )
    }

    // MARK: - RCL-002-open_saved_collection

    /// RCL-002-open_saved_collection: accepted zero와 failure provenance는 draft와 구분 가능한 상태를 유지한다.
    /// editable draft presentation 추가 전 Task 2/4가 제공하는 response와 failure state 경계를 고정한다.
    /// - 검증 내용: file-backed identity, accepted zero provenance, preserved failure response, active loading correlation
    /// - 사전 조건: empty file-backed Collection state에서 accepted, failed, loading 변형을 각각 구성함
    /// - 기대 결과: accepted/failure/loading 변형은 draft 판정에서 사용할 distinct provenance를 보유한다.
    func testOpenSavedCollection_presentationBaselineKeepsAcceptedFailureAndLoadingProvenanceDistinct() {
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/presentation-baseline.voycoll")
        let acceptedRequestID = UUID(960)
        let acceptedResponse = SearchResponsePayload(itemCount: 0, items: [])
        var acceptedZero = makeFileBackedEmptyCollectionContentState(targetURL: targetURL)
        acceptedZero.composer.lastAcceptedFiltersRequestID = acceptedRequestID
        acceptedZero.composer.lastFiltersResponse = acceptedResponse

        var failed = acceptedZero
        failed.composer.transientFeedback = .init(
            id: UUID(961),
            kind: .error,
            message: "Unable to Apply Collection Filters",
            stage: .queryExecution,
            category: .executionFailure,
        )

        var loading = makeFileBackedEmptyCollectionContentState(targetURL: targetURL)
        loading.composer.isLoadingFilters = true
        loading.composer.isFilteringInFlight = true
        loading.composer.activeFiltersRequestID = UUID(962)

        XCTAssertEqual(acceptedZero.openedCollectionURL, targetURL)
        XCTAssertEqual(acceptedZero.composer.lastAcceptedFiltersRequestID, acceptedRequestID)
        XCTAssertEqual(acceptedZero.composer.lastFiltersResponse, acceptedResponse)
        XCTAssertEqual(failed.composer.lastFiltersResponse, acceptedResponse)
        XCTAssertEqual(failed.composer.transientFeedback?.kind, .error)
        XCTAssertTrue(loading.composer.isCollectionSearching)
        XCTAssertNotNil(loading.composer.activeFiltersRequestID)
    }

    /// RCL-002-open_saved_collection: empty draft guidance를 accepted zero와 failure에서 구분한다.
    /// 저장 Collection state의 execution 및 response provenance가 content presentation으로 정확히 분류되는지 검증한다.
    /// - 검증 내용: file-backed draft, accepted zero, preserved failure response의 presentation policy
    /// - 사전 조건: 동일한 empty Collection context에 response/failure provenance만 다르게 구성함
    /// - 기대 결과: draft만 collectionEmptyDraft이고 accepted zero와 failure는 entries를 유지한다.
    func testOpenSavedCollection_emptyDraftPresentationDistinguishesAcceptedZeroAndFailures() async throws {
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/presentation.voycoll")
        let draft = makeFileBackedEmptyCollectionContentState(targetURL: targetURL)
        var whitespaceQuery = draft
        whitespaceQuery.collection.collectionContext = .init(query: "  \n ", scopes: [], conditions: [])
        whitespaceQuery.composer.collectionContext = whitespaceQuery.collection.collectionContext
        var scopeOnly = draft
        scopeOnly.collection.collectionContext = .init(query: "", scopes: ["/scope"], conditions: [])
        scopeOnly.composer.collectionContext = scopeOnly.collection.collectionContext
        var unsupportedOnly = draft
        unsupportedOnly.collection.collectionContext = .init(
            query: "",
            scopes: [],
            conditions: [makePresentationCondition(availability: .unsupportedProperty, values: ["old"])],
        )
        unsupportedOnly.composer.collectionContext = unsupportedOnly.collection.collectionContext
        var incompleteCondition = draft
        incompleteCondition.collection.collectionContext = .init(
            query: "",
            scopes: [],
            conditions: [makePresentationCondition(availability: .available, values: nil)],
        )
        incompleteCondition.composer.collectionContext = incompleteCondition.collection.collectionContext
        var acceptedZero = draft
        acceptedZero.composer.lastAcceptedFiltersRequestID = UUID(963)
        acceptedZero.composer.lastFiltersResponse = .init(itemCount: 0, items: [])
        var failed = draft
        failed.composer.transientFeedback = .init(
            id: UUID(964),
            kind: .error,
            message: "Unable to Apply Collection Filters",
            stage: .queryExecution,
            category: .executionFailure,
        )
        var loading = draft
        loading.composer.isLoadingFilters = true
        loading.composer.isFilteringInFlight = true
        loading.composer.activeFiltersRequestID = UUID(965)
        var entries = draft
        entries.entryViewLayout.collectionItems = [makeEntry(path: "/results/entry.txt")]
        var staleResponse = draft
        staleResponse.composer.lastFiltersResponse = .init(itemCount: 0, items: [])
        var executableQuery = draft
        executableQuery.collection.collectionContext = .init(query: "invoice", scopes: [], conditions: [])
        executableQuery.composer.collectionContext = executableQuery.collection.collectionContext
        var executableCondition = draft
        executableCondition.collection.collectionContext = .init(
            query: "",
            scopes: [],
            conditions: [makePresentationCondition(availability: .available, values: ["pdf"])],
        )
        executableCondition.composer.collectionContext = executableCondition.collection.collectionContext
        let directory = FileManagerContentState()
        var temporary = draft
        temporary.collection.collectionSession.document = nil
        temporary.composer.openedCollectionURL = nil
        temporary.navigation.navigationState = .collection(.init(
            kind: .temporary,
            context: .init(),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))

        let draftPolicies = [draft, whitespaceQuery, scopeOnly, unsupportedOnly, incompleteCondition].map {
            ContentPagePresentationPolicy.resolve(state: $0)
        }
        let excludedPolicies = [
            acceptedZero,
            failed,
            loading,
            entries,
            staleResponse,
            executableQuery,
            executableCondition,
            directory,
            temporary,
        ].map { ContentPagePresentationPolicy.resolve(state: $0) }

        XCTAssertEqual(draftPolicies, Array(repeating: .collectionEmptyDraft, count: 5))
        XCTAssertEqual(excludedPolicies[2], .collectionReplacementLoading)
        for policy in excludedPolicies.enumerated() where policy.offset != 2 {
            XCTAssertEqual(policy.element, .entries)
        }

        let fixtureDirectory = try FileManagerFixtureSandbox.readOnlyDirectory(
            from: "fixtures/fixtures/collections",
        )
        let acceptedZeroFixtureURL = fixtureDirectory
            .appendingPathComponent("empty_snapshot_collection.voycoll")
        let fixtureStore = TestStore(initialState: FileManagerWindowState()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient = .liveValue
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = makeRegistryClient()
            $0.searchClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.userDefaultsClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: fixture open의 child action보다 accepted-zero presentation을 검증한다.
        fixtureStore.exhaustivity = .off(showSkippedAssertions: false)

        await fixtureStore.send(.navigation(.view(.openCollectionFile(acceptedZeroFixtureURL))))
        await fixtureStore.skipReceivedActions(strict: false)
        await fixtureStore.finish()

        XCTAssertEqual(fixtureStore.state.content.composer.lastFiltersResponse?.itemCount, 0)
        XCTAssertEqual(ContentPagePresentationPolicy.resolve(state: fixtureStore.state.content), .entries)
    }

    /// RCL-002-open_saved_collection: executable definition open은 기존 submit 검색 경로를 한 번 유지한다.
    /// no-trigger 복원 변경 전에 실행 가능한 저장 Collection의 검색 동작을 characterization 한다.
    /// - 검증 내용: query-bearing file open이 SearchClient.search를 정확히 한 번 호출한다.
    /// - 사전 조건: snapshot이 없고 trimmed query가 있는 저장 Collection load result
    /// - 기대 결과: 저장 URL의 Collection route가 적용되고 search 요청이 한 번 기록된다.
    func testOpenSavedCollection_executableDefinitionKeepsExistingSearchDispatch() async {
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/executable.voycoll")
        let targetFile = VoyagerCollectionFile(
            id: "executable-baseline",
            name: "Executable",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            query: "invoice",
            scopes: ["/VoyagerFixtures/Documents"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: "test",
        )
        let searchRequests = LockIsolated<[SearchRequestPayload]>([])
        let loadResult = makeSnapshotLoadResult(file: targetFile)
        let store = TestStore(initialState: FileManagerWindowState()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in loadResult }
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.searchClient.search = { request in
                searchRequests.withValue { $0.append(request) }
                return .init(itemCount: 0)
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: canonical open의 child action보다 기존 executable 검색 경계를 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.openCollectionFile(targetURL))))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertEqual(searchRequests.value.count, 1)
        XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, targetURL)
        XCTAssertFalse(store.state.content.entryViewLayout.isCollectionContentLoading)
    }

    /// RCL-002-open_saved_collection: malformed, future-major, access failure는 기존 Page를 rollback 보존한다.
    /// valid no-trigger 복원과 구분되는 실제 load failure의 기존 alert/rollback 동작을 characterization 한다.
    /// - 검증 내용: 세 오류군 각각 pending/loading 정리, source route 보존, alert 1회 발생을 확인한다.
    /// - 사전 조건: folder source에서 malformed, unsupported future schema, file read no-permission 오류가 각각 발생함
    /// - 기대 결과: source Page와 history가 유지되고 부분 Collection session이 남지 않는다.
    func testOpenSavedCollection_trueLoadFailuresKeepExistingRollbackAndAlertBehavior() async {
        let failures: [CollectionOpenCharacterizationFailure] = [.malformed, .unsupportedSchema, .access]

        for (index, failure) in failures.enumerated() {
            let sourceRoute = ContentPageNavigationRoute.folder("/VoyagerFixtures/Source/\(index)")
            let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/failure-\(index).voycoll")
            let alerts = LockIsolated<[String]>([])
            var state = FileManagerWindowState()
            state.content.navigation.navigationState = sourceRoute
            let store = TestStore(initialState: state) {
                FileManagerFeature()
            } withDependencies: {
                $0.collectionFileClient.load = { _ in throw failure.error }
                $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, _ in
                    alerts.withValue { $0.append(title) }
                }
                $0.collectionStalenessClient = .testValue
                $0.registryClient = .testValue
                $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
                $0.uuid = .constant(UUID(index + 800))
                $0.continuousClock = ImmediateClock()
            }
            // store.exhaustivity = .off: failure rollback의 child cleanup보다 최종 source 보존을 검증한다.
            store.exhaustivity = .off(showSkippedAssertions: false)

            await store.send(.navigation(.view(.openCollectionFile(targetURL))))
            await store.skipReceivedActions(strict: false)
            await store.finish()

            XCTAssertEqual(store.state.content.navigation.navigationState, sourceRoute)
            XCTAssertNil(store.state.pendingCollectionOpenRequest)
            XCTAssertFalse(store.state.content.entryViewLayout.isCollectionContentLoading)
            XCTAssertNil(store.state.content.collection.collectionSession.document)
            XCTAssertEqual(alerts.value, ["Unable to Open Collection"])
        }
    }

    /// RCL-002-open_saved_collection: valid semantic-empty definition은 검색 없이 원본 file-backed Page로 commit한다.
    /// 사용자가 비어 있지만 유효한 저장 Collection을 직접 열 때 editable draft 복원 transaction을 검증한다.
    /// - 검증 내용: URL/session/baseline/Collection mode/loading terminal과 SearchClient 무호출을 확인한다.
    /// - 사전 조건: identity가 있고 query, scope, condition, snapshot이 없는 package load result
    /// - 기대 결과: 원본 URL의 clean Collection Page가 적용되고 submit/applyFilters 요청은 없다.
    func testOpenSavedCollection_validEmptyDefinitionCommitsDraftWithoutSearch() async throws {
        let fixtureDirectory = try FileManagerFixtureSandbox.readOnlyDirectory(
            from: "fixtures/fixtures/collections",
        )
        let fixtureURL = fixtureDirectory.appendingPathComponent("empty_definition_collection.voycoll")
        let sandboxRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerRCL002Open-\(UUID().uuidString)", isDirectory: true)
        let targetURL = sandboxRoot.appendingPathComponent(fixtureURL.lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: sandboxRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtureURL, to: targetURL)
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }
        let requests = LockIsolated<[String]>([])
        let alerts = LockIsolated<[String]>([])
        let store = TestStore(initialState: FileManagerWindowState()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient = .liveValue
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, _ in
                alerts.withValue { $0.append(title) }
            }
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.searchClient.search = { _ in
                requests.withValue { $0.append("submit") }
                return .init(itemCount: 0)
            }
            $0.searchClient.applyFilters = { _ in
                requests.withValue { $0.append("applyFilters") }
                return .init(itemCount: 0)
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: canonical open child action보다 최종 file-backed draft transaction을 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.openCollectionFile(targetURL))))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertTrue(requests.value.isEmpty)
        XCTAssertTrue(alerts.value.isEmpty)
        XCTAssertNil(store.state.pendingCollectionOpenRequest)
        XCTAssertFalse(store.state.content.entryViewLayout.isCollectionContentLoading)
        XCTAssertTrue(store.state.content.entryViewLayout.isCollectionMode)
        XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, targetURL)
        XCTAssertEqual(store.state.content.collection.collectionContext, .init())
        XCTAssertEqual(store.state.content.collection.collectionSession.metadata.baseline, .init(context: .init()))
        XCTAssertFalse(store.state.content.isOpenedCollectionDirty)
        guard case let .collection(navigation) = store.state.content.navigation.navigationState else {
            return XCTFail("Expected valid empty file-backed Collection navigation")
        }
        guard case let .file(openedURL, _) = navigation.kind else {
            return XCTFail("Expected file-backed Collection navigation")
        }
        XCTAssertEqual(openedURL, targetURL)
        XCTAssertEqual(navigation.context, .init())
    }

    /// RCL-002-open_saved_collection: 모든 valid no-trigger definition을 file-backed draft로 복원한다.
    /// semantic-empty, whitespace query, scope-only, unsupported-only, incomplete-condition 경계를 한 matrix로 검증한다.
    /// - 검증 내용: 각 payload의 URL/session/clean baseline/loading terminal과 search/filter 무호출
    /// - 사전 조건: snapshot과 execution-ready query/condition이 없는 다섯 저장 definition
    /// - 기대 결과: 각 원본 URL의 Collection Page가 commit되고 정확히 하나의 valid_empty metric이 기록된다.
    func testOpenSavedCollection_validNoTriggerDefinitionMatrixCommitsWithoutSearch() async {
        let definitions = [
            makeNoTriggerFile(id: "semantic-empty", name: "Semantic Empty"),
            makeNoTriggerFile(id: "whitespace-query", name: "Whitespace Query", query: "  \n "),
            makeNoTriggerFile(id: "scope-only", name: "Scope Only", scopes: ["/VoyagerFixtures/Scope"]),
            makeNoTriggerFile(
                id: "unsupported-only",
                name: "Unsupported Only",
                conditions: [.init(propertyKey: "removed_property", operatorCode: "eq", value: .string("old"))],
            ),
            makeNoTriggerFile(
                id: "incomplete-condition",
                name: "Incomplete Condition",
                conditions: [.init(propertyKey: "tag_names", operatorCode: "any")],
            ),
        ]

        for (index, definition) in definitions.enumerated() {
            let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/\(definition.id).voycoll")
            let requests = LockIsolated<[String]>([])
            let metrics = LockIsolated<[CollectionOpenMetricRecord]>([])
            var registry = makeRegistryClient()
            registry.resolvePropertyKey = { key in
                key == "removed_property" ? .unknown(key) : .canonical(key)
            }
            let loadResult = makeSnapshotLoadResult(file: definition)
            let store = TestStore(initialState: FileManagerWindowState()) {
                FileManagerFeature()
            } withDependencies: {
                $0.collectionFileClient.load = { _ in loadResult }
                $0.collectionAlertClient = .testValue
                $0.collectionStalenessClient = .testValue
                $0.registryClient = registry
                $0.searchClient.search = { _ in
                    requests.withValue { $0.append("submit") }
                    return .init(itemCount: 0)
                }
                $0.searchClient.applyFilters = { _ in
                    requests.withValue { $0.append("applyFilters") }
                    return .init(itemCount: 0)
                }
                $0.metricsClient = MetricsClient(
                    logMetric: { name, value, tags in
                        metrics.withValue { $0.append(.init(name: name, value: value, tags: tags)) }
                    },
                    logDAUNavigation: { _ in },
                    logDAUEntryAction: { _, _ in },
                )
                $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
                $0.uuid = .constant(UUID(index + 900))
                $0.continuousClock = ImmediateClock()
            }
            // store.exhaustivity = .off: matrix는 canonical child action보다 terminal draft 계약을 검증한다.
            store.exhaustivity = .off(showSkippedAssertions: false)

            await store.send(.navigation(.view(.openCollectionFile(targetURL))))
            await store.skipReceivedActions(strict: false)
            await store.finish()

            XCTAssertTrue(requests.value.isEmpty)
            XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, targetURL)
            XCTAssertEqual(
                store.state.content.collection.collectionSession.metadata.baseline?.context,
                store.state.content.collection.collectionContext,
            )
            XCTAssertFalse(store.state.content.isOpenedCollectionDirty)
            XCTAssertFalse(store.state.content.entryViewLayout.isCollectionContentLoading)
            XCTAssertEqual(metrics.value, [
                .init(name: "collection.open", value: 1, tags: ["result_status": "valid_empty"]),
            ])
        }
    }

    /// RCL-002-open_saved_collection: stale target를 열 때 다른 file의 reopen context를 재사용하지 않는다.
    /// open 중 source Collection의 context가 target file의 stale restoration context를 오염시키지 않는지 검증한다.
    /// - 검증 내용: target URL, loaded empty context, reopenContext nil, retrieval request 0
    /// - 사전 조건: source file-backed Collection이 열려 있고 target file이 persisted invalidation으로 stale 상태임
    /// - 기대 결과: target definition context가 유지되고 source query/scope가 target에 전파되지 않는다.
    func testOpenSavedCollection_staleDifferentFileDoesNotReuseSourceReopenContext() async {
        let sourceURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/source-reopen.voycoll")
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/target-stale-empty.voycoll")
        let sourceContext = CollectionContext(
            query: "source query",
            scopes: ["/VoyagerFixtures/Source"],
            conditions: [],
        )
        let targetFile = makeNoTriggerFile(id: "stale-different-file", name: "Target Stale Empty")
        let targetPath = targetURL.standardizedFileURL.path
        let invalidatedRecord = CollectionStalenessRecord(
            definitionFingerprint: "target",
            relevanceRoots: [],
            excludedScopes: [],
            includeSubfolders: true,
            lastInvalidatedAt: Date(timeIntervalSince1970: 1_700_000_200),
        )
        var state = makeOpenedCollectionState(url: sourceURL, context: sourceContext)
        state.content.composer.collectionContext = sourceContext
        state.content.composer.openedCollectionURL = sourceURL
        state.content.composer.isCollectionMode = true
        let loadResult = makeSnapshotLoadResult(file: targetFile)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in loadResult }
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .init(
                record: { path in path == targetPath ? invalidatedRecord : nil },
                upsertRecord: { _, _ in },
                invalidateRecords: { _ in },
                suppressPaths: { _ in },
                clearRecord: { _ in },
                registerCollection: { _, _, _, _ in },
                consumeInvalidation: { _ in false },
            )
            $0.registryClient = .testValue
            $0.searchClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .constant(UUID(974))
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: open child action보다 stale restoration context의 source/target 경계를 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.openCollectionFile(targetURL))))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertNil(store.state.pendingCollectionOpenRequest)
        XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, targetURL)
        let expectedTargetContext = CollectionContext(includeDirectories: true)
        XCTAssertEqual(store.state.content.collection.collectionContext, expectedTargetContext)
        XCTAssertNil(store.state.content.collection.collectionSession.metadata.reopenContext)
        guard case let .collection(navigation) = store.state.content.navigation.navigationState else {
            return XCTFail("Expected target Collection navigation")
        }
        XCTAssertEqual(navigation.kind, .file(url: targetURL, name: targetFile.name))
        XCTAssertEqual(navigation.context, expectedTargetContext)
    }

    /// RCL-002-open_saved_collection: no-trigger open은 reused tab의 이전 결과와 failure provenance를 제거한다.
    /// 새 저장 draft가 이전 executable Collection의 검색/필터 결과나 scope transaction을 상속하지 않는지 검증한다.
    /// - 검증 내용: entries, selection, response/request IDs, pending query, feedback, dirty scope editor, old context
    /// reset
    /// - 사전 조건: accepted zero와 이전 entries 및 active requests가 함께 남은 file-backed Collection tab
    /// - 기대 결과: 새 target context만 남고 scope dismissal이 submit/applyFilters를 발생시키지 않는다.
    func testOpenSavedCollection_noTriggerOpenClearsReusedTabResponseAndFailureProvenance() async {
        let sourceURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/old.voycoll")
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/new-empty.voycoll")
        let targetFile = makeNoTriggerFile(id: "reused-target", name: "Reused Target")
        let oldContext = CollectionContext(query: "old executable", scopes: ["/old"], conditions: [])
        let oldEntry = makeEntry(path: "/old/result.txt")
        let requests = LockIsolated<[String]>([])
        var state = makeOpenedCollectionState(url: sourceURL, context: oldContext)
        state.content.entryViewLayout.collectionItems = [oldEntry]
        state.content.entryViewLayout.entries = [oldEntry]
        state.content.entryViewLayout.selectedIds = [oldEntry.id]
        state.content.entryViewLayout.lastSelectedId = oldEntry.id
        state.content.entryViewLayout.rangeAnchorId = oldEntry.id
        state.content.entryViewLayout.entryOperations.selectedEntryIDs = [oldEntry.id]
        state.inspector.aiChat.currentContext = .init(summary: "stale selection")
        state.content.composer.collectionContext = oldContext
        state.content.composer.pendingSearchQuery = "pending old query"
        state.content.composer.activeSearchRequestID = UUID(920)
        state.content.composer.activeFiltersRequestID = UUID(921)
        state.content.composer.lastAcceptedSearchRequestID = UUID(922)
        state.content.composer.lastAcceptedFiltersRequestID = UUID(923)
        state.content.composer.lastSearchResponse = .init(itemCount: 1, items: [.string(oldEntry.fullPath)])
        state.content.composer.lastFiltersResponse = .init(itemCount: 0, items: [])
        state.content.entryViewLayout.collectionReplaceEpoch = 17
        state.content.entryViewLayout.activeCollectionReplacePaths = ["/old/in-flight"]
        state.content.entryViewLayout.activeCollectionAppendPaths = [1: ["/old/in-flight"]]
        state.content.entryViewLayout.activeAppendExpectedBatchIndices = [1: 0]
        state.content.composer.transientFeedback = .init(
            id: UUID(924),
            kind: .error,
            message: "old failure",
            stage: .queryExecution,
            category: .executionFailure,
        )
        state.content.composer.scopes = ["/dirty-scope"]
        state.content.composer.beginScopeEditing(path: nil)
        state.content.composer.isPresented = true
        let loadResult = makeSnapshotLoadResult(file: targetFile)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in loadResult }
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = self.makeRegistryClient()
            $0.searchClient.search = { _ in
                requests.withValue { $0.append("submit") }
                return .init(itemCount: 0)
            }
            $0.searchClient.applyFilters = { _ in
                requests.withValue { $0.append("applyFilters") }
                return .init(itemCount: 0)
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: reused tab의 여러 child reset보다 atomic terminal state를 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.openCollectionFile(targetURL))))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertTrue(requests.value.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.collectionItems.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.entries.isEmpty)
        XCTAssertEqual(store.state.content.entryViewLayout.collectionReplaceEpoch, 18)
        XCTAssertTrue(store.state.content.entryViewLayout.activeCollectionReplacePaths.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.activeCollectionAppendPaths.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.activeAppendExpectedBatchIndices.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.selectedIds.isEmpty)
        XCTAssertTrue(
            store.state.content.entryViewLayout.entryOperations.selectedEntryIDs.isEmpty,
            "EntryOperations selection must be cleared through semantic action",
        )
        XCTAssertEqual(
            store.state.inspector.aiChat.currentContext.summary,
            targetFile.name,
            "AI Inspector context must be refreshed through selectionChanged",
        )
        XCTAssertNil(store.state.content.entryViewLayout.lastSelectedId)
        XCTAssertNil(store.state.content.entryViewLayout.rangeAnchorId)
        XCTAssertEqual(store.state.content.composer.collectionContext, .init(includeDirectories: true))
        XCTAssertNil(store.state.content.composer.pendingSearchQuery)
        XCTAssertNil(store.state.content.composer.activeSearchRequestID)
        XCTAssertNil(store.state.content.composer.activeFiltersRequestID)
        XCTAssertNil(store.state.content.composer.lastAcceptedSearchRequestID)
        XCTAssertNil(store.state.content.composer.lastAcceptedFiltersRequestID)
        XCTAssertNil(store.state.content.composer.lastSearchResponse)
        XCTAssertNil(store.state.content.composer.lastFiltersResponse)
        XCTAssertNil(store.state.content.composer.transientFeedback)
        XCTAssertFalse(store.state.content.composer.scopeEditor.isPresented)
        XCTAssertFalse(store.state.content.composer.scopeEditor.hasPendingScopeRuleChanges)
    }

    /// RCL-002-open_saved_collection: restoration dismissal은 dirty old scope editor를 자동 실행하지 않는다.
    /// Composer presentation 종료가 동기 restoration reset 이후 관찰되는 ordering을 검증한다.
    /// - 검증 내용: scope transaction 정리와 submit/applyFilters request cardinality 0
    /// - 사전 조건: open scope editor에 pending scope change가 있고 이전 query search가 committed 된 reused tab
    /// - 기대 결과: target draft가 terminal 상태로 열리고 어떤 retrieval request도 발생하지 않는다.
    func testOpenSavedCollection_dirtyOldScopeEditorCannotAutoExecuteDuringRestorationDismissal() async {
        let sourceURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/old-scope.voycoll")
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/new-scope-empty.voycoll")
        let targetFile = makeNoTriggerFile(id: "scope-dismissal-target", name: "Scope Dismissal Target")
        let oldContext = CollectionContext(query: "old executable", scopes: ["/old"], conditions: [])
        let requests = LockIsolated<[String]>([])
        var state = makeOpenedCollectionState(url: sourceURL, context: oldContext)
        state.content.composer.collectionContext = oldContext
        state.content.composer.scopes = ["/dirty-scope"]
        state.content.composer.beginScopeEditing(path: nil)
        state.content.composer.isPresented = true
        let loadResult = makeSnapshotLoadResult(file: targetFile)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in loadResult }
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = self.makeRegistryClient()
            $0.searchClient.search = { _ in
                requests.withValue { $0.append("submit") }
                return .init(itemCount: 0)
            }
            $0.searchClient.applyFilters = { _ in
                requests.withValue { $0.append("applyFilters") }
                return .init(itemCount: 0)
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: dismissal ordering의 child action보다 request-free terminal state를 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.openCollectionFile(targetURL))))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertTrue(requests.value.isEmpty)
        XCTAssertFalse(store.state.content.composer.scopeEditor.isPresented)
        XCTAssertFalse(store.state.content.composer.scopeEditor.hasPendingScopeRuleChanges)
        XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, targetURL)
    }

    /// RCL-002-open_saved_collection: restoration은 stale scope projection과 in-flight directory search를 폐기한다.
    /// 이전 문서의 scope 검색 결과가 새 valid-empty Collection draft에 늦게 반영되지 않는지 검증한다.
    /// - 검증 내용: list/candidate reset, scopeEditorSearch cancellation, late response 무시, retrieval request 0
    /// - 사전 조건: old search projection과 candidate가 있고 같은 query의 scope directory search가 진행 중임
    /// - 기대 결과: target draft는 fresh default projection을 유지하고 late candidate를 수용하지 않는다.
    func testOpenSavedCollection_restorationCancelsStaleScopeSearchAndClearsProjection() async {
        let sourceURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/old-scope-search.voycoll")
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/new-scope-search-empty.voycoll")
        let targetFile = makeNoTriggerFile(id: "scope-search-target", name: "Scope Search Target")
        let oldContext = CollectionContext(query: "old executable", scopes: ["/old"], conditions: [])
        let oldItem = ComposerScopeUtils.DirectoryItem(
            id: "/old/candidate",
            path: "/old/candidate",
            name: "Old Candidate",
            iconName: "folder",
        )
        let lateItem = ComposerScopeUtils.DirectoryItem(
            id: "/late/candidate",
            path: "/late/candidate",
            name: "Late Candidate",
            iconName: "folder",
        )
        let requests = LockIsolated<[String]>([])
        var state = makeOpenedCollectionState(url: sourceURL, context: oldContext)
        state.content.composer.collectionContext = oldContext
        state.content.composer.scopeEditor.isPresented = true
        state.content.composer.scopeEditor.queryText = "old"
        state.content.composer.scopeEditor.listState = .searchResults(query: "old")
        state.content.composer.scopeEditor.candidateItems = [
            .init(path: oldItem.path, name: oldItem.name, iconName: oldItem.iconName),
        ]
        let loadResult = makeSnapshotLoadResult(file: targetFile)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in loadResult }
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = self.makeRegistryClient()
            $0.searchClient.search = { _ in
                requests.withValue { $0.append("submit") }
                return .init(itemCount: 0)
            }
            $0.searchClient.applyFilters = { _ in
                requests.withValue { $0.append("applyFilters") }
                return .init(itemCount: 0)
            }
            $0.entryLoadingClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: cancellation chain보다 새 document projection과 late-response 불변을 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.content(.composer(.scopeEditorSetQueryText("old"))))
        await store.send(.content(.composer(.scopeEditorSearchResponse("old", .success([oldItem])))))
        await store.send(.navigation(.view(.openCollectionFile(targetURL))))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertTrue(requests.value.isEmpty)
        XCTAssertEqual(store.state.content.composer.scopeEditor.listState, .defaultCandidates)
        XCTAssertTrue(store.state.content.composer.scopeEditor.candidateItems.isEmpty)
        XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, targetURL)

        await store.send(.content(.composer(.scopeEditorSearchResponse("old", .success([lateItem])))))
        XCTAssertEqual(store.state.content.composer.scopeEditor.listState, .defaultCandidates)
        XCTAssertTrue(store.state.content.composer.scopeEditor.candidateItems.isEmpty)
        XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, targetURL)
    }

    /// RCL-002-open_saved_collection: valid-empty metric은 result_status 이외 metadata를 포함하지 않는다.
    /// 저장 draft open의 analytics producer가 민감한 file/query/scope/error 값을 노출하지 않는지 검증한다.
    /// - 검증 내용: collection.open cardinality 1과 exact metadata-only tags
    /// - 사전 조건: semantic-empty definition의 accepted direct open
    /// - 기대 결과: `result_status=valid_empty` 한 필드만 기록된다.
    func testOpenSavedCollection_validEmptyMetricContainsOnlyResultStatus() async {
        let targetURL = URL(fileURLWithPath: "/private/secret/empty.voycoll")
        let file = makeNoTriggerFile(id: "private-id", name: "Private Name")
        let metrics = LockIsolated<[CollectionOpenMetricRecord]>([])
        let loadResult = makeSnapshotLoadResult(file: file)
        let store = TestStore(initialState: FileManagerWindowState()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in loadResult }
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.metricsClient = MetricsClient(
                logMetric: { name, value, tags in
                    metrics.withValue { $0.append(.init(name: name, value: value, tags: tags)) }
                },
                logDAUNavigation: { _ in },
                logDAUEntryAction: { _, _ in },
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: analytics assertion은 canonical open child action을 열거하지 않는다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.openCollectionFile(targetURL))))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertEqual(metrics.value, [
            .init(name: "collection.open", value: 1, tags: ["result_status": "valid_empty"]),
        ])
    }

    /// RCL-002-open_saved_collection: terminal load failure는 original error의 typed category를 기록한다.
    /// fingerprint 문자열에 의존하지 않고 모든 private outcome category가 bounded tag로 생산되는지 검증한다.
    /// - 검증 내용: unsupportedSchema, invalidDefinition, malformed, access, unknown 각각 exact metric 1회
    /// - 사전 조건: accepted direct open load가 각 원본 error type으로 종료됨
    /// - 기대 결과: load_failure와 typed raw category만 기록되고 rollback/alert가 유지된다.
    func testOpenSavedCollection_loadFailureMetricsUseExhaustiveTypedCategories() async {
        let cases: [(CollectionOpenCharacterizationFailure, String)] = [
            (.unsupportedSchema, "unsupportedSchema"),
            (.invalidDefinition, "invalidDefinition"),
            (.malformed, "malformed"),
            (.access, "access"),
            (.unknown, "unknown"),
        ]

        for (index, testCase) in cases.enumerated() {
            let metrics = LockIsolated<[CollectionOpenMetricRecord]>([])
            let targetURL = URL(fileURLWithPath: "/private/secret/failure-\(index).voycoll")
            let store = TestStore(initialState: FileManagerWindowState()) {
                FileManagerFeature()
            } withDependencies: {
                $0.collectionFileClient.load = { _ in throw testCase.0.error }
                $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
                $0.collectionStalenessClient = .testValue
                $0.registryClient = .testValue
                $0.metricsClient = MetricsClient(
                    logMetric: { name, value, tags in
                        metrics.withValue { $0.append(.init(name: name, value: value, tags: tags)) }
                    },
                    logDAUNavigation: { _ in },
                    logDAUEntryAction: { _, _ in },
                )
                $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
                $0.uuid = .constant(UUID(index + 930))
                $0.continuousClock = ImmediateClock()
            }
            // store.exhaustivity = .off: category matrix는 failure cleanup child action보다 metric 경계를 검증한다.
            store.exhaustivity = .off(showSkippedAssertions: false)

            await store.send(.navigation(.view(.openCollectionFile(targetURL))))
            await store.skipReceivedActions(strict: false)
            await store.finish()

            XCTAssertEqual(metrics.value, [
                .init(
                    name: "collection.open",
                    value: 1,
                    tags: ["result_status": "load_failure", "error_category": testCase.1],
                ),
            ])
        }
    }

    /// RCL-002-open_saved_collection: executable과 superseded completion은 VOY-590 outcome metric을 내지 않는다.
    /// terminal class가 아닌 open attempt가 valid_empty/load_failure로 오분류되지 않는지 검증한다.
    /// - 검증 내용: executable success와 correlation이 제거된 stale success/failure의 metric cardinality 0
    /// - 사전 조건: query-bearing accepted open 이후 별도 request의 pending correlation이 취소됨
    /// - 기대 결과: 두 경로 모두 collection.open event가 없다.
    func testOpenSavedCollection_supersededOrExecutableAttemptsEmitNoVoy590OutcomeMetric() async {
        let executableURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/executable-no-metric.voycoll")
        let executable = makeNoTriggerFile(id: "executable-no-metric", name: "Executable", query: "invoice")
        let metrics = LockIsolated<[CollectionOpenMetricRecord]>([])
        let executableLoadResult = makeSnapshotLoadResult(file: executable)
        let store = TestStore(initialState: FileManagerWindowState()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in executableLoadResult }
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.searchClient = .testValue
            $0.metricsClient = MetricsClient(
                logMetric: { name, value, tags in
                    metrics.withValue { $0.append(.init(name: name, value: value, tags: tags)) }
                },
                logDAUNavigation: { _ in },
                logDAUEntryAction: { _, _ in },
            )
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: executable chain과 stale terminal 무시의 metric 결과만 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.openCollectionFile(executableURL))))
        await store.skipReceivedActions(strict: false)
        await store.finish()
        XCTAssertTrue(metrics.value.isEmpty)

        let sourceRoute = ContentPageNavigationRoute.folder("/VoyagerFixtures/Source")
        let supersededRequest = ContentPageCollectionOpenRequest(
            id: UUID(940),
            url: URL(fileURLWithPath: "/VoyagerFixtures/Collections/superseded.voycoll"),
            sourceRoute: sourceRoute,
            prePrepareBackHistory: [.init(navigationState: .home)],
            prePrepareForwardHistory: [.init(navigationState: .computer)],
        )
        let replacementURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/replacement.voycoll")
        var supersessionState = FileManagerWindowState()
        supersessionState.content.navigation.navigationState = sourceRoute
        supersessionState.pendingCollectionOpenRequest = supersededRequest
        supersessionState.content.entryViewLayout.isCollectionContentLoading = true
        let supersessionStore = TestStore(initialState: supersessionState) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in executableLoadResult }
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.searchClient = .testValue
            $0.metricsClient = MetricsClient(
                logMetric: { name, value, tags in
                    metrics.withValue { $0.append(.init(name: name, value: value, tags: tags)) }
                },
                logDAUNavigation: { _ in },
                logDAUEntryAction: { _, _ in },
            )
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: replacement open의 child chain보다 superseded correlation과 metric을 검증한다.
        supersessionStore.exhaustivity = .off(showSkippedAssertions: false)

        await supersessionStore.send(.navigation(.view(.openCollectionFile(replacementURL))))
        await supersessionStore.skipReceivedActions(strict: false)
        await supersessionStore.finish()
        await supersessionStore.send(.navigation(.internal(.collectionFileLoaded(
            request: supersededRequest,
            result: .failure(.init(
                error: CollectionFileCompatibilityError.invalidPropertyListPayload,
                category: .malformed,
            )),
        ))))
        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// RCL-002-open_saved_collection: 저장 Collection에서 다른 저장 Collection 열기 완료 적용
    /// 기존 Collection 정리 action이 실행된 뒤에도 동일 요청의 load 완료가 새 Collection으로 전환되는지 검증한다.
    /// - 검증 내용: dirty Collection A의 load 중 Save 차단과 B route 적용 및 pending/loading 정리
    /// - 사전 조건: dirty Collection A가 열려 있고 B 파일 load가 snapshot-bearing 결과를 반환함
    /// - 기대 결과: load 중 A 상태와 Save 차단을 유지한 뒤 Collection B로 전환됨
    func testOpenSavedCollection_fromSavedCollection_appliesMatchingCompletion() async {
        let sourceURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/source.voycoll")
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/target.voycoll")
        let sourceContext = CollectionContext(
            query: "source",
            scopes: ["/VoyagerFixtures/Source"],
            conditions: [],
        )
        let dirtySourceContext = makeDirtySourceContext(basedOn: sourceContext)
        let targetFile = makeSnapshotFile()
        let targetLoadResult = makeSnapshotLoadResult(file: targetFile)
        let loadGate = CollectionFileLoadSuspensionGate()

        let initialState = makeDirtyCollectionSwitchState(
            sourceURL: sourceURL,
            sourceContext: sourceContext,
            dirtySourceContext: dirtySourceContext,
        )

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in try await loadGate.wait() }
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .constant(UUID(608))
            $0.continuousClock = ImmediateClock()
        }
        // 비포괄적: Collection open은 여러 child reducer action을 방출하므로 최종 lifecycle 상태를 검증한다.
        store.exhaustivity = .off

        XCTAssertTrue(store.state.content.canSaveCollection)

        await store.send(.navigation(.view(.openCollectionFile(targetURL))))
        await loadGate.waitUntilWaiting()
        await store.skipReceivedActions()

        assertCollectionOpenInFlight(
            store.state,
            sourceURL: sourceURL,
            targetURL: targetURL,
            sourceContext: sourceContext,
            sourceDraftContext: dirtySourceContext,
        )

        await loadGate.resume(with: .success(targetLoadResult))
        await store.skipReceivedActions()
        await store.finish()

        assertCollectionOpenCompleted(
            store.state,
            targetURL: targetURL,
            targetFile: targetFile,
        )
    }

    /// RCL-002-open_saved_collection: 다른 저장 Collection 열기 실패 시 기존 Collection 복원
    /// Collection B load 실패가 Collection A와 기존 navigation history를 파괴하지 않는지 검증한다.
    /// - 검증 내용: Collection A document/route/history 복원과 pending/loading 정리
    /// - 사전 조건: Collection A가 열려 있고 기존 Home history가 있으며 B 파일 load가 실패함
    /// - 기대 결과: Collection A가 유지되고 기존 history가 보존되며 오류 요청 상태가 남지 않음
    func testOpenSavedCollection_fromSavedCollectionFailure_restoresSourceWithoutHistoryRollback() async {
        let sourceURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/source.voycoll")
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/missing.voycoll")
        let sourceContext = CollectionContext(
            query: "source",
            scopes: ["/VoyagerFixtures/Source"],
            conditions: [],
        )
        let dirtySourceContext = makeDirtySourceContext(basedOn: sourceContext)
        let expectedHistory = [ContentPageNavigationHistorySnapshot(navigationState: .home)]
        let loadGate = CollectionFileLoadSuspensionGate()
        var initialState = makeOpenedCollectionState(url: sourceURL, context: sourceContext)
        initialState.content.collection.collectionContext = dirtySourceContext
        initialState.content.navigation.backHistory = expectedHistory

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in try await loadGate.wait() }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.searchClient = .testValue
            $0.userDefaultsClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .constant(UUID(610))
            $0.continuousClock = ImmediateClock()
        }
        // 비포괄적: Collection 복원은 child reducer action을 방출하므로 최종 복원 상태를 검증한다.
        store.exhaustivity = .off

        XCTAssertTrue(store.state.content.canSaveCollection)

        await store.send(.navigation(.view(.openCollectionFile(targetURL))))
        await loadGate.waitUntilWaiting()
        await store.skipReceivedActions()
        assertCollectionOpenInFlight(
            store.state,
            sourceURL: sourceURL,
            targetURL: targetURL,
            sourceContext: sourceContext,
            sourceDraftContext: dirtySourceContext,
        )

        await loadGate.resume(with: .failure)
        await store.skipReceivedActions()
        await store.finish()

        assertCollectionOpenFailurePreservedSource(
            store.state,
            sourceURL: sourceURL,
            sourceContext: sourceContext,
            sourceDraftContext: dirtySourceContext,
            expectedHistory: expectedHistory,
        )
    }

    /// RCL-002-open_saved_collection: pending Collection checkpoint 복원 후 새 경로로 이동
    /// 동일 user navigation action의 restore와 perform effect가 병합되어 history가 역전되지 않는지 검증한다.
    /// - 검증 내용: pending/loading 정리와 checkpoint 복원 뒤 새 source snapshot 기록
    /// - 사전 조건: folder source에서 Collection open prepare가 back/forward history를 변경한 상태
    /// - 기대 결과: 새 경로와 back/forward history가 하나의 직렬화된 navigation transaction으로 일치함
    func testNavigateToPathWhileCollectionOpenPendingRestoresCheckpointBeforeNavigation() async {
        let sourceRoute = ContentPageNavigationRoute.folder("/source")
        let targetRoute = ContentPageNavigationRoute.folder("/new")
        let originalBackHistory = [
            ContentPageNavigationHistorySnapshot(navigationState: .folder("/old")),
        ]
        let originalForwardHistory = [
            ContentPageNavigationHistorySnapshot(navigationState: .folder("/future")),
        ]
        let sourceSnapshot = ContentPageNavigationHistorySnapshot(navigationState: sourceRoute)
        var initialState = FileManagerFeature.State()
        initialState.content.navigation.navigationState = sourceRoute
        initialState.content.navigation.backHistory = originalBackHistory + [sourceSnapshot]
        initialState.content.navigation.forwardHistory = []
        initialState.content.entryViewLayout.isCollectionContentLoading = true
        initialState.pendingCollectionOpenRequest = ContentPageCollectionOpenRequest(
            id: UUID(734),
            url: URL(fileURLWithPath: "/target.voycollection"),
            sourceRoute: sourceRoute,
            prePrepareBackHistory: originalBackHistory,
            prePrepareForwardHistory: originalForwardHistory,
        )

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 734))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileManagerClient.displayName = { $0 }
        }
        // 비포괄적: downstream content load보다 restore와 새 navigation의 최종 순서를 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.navigateToPath("/new"))))
        await store.skipReceivedActions(strict: false)

        XCTAssertNil(store.state.pendingCollectionOpenRequest)
        XCTAssertFalse(store.state.content.entryViewLayout.isCollectionContentLoading)
        XCTAssertEqual(store.state.content.navigation.navigationState, targetRoute)
        XCTAssertEqual(store.state.content.navigation.backHistory, originalBackHistory + [sourceSnapshot])
        XCTAssertEqual(store.state.content.navigation.forwardHistory, [])
    }

    // MARK: - RCL-002-show_restored_collection_snapshot

    /// RCL-002-show_restored_collection_snapshot: snapshot-bearing collection open은 저장 snapshot path를 content list에 적용함
    /// FileManager window open reducer가 hydrated snapshot payload를 entry view layout 검색 path 적용 action으로 라우팅하는지 검증한다.
    /// - 검증 내용: collection file load 후 collection navigation, collection mode, snapshot path 적용 action 수신
    /// - 사전 조건: snapshotMeta fingerprint가 현재 definition과 일치하는 `.voycoll` equivalent file load result
    /// - 기대 결과: snapshot-first display를 위해 `applyCollectionSearchPaths`가 저장된 snapshot path로 호출됨
    func testShowRestoredCollectionSnapshot_withHydratedLoadResult_appliesSnapshotPaths() async {
        let file = makeSnapshotFile()
        let searchRequests = LockIsolated<Int>(0)
        let filterRequests = LockIsolated<Int>(0)
        let loadResult = CollectionFileLoadResult(
            file: file,
            containerFormat: .package,
            compatibility: makeSnapshotAllowedCompatibility(),
        )
        var initialState = FileManagerWindowState()
        let collectionURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/snapshot.voycoll")
        let request = ContentPageCollectionOpenRequest(
            id: UUID(608),
            url: collectionURL,
            sourceRoute: initialState.content.navigation.navigationState,
            prePrepareBackHistory: initialState.content.navigation.backHistory,
            prePrepareForwardHistory: initialState.content.navigation.forwardHistory,
        )
        initialState.pendingCollectionOpenRequest = request
        initialState.content.collection.collectionSession.document = .init(
            url: collectionURL,
            name: "snapshot",
            compatibility: makeSnapshotAllowedCompatibility(),
        )

        let store = TestStore(initialState: initialState) {
            FileManagerNavigationActionReducer()
        } withDependencies: {
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.searchClient.search = { _ in
                searchRequests.withValue { $0 += 1 }
                return .init(itemCount: 0)
            }
            $0.searchClient.applyFilters = { _ in
                filterRequests.withValue { $0 += 1 }
                return .init(itemCount: 0)
            }
        }
        // 이 suite는 window open effect의 라우팅을 검증하므로 composer/content child 내부 state diff는 제외한다.
        store.exhaustivity = .off

        await store.send(.navigation(.internal(.collectionFileLoaded(
            request: request,
            result: .success(loadResult),
        ))))
        await store.receive(\.content.composer.view.setPresented)
        await store.receive { action in
            guard case .tabContent(_, .internal(.requestNavigation)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .tabContent(_, .internal(.applyNavigationState)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .tabContent(_, .entryViewLayout(.internal(.setCollectionMode))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .tabContent(_, .composer(.internal(.syncCollectionState))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .tabContent(_, .entryViewLayout(.internal(.applyCollectionSearchPaths))) = action else {
                return false
            }
            return true
        }
        await store.receive { action in
            guard case .tabContent(_, .composer(.internal(.searchListApplied))) = action else { return false }
            return true
        }
        await store.finish()
        XCTAssertEqual(searchRequests.value, 0)
        XCTAssertEqual(filterRequests.value, 0)
    }

    // MARK: - RCL-002-alert_unsaved_collection_filter_changes

    /// RCL-002-save_collection_filter_changes: undo는 제거한 condition draft를 canonical owner에 복원한다.
    /// Composer history가 conditionEditors를 되돌린 뒤 CollectionState/Composer context도 함께 복원되는지 검증한다.
    func testEditFileBackedCollection_undoRestoresConditionToCanonicalDraft() async {
        let targetURL = URL(fileURLWithPath: "/VoyagerFixtures/Collections/undo-condition.voycoll")
        let condition = makeEditCondition(values: nil)
        let baseline = CollectionContext(query: "baseline", scopes: ["/tmp"], conditions: [condition])
        let requests = LockIsolated<[String]>([])
        var state = makeFileBackedEmptyCollectionContentState(targetURL: targetURL)
        state.collection.collectionContext = baseline
        state.collection.collectionSession.metadata.baseline = .init(context: baseline)
        state.composer.collectionContext = baseline
        state.composer.scopes = baseline.scopes
        state.composer.conditionEditors = [ConditionEditorState(id: UUID(952), condition: condition)]
        let store = makeCollectionEditStore(initialState: state, requests: requests)

        await store.send(.composer(.view(.removeCondition(id: UUID(952)))))
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(store.state.collection.collectionContext?.conditions, [])
        XCTAssertTrue(store.state.collection.isDirty)

        await store.send(.composer(.view(.undo)))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertEqual(store.state.composer.conditions, [condition])
        XCTAssertEqual(store.state.collection.collectionContext?.conditions, [condition])
        XCTAssertEqual(store.state.composer.collectionContext?.conditions, [condition])
        XCTAssertFalse(store.state.collection.isDirty)
        XCTAssertTrue(requests.value.isEmpty)
    }

    /// RCL-002-alert_unsaved_collection_filter_changes: 직접 탐색도 unsaved alert 경계를 거친다.
    /// sidebar의 Recents 등 direct navigation이 history 탐색과 같은 draft 동기화와 경고 경계를 공유하는지 검증한다.
    func testAlertUnsavedCollectionFilterChanges_directNavigationSyncsDraftAndPrompts() async {
        let baseline = CollectionContext(query: "", scopes: [], conditions: [])
        var state = makeOpenedCollectionState(
            url: URL(fileURLWithPath: "/VoyagerFixtures/Collections/direct-navigation.voycoll"),
            context: baseline,
        )
        state.content.composer.collectionContext = baseline
        state.content.composer.conditionEditors = [
            ConditionEditorState(id: UUID(953), condition: makeEditCondition(values: nil)),
        ]
        let collectionRoute = state.content.navigation.navigationState
        let store = TestStore(initialState: state) {
            FileManagerNavigationActionReducer()
        } withDependencies: {
            $0.collectionAlertClient.showUnsavedNavigationAlert = { .cancel }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.showRecents)))
        await store.receive(\.navigation.internal.showUnsavedNavigationAlert)
        await store.receive(\.navigation.internal.unsavedNavigationAlertResponse)
        await store.finish()

        let condition = state.content.composer.conditions[0]
        XCTAssertEqual(store.state.content.collection.collectionContext?.conditions, [condition])
        XCTAssertEqual(store.state.content.composer.collectionContext?.conditions, [condition])
        XCTAssertTrue(store.state.content.collection.isDirty)
        XCTAssertEqual(store.state.content.navigation.navigationState, collectionRoute)
    }

    /// RCL-002-alert_unsaved_collection_filter_changes: cancel does not install a navigation reveal.
    /// Cancelled dirty navigation must not create a pending entry ID or destination guard.
    /// - 검증 내용: unsaved alert cancel leaves both pending-selection fields empty.
    /// - 사전 조건: dirty collection state and a Back navigation request.
    /// - 기대 결과: cancel response completes with no pending reveal state.
    func testAlertUnsavedCollectionFilterChanges_cancelLeavesRevealStateEmpty() async {
        let store = TestStore(initialState: makeDirtyWindowState()) {
            FileManagerNavigationActionReducer()
        } withDependencies: {
            $0.collectionAlertClient.showUnsavedNavigationAlert = { .cancel }
        }

        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.showUnsavedNavigationAlert)
        await store.receive(\.navigation.internal.unsavedNavigationAlertResponse)
        await store.finish()

        XCTAssertNil(store.state.content.pendingSelectEntryID)
        XCTAssertNil(store.state.content.pendingSelectEntryDestinationPath)
    }

    /// RCL-002-alert_unsaved_collection_filter_changes: dirty collection navigation은 unsaved alert로 라우팅됨
    /// 저장되지 않은 collection filter 변경이 있을 때 window navigation reducer가 alert action을 내보내는지 검증한다.
    /// - 검증 내용: goBack navigation request가 performNavigation 대신 showUnsavedNavigationAlert로 전환됨
    /// - 사전 조건: collection mode이며 현재 context가 baseline과 달라 저장 가능한 dirty 상태
    /// - 기대 결과: pending back navigation을 포함한 unsaved alert action이 수신됨
    func testAlertUnsavedCollectionFilterChanges_withDirtyCollection_routesToUnsavedAlert() async {
        let store = TestStore(initialState: makeDirtyWindowState()) {
            FileManagerNavigationActionReducer()
        } withDependencies: {
            $0.collectionAlertClient = .testValue
        }

        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.showUnsavedNavigationAlert)
        await store.receive(\.navigation.internal.unsavedNavigationAlertResponse)
        await store.finish()
    }

    /// RCL-002-alert_unsaved_collection_filter_changes: condition-only draft도 history 이동 전에 동기화됨
    /// Composer state에만 남은 condition 변경을 window navigation의 dirty guard가 놓치지 않는지 검증한다.
    func testAlertUnsavedCollectionFilterChanges_conditionOnlyDraftSyncsBeforeHistoryPrompt() async {
        let baseline = CollectionContext(query: "", scopes: [], conditions: [])
        var state = makeOpenedCollectionState(
            url: URL(fileURLWithPath: "/VoyagerFixtures/Collections/condition-navigation.voycoll"),
            context: baseline,
        )
        state.content.composer.collectionContext = baseline
        state.content.composer.conditionEditors = [
            ConditionEditorState(id: UUID(953), condition: makeEditCondition(values: nil)),
        ]
        let store = TestStore(initialState: state) {
            FileManagerNavigationActionReducer()
        } withDependencies: {
            $0.collectionAlertClient.showUnsavedNavigationAlert = { .cancel }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.showUnsavedNavigationAlert)
        await store.receive(\.navigation.internal.unsavedNavigationAlertResponse)
        await store.finish()

        let condition = state.content.composer.conditions[0]
        XCTAssertEqual(store.state.content.collection.collectionContext?.conditions, [condition])
        XCTAssertEqual(store.state.content.composer.collectionContext?.conditions, [condition])
        XCTAssertTrue(store.state.content.collection.isDirty)
    }

    /// RCL-002-alert_unsaved_collection_filter_changes: Collection open loading 중에도 dirty navigation 보호 유지
    /// Save UI가 비활성화된 loading 상태와 미저장 변경 보호 판정이 분리되는지 검증한다.
    /// - 검증 내용: loading 중 goBack 요청이 unsaved alert로 라우팅됨
    /// - 사전 조건: dirty Collection이며 다른 Collection open loading이 진행 중
    /// - 기대 결과: Save eligibility는 false지만 back navigation은 alert를 거침
    func testAlertUnsavedCollectionFilterChanges_whileLoading_routesToUnsavedAlert() async {
        var state = makeDirtyWindowState()
        state.content.entryViewLayout.isCollectionContentLoading = true
        let store = TestStore(initialState: state) {
            FileManagerNavigationActionReducer()
        } withDependencies: {
            $0.collectionAlertClient = .testValue
        }

        XCTAssertFalse(store.state.content.canSaveCollection)
        XCTAssertTrue(store.state.content.hasUnsavedCollectionChanges)

        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.showUnsavedNavigationAlert)
        await store.receive(\.navigation.internal.unsavedNavigationAlertResponse)
        await store.finish()
    }

    private func makeSnapshotFile() -> VoyagerCollectionFile {
        let base = VoyagerCollectionFile(
            id: "rcl-filemanager-snapshot",
            name: "RCL FileManager Snapshot",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            query: "design review",
            scopes: ["/VoyagerFixtures/Projects"],
            excludedScopes: [],
            includeSubfolders: true,
            includeDirectories: true,
            conditions: [],
            snapshot: CollectionPersistedSnapshot(items: [
                .string("/VoyagerFixtures/Projects/RCL/spec.md"),
                .string("/VoyagerFixtures/Projects/RCL/notes.txt"),
            ]),
            snapshotMeta: nil,
            appVersion: "VOY-346-test",
        )
        return VoyagerCollectionFile(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            query: base.query,
            scopes: base.scopes,
            excludedScopes: base.excludedScopes,
            includeSubfolders: base.includeSubfolders,
            includeDirectories: base.includeDirectories,
            conditions: base.conditions,
            snapshot: base.snapshot,
            snapshotMeta: CollectionSnapshotMeta(
                definitionFingerprint: CollectionSnapshotHydration.definitionFingerprint(file: base),
                capturedAt: Date(timeIntervalSince1970: 1_700_000_200),
                itemCount: 2,
                relevanceRoots: ["/VoyagerFixtures/Projects"],
            ),
            appVersion: base.appVersion,
        )
    }

    private func makeNoTriggerFile(
        id: String,
        name: String,
        query: String = "",
        scopes: [String] = [],
        conditions: [CollectionCondition] = [],
    ) -> VoyagerCollectionFile {
        VoyagerCollectionFile(
            id: id,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            query: query,
            scopes: scopes,
            excludedScopes: [],
            includeSubfolders: true,
            includeDirectories: true,
            conditions: conditions,
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: "test",
        )
    }

    private func makeEntry(path: String) -> EntryModel {
        EntryModel(
            name: URL(fileURLWithPath: path).lastPathComponent,
            fullPath: path,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: URL(fileURLWithPath: path).pathExtension,
            facets: EntryFacets(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }

    private func makeDirtySourceContext(basedOn sourceContext: CollectionContext) -> CollectionContext {
        CollectionContext(
            query: "source draft",
            scopes: sourceContext.scopes,
            conditions: [],
        )
    }

    private func makeSnapshotLoadResult(file: VoyagerCollectionFile) -> CollectionFileLoadResult {
        CollectionFileLoadResult(
            file: file,
            containerFormat: .package,
            compatibility: makeSnapshotAllowedCompatibility(),
        )
    }

    private func makeDirtyCollectionSwitchState(
        sourceURL: URL,
        sourceContext: CollectionContext,
        dirtySourceContext: CollectionContext,
    ) -> FileManagerWindowState {
        var state = makeOpenedCollectionState(url: sourceURL, context: sourceContext)
        state.content.collection.collectionContext = dirtySourceContext
        state.content.composer.isLoadingFilters = true
        state.content.composer.isFilteringInFlight = true
        state.content.composer.activeFiltersRequestID = UUID(609)
        state.content.composer.pendingSearchQuery = "source"
        state.content.composer.queryRenderPhase = .searching
        return state
    }

    private func assertCollectionOpenInFlight(
        _ state: FileManagerWindowState,
        sourceURL: URL,
        targetURL: URL,
        sourceContext: CollectionContext,
        sourceDraftContext: CollectionContext,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(state.pendingCollectionOpenRequest?.url, targetURL, file: file, line: line)
        XCTAssertTrue(state.content.entryViewLayout.isCollectionContentLoading, file: file, line: line)
        XCTAssertEqual(state.content.collection.collectionSession.document?.url, sourceURL, file: file, line: line)
        XCTAssertEqual(
            state.content.collection.collectionSession.metadata.baseline?.context,
            sourceContext,
            file: file,
            line: line,
        )
        XCTAssertEqual(state.content.collection.collectionContext, sourceDraftContext, file: file, line: line)
        XCTAssertFalse(state.content.canSaveCollection, file: file, line: line)
        guard case let .collection(navigation) = state.content.navigation.navigationState else {
            return XCTFail("Collection B load 중에는 Collection A route가 유지되어야 합니다", file: file, line: line)
        }
        XCTAssertEqual(navigation.kind, .file(url: sourceURL, name: "source"), file: file, line: line)
        XCTAssertEqual(navigation.context, sourceContext, file: file, line: line)
    }

    private func assertCollectionOpenFailurePreservedSource(
        _ state: FileManagerWindowState,
        sourceURL: URL,
        sourceContext: CollectionContext,
        sourceDraftContext: CollectionContext,
        expectedHistory: [ContentPageNavigationHistorySnapshot],
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertNil(state.pendingCollectionOpenRequest, file: file, line: line)
        XCTAssertFalse(state.content.entryViewLayout.isCollectionContentLoading, file: file, line: line)
        XCTAssertTrue(state.content.entryViewLayout.isCollectionMode, file: file, line: line)
        XCTAssertTrue(state.content.canSaveCollection, file: file, line: line)
        XCTAssertEqual(state.content.collection.collectionSession.document?.url, sourceURL, file: file, line: line)
        XCTAssertEqual(
            state.content.collection.collectionSession.metadata.baseline?.context,
            sourceContext,
            file: file,
            line: line,
        )
        XCTAssertEqual(state.content.collection.collectionContext, sourceDraftContext, file: file, line: line)
        XCTAssertEqual(state.content.navigation.backHistory, expectedHistory, file: file, line: line)
        guard case let .collection(navigation) = state.content.navigation.navigationState else {
            return XCTFail("Collection A route가 유지되어야 합니다", file: file, line: line)
        }
        XCTAssertEqual(navigation.kind, .file(url: sourceURL, name: "source"), file: file, line: line)
        XCTAssertEqual(navigation.context, sourceContext, file: file, line: line)
    }

    private func assertCollectionOpenCompleted(
        _ state: FileManagerWindowState,
        targetURL: URL,
        targetFile: VoyagerCollectionFile,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertNil(state.pendingCollectionOpenRequest, file: file, line: line)
        XCTAssertFalse(state.content.entryViewLayout.isCollectionContentLoading, file: file, line: line)
        XCTAssertFalse(state.content.composer.isLoadingFilters, file: file, line: line)
        XCTAssertFalse(state.content.composer.isFilteringInFlight, file: file, line: line)
        XCTAssertNil(state.content.composer.activeFiltersRequestID, file: file, line: line)
        XCTAssertNil(state.content.composer.pendingSearchQuery, file: file, line: line)
        XCTAssertEqual(state.content.composer.queryRenderPhase, .idle, file: file, line: line)
        XCTAssertEqual(state.content.collection.collectionSession.document?.url, targetURL, file: file, line: line)
        guard case let .collection(navigation) = state.content.navigation.navigationState else {
            return XCTFail("Collection B route가 적용되어야 합니다", file: file, line: line)
        }
        XCTAssertEqual(navigation.kind, .file(url: targetURL, name: targetFile.name), file: file, line: line)
        XCTAssertEqual(navigation.context.query, targetFile.query, file: file, line: line)
        XCTAssertEqual(navigation.context.scopes, targetFile.scopes, file: file, line: line)
    }

    private func makeOpenedCollectionState(
        url: URL,
        context: CollectionContext,
    ) -> FileManagerWindowState {
        let navigation = ContentPageCollectionNavigation(
            kind: .file(url: url, name: url.deletingPathExtension().lastPathComponent),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
            compatibility: makeSnapshotAllowedCompatibility(),
        )
        var state = FileManagerWindowState()
        state.content.navigation.navigationState = .collection(navigation)
        state.content.navigation.titlePath = context.scopes.first ?? "/"
        state.content.entryViewLayout.isCollectionMode = true
        state.content.collection.collectionContext = context
        state.content.collection.collectionSession.document = .init(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            compatibility: makeSnapshotAllowedCompatibility(),
        )
        state.content.collection.collectionSession.metadata.baseline = .init(context: context)
        return state
    }

    private func makeDirtyWindowState() -> FileManagerWindowState {
        let baseline = CollectionContext(query: "baseline", scopes: ["/VoyagerFixtures/Documents"], conditions: [])
        let current = CollectionContext(query: "changed", scopes: ["/VoyagerFixtures/Documents"], conditions: [])
        var state = FileManagerWindowState()
        state.content.entryViewLayout.isCollectionMode = true
        state.content.collection.collectionContext = current
        state.content.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/VoyagerFixtures/Collections/dirty.voycoll"),
            name: "dirty",
            compatibility: makeSnapshotAllowedCompatibility(),
        )
        state.content.collection.collectionSession.metadata.baseline = .init(context: baseline)
        state.content.collection.collectionSession.phase = .opened(kind: .definition, base: .ready, inflight: .none)
        return state
    }

    private func makeSnapshotAllowedCompatibility() -> CollectionFileCompatibilityMetadata {
        .init(
            sourceSchemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
            migrationPath: [.currentSchemaV2],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: true,
            writeBackReason: .allowed,
        )
    }

    private func makeFileBackedEmptyCollectionContentState(
        targetURL: URL,
    ) -> FileManagerContentState {
        let context = CollectionContext()
        let compatibility = makeSnapshotAllowedCompatibility()
        var state = FileManagerContentState()
        state.navigation.navigationState = .collection(.init(
            kind: .file(url: targetURL, name: targetURL.deletingPathExtension().lastPathComponent),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
            compatibility: compatibility,
        ))
        state.entryViewLayout.isCollectionMode = true
        state.collection.collectionContext = context
        state.collection.collectionSession.document = .init(
            url: targetURL,
            name: targetURL.deletingPathExtension().lastPathComponent,
            compatibility: compatibility,
        )
        state.collection.collectionSession.metadata.baseline = .init(context: context)
        state.collection.collectionSession.phase = .opened(kind: .definition, base: .ready, inflight: .none)
        state.composer.collectionContext = context
        state.composer.openedCollectionURL = targetURL
        state.composer.openedCollectionCompatibility = compatibility
        state.composer.isCollectionMode = true
        return state
    }

    private func makeCollectionEditStore(
        targetURL: URL,
        requests: LockIsolated<[String]>,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        makeCollectionEditStore(
            initialState: makeFileBackedEmptyCollectionContentState(targetURL: targetURL),
            requests: requests,
        )
    }

    private func makeCollectionEditStore(
        initialState: FileManagerContentState,
        requests: LockIsolated<[String]>,
        saveURLs: LockIsolated<[URL]>? = nil,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.collectionAlertClient = .testValue
            $0.collectionFileClient = .testValue
            $0.collectionFileClient.save = { _, url in
                saveURLs?.withValue { $0.append(url) }
            }
            $0.collectionStalenessClient = .testValue
            $0.registryClient = makeRegistryClient()
            $0.searchClient.search = { _ in
                requests.withValue { $0.append("submit") }
                return .init(itemCount: 0)
            }
            $0.searchClient.applyFilters = { _ in
                requests.withValue { $0.append("applyFilters") }
                return .init(itemCount: 0)
            }
            $0.entryLoadingClient = .testValue
            $0.userDefaultsClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: composed child response보다 retrieval request cardinality와 terminal state를 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private func makeEditCondition(values: [String]?) -> Condition {
        Condition(
            property: .init(
                key: "kind",
                label: "Kind",
                type: .string,
                unitContract: nil,
                operatorOptions: [.init(code: "eq", label: "Equals")],
            ),
            operation: values == nil ? nil : .init(
                code: "eq",
                label: "Equals",
                valueContract: .init(shape: .single, count: .fixed(1), input: .singleText),
            ),
            values: values,
            availability: .available,
            opaqueSource: nil,
        )
    }

    private func makePresentationCondition(
        availability: Condition.Availability,
        values: [String]?,
    ) -> Condition {
        Condition(
            property: .init(
                key: "kind",
                label: "Kind",
                type: .string,
                unitContract: nil,
                operatorOptions: [.init(code: "eq", label: "Equals")],
            ),
            operation: values == nil ? nil : .init(
                code: "eq",
                label: "Equals",
                valueContract: .init(shape: .single, count: .fixed(1), input: .singleText),
            ),
            values: values,
            availability: availability,
            opaqueSource: nil,
        )
    }

    private func makeEditSavePayload(context: CollectionContext) -> SaveRequestPayload {
        SaveRequestPayload(
            context: context,
            isSearchLoading: false,
            isFiltersLoading: false,
            snapshotItems: nil,
            definitionFingerprint: "rcl-002-edit",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_200),
            relevanceRoots: context.scopes,
            openedCompatibility: nil,
        )
    }
}
