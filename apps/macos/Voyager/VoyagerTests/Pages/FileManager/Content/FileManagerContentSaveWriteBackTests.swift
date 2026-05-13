import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentSaveWriteBackTests: XCTestCase {
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

        // regression: must emit .writeBackFailed (discussion_r3209568117)
        await store.receive { action in
            guard case .collection(.writeBackFailed) = action else { return false }
            return true
        }

        // regression: must clear pending navigation on write-back failure
        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.setPendingNavigation(nil)))) = action
            else { return false }
            return true
        }

        await store.finish()

        XCTAssertNotEqual(
            store.state.collection.collectionSession.phase.inflightStatus,
            .writingBackRefreshedSnapshot,
        )
    }

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

        // regression: Composer must receive sync with new URL after write-back
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
