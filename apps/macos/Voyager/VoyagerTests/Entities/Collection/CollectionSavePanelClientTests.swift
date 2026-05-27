import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class CollectionSavePanelClientTests: XCTestCase {
    func testSaveRequestedHappyPathProceedsThroughPanelToSaveCompleted() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let selectedURL = URL(fileURLWithPath: "/tmp/test-happy.voycoll")

        let payload = makeValidSaveRequestPayload()

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { file, url in
                    await recorder.append(file: file, url: url)
                },
                load: { _ in
                    makeCollectionLoadResult(
                        kEmptyCollectionFile,
                        sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                    )
                },
            )
            $0.collectionSavePanelClient = CollectionSavePanelClient(
                presentSavePanel: { _ in selectedURL },
                defaultSaveDirectory: { _ in URL(fileURLWithPath: "/tmp") },
            )
            $0.userDefaultsClient = .testValue
            $0.collectionStalenessClient = stalenessClient
        }
        store.exhaustivity = .off

        await store.send(.saveRequested(payload))
        await store.receive(\.savePanelResponse)
        await store.receive(\.saveCompleted)
        await store.finish()

        let saved = await recorder.last()
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.url.pathExtension, "voycoll")
        XCTAssertEqual(saved?.file.snapshot?.items, [.string("/tmp/report.txt")])
    }

    func testSaveRequestedCancelPathClearsPendingSaveWithoutWriting() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)

        let payload = makeValidSaveRequestPayload()

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { file, url in
                    await recorder.append(file: file, url: url)
                },
                load: { _ in
                    makeCollectionLoadResult(
                        kEmptyCollectionFile,
                        sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                    )
                },
            )
            $0.collectionSavePanelClient = CollectionSavePanelClient(
                presentSavePanel: { _ in nil },
                defaultSaveDirectory: { _ in URL(fileURLWithPath: "/tmp") },
            )
            $0.userDefaultsClient = .testValue
            $0.collectionStalenessClient = stalenessClient
        }
        store.exhaustivity = .off

        await store.send(.saveRequested(payload))
        await store.receive(\.savePanelResponse)
        await store.finish()

        let saved = await recorder.last()
        XCTAssertNil(saved, "No file should be saved when panel is cancelled")
    }

    func testSaveRequestedFailurePathEmitsSaveCompletedFailure() async {
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let selectedURL = URL(fileURLWithPath: "/tmp/test-fail.voycoll")

        let payload = makeValidSaveRequestPayload()

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { _, _ in
                    throw NSError(domain: "test", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Disk write failed",
                    ])
                },
                load: { _ in
                    makeCollectionLoadResult(
                        kEmptyCollectionFile,
                        sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                    )
                },
            )
            $0.collectionSavePanelClient = CollectionSavePanelClient(
                presentSavePanel: { _ in selectedURL },
                defaultSaveDirectory: { _ in URL(fileURLWithPath: "/tmp") },
            )
            $0.userDefaultsClient = .testValue
            $0.collectionStalenessClient = stalenessClient
        }
        store.exhaustivity = .off

        await store.send(.saveRequested(payload))
        await store.receive(\.savePanelResponse)
        await store.receive(\.saveCompleted)
        await store.finish()
    }
}

private func makeValidSaveRequestPayload() -> SaveRequestPayload {
    SaveRequestPayload(
        context: CollectionContext(query: "Report", scopes: ["/tmp"], conditions: []),
        isSearchLoading: false,
        isFiltersLoading: false,
        snapshotItems: [.string("/tmp/report.txt")],
        definitionFingerprint: "fingerprint",
        capturedAt: .distantFuture,
        relevanceRoots: ["/tmp"],
        openedCompatibility: nil,
    )
}
