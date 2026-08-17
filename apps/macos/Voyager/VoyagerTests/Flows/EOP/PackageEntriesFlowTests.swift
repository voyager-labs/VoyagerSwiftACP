// FLOW-ID: eop.package_entries
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
final class PackageEntriesFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.compress_selected_file_creates_archive

    /// EOP-005-compress_entries: 선택 파일 압축 command는 planner/archive action을 거쳐 실제 archive를 생성한다.
    /// - 검증 내용: executeCommand를 통해 planner가 topmostSelectedPaths를 계산하고 archive action이 live compressItems를 실행하여
    /// 실제 .zip 파일이 생성되며, page 상태와 원본 fixture는 유지된다.
    /// - 사전 조건: sandbox에 복사한 실제 텍스트 fixture 하나가 현재 page에서 선택되어 있다.
    /// - 기대 결과: archive 파일이 sandbox root에 생성되고, 압축된 Entry 이름을 포함하며, page route/history/selection이 유지되고
    /// 원본 fixture는 변경되지 않는다.
    func testCompressSelectedFileThroughProductionComposition() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let entry = makeFileEntry(at: sandbox.fileURL)
        let store = makeStore(
            rootPath: sandbox.root.path,
            entries: [entry],
            selectedIDs: [entry.id],
        )
        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        let initialSelection = store.state.entryViewLayout.selectedIds

        await store.send(.entryViewLayout(.delegate(.executeCommand("mutation.compressSelectedItems"))))

        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(command, context)))) = action,
                  case .mutation(.compressSelectedItems) = command
            else { return false }
            return context.selectedIds == [entry.id]
                && context.displayItems.map(\.id) == [entry.id]
                && context.currentPath == sandbox.root.path
        }

        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.archive(.compressItems(paths)))) = action
            else { return false }
            return paths == [sandbox.fileURL.path]
        }

        await store.receive(\.entryViewLayout.entryOperations.lifecycle.operationStarted)
        await store.receive(\.entryViewLayout.entryOperations.lifecycle.operationFinished)
        await store.finish()

        let expectedArchiveURL = sandbox.root.appendingPathComponent("\(sandbox.fileURL.lastPathComponent).zip")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedArchiveURL.path),
            "archive 파일이 sandbox root에 생성되어야 합니다",
        )
        let entryNames = try archiveEntryNames(at: expectedArchiveURL)
        let expectedEntryNames = [sandbox.fileURL.lastPathComponent]
        XCTAssertEqual(
            entryNames,
            expectedEntryNames,
            "archive는 선택한 Entry의 상대 경로를 포함해야 합니다",
        )
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, initialSelection)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sandbox.originalFixture.path),
            "원본 fixture는 변경되지 않아야 합니다",
        )
    }

    // FLOW-PATH: negative_path.empty_selection_does_not_create_archive

    /// EOP-005-compress_entries: 선택 항목이 없으면 archive를 생성하지 않는다.
    /// - 검증 내용: 빈 selection으로 compress command를 전달해도 planner가 compressItems action을 만들지 않고
    /// archive가 생성되지 않는지 확인한다.
    /// - 사전 조건: 실제 fixture entry는 현재 page에 표시되지만 선택되어 있지 않다.
    /// - 기대 결과: archive 호출 없이 page route/selection이 유지되고 archive 파일이 생성되지 않는다.
    func testCompressSelectedFileWithEmptySelectionDoesNotCreateArchive() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let entry = makeFileEntry(at: sandbox.fileURL)
        let store = makeStore(
            rootPath: sandbox.root.path,
            entries: [entry],
            selectedIDs: [],
        )
        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory

        await store.send(.entryViewLayout(.delegate(.executeCommand("mutation.compressSelectedItems"))))
        await store.receive(\.entryViewLayout.entryOperations.routing.executeCommand)
        await store.finish()

        let archiveURLsAfter = sandboxArchiveURLs(in: sandbox.root)
        XCTAssertTrue(
            archiveURLsAfter.isEmpty,
            "빈 selection에서는 archive가 생성되지 않아야 합니다",
        )
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sandbox.originalFixture.path),
            "원본 fixture는 변경되지 않아야 합니다",
        )
    }

    // MARK: - Helpers

    private func makeStore(
        rootPath: String,
        entries: [EntryModel],
        selectedIDs: Set<EntryModel.ID>,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entryOperations.items = .init(uniqueElements: entries)
        state.entryViewLayout.entries = entries
        state.entryViewLayout.selectedIds = selectedIDs

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryFileOpsClient = .liveValue
            $0.entryThumbnailCacheClient = .testValue
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            )
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.coreFinished(batchCount: 0))
                    continuation.finish()
                }
            }
            $0.userDefaultsClient.setString = { _, _ in }
            $0.workspaceClient = .testValue
        }
        // flow는 lifecycle 내부 action보다 parent command부터 archive 생성 결과까지의
        // production composition을 검증한다.
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

    /// 샌드박스 root에 생성된 .zip 파일 URL 목록을 반환한다.
    private func sandboxArchiveURLs(in root: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
        ) else { return [] }
        return contents.filter { $0.pathExtension == "zip" }
    }

    /// archive 파일 내부 Entry 이름 목록을 반환한다.
    private func archiveEntryNames(at url: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", url.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw NSError(
                domain: "PackageEntriesFlowTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message],
            )
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let outputString = String(data: data, encoding: .utf8) ?? ""
        return outputString
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
