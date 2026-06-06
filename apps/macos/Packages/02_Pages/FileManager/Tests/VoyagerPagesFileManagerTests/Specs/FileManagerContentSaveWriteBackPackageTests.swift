import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentSaveWriteBackPackageTests: XCTestCase {
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
        XCTAssertEqual(store.state.collection.collectionSession.metadata.baseline, CollectionBaseline(context: savedContext))
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
