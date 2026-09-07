// FLOW-ID: eop.edit_entry_metadata
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EditEntryMetadataFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.rename_updates_visible_entry_and_preserves_route

    /// EOP-004-rename_entry: composed rename은 sandbox 파일과 visible entry identity를 함께 갱신한다.
    /// - 검증 내용: EntryViewLayout의 startRename/renameCommitted가 실제 rename과 directory reload를 거쳐 새 Entry를 표시한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 isolated sandbox copy와 해당 directory route가 있다.
    /// - 기대 결과: 새 파일과 새 identity/name이 표시되고 route/history와 원본 fixture는 유지된다.
    func testRenameUpdatesVisibleEntryAndPreservesRoute() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let sourceEntry = makeEntry(at: sandbox.fileURL)
        let renamedURL = sandbox.root.appendingPathComponent("11-renamed.txt")
        let renamedEntry = makeEntry(at: renamedURL)
        let sandboxRootPath = sandbox.root.path
        var state = FileManagerContentFeature.State()
        state.navigation.seedInitialFolderPath(sandboxRootPath)
        state.navigation.appendBackHistory(.init(navigationState: .folder("/flow/previous")))
        state.entryViewLayout.entryOperations.items = [sourceEntry]
        state.entryViewLayout.entries = [sourceEntry]
        state.entryViewLayout.selectedIds = [sourceEntry.id]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryFileOpsClient = .liveValue
            $0.entryLoadingClient.stagedLoadItems = { directoryURL, _, _ in
                XCTAssertEqual(directoryURL.path, sandboxRootPath)
                let entries = FileManager.default.fileExists(atPath: renamedURL.path)
                    ? [renamedEntry]
                    : [sourceEntry]
                return Self.stagedStream(with: entries)
            }
            $0.entryThumbnailCacheClient = .testValue
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            )
            $0.userDefaultsClient.setString = { _, _ in }
        }
        // store.exhaustivity = .off: composed rename은 reload와 hierarchy invalidation의 내부 lifecycle 순서보다 filesystem과
        // visible projection을 소유한다.
        store.exhaustivity = .off

        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        await store.send(.entryViewLayout(.delegate(.startRename(
            item: sourceEntry,
            text: sourceEntry.name,
            source: .fileManagerContent,
        ))))
        await store.send(.entryViewLayout(.delegate(.renameCommitted(
            itemID: sourceEntry.id,
            newName: renamedURL.lastPathComponent,
        ))))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
        XCTAssertEqual(store.state.entryViewLayout.entries, [renamedEntry])
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.items, [renamedEntry])
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
    }

    // FLOW-PATH: failure.rename_failure_preserves_visible_entry

    /// EOP-004-rename_entry: injected rename failure는 기존 파일과 visible entry를 보존하고 오류를 기록한다.
    /// - 검증 내용: filesystem boundary failure 뒤 reload가 기존 Entry를 유지하고 EntryOperations lastError를 남긴다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 isolated sandbox copy와 system failure를 던지는 rename client가 있다.
    /// - 기대 결과: 기존 파일/identity/name/route는 유지되고 새 파일은 없으며 실패 사유가 기록된다.
    func testRenameFailurePreservesVisibleEntryAndRecordsError() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let sourceEntry = makeEntry(at: sandbox.fileURL)
        let renamedURL = sandbox.root.appendingPathComponent("11-renamed.txt")
        let sandboxRootPath = sandbox.root.path
        var entryFileOpsClient = EntryFileOpsClient.liveValue
        entryFileOpsClient.renameFile = { _, _ in
            throw FileOpError.system(message: "Rename write failed")
        }
        var state = FileManagerContentFeature.State()
        state.navigation.seedInitialFolderPath(sandboxRootPath)
        state.entryViewLayout.entryOperations.items = [sourceEntry]
        state.entryViewLayout.entries = [sourceEntry]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryFileOpsClient = entryFileOpsClient
            $0.entryLoadingClient.stagedLoadItems = { directoryURL, _, _ in
                XCTAssertEqual(directoryURL.path, sandboxRootPath)
                XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: renamedURL.path))
                return Self.stagedStream(with: [sourceEntry])
            }
            $0.entryThumbnailCacheClient = .testValue
            $0.userDefaultsClient.setString = { _, _ in }
        }
        // store.exhaustivity = .off: 실패 후 reload가 발생하는 composed lifecycle에서 사용자 관찰 결과와 error ownership을 검증한다.
        store.exhaustivity = .off

        let initialRoute = store.state.navigation.navigationState
        await store.send(.entryViewLayout(.delegate(.startRename(
            item: sourceEntry,
            text: sourceEntry.name,
            source: .fileManagerContent,
        ))))
        await store.send(.entryViewLayout(.delegate(.renameCommitted(
            itemID: sourceEntry.id,
            newName: renamedURL.lastPathComponent,
        ))))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
        XCTAssertEqual(store.state.entryViewLayout.entries, [sourceEntry])
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.items, [sourceEntry])
        XCTAssertEqual(
            store.state.entryViewLayout.entryOperations.itemStates[sourceEntry.id]?.lastError?.message,
            "Rename write failed",
        )
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
    }

    private func makeEntry(at url: URL) -> EntryModel {
        EntryModel(
            name: url.lastPathComponent,
            fullPath: url.path,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: url.pathExtension,
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "Plain Text",
                creatorApplication: nil,
                tags: [],
                supplementaryMetadata: nil,
            ),
        )
    }

    nonisolated private static func stagedStream(
        with entries: [EntryModel],
    ) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.coreBatch(items: entries, batchIndex: 0))
            continuation.yield(.coreFinished(batchCount: 1))
            continuation.finish()
        }
    }
}
