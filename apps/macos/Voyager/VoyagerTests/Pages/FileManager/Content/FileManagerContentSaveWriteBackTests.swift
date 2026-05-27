import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

/// FileManagerContent — 컬렉션 저장(write-back) 실패·성공 시나리오에서
/// 세션 페이즈 전이, 대기 중인 내비게이션 해제, Composer URL 동기화가
/// 올바르게 수행되는지 검증하는 테스트 모음.
/// write-back 회귀는 사용자 데이터 손실로 이어질 수 있어 방어적 테스트가 중요하다.
@MainActor
final class FileManagerContentSaveWriteBackTests: XCTestCase {
    /// 저장 실패 시 write-back 페이즈가 종료되고 대기 중인 내비게이션이 해제되어야 함.
    func testSaveFailureTerminatesWriteBackPhase() async {
        struct SaveError: Error {}

        var initialState = makeWriteBackState()
        initialState.collection.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )

        let store = makeWriteBackStore(initialState: initialState)

        XCTAssertEqual(
            store.state.collection.collectionSession.phase.inflightStatus,
            .writingBackRefreshedSnapshot,
        )

        await store.send(.collection(.saveCompleted(.failure(SaveError()))))

        // 회귀: .writeBackFailed를 방출해야 함 (discussion_r3209568117)
        await store.receive { action in
            guard case .collection(.writeBackFailed) = action else { return false }
            return true
        }

        // 회귀: write-back 실패 시 대기 중인 내비게이션을 해제해야 함
        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.setPendingNavigation(nil)))) = action
            else { return false }
            return true
        }

        XCTAssertNotEqual(
            store.state.collection.collectionSession.phase.inflightStatus,
            .writingBackRefreshedSnapshot,
        )
    }

    /// write-back이 아닌 일반 저장 실패에서는 write-back 실패 상태로 전이하지 않아야 함.
    func testGeneralSaveFailureDoesNotEnterWriteBackFailure() async {
        struct SaveError: Error {}

        var initialState = makeWriteBackState()
        initialState.navigation.pendingNavigation = .back
        initialState.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .ready,
            inflight: .none,
        )

        let store = makeWriteBackStore(initialState: initialState)

        await store.send(.collection(.saveCompleted(.failure(SaveError()))))

        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.setPendingNavigation(nil)))) = action
            else { return false }
            return true
        }

        XCTAssertEqual(
            store.state.collection.collectionSession.phase,
            .opened(kind: .definition, base: .ready, inflight: .none),
        )
    }

    /// write-back 성공 시 Composer의 openedCollectionURL이 새 URL로 동기화되어야 함.
    func testWriteBackSyncsComposerOpenedCollectionURL() async {
        let originalURL = URL(fileURLWithPath: "/tmp/voyager/original.voycoll")
        let newURL = URL(fileURLWithPath: "/tmp/voyager/saved.voycoll")
        let completion = makeSaveCompletion(url: newURL)

        var initialState = makeWriteBackState()
        initialState.collection.collectionSession.document = .init(
            url: originalURL,
            name: "original",
            compatibility: makeAllowedCompatibility(),
        )
        initialState.collection.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        initialState.composer.openedCollectionURL = originalURL

        let store = makeWriteBackStore(initialState: initialState)

        XCTAssertEqual(store.state.composer.openedCollectionURL, originalURL)

        await store.send(.collection(.saveCompleted(.success(completion))))

        await store.receive { action in
            guard case .collection(.writeBackCompleted) = action else { return false }
            return true
        }

        await store.receive { action in
            guard case .collection(.delegate(.writeBackNavigationPrepared)) = action else { return false }
            return true
        }

        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.setNavigationState))) = action else { return false }
            return true
        }

        // 회귀: write-back 후 Composer가 새 URL로 동기화를 받아야 함
        await store.receive { action in
            guard case let .composer(.internal(.syncCollectionState(_, url, _, _))) = action else { return false }
            return url == newURL
        }

        await store.finish()

        XCTAssertEqual(store.state.composer.openedCollectionURL, newURL)
        XCTAssertEqual(
            store.state.collection.collectionSession.document?.url,
            newURL,
        )
    }

    private func makeWriteBackStore(
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
        state.navigation.navigationState = .collection(
            .init(
                kind: .temporary,
                context: makeReportContext(),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        state.collection.collectionContext = makeReportContext()
        state.collection.collectionSession.metadata.baseline = .init(context: makeReportContext())
        state.composer.scopes = ["/tmp/voyager"]
        state.composer.conditions = []
        state.composer.pendingSearchQuery = "report"
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

    private func makeSaveCompletion(url: URL) -> CollectionSaveCompletion {
        .init(
            url: url,
            file: VoyagerCollectionFile(
                schemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
                id: "test-id",
                name: "saved",
                createdAt: .distantPast,
                updatedAt: .distantFuture,
                query: "report",
                scopes: ["/tmp/voyager"],
                conditions: [],
                snapshot: nil,
                snapshotMeta: nil,
                appVersion: nil,
            ),
        )
    }
}
