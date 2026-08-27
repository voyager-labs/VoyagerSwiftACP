import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
extension EVM002FileManagerPagePresentationTests {
    // MARK: - EVM-002-nested_entry_commands

    /// EVM-002-toggle_directory_expansion_in_list: list의 오른쪽 방향키는 선택한 접힌 폴더를 펼친다.
    /// key-command overlay가 first responder인 경우에도 outline hierarchy action으로 연결되는지 검증한다.
    /// - 검증 내용: 오른쪽 방향키가 선택된 expandable folder의 expansion action을 발행한다.
    /// - 사전 조건: /root/folder가 선택된 접힌 root folder이고 list hierarchy가 활성화돼 있다.
    /// - 기대 결과: folderExpansionRequested(/root/folder)가 발행된다.
    func testListRightArrowExpandsSelectedCollapsedFolder() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.selectedIds = [folder.id]
        state.entryViewLayout.lastSelectedId = folder.id
        state.entryViewLayout.rangeAnchorId = folder.id
        state.entryViewLayout.hierarchy = .init(rootPath: "/root")
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 124,
            modifiers: [],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.receive {
            guard case let .entryViewLayout(.hierarchy(.folderExpansionRequested(id))) = $0 else {
                return false
            }
            return id == folder.id
        }
    }

    /// EVM-002-toggle_directory_expansion_in_list: list의 왼쪽 방향키는 선택한 펼친 폴더를 접는다.
    /// key-command overlay가 outline의 native keyDown을 대신할 때도 canonical collapse action을 유지하는지 검증한다.
    /// - 검증 내용: 왼쪽 방향키가 선택된 expanded folder의 collapse action을 발행한다.
    /// - 사전 조건: /root/folder가 선택되고 expandedFolderIDs에 포함돼 있다.
    /// - 기대 결과: folderCollapseRequested(/root/folder)가 발행된다.
    func testListLeftArrowCollapsesSelectedExpandedFolder() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.selectedIds = [folder.id]
        state.entryViewLayout.lastSelectedId = folder.id
        state.entryViewLayout.rangeAnchorId = folder.id
        state.entryViewLayout.hierarchy = .init(rootPath: "/root")
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 123,
            modifiers: [],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.receive {
            guard case let .entryViewLayout(.hierarchy(.folderCollapseRequested(id))) = $0 else {
                return false
            }
            return id == folder.id
        }
    }

    /// EVM-002-nested_entry_commands: expanded child folder 선택의 open 명령은 nested entry를 navigation으로 전달한다.
    /// - 검증 내용: hierarchy outline projection이 nested folder를 command context에 포함한다.
    /// - 사전 조건: /root/folder가 expanded이고 /root/folder/child가 선택돼 있다.
    /// - 기대 결과: open command가 /root/folder/child navigation delegate를 발생시킨다.
    func testNestedFolderOpenCommandUsesHierarchySelectableEntries() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/root/folder/child", name: "child")
        let store = makeFileManagerContentFeatureStore(initialState: nestedCommandState(
            root: folder,
            child: child,
            selectedID: child.id,
        ))
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand(
            "navigation.openSelectedItem",
            source: .fileManagerContent,
        ))))
        await store.receive(\.entryViewLayout.entryOperations.routing.executeCommand)
        await store.receive {
            guard case let .entryViewLayout(.entryOperations(.delegate(.navigateToPath(path)))) = $0 else {
                return false
            }
            return path == child.fullPath
        }
        await store.receive(\.internal.requestNavigation)
        await store.finish()
    }

    /// EVM-002-nested_entry_commands: expanded child file 선택의 Quick Look 명령은 nested path를 사용한다.
    /// - 검증 내용: hierarchy projection이 root entries에 없는 nested file을 command context에 제공한다.
    /// - 사전 조건: /root/folder가 expanded이고 /root/folder/file.txt가 선택돼 있다.
    /// - 기대 결과: Quick Look action이 nested file path 하나로 실행된다.
    func testNestedFileQuickLookCommandUsesHierarchySelectableEntries() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel(
            name: "file.txt",
            fullPath: "/root/folder/file.txt",
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: "txt",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
        let store = makeFileManagerContentFeatureStore(initialState: nestedCommandState(
            root: folder,
            child: child,
            selectedID: child.id,
        ))
        store.exhaustivity = .off // Quick Look success 후 root reload chain은 nested path routing 계약과 무관하다.

        await store.send(.entryViewLayout(.delegate(.executeCommand(
            "navigation.quickLookSelectedItem",
            source: .fileManagerContent,
        ))))
        await store.receive(\.entryViewLayout.entryOperations.routing.executeCommand)
        await store.receive {
            guard case let .entryViewLayout(.entryOperations(.acceptedCommand(
                _,
                .open(.quickLookFiles(paths)),
            ))) = $0 else {
                return false
            }
            return paths == [child.fullPath]
        }
        await store.finish()
    }

    // MARK: - EVM-002-open_entry_double_click

    /// EVM-002-open_entry_double_click: 그리드/아이콘 폴더 더블클릭은 내부 네비게이션으로 라우팅된다.
    /// EntryGridCoordinator.handleDoubleClick이 .delegate(.openEntry(folder))를 전송하면
    /// bridge가 직접 .open(.openFiles)를 호출하지 않고 EntryOperationsCommandPlanner를 통해
    /// planner가 .delegate(.navigateToPath)를 생성하도록 라우팅해야 한다.
    /// - 검증 내용: bridge가 .openEntry(folder)를 navigation.openSelectedItem command로 변환하고
    ///   planner가 폴더를 navigateToPath delegate로 라우팅하는지 확인
    /// - 사전 조건: texts/plain/ 디렉토리 fixture, 다른 항목이 선택된 상태
    /// - 기대 결과: clicked entry만 selectedIds/displayItems에 포함된 command context →
    ///   .delegate(.navigateToPath(fixturePath)) → .internal(.requestNavigation) 순서로 전송
    func testOpenEntryFolderRoutesThroughCommandPlannerToNavigateToPath() async {
        guard let plainDir = try? FileManagerFixtureSandbox.readOnlyDirectory(from: "fixtures/fixtures/texts/plain")
        else {
            XCTFail("Fixture directory not found: fixtures/fixtures/texts/plain")
            return
        }
        let folderPath = plainDir.path
        let folder = EntryModel.temporaryFolder(id: folderPath, name: "plain")
        let otherEntry = EntryModel.temporaryFolder(id: folderPath + "/other_selected", name: "other")

        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(plainDir.deletingLastPathComponent().path)
        state.entryViewLayout.entries = [folder, otherEntry]
        state.entryViewLayout.selectedIds = [otherEntry.id]

        let store = makeOpenEntryStore(initialState: state)

        await store.send(.entryViewLayout(.delegate(.openEntry(folder))))
        // Bridge가 command planner를 통해 라우팅 — clicked entry만 context에 포함
        await store.receive {
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(command, context, _)))) = $0
            else {
                return false
            }
            guard case .navigation(.openSelectedItem) = command else { return false }
            return context.selectedIds == Set([folder.id])
                && context.displayItems.count == 1
                && context.displayItems.first?.id == folder.id
                && context.currentPath == state.navigation.currentPath
        }
        // Planner가 폴더를 navigateToPath delegate로 변환
        await store.receive {
            guard case let .entryViewLayout(.entryOperations(.delegate(.navigateToPath(path)))) = $0 else {
                return false
            }
            return path == folderPath
        }
        // Bridge가 delegate를 navigation으로 연결
        await store.receive(\.internal.requestNavigation)
        await store.finish()
    }

    /// EVM-002-open_entry_double_click: 일반 파일 더블클릭은 EntryOperationsCommandPlanner를 통해
    /// openFiles 라우팅으로 전달된다.
    /// - 검증 내용: bridge가 .openEntry(file)를 navigation.openSelectedItem command로 변환하고
    ///   planner가 일반 파일을 openFiles로 라우팅하는지 확인
    /// - 사전 조건: texts/plain/11.txt fixture 파일
    /// - 기대 결과: .entryViewLayout(.entryOperations(.routing(.executeCommand))) →
    ///   .entryViewLayout(.entryOperations(.open(.openFiles([fixturePath])))) 순서로 전송
    func testOpenEntryFileRoutesThroughCommandPlannerToOpenFiles() async {
        guard let plainDir = try? FileManagerFixtureSandbox.readOnlyDirectory(from: "fixtures/fixtures/texts/plain")
        else {
            XCTFail("Fixture directory not found: fixtures/fixtures/texts/plain")
            return
        }
        let fileURL = plainDir.appendingPathComponent("11.txt")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            XCTFail("Fixture file not found: \(fileURL.path)")
            return
        }

        let file = EntryModel(
            name: "11.txt",
            fullPath: fileURL.path,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: "txt",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(plainDir.path)
        state.entryViewLayout.entries = [file]

        let store = makeOpenEntryStore(initialState: state)

        await store.send(.entryViewLayout(.delegate(.openEntry(file))))
        // Bridge가 command planner를 통해 라우팅
        await store.receive(\.entryViewLayout.entryOperations.routing.executeCommand)
        // Planner가 일반 파일을 openFiles로 변환
        await store.receive {
            guard case let .entryViewLayout(.entryOperations(.open(.openFiles(paths)))) = $0 else {
                return false
            }
            return paths == [fileURL.path]
        }
        await store.finish()
    }

    /// EVM-002-open_entry_double_click: .voycoll 컬렉션 파일 더블클릭은
    /// EntryOperationsCommandPlanner를 통해 openCollectionFile로 라우팅된다.
    /// - 검증 내용: bridge가 .openEntry(voycoll)를 navigation.openSelectedItem command로 변환하고
    ///   planner가 .voycoll 파일을 openCollectionFile delegate로 라우팅하는지 확인
    /// - 사전 조건: collections/legacy_schema_v1_collection.voycoll fixture
    /// - 기대 결과: .entryViewLayout(.entryOperations(.routing(.executeCommand))) →
    ///   .entryViewLayout(.entryOperations(.delegate(.openCollectionFile(fixtureURL)))) 순서로 전송
    func testOpenEntryVoycollRoutesThroughCommandPlannerToOpenCollectionFile() async {
        guard let collDir = try? FileManagerFixtureSandbox.readOnlyDirectory(from: "fixtures/fixtures/collections")
        else {
            XCTFail("Fixture directory not found: fixtures/fixtures/collections")
            return
        }
        let voycollURL = collDir.appendingPathComponent("legacy_schema_v1_collection.voycoll")
        guard FileManager.default.fileExists(atPath: voycollURL.path) else {
            XCTFail("Fixture file not found: \(voycollURL.path)")
            return
        }

        let voycoll = EntryModel(
            name: "legacy_schema_v1_collection.voycoll",
            fullPath: voycollURL.path,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: "voycoll",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "Voyager Collection",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(collDir.path)
        state.entryViewLayout.entries = [voycoll]

        let store = makeOpenEntryStore(initialState: state)

        await store.send(.entryViewLayout(.delegate(.openEntry(voycoll))))
        // Bridge가 command planner를 통해 라우팅
        await store.receive(\.entryViewLayout.entryOperations.routing.executeCommand)
        // Planner가 .voycoll 파일을 openCollectionFile delegate로 변환
        await store.receive {
            guard case let .entryViewLayout(.entryOperations(.delegate(.openCollectionFile(url)))) = $0 else {
                return false
            }
            return url == voycollURL
        }
        await store.finish()
    }

    /// openEntry bridge 테스트 전용 store: entryOpenClient와 workspaceClient를 mock으로 주입한다.
    @MainActor
    private func makeOpenEntryStore(
        initialState: FileManagerContentState,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .previewValue
            $0.entryQuickLookClient = .previewValue
            $0.workspaceClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.userDefaultsClient.setString = { _, _ in }
        }
        // store.exhaustivity = .off: command planner delegate chain 이후
        // routing reducer의 내부 effect는 bridge 계약과 무관하다.
        store.exhaustivity = .off
        return store
    }

    private func nestedCommandState(
        root: EntryModel,
        child: EntryModel,
        selectedID: EntryModel.ID,
    ) -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [root]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [
                root.id: .init(
                    children: [child],
                    loadPhase: .loaded,
                    generation: 1,
                    expectedBatchIndex: 1,
                    coreFinished: true,
                ),
            ],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([root.id])
        state.entryViewLayout.selectedIds = [selectedID]
        return state
    }
}
