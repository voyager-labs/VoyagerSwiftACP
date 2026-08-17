// FLOW-ID: eop.copy_entry_references
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
final class CopyEntryReferencesFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.copy_selected_absolute_paths_through_entry_operations

    /// EOP-006-copy_absolute_paths_of_entries: composed clipboard copyAbsolutePaths는 planner에서
    /// `.entryOperations(.clipboard(.copyAbsolutePaths(paths:)))`로 변환되어 pasteboard 경계에 도달한다.
    /// - 검증 내용: EntryViewLayout command가 command planner를 거쳐 pasteboard boundary 호출을 만든다.
    /// - 사전 조건: sandbox에 복사한 실제 텍스트 fixture 하나가 현재 page에서 선택되어 있다.
    /// - 기대 결과: pasteboard boundary가 정확히 한 번 호출되고 page route와 selection은 유지되며 sandbox directory는 변경되지 않는다.
    func testCopySelectedAbsolutePathsThroughProductionComposition() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let entry = makeFileEntry(at: sandbox.fileURL)
        let pasteboardCallCount = LockIsolated(0)
        let sandboxSnapshot = try FileManager.default.contentsOfDirectory(atPath: sandbox.root.path)
        let store = makeStore(
            rootPath: sandbox.root.path,
            entries: [entry],
            selectedIDs: [entry.id],
            pasteboardCallCount: pasteboardCallCount,
        )
        // store.exhaustivity = .off: flow는 clipboard lifecycle 내부 action보다 planner routing과 상태 보존을 검증한다.
        store.exhaustivity = .off
        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        let initialSelection = store.state.entryViewLayout.selectedIds

        await store.send(.entryViewLayout(.delegate(.executeCommand("clipboard.copySelectedAbsolutePaths"))))
        await store.receive(\.entryViewLayout.entryOperations.routing.executeCommand)
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.clipboard(.copyAbsolutePaths(paths)))) = action
            else { return false }
            return paths == [sandbox.fileURL.path]
        }
        await store.finish()

        XCTAssertEqual(pasteboardCallCount.withValue { $0 }, 1)
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, initialSelection)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: sandbox.root.path),
            sandboxSnapshot,
        )
    }

    // FLOW-PATH: negative_path.empty_selection_does_not_write_pasteboard

    /// EOP-006-copy_absolute_paths_of_entries: 빈 selection은 pasteboard boundary를 호출하지 않는다.
    /// - 검증 내용: EntryViewLayout command가 bridge를 통해 planner에 도달하지만 빈 selection guard로 인해 no-op이 된다.
    /// - 사전 조건: Directory Page에 fixture Entry는 있지만 선택된 Entry가 없다.
    /// - 기대 결과: pasteboard boundary 호출이 없고 page route와 selection은 유지되며 sandbox directory는 변경되지 않는다.
    func testCopySelectedAbsolutePathsWithEmptySelectionDoesNotWrite() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let entry = makeFileEntry(at: sandbox.fileURL)
        let pasteboardCallCount = LockIsolated(0)
        let sandboxSnapshot = try FileManager.default.contentsOfDirectory(atPath: sandbox.root.path)
        let store = makeStore(
            rootPath: sandbox.root.path,
            entries: [entry],
            selectedIDs: [],
            pasteboardCallCount: pasteboardCallCount,
        )
        // store.exhaustivity = .off: 빈 selection의 no-op 결과와 상태 보존을 검증한다.
        store.exhaustivity = .off
        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        let initialSelection = store.state.entryViewLayout.selectedIds

        await store.send(.entryViewLayout(.delegate(.executeCommand("clipboard.copySelectedAbsolutePaths"))))
        await store.finish()

        XCTAssertEqual(pasteboardCallCount.withValue { $0 }, 0)
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, initialSelection)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: sandbox.root.path),
            sandboxSnapshot,
        )
    }

    // MARK: - Helpers

    private func makeStore(
        rootPath: String,
        entries: [EntryModel],
        selectedIDs: Set<EntryModel.ID>,
        pasteboardCallCount: LockIsolated<Int>,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entryOperations.items = IdentifiedArray(uniqueElements: entries)
        state.entryViewLayout.entries = entries
        state.entryViewLayout.selectedIds = selectedIDs

        let pasteboardClient = PasteboardClient(
            changeCount: { 0 },
            clearContents: {},
            writeObjects: { _ in true },
            readObjects: { _, _ in nil },
            setString: { _, _ in
                pasteboardCallCount.withValue { $0 += 1 }
                return true
            },
            string: { _ in nil },
        )

        return TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.pasteboardClient = pasteboardClient
        }
    }

    private func makeFileEntry(at url: URL) -> EntryModel {
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
}
