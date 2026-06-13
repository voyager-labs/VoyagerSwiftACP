import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

// RCL-002 manage_retrieval_collections의 collection filter 변경 저장 및
// write-back 성공/실패 시나리오를 검증하는 package-scoped 결정론적 TCA TestStore 테스트 모음.

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
}
