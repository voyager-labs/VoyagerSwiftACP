@_spi(Internals) import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

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
        initialState.content.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/VoyagerFixtures/Collections/snapshot.voycoll"),
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

        await store.send(.navigation(.internal(.collectionFileLoaded(.success(loadResult)))))
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
