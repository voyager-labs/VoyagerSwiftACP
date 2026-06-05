import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryRenameExtensionAlertTests: XCTestCase {
    // MARK: - 도우미

    private func makeFileEntry(
        id: String,
        name: String,
        fileExtension: String? = nil,
    ) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let ext = fileExtension ?? (name.components(separatedBy: ".").last ?? "")
        return EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 100,
            modifiedDate: date,
            fileExtension: ext,
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: "Document",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }

    private func makeStore(
        entry: EntryModel,
        renamingText: String,
        alertOverride: (@Sendable (String, String) async -> Bool)? = nil,
        renameFileOverride: (@Sendable (URL, URL) async throws -> Void)? = nil,
    ) -> TestStore<EntryOperationsState, EntryOperationsAction> {
        TestStore(initialState: {
            var state = EntryOperationsState()
            state.loadingContext.items = IdentifiedArrayOf(uniqueElements: [entry])
            state.renamingItemId = entry.id
            state.renamingText = renamingText
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            if let alertOverride {
                $0.entryOperationsAlertClient.showRenameExtensionChangeAlert = alertOverride
            }
            if let renameFileOverride {
                $0.entryFileOpsClient.renameFile = renameFileOverride
            }
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }
    }

    // MARK: - 동일 확장자는 경고를 건너뜀

    func testBasenameRenameWithSameExtensionCommitsWithoutWarning() async {
        let entry = makeFileEntry(id: "/tmp/report.txt", name: "report.txt")
        let store = makeStore(entry: entry, renamingText: "notes.txt") { _, _ in
            XCTFail("Extension alert should not be shown for same-extension rename")
            return false
        } renameFileOverride: { _, _ in }

        await store.send(.edit(.commitRename))
        await store.receive(\.edit.renameItem)
        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates["/tmp/report.txt"] = ItemOperationState(isBusy: true)
        }
        await store.receive(\.lifecycle.pathsMutated)
        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates["/tmp/report.txt"]?.isBusy = false
            $0.renamingItemId = nil
            $0.renamingText = ""
        }
        store.exhaustivity = .off
        await store.receive(\.lifecycle.entryActionCompleted)
        await store.finish()

        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertEqual(store.state.undoRecords.first?.operationKind, .rename)
        XCTAssertEqual(store.state.undoRecords.first?.targets.first?.beforePath, "/tmp/report.txt")
        XCTAssertEqual(store.state.undoRecords.first?.targets.first?.afterPath, "/tmp/notes.txt")
    }

    // MARK: - 확장자 추가됨

    func testExtensionAddedShowsWarningAndCancelPreservesState() async {
        let entry = makeFileEntry(id: "/tmp/README", name: "README")
        let store = makeStore(entry: entry, renamingText: "README.md") { _, _ in false }

        await store.send(.edit(.commitRename))

        await store.finish()

        XCTAssertEqual(store.state.renamingItemId, entry.id)
        XCTAssertEqual(store.state.renamingText, "README.md")
    }

    // MARK: - 확장자 제거됨

    func testExtensionRemovedShowsWarningAndCancelPreservesState() async {
        let entry = makeFileEntry(id: "/tmp/report.txt", name: "report.txt")
        let store = makeStore(entry: entry, renamingText: "report") { _, _ in false }

        await store.send(.edit(.commitRename))

        await store.finish()

        XCTAssertEqual(store.state.renamingItemId, entry.id)
        XCTAssertEqual(store.state.renamingText, "report")
    }

    // MARK: - 확장자 변경 — 취소

    func testExtensionChangedCancelPreservesRenameState() async {
        let entry = makeFileEntry(id: "/tmp/report.txt", name: "report.txt")
        let store = makeStore(entry: entry, renamingText: "report.pdf") { _, _ in false }

        await store.send(.edit(.commitRename))

        await store.finish()

        XCTAssertEqual(store.state.renamingItemId, entry.id)
        XCTAssertEqual(store.state.renamingText, "report.pdf")
    }

    // MARK: - 확장자 변경 — 계속

    func testExtensionChangedContinueProceedsToRename() async {
        let entry = makeFileEntry(id: "/tmp/report.txt", name: "report.txt")
        let store = makeStore(entry: entry, renamingText: "report.pdf") { _, _ in true } renameFileOverride: { _, _ in }

        await store.send(.edit(.commitRename))
        await store.receive(\.edit.renameItem)
        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates["/tmp/report.txt"] = ItemOperationState(isBusy: true)
        }
        await store.receive(\.lifecycle.pathsMutated)
        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates["/tmp/report.txt"]?.isBusy = false
            $0.renamingItemId = nil
            $0.renamingText = ""
        }
        store.exhaustivity = .off
        await store.receive(\.lifecycle.entryActionCompleted)
        await store.finish()

        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertEqual(store.state.undoRecords.first?.operationKind, .rename)
        XCTAssertEqual(store.state.undoRecords.first?.targets.first?.beforePath, "/tmp/report.txt")
        XCTAssertEqual(store.state.undoRecords.first?.targets.first?.afterPath, "/tmp/report.pdf")
    }

    // MARK: - 폴더는 확장자 경고를 건너뜀

    func testFolderRenameSkipsExtensionAlert() async {
        let folder = EntryModel.temporaryFolder(id: "/tmp/MyFolder", name: "MyFolder")
        let store = TestStore(initialState: {
            var state = EntryOperationsState()
            state.loadingContext.items = IdentifiedArrayOf(uniqueElements: [folder])
            state.renamingItemId = folder.id
            state.renamingText = "MyFolder.backup"
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryOperationsAlertClient.showRenameExtensionChangeAlert = { _, _ in
                XCTFail("Extension alert should not be shown for folder rename")
                return false
            }
            $0.entryFileOpsClient.renameFile = { _, _ in }
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        await store.send(.edit(.commitRename))
        await store.receive(\.edit.renameItem)
        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates["/tmp/MyFolder"] = ItemOperationState(isBusy: true)
        }
        await store.receive(\.lifecycle.pathsMutated)
        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates["/tmp/MyFolder"]?.isBusy = false
            $0.renamingItemId = nil
            $0.renamingText = ""
        }
        store.exhaustivity = .off
        await store.receive(\.lifecycle.entryActionCompleted)
        await store.finish()

        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertEqual(store.state.undoRecords.first?.operationKind, .rename)
        XCTAssertEqual(store.state.undoRecords.first?.targets.first?.beforePath, "/tmp/MyFolder")
        XCTAssertEqual(store.state.undoRecords.first?.targets.first?.afterPath, "/tmp/MyFolder.backup")
    }

    // MARK: - 확장자 변경 확인 후 충돌

    func testConflictAlertStillRunsAfterConfirmedExtensionChange() async {
        let entry = makeFileEntry(id: "/tmp/report.txt", name: "report.txt")
        let store = TestStore(initialState: {
            var state = EntryOperationsState()
            state.loadingContext.items = IdentifiedArrayOf(uniqueElements: [entry])
            state.renamingItemId = entry.id
            state.renamingText = "report.pdf"
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryOperationsAlertClient.showRenameExtensionChangeAlert = { _, _ in true }
            $0.entryFileOpsClient.renameFile = { _, _ in
                throw FileOpError.fileExists(itemName: "report.pdf")
            }
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        await store.send(.edit(.commitRename))
        await store.receive(\.edit.renameItem)
        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates["/tmp/report.txt"] = ItemOperationState(isBusy: true)
        }
        store.exhaustivity = .off
        await store.receive(\.lifecycle.operationFinished)
        await store.finish()

        XCTAssertEqual(
            store.state.itemStates["/tmp/report.txt"]?.lastError,
            .fileExists(itemName: "report.pdf"),
        )
    }
}
