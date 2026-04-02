import ComposableArchitecture
import Foundation
import IdentifiedCollections
@testable import Voyager
import XCTest

@MainActor
final class EntryRenameExtensionAlertTests: XCTestCase {
    // MARK: - Helpers

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
        }
    }

    // MARK: - Same extension bypasses warning

    func testBasenameRenameWithSameExtensionCommitsWithoutWarning() async {
        let entry = makeFileEntry(id: "/tmp/report.txt", name: "report.txt")
        let store = makeStore(entry: entry, renamingText: "notes.txt") { _, _ in
            XCTFail("Extension alert should not be shown for same-extension rename")
            return false
        } renameFileOverride: { _, _ in }

        await store.send(.edit(.commitRename)) {
            $0.renamingText = "notes.txt"
        }

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

        await store.receive(\.lifecycle.entryActionCompleted) {
            $0.undoRecords = [
                EntryActionRecord(
                    operationKind: .rename,
                    targets: [.init(beforePath: "/tmp/report.txt", afterPath: "/tmp/notes.txt")],
                ),
            ]
            $0.redoRecords = []
        }

        await store.finish()
    }

    // MARK: - Extension added

    func testExtensionAddedShowsWarningAndCancelPreservesState() async {
        let entry = makeFileEntry(id: "/tmp/README", name: "README")
        let store = makeStore(entry: entry, renamingText: "README.md") { _, _ in false }

        await store.send(.edit(.commitRename)) {
            $0.renamingText = "README.md"
        }

        await store.finish()

        XCTAssertEqual(store.state.renamingItemId, entry.id)
        XCTAssertEqual(store.state.renamingText, "README.md")
    }

    // MARK: - Extension removed

    func testExtensionRemovedShowsWarningAndCancelPreservesState() async {
        let entry = makeFileEntry(id: "/tmp/report.txt", name: "report.txt")
        let store = makeStore(entry: entry, renamingText: "report") { _, _ in false }

        await store.send(.edit(.commitRename)) {
            $0.renamingText = "report"
        }

        await store.finish()

        XCTAssertEqual(store.state.renamingItemId, entry.id)
        XCTAssertEqual(store.state.renamingText, "report")
    }

    // MARK: - Extension changed — cancel

    func testExtensionChangedCancelPreservesRenameState() async {
        let entry = makeFileEntry(id: "/tmp/report.txt", name: "report.txt")
        let store = makeStore(entry: entry, renamingText: "report.pdf") { _, _ in false }

        await store.send(.edit(.commitRename)) {
            $0.renamingText = "report.pdf"
        }

        await store.finish()

        XCTAssertEqual(store.state.renamingItemId, entry.id)
        XCTAssertEqual(store.state.renamingText, "report.pdf")
    }

    // MARK: - Extension changed — continue

    func testExtensionChangedContinueProceedsToRename() async {
        let entry = makeFileEntry(id: "/tmp/report.txt", name: "report.txt")
        let store = makeStore(entry: entry, renamingText: "report.pdf") { _, _ in true } renameFileOverride: { _, _ in }

        await store.send(.edit(.commitRename)) {
            $0.renamingText = "report.pdf"
        }

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

        await store.receive(\.lifecycle.entryActionCompleted) {
            $0.undoRecords = [
                EntryActionRecord(
                    operationKind: .rename,
                    targets: [.init(beforePath: "/tmp/report.txt", afterPath: "/tmp/report.pdf")],
                ),
            ]
            $0.redoRecords = []
        }

        await store.finish()
    }

    // MARK: - Folder skips extension alert

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
        }

        await store.send(.edit(.commitRename)) {
            $0.renamingText = "MyFolder.backup"
        }

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

        await store.receive(\.lifecycle.entryActionCompleted) {
            $0.undoRecords = [
                EntryActionRecord(
                    operationKind: .rename,
                    targets: [.init(beforePath: "/tmp/MyFolder", afterPath: "/tmp/MyFolder.backup")],
                ),
            ]
            $0.redoRecords = []
        }

        await store.finish()
    }

    // MARK: - Conflict after confirmed extension change

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
        }

        await store.send(.edit(.commitRename)) {
            $0.renamingText = "report.pdf"
        }

        await store.receive(\.edit.renameItem)

        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates["/tmp/report.txt"] = ItemOperationState(isBusy: true)
        }

        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates["/tmp/report.txt"]?.isBusy = false
            $0.itemStates["/tmp/report.txt"]?.lastError = .fileExists(itemName: "report.pdf")
            $0.renamingItemId = nil
            $0.renamingText = ""
        }

        await store.finish()
    }
}
