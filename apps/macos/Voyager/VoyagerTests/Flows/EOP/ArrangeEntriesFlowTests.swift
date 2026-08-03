// FLOW-ID: eop.arrange_entries
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
final class ArrangeEntriesFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.nested_list_drop_moves_entry

    /// EOP-002-move_entries: nested list directory drop은 source Entry를 대상 위치로 이동한다.
    /// AppKit이 만든 drop intent부터 FileManager composition과 EntryOperations filesystem effect까지 실제 사용자 경로를 검증한다.
    /// - 검증 내용: `.view(.dropItems)`가 composed reducer를 지나 live move effect와 directory refresh를 완료한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt` sandbox copy와 expanded parent 아래 writable target directory가 있다.
    /// - 기대 결과: source 파일은 사라지고 nested target에 나타나며 current page identity는 유지된다.
    func testNestedListDropMovesEntryThroughProductionComposition() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let parentDirectory = sandbox.root.appendingPathComponent("parent")
        let targetDirectory = parentDirectory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let sourceEntry = makeEntry(at: sandbox.fileURL, isFolder: false)
        let parentEntry = makeEntry(at: parentDirectory, isFolder: true)
        let targetEntry = makeEntry(at: targetDirectory, isFolder: true)
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(sandbox.root.path)
        state.entryOperations.items = [sourceEntry, parentEntry]
        state.entryViewLayout.entries = [sourceEntry, parentEntry]
        state.entryViewLayout.hierarchy = .init(
            rootPath: sandbox.root.path,
            expandedFolderIDs: [parentEntry.id],
            foldersByID: [
                parentEntry.id: .init(children: [targetEntry], phase: .loaded, generation: 1),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryFileOpsClient = .liveValue
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.coreFinished(batchCount: 0))
                    continuation.finish()
                }
            }
            $0.userDefaultsClient.setString = { _, _ in }
        }
        // store.exhaustivity = .off: flow는 내부 lifecycle action보다 실제 filesystem 이동과 page identity를 검증한다.
        store.exhaustivity = .off
        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory

        await store.send(.entryViewLayout(.view(.dropItems(
            sourcePaths: [sandbox.fileURL.path],
            destinationPath: targetDirectory.path,
            isOptionDrag: false,
        ))))
        await store.finish()
        await store.skipReceivedActions()

        let movedFile = targetDirectory.appendingPathComponent(sandbox.fileURL.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertFalse(
            store.state.entryOperations.undoRecords.isEmpty,
            "drag-and-drop move must produce an undo record",
        )
        XCTAssertTrue(store.state.entryOperations.canUndoEntryAction)
    }

    private func makeEntry(at url: URL, isFolder: Bool) -> EntryModel {
        EntryModel(
            name: url.lastPathComponent,
            fullPath: url.path,
            isFolder: isFolder,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: url.pathExtension,
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: isFolder ? "Folder" : "Plain Text",
                creatorApplication: nil,
                tags: [],
                supplementaryMetadata: nil,
            ),
        )
    }
}
