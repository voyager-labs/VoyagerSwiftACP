// FLOW-ID: eop.execute_entry
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
final class ExecuteEntryFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.open_selected_file_through_entry_operations

    /// EOP-001-open_entry_with_default_app: 선택 파일 열기 command는 composed EntryOperations 경로를 거쳐 외부 open boundary에 도달한다.
    /// - 검증 내용: EntryViewLayout command가 command planner와 `.open(.openFiles)`를 거쳐 fixture URL을 EntryOpenClient에 전달하는지
    /// 확인한다.
    /// - 사전 조건: sandbox에 복사한 실제 텍스트 fixture 하나가 현재 page에서 선택되어 있다.
    /// - 기대 결과: fixture URL이 한 번 열리고 page route와 selection은 유지되며 원본 fixture는 변경되지 않는다.
    func testOpenSelectedFileThroughProductionComposition() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let entry = makeFileEntry(at: sandbox.fileURL)
        let recorder = EntryOpenRecorder()
        let store = makeStore(
            rootPath: sandbox.root.path,
            entries: [entry],
            selectedIDs: [entry.id],
            recorder: recorder,
        )
        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        let initialSelection = store.state.entryViewLayout.selectedIds

        await store.send(.entryViewLayout(.delegate(.executeCommand(
            "navigation.openSelectedItem",
            source: .fileManagerContent,
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(command, context, _)))) = action,
                  case .navigation(.openSelectedItem) = command
            else { return false }
            return context.selectedIds == [entry.id]
                && context.displayItems.map(\.id) == [entry.id]
                && context.currentPath == sandbox.root.path
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.acceptedCommand(
                _,
                .open(.openFiles(paths)),
            ))) = action else { return false }
            return paths == [sandbox.fileURL.path]
        }
        await store.receive(\.entryViewLayout.entryOperations.lifecycle.operationStarted)
        await store.receive(\.entryViewLayout.entryOperations.lifecycle.operationFinished)
        await store.finish()

        let openedURLs = await recorder.recordedURLs()
        XCTAssertEqual(openedURLs, [sandbox.fileURL])
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, initialSelection)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // FLOW-PATH: negative_path.empty_selection_does_not_open

    /// EOP-001-open_entry_with_default_app: 선택 항목이 없으면 open boundary를 호출하지 않는다.
    /// - 검증 내용: 빈 selection command가 planner를 통과해도 `.open(.openFiles)`와 EntryOpenClient 호출을 만들지 않는지 확인한다.
    /// - 사전 조건: 실제 fixture entry는 현재 page에 표시되지만 선택되어 있지 않다.
    /// - 기대 결과: open call 없이 page route와 selection이 유지된다.
    func testOpenSelectedFileWithEmptySelectionDoesNotOpen() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let entry = makeFileEntry(at: sandbox.fileURL)
        let recorder = EntryOpenRecorder()
        let store = makeStore(
            rootPath: sandbox.root.path,
            entries: [entry],
            selectedIDs: [],
            recorder: recorder,
        )
        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        let initialSelection = store.state.entryViewLayout.selectedIds

        await store.send(.entryViewLayout(.delegate(.executeCommand(
            "navigation.openSelectedItem",
            source: .fileManagerContent,
        ))))
        await store.receive(\.entryViewLayout.entryOperations.routing.executeCommand)
        await store.finish()

        let openedURLs = await recorder.recordedURLs()
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, initialSelection)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    private func makeStore(
        rootPath: String,
        entries: [EntryModel],
        selectedIDs: Set<EntryModel.ID>,
        recorder: EntryOpenRecorder,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entryOperations.items = .init(uniqueElements: entries)
        state.entryViewLayout.entries = entries
        state.entryViewLayout.selectedIds = selectedIDs

        var entryOpenClient = EntryOpenClient.previewValue
        entryOpenClient.open = { url, _ in
            await recorder.record(url)
        }
        entryOpenClient.trashDirectoryPath = { nil }

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryOpenClient = entryOpenClient
            $0.workspaceClient = .testValue
            $0.userDefaultsClient.setString = { _, _ in }
        }
        // flow는 lifecycle 내부 action이 아니라 parent command부터 외부 open boundary까지의 결과를 검증한다.
        store.exhaustivity = .off
        return store
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

private actor EntryOpenRecorder {
    private var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }

    func recordedURLs() -> [URL] {
        urls
    }
}
