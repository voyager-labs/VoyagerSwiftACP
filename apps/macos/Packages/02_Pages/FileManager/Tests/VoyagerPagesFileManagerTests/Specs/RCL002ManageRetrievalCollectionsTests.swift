@_spi(Internals) import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
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

@MainActor
final class RCL002ManageRetrievalCollectionsTests: XCTestCase {
    // MARK: - RCL-002-save_collection_filter_changes

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
        XCTAssertEqual(condition.propertyKey, "tag_names")
        XCTAssertEqual(condition.propertyLabel, "Registry Tag Label")
        XCTAssertEqual(condition.propertyType, "categorical")
        XCTAssertEqual(condition.operatorCode, "any")
        XCTAssertEqual(condition.operatorLabel, "Registry Any Label")
        XCTAssertEqual(condition.operatorValueArity, 1)
        XCTAssertEqual(condition.operatorValueUIKind, "listText")
        XCTAssertEqual(condition.valueType, "string_list")
        XCTAssertEqual(condition.values, ["Work"])
        XCTAssertTrue(condition.isActive)
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
        let recentCondition = try XCTUnwrap(context.conditions.first { $0.propertyKey == "last_used_date" })
        XCTAssertEqual(recentCondition.propertyLabel, "Registry Last Used Label")
        XCTAssertEqual(recentCondition.propertyType, "date")
        XCTAssertEqual(recentCondition.operatorCode, "gt")
        XCTAssertEqual(recentCondition.operatorLabel, "Registry Greater Than Label")
        XCTAssertEqual(recentCondition.operatorValueArity, 1)
        XCTAssertEqual(recentCondition.operatorValueUIKind, "singleDate")
        XCTAssertEqual(recentCondition.valueType, "date")
        XCTAssertEqual(
            recentCondition.values,
            [FileManagerVirtualCollectionContextFactory.recentsSinceAnyOpenedLiteral],
        )
        XCTAssertTrue(recentCondition.isActive)

        let directoryExclusion = try XCTUnwrap(context.conditions.first { $0.propertyKey == "content_type_tree" })
        XCTAssertEqual(directoryExclusion.propertyLabel, "Registry Content Type Tree Label")
        XCTAssertEqual(directoryExclusion.propertyType, "string")
        XCTAssertEqual(directoryExclusion.operatorCode, "neq")
        XCTAssertEqual(directoryExclusion.operatorLabel, "Registry Not Equal Label")
        XCTAssertEqual(directoryExclusion.operatorValueArity, 1)
        XCTAssertEqual(directoryExclusion.operatorValueUIKind, "singleText")
        XCTAssertEqual(directoryExclusion.valueType, "string")
        XCTAssertEqual(directoryExclusion.values, ["public.folder"])
        XCTAssertTrue(directoryExclusion.isActive)
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
            builtInContext.conditions.first { $0.propertyKey == "last_used_date" }?.values,
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
        XCTAssertEqual(condition.propertyKey, "tag_names")
        XCTAssertEqual(condition.operatorCode, "any")
        XCTAssertNotEqual(condition.operatorCode, "contains")
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
        var conditions = context.conditions
        conditions[0].operatorCode = "eq"

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
            operatorValueUIKind: Self.registryOperatorUIKind(for:typeKey:),
            resolvePropertyKey: { .canonical($0) },
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

    nonisolated private static func registryOperatorUIKind(for code: String, typeKey: String) -> String {
        switch (code, typeKey) {
        case ("any", "categorical"):
            "listText"
        case ("gt", "date"):
            "singleDate"
        case ("neq", "string"):
            "singleText"
        default:
            "singleText"
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

    // MARK: - RCL-002-show_restored_collection_snapshot

    /// RCL-002-show_restored_collection_snapshot: snapshot-bearing collection open은 저장 snapshot path를 content list에 적용함
    /// FileManager window open reducer가 hydrated snapshot payload를 entry view layout 검색 path 적용 action으로 라우팅하는지 검증한다.
    /// - 검증 내용: collection file load 후 collection navigation, collection mode, snapshot path 적용 action 수신
    /// - 사전 조건: snapshotMeta fingerprint가 현재 definition과 일치하는 `.voycoll` equivalent file load result
    /// - 기대 결과: snapshot-first display를 위해 `applyCollectionSearchPaths`가 저장된 snapshot path로 호출됨
    func testShowRestoredCollectionSnapshot_withHydratedLoadResult_appliesSnapshotPaths() async {
        let file = makeSnapshotFile()
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
        }
        // 이 suite는 window open effect의 라우팅을 검증하므로 composer/content child 내부 state diff는 제외한다.
        store.exhaustivity = .off

        await store.send(.navigation(.internal(.collectionFileLoaded(
            request: request,
            result: .success(loadResult),
        ))))
        await store.receive(\.content.composer.view.setPresented)
        await store.receive(\.content.internal.requestNavigation)
        await store.receive(\.content.internal.applyNavigationState)
        await store.receive(\.content.entryViewLayout.internal.setCollectionMode)
        await store.receive(\.content.composer.internal.syncCollectionState)
        await store.receive(\.content.entryViewLayout.internal.applyCollectionSearchPaths)
        await store.receive(\.content.composer.internal.searchListApplied)
        await store.finish()
    }

    // MARK: - RCL-002-alert_unsaved_collection_filter_changes

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
}
