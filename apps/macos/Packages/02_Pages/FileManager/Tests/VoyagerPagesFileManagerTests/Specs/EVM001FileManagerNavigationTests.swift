import ComposableArchitecture
import CoreServices
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

private struct ExpandedChildTransitionFixture {
    let state: FileManagerContentState
    let folder: EntryModel
    let before: EntryModel
    let after: EntryModel
}

private struct CrossFolderMoveFixture {
    let state: FileManagerContentState
    let source: EntryModel
    let destination: EntryModel
    let before: EntryModel
    let after: EntryModel
}

@MainActor
final class EVM001FileManagerNavigationTests: XCTestCase {
    // MARK: - EVM-001-dau_navigation_metrics

    /// EVM-001-dau_navigation_metrics: content-row directory open reaches the FileManager metrics client
    /// 실제 Open Selected Item 경로가 navigation delegate를 거쳐 folder metric을 정확히 한 번 기록하는지 검증.
    /// - 검증 내용: FileManagerFeature → EntryViewLayout command → navigation delegate → MetricsClient
    /// - 사전 조건: ordinary folder entry가 선택된 FileManagerFeature 상태
    /// - 기대 결과: `.folder` 1회, collection/no-op metric 없음
    func testContentRowFolderOpenLogsFolderNavigationExactlyOnce() async {
        let folderPath = "/tmp/voyager-content-row-folder"
        let folder = EntryModel.temporaryFolder(id: folderPath, name: "folder")
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder("/tmp")
        state.content.entryViewLayout.entries = [folder]
        state.content.entryViewLayout.selectedIds = [folder.id]

        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.metricsClient = MetricsClient(
                logMetric: { _, _, _ in },
                logDAUNavigation: { kind in metrics.withValue { $0.append(kind) } },
                logDAUEntryAction: { _, _ in },
            )
        }
        // store.exhaustivity = .off: 전체 FileManager routing의 부수적인 loading effect보다 metric count를 검증한다.
        store.exhaustivity = .off

        await store.send(.content(.entryViewLayout(.delegate(.executeCommand("navigation.openSelectedItem")))))
        await store.skipInFlightEffects()

        XCTAssertEqual(metrics.value, [.folder], "content-row folder navigation must log exactly one folder metric")
    }

    /// EVM-001-dau_navigation_metrics: direct fixed-location folder selection logs one folder metric
    /// FileManager window의 직접 folder selection 경로가 동일한 metric owner를 사용하는지 검증.
    /// - 검증 내용: navigation view action이 folder metric으로 연결되는지 확인
    /// - 사전 조건: Home route의 FileManagerFeature
    /// - 기대 결과: 지정한 ordinary folder에 대해 `.folder` 1회
    func testDirectFolderSelectionLogsFolderNavigationExactlyOnce() async {
        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let store = makeMetricsStore(metrics: metrics)

        await store.send(.navigation(.view(.navigateToPath("/tmp/voyager-fixed-location"))))
        await store.skipInFlightEffects()

        XCTAssertEqual(metrics.value, [.folder])
    }

    /// EVM-001-dau_navigation_metrics: same folder selection is a metric no-op
    /// 동일 route 재선택이 navigation metric을 중복 기록하지 않는지 검증.
    /// - 검증 내용: current folder와 동일한 navigation 입력의 metric count
    /// - 사전 조건: 현재 route가 지정 folder인 FileManagerFeature
    /// - 기대 결과: metric 0회
    func testSameFolderSelectionDoesNotLogNavigation() async {
        let path = "/tmp/voyager-same-folder"
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder(path)
        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let store = makeMetricsStore(metrics: metrics, initialState: state)

        await store.send(.navigation(.view(.navigateToPath(path))))
        await store.skipInFlightEffects()

        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-dau_navigation_metrics: collection open remains exactly one collection metric
    /// collection open의 직접 logging과 navigation delegate가 중복되지 않는지 검증.
    /// - 검증 내용: collection file open 실패에서도 metric 호출 count와 kind
    /// - 사전 조건: ordinary folder route와 throwing collection loader
    /// - 기대 결과: `.collection` 1회
    func testCollectionOpenLogsCollectionNavigationExactlyOnce() async {
        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let url = URL(fileURLWithPath: "/tmp/voyager-metrics.voycoll")
        let store = makeMetricsStore(metrics: metrics) { dependencies in
            dependencies.collectionFileClient.load = { _ in
                throw NSError(domain: "metrics-test", code: 1)
            }
        }

        await store.send(.navigation(.view(.openCollectionFile(url))))

        XCTAssertEqual(metrics.value, [.collection])
    }

    /// EVM-001-dau_navigation_metrics: sidebar fixed-location selection logs one folder metric
    /// 실제 Sidebar delegate action이 navigation route 변경과 folder metric을 함께 처리하는지 검증.
    /// - 검증 내용: `.sidebar(.delegate(.selectFixedLocation(id)))` 이후 anchor transition과 metric kind/count
    /// - 사전 조건: active Home tab과 다른 ordinary fixed location이 있는 FileManagerFeature 상태
    /// - 기대 결과: directory anchor로 전환되고 `.folder`만 정확히 1회 기록됨
    func testSidebarFixedLocationSelectionLogsOneFolderMetric() async throws {
        let location = FileManagerFixedLocationItem(
            id: "location-documents",
            title: "Documents",
            path: "/Users/test/Documents",
            iconName: "folder",
            accessibilityLabel: "Documents",
        )
        var state = FileManagerFeature.State()
        state.sidebar.fixedLocationItems = [location]
        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let store = makeMetricsStore(metrics: metrics, initialState: state)

        await store.send(.sidebar(.delegate(.selectFixedLocation(location.id))))
        await store.receive(\.contentTabs)

        let activeTabID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertEqual(
            store.state.contentTabs.tabs[id: activeTabID]?.anchor,
            .directory(path: location.path),
        )
        XCTAssertEqual(metrics.value, [.folder])
    }

    /// EVM-001-dau_navigation_metrics: sidebar fixed-location re-selection is a metric no-op
    /// 같은 Sidebar fixed location을 다시 누를 때 route와 metric이 중복 처리되지 않는지 검증.
    /// - 검증 내용: 동일 location ID에 대한 실제 sidebar delegate action의 anchor와 metric count
    /// - 사전 조건: active tab과 content route가 같은 fixed location path를 가리키는 상태
    /// - 기대 결과: anchor는 유지되고 navigation metric은 0회이며 collection metric도 없음
    func testSidebarSameFixedLocationSelectionDoesNotLogNavigation() async throws {
        let path = "/Users/test/Documents"
        let location = FileManagerFixedLocationItem(
            id: "location-documents",
            title: "Documents",
            path: path,
            iconName: "folder",
            accessibilityLabel: "Documents",
        )
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder(path)
        state.sidebar.fixedLocationItems = [location]
        let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)
        state.contentTabs.tabs[id: activeTabID]?.anchor = .directory(path: path)
        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let store = makeMetricsStore(metrics: metrics, initialState: state)

        await store.send(.sidebar(.delegate(.selectFixedLocation(location.id))))
        await store.receive(\.contentTabs)

        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.anchor, .directory(path: path))
        XCTAssertTrue(metrics.value.isEmpty)
    }

    private func makeMetricsStore(
        metrics: LockIsolated<[DAUNavigationKind]>,
        initialState: FileManagerFeature.State = .init(),
        configure: (inout DependencyValues) -> Void = { _ in },
    ) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: { dependencies in
            dependencies.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            dependencies.uuid = .incrementing
            dependencies.metricsClient = MetricsClient(
                logMetric: { _, _, _ in },
                logDAUNavigation: { kind in metrics.withValue { $0.append(kind) } },
                logDAUEntryAction: { _, _ in },
            )
            configure(&dependencies)
        }
        store.exhaustivity = .off
        return store
    }

    // MARK: - EVM-001-route_entry_selection_commands

    /// EVM-001-route_entry_selection_commands: Select All은 hierarchy visible preorder를 layout reducer로 전달한다.
    /// normal directory list에서 collapsed descendant와 synthetic row를 제외한 visible entries만 선택 명령으로 전달되는지 검증한다.
    /// - 검증 내용: selectAllEntries routing이 visible selectable ID 순서를 유지한다.
    /// - 사전 조건: /root/a가 expanded이고 /root/a/child가 loaded이며 /root/b는 root sibling이다.
    /// - 기대 결과: applySelectAll의 ordered IDs는 [/root/a, /root/a/child, /root/b]다.
    func testSelectAllRoutesVisibleOutlineOrder() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = EntryModel.temporaryFolder(id: "/root/a/child", name: "child")
        let sibling = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [folder, sibling]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [folder.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        }

        await store.send(.view(.selectAllEntries))
        await store.receive { action in
            guard case let .entryViewLayout(.internal(.applySelectAll(orderedItemIds))) = action else {
                return false
            }
            return orderedItemIds == [folder.id, child.id, sibling.id]
        }
    }

    /// EVM-001-route_entry_selection_commands: arrow navigation은 hierarchy visible preorder를 layout reducer로 전달한다.
    /// normal directory list에서 현재 selection 다음 항목이 expanded child여야 하는지 검증한다.
    /// - 검증 내용: down-arrow routing이 applySelectionOffset에 visible selectable IDs를 보낸다.
    /// - 사전 조건: /root/a가 expanded이고 /root/a/child가 loaded이며 current focus는 /root/a다.
    /// - 기대 결과: ordered IDs는 [/root/a, /root/a/child, /root/b]이고 offset은 1이다.
    func testArrowNavigationRoutesVisibleOutlineOrder() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = EntryModel.temporaryFolder(id: "/root/a/child", name: "child")
        let sibling = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [folder, sibling]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [folder.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 125,
            modifiers: [],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.internal(.applySelectionOffset(offset, isShiftPressed, orderedItemIds))) =
                action
            else {
                return false
            }
            return offset == 1
                && !isShiftPressed
                && orderedItemIds == [folder.id, child.id, sibling.id]
        }
    }

    /// EVM-001-route_entry_selection_commands: nested selection의 Delete와 Return은 visible entry를 해석한다.
    /// 키보드 이동으로 선택된 expanded child가 root entries에 없어도 mutation과 rename 명령이 동작하는지 검증한다.
    /// - 검증 내용: Cmd+Delete의 child path와 Return의 child rename item routing
    /// - 사전 조건: /root/a가 expanded이고 /root/a/child가 선택돼 있다.
    /// - 기대 결과: child moveToTrash command와 startRename action이 각각 전달된다.
    func testNestedSelectionDeleteAndRenameResolveVisibleEntry() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = EntryModel.temporaryFolder(id: "/root/a/child", name: "child")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.selectedIds = [child.id]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [folder.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 51,
            modifiers: [.command],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.receive { action in
            guard case .entryViewLayout(.delegate(.executeCommand("mutation.moveSelectedItemsToTrash"))) = action
            else {
                return false
            }
            return true
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 36,
            modifiers: [],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.delegate(.startRename(item, text))) = action else {
                return false
            }
            return item == child && text == child.name
        }
    }

    /// EVM-001-route_entry_selection_commands: directory symlink Open preserves lexical navigation identity.
    /// The open delegate must route the requested alias string without resolving it to its destination path.
    /// - 검증 내용: navigateToPath bridge payload가 lexical alias path와 동일하다.
    /// - 사전 조건: directory symlink fixture와 alias folder entry가 준비돼 있다.
    /// - 기대 결과: internal requestNavigation이 alias path를 그대로 전달한다.
    func testDirectorySymlinkOpenRoutesLexicalPath() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain",
        )
        defer { sandbox.cleanup() }

        let aliasPath = sandbox.symlinkedFileURL.deletingLastPathComponent().path
        let store = TestStore(initialState: FileManagerContentState()) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.entryOperations(.delegate(.navigateToPath(aliasPath)))))
        await store.receive { action in
            guard case let .internal(.requestNavigation(.view(.navigateToPath(path)))) = action else {
                return false
            }
            return path == aliasPath
        }
    }

    // MARK: - EVM-001-route_empty_trash_command

    /// EVM-001-route_empty_trash_command: Empty Trash는 hierarchy descendant 없이 root entry만 command context로 전달한다.
    /// expanded hierarchy의 child가 Trash root 항목처럼 처리되지 않도록 Empty Trash command context를 검증한다.
    /// - 검증 내용: emptyTrash executeCommand의 displayItems가 root entries 순서만 유지한다.
    /// - 사전 조건: /root/a가 expanded이고 /root/a/child가 loaded이며 /root/b는 root sibling이다.
    /// - 기대 결과: command context displayItems는 [/root/a, /root/b]다.
    func testEmptyTrashRoutesOnlyRootEntriesAsCommandContext() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = EntryModel.temporaryFolder(id: "/root/a/child", name: "child")
        let sibling = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [folder, sibling]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [folder.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand("mutation.emptyTrash"))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(command, context)))) = action
            else {
                return false
            }
            guard case .mutation(.emptyTrash) = command else {
                return false
            }
            return context.displayItems == [folder, sibling]
        }
    }

    // MARK: - EVM-001-reload_directory_page_on_external_change

    /// EVM-001-reload_directory_page_on_external_change: folder 내부 child path 변경 시 reload
    /// 현재 folder 경로 하위의 file 또는 nested child path가 외부에서 변경되면 현재 폴더를 reload하는지 검증.
    /// - 검증 내용: folder route에서 child path 변경을 event path와 affected parent로 전달하고 loadItems 수신
    /// - 사전 조건: navigationState == .folder(fixtures/fixtures/texts/plain), showHiddenFiles == true
    /// - 기대 결과: removed prefix 없이 hierarchy invalidation 후 entryOperations.loading.loadItems 수신
    func testExternalFolderChildChangeReloadsCurrentFolder() async {
        let folderPath = Self.fixtureDir("texts/plain")
        let changedPath = "\(folderPath)/11.txt"
        let canonicalFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalChangedPath = URL(fileURLWithPath: changedPath).standardizedFileURL.resolvingSymlinksInPath().path
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        state.entryViewLayout.showHiddenFiles = true
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, removedPrefixes))) = action
            else { return false }
            return affectedPaths == [canonicalChangedPath, canonicalFolderPath] && removedPrefixes.isEmpty
        }
        await store.receive(\.entryViewLayout.entryOperations.loading.loadItems)
    }

    /// EVM-001-reload_directory_page_on_external_change: expanded folder 자체 변경 시 child cache reload
    /// folder path 자체에 modified/rescan event가 발생해도 해당 folder hierarchy cache를 갱신하는지 검증한다.
    /// - 검증 내용: changed folder path와 parent path를 hierarchy invalidation에 함께 전달
    /// - 사전 조건: 현재 directory 아래 expanded folder path에 non-deletion event가 발생함
    /// - 기대 결과: removed prefix 없이 folder path와 parent path가 affectedPaths에 포함됨
    func testExternalExpandedFolderChangeInvalidatesFolderAndParent() async {
        let folderPath = Self.fixtureDir("texts")
        let changedFolderPath = Self.fixtureDir("texts/plain")
        let canonicalFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalChangedFolderPath = URL(fileURLWithPath: changedFolderPath).standardizedFileURL
            .resolvingSymlinksInPath().path
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedFolderPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, removedPrefixes))) = action
            else { return false }
            return affectedPaths == [canonicalChangedFolderPath, canonicalFolderPath] && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            return true
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: coarse rescan flag는 hierarchy cache 전체 reload로 전달된다.
    /// ancestor path 하나만 포함한 dropped event가 expanded descendant cache를 남기지 않는지 검증한다.
    /// - 검증 내용: MustScanSubDirs event가 coarseHierarchyInvalidated action을 생성함
    /// - 사전 조건: 현재 folder 아래 expanded hierarchy가 있고 root path에 coarse event가 도착함
    /// - 기대 결과: removed prefix 없이 coarse hierarchy invalidation 후 root load가 이어짐
    func testCoarseExternalChangeRequestsCachedHierarchyReload() async {
        let folderPath = Self.fixtureDir("texts")
        let expandedFolderPath = Self.fixtureDir("texts/plain")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        state.entryViewLayout.hierarchy.setExpandedIDs([expandedFolderPath])
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents(
            [folderPath],
            flags: UInt32(kFSEventStreamEventFlagMustScanSubDirs),
        )))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.coarseHierarchyInvalidated(removedPrefixes))) = action
            else { return false }
            return removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            return true
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: expanded folder 외부 삭제·rename 시 hierarchy identity 제거
    /// watcher의 remove·rename event가 parent reload뿐 아니라 사라진 folder cache prefix도 전달하는지 검증한다.
    /// - 검증 내용: identity 변경 path의 parent affected path와 removed prefix 분리
    /// - 사전 조건: 현재 directory 아래 expanded folder에 remove 또는 rename event가 발생함
    /// - 기대 결과: 두 event 모두 folder path를 removedPrefixes로 전달함
    func testExternalExpandedFolderRemovalOrRenameEvictsHierarchyPrefix() async {
        let folderPath = Self.fixtureDir("texts")
        let removedFolderPath = Self.fixtureDir("texts/plain")
        let canonicalFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalRemovedPath = URL(fileURLWithPath: removedFolderPath).standardizedFileURL.resolvingSymlinksInPath()
            .path
        let identityChangeFlags = [
            UInt32(kFSEventStreamEventFlagItemRemoved),
            UInt32(kFSEventStreamEventFlagItemRenamed),
        ]

        for flags in identityChangeFlags {
            var state = FileManagerContentState()
            state.navigation.navigationState = .folder(folderPath)
            let store = makeStore(initialState: state)

            await store.send(.externalFileSystemChanged(Self.externalChangeEvents([removedFolderPath], flags: flags)))
            await store.receive { action in
                guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, removedPrefixes))) =
                    action
                else { return false }
                return affectedPaths == [canonicalRemovedPath, canonicalFolderPath]
                    && removedPrefixes == [canonicalRemovedPath]
            }
            await store.receive { action in
                guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
                return true
            }
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: Finder file create는 canonical affected path와 parent를 한 번
    /// reload한다.
    /// 현재 folder의 route와 history를 유지하면서 새 파일과 그 parent hierarchy를 invalidate하는지 검증한다.
    /// - 검증 내용: created file의 canonical path와 parent, 단일 loadItems transaction
    /// - 사전 조건: folder route에 back/forward history가 있고 Finder file create event가 도착함
    /// - 기대 결과: removed prefix 없이 affected path와 parent를 전달하고 route/history는 유지됨
    func testExternalFinderFileCreateInvalidatesAffectedPathAndParentOnce() async {
        await assertExternalFinderMutation(
            path: "/tmp/voyager/current/../current/new-file.txt",
            flags: UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile),
            removesSource: false,
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: Finder delete는 canonical affected path와 removed prefix를 한 번
    /// reload한다.
    /// 삭제된 entry의 원래 subtree cache를 제거하면서 현재 folder route와 history를 유지하는지 검증한다.
    /// - 검증 내용: removed file의 canonical path, parent, removed prefix, 단일 loadItems transaction
    /// - 사전 조건: folder route에 back/forward history가 있고 Finder file delete event가 도착함
    /// - 기대 결과: affected path와 parent 및 removed prefix를 전달하고 route/history는 유지됨
    func testExternalFinderFileDeleteInvalidatesAffectedPathAndRemovedPrefixOnce() async {
        await assertExternalFinderMutation(
            path: "/tmp/voyager/current/../current/deleted-file.txt",
            flags: UInt32(kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemIsFile),
            removesSource: true,
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: Finder rename은 canonical affected path와 removed prefix를 한 번
    /// reload한다.
    /// rename 이전 entry의 stale subtree cache를 제거하면서 현재 folder route와 history를 유지하는지 검증한다.
    /// - 검증 내용: renamed file의 canonical path, parent, removed prefix, 단일 loadItems transaction
    /// - 사전 조건: folder route에 back/forward history가 있고 Finder file rename event가 도착함
    /// - 기대 결과: affected path와 parent 및 removed prefix를 전달하고 route/history는 유지됨
    func testExternalFinderFileRenameInvalidatesAffectedPathAndRemovedPrefixOnce() async {
        await assertExternalFinderMutation(
            path: "/tmp/voyager/current/../current/renamed-file.txt",
            flags: UInt32(kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemIsFile),
            removesSource: true,
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: Finder subfolder create는 canonical affected path와 parent를 한 번
    /// reload한다.
    /// 새 하위 폴더의 hierarchy와 현재 folder parent를 invalidate하면서 route와 history를 유지하는지 검증한다.
    /// - 검증 내용: created subfolder의 canonical path와 parent, 단일 loadItems transaction
    /// - 사전 조건: folder route에 back/forward history가 있고 Finder directory create event가 도착함
    /// - 기대 결과: removed prefix 없이 affected path와 parent를 전달하고 route/history는 유지됨
    func testExternalFinderSubfolderCreateInvalidatesAffectedPathAndParentOnce() async {
        await assertExternalFinderMutation(
            path: "/tmp/voyager/current/../current/new-folder",
            flags: UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsDir),
            removesSource: false,
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: 관련 없는 folder 외부 변경 시 reload 안 함
    /// 현재 폴더와 관련 없는 경로의 외부 변경은 reload를 트리거하지 않는지 검증.
    /// - 검증 내용: sibling 경로 변경 시 어떤 load 액션도 수신하지 않음
    /// - 사전 조건: navigationState == .folder(fixtures/fixtures/texts/plain)
    /// - 기대 결과: externalFileSystemChanged 전송 후 수신 액션 없음
    func testExternalSiblingChangeDoesNotReloadCurrentFolder() async {
        let folderPath = Self.fixtureDir("texts/plain")
        let unrelatedPath = Self.fixturePath("images/jpeg/hopper.jpg")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([unrelatedPath])))
    }

    /// EVM-001-reload_directory_page_on_external_change: metadata-only event는 folder reload로 전달되지 않는다.
    /// filesystem metadata 변화가 stale-worthy path event가 아니므로 current folder reload를 만들지 않는지 검증한다.
    /// - 검증 내용: metadata-only gateway event의 FileManager relevance 결과
    /// - 사전 조건: visible folder interest와 xattr-only event가 존재함
    /// - 기대 결과: gateway event가 제거되어 hierarchy invalidation과 reload가 발생하지 않음
    func testMetadataOnlyFolderEventDoesNotReloadCurrentFolder() {
        let interest = FileChangeWatchInterest(
            id: "visible-folder",
            owner: .fileManager,
            purpose: .visibleFolderReload,
            roots: ["/tmp/voyager/current"],
            includeSubfolders: true,
        )
        let event = FileChangeGatewayEvent(
            path: "/tmp/voyager/current/metadata-only.txt",
            flags: UInt32(kFSEventStreamEventFlagItemXattrMod),
        )

        XCTAssertTrue(gatewayRelevantChangedEvents([event], interest: interest, openedURL: nil).isEmpty)
    }

    /// EVM-001-reload_directory_page_on_external_change: Recents route에서 route loader refresh
    /// Recents route에서 외부 변경 감지 시 recents 전용 loader만 refresh하는지 검증.
    /// - 검증 내용: recents route에서 externalFileSystemChanged 전송 시 loadRecentItems 수신
    /// - 사전 조건: navigationState == .recents, showHiddenFiles == true
    /// - 기대 결과: entryOperations.loading.loadRecentItems 액션 수신
    func testExternalChangeReloadsRecentsRoute() async {
        let changedPath = Self.fixturePath("texts/plain/11.txt")
        var state = FileManagerContentState()
        state.navigation.navigationState = .recents
        state.entryViewLayout.showHiddenFiles = true
        state.entryViewLayout.entryArrangements.sortKey = .kind
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden, priority)))) =
                action else { return false }
            return showHidden && priority == .active([.spotlight])
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: Tags route에서 route loader refresh
    /// Tags route에서 외부 변경 감지 시 tags 전용 loader만 refresh하는지 검증.
    /// - 검증 내용: tags route에서 externalFileSystemChanged 전송 시 loadTagItems 수신
    /// - 사전 조건: navigationState == .tags("Work")
    /// - 기대 결과: entryOperations.loading.loadTagItems 액션 수신
    func testExternalChangeReloadsTagsRoute() async {
        let changedPath = Self.fixturePath("texts/plain/11.txt")
        var state = FileManagerContentState()
        state.navigation.navigationState = .tags("Work")
        state.entryViewLayout.entryArrangements.groupKey = .tags
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadTagItems(
                tagName,
                showHidden,
                priority,
            )))) = action else { return false }
            return tagName == "Work" && !showHidden && priority == .active([.tags])
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: Collection route에서 directory reload로 contents 대체하지 않음
    /// Collection route에서 collection document path의 외부 변경이 directory reload로 collection contents를 대체하지 않는지 검증.
    /// - 검증 내용: collection route에서 collectionURL path 및 metadata.json path 변경 시 어떤 load 액션도 수신하지 않음
    /// - 사전 조건: navigationState == .collection, collectionSession.document 설정됨
    /// - 기대 결과: externalFileSystemChanged 전송 후 수신 액션 없음
    func testExternalChangeIgnoresOpenedCollectionDocumentPath() async {
        let collectionURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-config-\(UUID().uuidString).voycoll", isDirectory: true)
        var state = FileManagerContentState()
        state.navigation.navigationState = .collection(.init(
            kind: .file(url: collectionURL, name: "sample-config"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        state.collection.collectionSession.document = .init(url: collectionURL, name: "sample-config")
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([
            collectionURL.path,
            collectionURL.appendingPathComponent("metadata.json").path,
        ])))
    }

    /// EVM-001-reload_directory_page_on_external_change: folder 이동 시 watcher 시작 및 외부 변경 전달
    /// folder navigation 시 directory watcher가 시작되고, 외부 변경 사항이 externalFileSystemChanged로 전달되는지 검증.
    /// - 검증 내용: applyNavigationState(.folder) 전송 시 watcher 시작, clearCollectionPresentation, loadItems,
    /// externalFileSystemChanged 수신
    /// - 사전 조건: navigationState == .folder(fixtures/fixtures/texts/plain), custom fileChangeGatewayClient
    /// - 기대 결과: watcher가 changedPath를 yield하고 externalFileSystemChanged로 전달
    func testFolderNavigationStartsWatcherAndForwardsExternalChanges() async {
        let currentPath = Self.fixtureDir("texts/plain")
        let changedPath = "\(currentPath)/11.txt"
        let changedEvents = Self.externalChangeEvents(
            [changedPath],
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
        )
        let eventContinuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(currentPath)
        let interestUpdated = expectation(description: "Folder interest forwarded promptly")
        let effectOrder = LockIsolated<[String]>([])
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.updateInterests = { interests in
                effectOrder.withValue { $0.append("interest") }
                XCTAssertEqual(interests.map(\.roots), [[currentPath]])
                XCTAssertEqual(interests.map(\.purpose), [.visibleFolderReload])
                interestUpdated.fulfill()
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    eventContinuation.setValue(continuation)
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.folder(currentPath))))
        await fulfillment(of: [interestUpdated], timeout: 1)
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            XCTAssertEqual(effectOrder.value, ["interest"])
            return true
        }
        eventContinuation.value?.yield(.init(events: changedEvents))
        await store.receive { action in
            guard case let .externalFileSystemChanged(events, deliveryChainToken) = action else {
                return false
            }
            return events == changedEvents && deliveryChainToken == nil
        }
        eventContinuation.value?.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: queued batches retain their own delivery-chain token.
    /// observer가 두 batch를 먼저 enqueue해도 bridge action이 batch별 token을 그대로 전달하는지 검증한다.
    /// - 검증 내용: first와 second externalFileSystemChanged action이 각각 원래 batch token을 보존한다.
    /// - 사전 조건: 같은 folder observer에 서로 다른 token의 relevant event batch 두 개가 queue된다.
    /// - 기대 결과: 첫 action에는 first token, 둘째 action에는 second token이 전달된다.
    func testGatewayDeliveryChainTokensRemainBoundToBatches() async {
        let folderPath = "/tmp/voyager"
        let firstBatch = FileChangeGatewayEventBatch(
            events: [FileChangeGatewayEvent(
                path: "\(folderPath)/first.txt",
                flags: UInt32(kFSEventStreamEventFlagItemCreated),
                emittedAt: Date(timeIntervalSince1970: 1_700_000_000),
            )],
            deliveryChainToken: "00000000-0000-0000-0000-000000000001",
        )
        let secondBatch = FileChangeGatewayEventBatch(
            events: [FileChangeGatewayEvent(
                path: "\(folderPath)/second.txt",
                flags: UInt32(kFSEventStreamEventFlagItemCreated),
                emittedAt: Date(timeIntervalSince1970: 1_700_000_001),
            )],
            deliveryChainToken: "00000000-0000-0000-0000-000000000002",
        )
        let eventContinuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        let streamStarted = expectation(description: "Gateway observation stream started")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    eventContinuation.setValue(continuation)
                    streamStarted.fulfill()
                }
            }
        }
        // store.exhaustivity = .off: delivery token forwarding만 검증하고 navigation 내부 action은 기존 테스트가 소유한다.
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.folder(folderPath))))
        await fulfillment(of: [streamStarted], timeout: 1)
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            return true
        }

        eventContinuation.value?.yield(firstBatch)
        eventContinuation.value?.yield(secondBatch)
        await store.receive { action in
            guard case let .externalFileSystemChanged(events, deliveryChainToken) = action else {
                return false
            }
            return events == firstBatch.events && deliveryChainToken == firstBatch.deliveryChainToken
        }
        await store.receive { action in
            guard case let .externalFileSystemChanged(events, deliveryChainToken) = action else {
                return false
            }
            return events == secondBatch.events && deliveryChainToken == secondBatch.deliveryChainToken
        }
        eventContinuation.value?.finish()
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: exact gateway batch retransmission is not forwarded twice.
    /// 동일 observer lifetime에서 직전 accepted batch의 exact retransmission이 중복 invalidation을 만들지 않는지 검증한다.
    /// - 검증 내용: 동일 event count, normalized path set, flags, emittedAt set을 가진 두 번째 batch의 외부 변경 전달 여부
    /// - 사전 조건: folder watcher가 실제 observation effect를 실행하고 하나의 batch를 수신한다.
    /// - 기대 결과: 첫 batch만 `externalFileSystemChanged`로 전달되고 exact retransmission은 무시된다.
    func testExactGatewayBatchRetransmissionForwardsOnlyOnce() async {
        let folderPath = "/tmp/voyager"
        let eventContinuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        let streamStarted = expectation(description: "Gateway observation stream started")
        let observedChangeCount = LockIsolated(0)
        let event = FileChangeGatewayEvent(
            path: "\(folderPath)/created.txt",
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
            emittedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        var state = GatewayObservationHarness.State()
        state.content.navigation.navigationState = .folder(folderPath)
        let store = TestStore(initialState: state) {
            GatewayObservationHarness { count in
                observedChangeCount.setValue(count)
            }
        } withDependencies: {
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    eventContinuation.setValue(continuation)
                    streamStarted.fulfill()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.content(.internal(.applyNavigationState(.folder(folderPath)))))
        await fulfillment(of: [streamStarted], timeout: 1)

        eventContinuation.value?.yield(.init(events: [event]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [event] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 1
        })

        eventContinuation.value?.yield(.init(events: [event]))
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(observedChangeCount.value, 1)
        eventContinuation.value?.finish()
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: changed gateway batches remain accepted after dedup.
    /// exact retransmission만 억제하고 emittedAt, path, count가 달라진 batch는 계속 전달하는지 검증한다.
    /// - 검증 내용: previous accepted batch와 fingerprint가 다른 세 batch의 전달 횟수
    /// - 사전 조건: folder watcher가 실제 observation effect를 실행하고 첫 batch를 수신한다.
    /// - 기대 결과: exact retransmission은 무시되고 emittedAt/path/count 변경 batch는 각각 전달된다.
    func testChangedGatewayBatchesRemainAcceptedAfterExactDeduplication() async {
        let folderPath = "/tmp/voyager"
        let eventContinuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        let streamStarted = expectation(description: "Gateway observation stream started")
        let firstEvent = FileChangeGatewayEvent(
            path: "\(folderPath)/created.txt",
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
            emittedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let emittedAtChanged = FileChangeGatewayEvent(
            path: firstEvent.path,
            flags: firstEvent.flags,
            emittedAt: firstEvent.emittedAt.addingTimeInterval(1),
        )
        let pathChanged = FileChangeGatewayEvent(
            path: "\(folderPath)/renamed.txt",
            flags: firstEvent.flags,
            emittedAt: emittedAtChanged.emittedAt,
        )
        let countChanged = [pathChanged, FileChangeGatewayEvent(
            path: "\(folderPath)/second.txt",
            flags: firstEvent.flags,
            emittedAt: pathChanged.emittedAt.addingTimeInterval(1),
        )]
        var state = GatewayObservationHarness.State()
        state.content.navigation.navigationState = .folder(folderPath)
        let store = TestStore(initialState: state) {
            GatewayObservationHarness { _ in }
        } withDependencies: {
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    eventContinuation.setValue(continuation)
                    streamStarted.fulfill()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.content(.internal(.applyNavigationState(.folder(folderPath)))))
        await fulfillment(of: [streamStarted], timeout: 1)

        eventContinuation.value?.yield(.init(events: [firstEvent]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [firstEvent] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 1
        })
        eventContinuation.value?.yield(.init(events: [firstEvent]))
        eventContinuation.value?.yield(.init(events: [emittedAtChanged]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [emittedAtChanged] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 2
        })
        eventContinuation.value?.yield(.init(events: [pathChanged]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [pathChanged] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 3
        })
        eventContinuation.value?.yield(.init(events: countChanged))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == countChanged && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 4
        })
        eventContinuation.value?.finish()
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: cancellation and restart clear the previous batch fingerprint.
    /// watcher cancellation 뒤 새 observer lifetime에서 같은 batch가 다시 전달되는지 검증한다.
    /// - 검증 내용: folder watcher cancel/restart 이후 동일 event의 전달 횟수
    /// - 사전 조건: 첫 folder observer가 batch를 수신한 뒤 home route로 cancellation된다.
    /// - 기대 결과: 재시작된 observer는 이전 lifetime의 fingerprint에 영향받지 않는다.
    func testGatewayBatchDeduplicationResetsAfterWatcherRestart() async {
        let folderPath = "/tmp/voyager"
        let event = FileChangeGatewayEvent(
            path: "\(folderPath)/created.txt",
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
            emittedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let continuations = LockIsolated<[AsyncStream<FileChangeGatewayEventBatch>.Continuation]>([])
        let firstStreamStarted = expectation(description: "First gateway observation stream started")
        let secondStreamStarted = expectation(description: "Second gateway observation stream started")
        let streamCount = LockIsolated(0)
        var state = GatewayObservationHarness.State()
        state.content.navigation.navigationState = .folder(folderPath)
        let store = TestStore(initialState: state) {
            GatewayObservationHarness { _ in }
        } withDependencies: {
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuations.withValue { $0.append(continuation) }
                    streamCount.withValue { count in
                        count += 1
                        (count == 1 ? firstStreamStarted : secondStreamStarted).fulfill()
                    }
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.content(.internal(.applyNavigationState(.folder(folderPath)))))
        await fulfillment(of: [firstStreamStarted], timeout: 1)
        continuations.value[0].yield(.init(events: [event]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [event] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 1
        })

        await store.send(.content(.internal(.applyNavigationState(.home))))
        continuations.value[0].finish()
        await store.send(.content(.internal(.applyNavigationState(.folder(folderPath)))))
        await fulfillment(of: [secondStreamStarted], timeout: 1)
        continuations.value[1].yield(.init(events: [event]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [event] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 2
        })
        continuations.value[1].finish()
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: symlink-resolved gateway event 보존
    /// lexical watch root와 canonical event path가 달라도 sync reducer까지 event가 전달되는지 검증한다.
    /// - 검증 내용: `/var` interest에 대한 `/private/var` child event의 relevance 결과
    /// - 사전 조건: includeSubfolders가 활성화된 visible-folder interest
    /// - 기대 결과: 원본 FileChangeGatewayEvent가 필터에서 제거되지 않음
    func testGatewayRelevancePreservesCanonicalSymlinkEvent() {
        let interest = FileChangeWatchInterest(
            id: "visible-folder",
            owner: .fileManager,
            purpose: .visibleFolderReload,
            roots: ["/var/tmp"],
            includeSubfolders: true,
        )
        let event = FileChangeGatewayEvent(
            path: "/private/var/tmp/voyager-changed.txt",
            flags: UInt32(kFSEventStreamEventFlagItemModified),
        )

        XCTAssertEqual(
            gatewayRelevantChangedEvents([event], interest: interest, openedURL: nil),
            [event],
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: collection 이동 시 scope watcher 시작 및 외부 변경 전달
    /// Collection route 진입 시 `.voycoll` 위치가 아닌 collection scope 절대경로만 감시하고 변경을 전달하는지 검증.
    /// - 검증 내용: applyNavigationState(.collection) 전송 시 FileChangeGateway interest 등록, externalFileSystemChanged 수신
    /// - 사전 조건: collectionContext.scopes에 중복/상대 경로가 섞여 있음
    /// - 기대 결과: canonical absolute scope만 감시하고 changedPath를 전달
    func testCollectionScopeRootsChangedSinceSnapshotDetectsNewerRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voyager-scope-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: root.path,
        )
        let file = VoyagerCollectionFile(
            id: UUID().uuidString,
            name: "demo",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            query: "",
            scopes: [root.path],
            conditions: [],
            snapshot: nil,
            snapshotMeta: CollectionSnapshotMeta(
                definitionFingerprint: "fingerprint",
                capturedAt: Date(timeIntervalSince1970: 100),
                itemCount: 0,
                relevanceRoots: [root.path],
            ),
            appVersion: nil,
        )

        XCTAssertTrue(collectionScopeRootsChangedSinceSnapshot(file))
    }

    func testCollectionScopeRootsChangedSinceSnapshotIgnoresMissingSnapshot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voyager-scope-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = VoyagerCollectionFile(
            id: UUID().uuidString,
            name: "demo",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            query: "",
            scopes: [root.path],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )

        XCTAssertFalse(collectionScopeRootsChangedSinceSnapshot(file))
    }

    func testCollectionNavigationStartsScopeWatcherAndForwardsExternalChanges() async {
        let firstScope = "/tmp/voyager/scope-a"
        let secondScope = "/tmp/voyager/scope-b/../scope-b"
        let changedPath = "/tmp/voyager/scope-a/changed.txt"
        let changedEvents = Self.externalChangeEvents(
            [changedPath],
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
        )
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/demo.voycoll")
        let context = CollectionContext(
            query: "",
            scopes: [firstScope, "relative", secondScope, firstScope],
            conditions: [],
        )
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "demo"),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.collection.collectionContext = context
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.updateInterests = { interests in
                XCTAssertEqual(interests.map(\.roots), [["/tmp/voyager/scope-a", "/tmp/voyager/scope-b"]])
                XCTAssertEqual(interests.map(\.purpose), [.collectionStale])
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.yield(.init(events: changedEvents))
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState))) {
            $0.entryViewLayout.currentPath = "collection:\(collectionURL.standardizedFileURL.path)"
        }
        await store.receive { action in
            guard case let .externalFileSystemChanged(events, deliveryChainToken) = action else {
                return false
            }
            return events == changedEvents && deliveryChainToken == nil
        }
    }

    func testCollectionNavigationIgnoresMetadataOnlyScopeEvents() async {
        let scope = "/tmp/voyager/scope-a"
        let changedPath = "/tmp/voyager/scope-a/opened.txt"
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/demo.voycoll")
        let context = CollectionContext(query: "", scopes: [scope], conditions: [])
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "demo"),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.collection.collectionContext = context
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.updateInterests = { interests in
                XCTAssertEqual(interests.map(\.roots), [[scope]])
                XCTAssertEqual(interests.map(\.purpose), [.collectionStale])
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.yield(.init(events: [
                        FileChangeGatewayEvent(
                            path: changedPath,
                            flags: UInt32(kFSEventStreamEventFlagItemXattrMod),
                        ),
                    ]))
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState))) {
            $0.entryViewLayout.currentPath = "collection:\(collectionURL.standardizedFileURL.path)"
        }
    }

    /// EVM-001-navigate_pages: collection navigation도 scroll position key를 저장/복원
    /// Collection route 진입 시 saved collection URL 기반 key로 currentPath와 savedScrollOffset을 주입하는지 검증.
    /// - 검증 내용: applyNavigationState(.collection(.file)) 전송 시 entryViewLayout.currentPath와 savedScrollOffset 동기화
    /// - 사전 조건: scrollPositions에 saved collection URL 기반 key가 저장됨
    /// - 기대 결과: collection 진입 후 list/grid coordinator가 같은 key로 scroll offset을 복원할 수 있음
    func testCollectionNavigationRestoresSavedScrollOffset() async {
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/saved.voycoll")
        let scrollKey = "collection:\(collectionURL.standardizedFileURL.path)"
        let savedOffset = CGPoint(x: 0, y: 240)
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "saved"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.navigation.scrollPositions[scrollKey] = savedOffset

        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState))) {
            $0.entryViewLayout.currentPath = scrollKey
            $0.entryViewLayout.savedScrollOffset = savedOffset
        }
    }

    /// EVM-001-navigate_pages: collection scroll offset 저장은 현재 collection key에 즉시 반영
    /// EntryViewLayout delegate가 저장한 collection scroll offset이 현재 route의 savedScrollOffset과 scrollPositions에 동기화되는지 검증.
    /// - 검증 내용: saveScrollOffset(offset, forPath: collectionKey) 전송 시 scrollPositions와 savedScrollOffset 갱신
    /// - 사전 조건: navigationState == .collection(.file), entryViewLayout.currentPath == collection URL 기반 key
    /// - 기대 결과: collection에서 다른 route로 이동 후 돌아왔을 때 같은 offset을 복원할 수 있음
    func testCollectionNavigationSavesScrollOffsetForCurrentCollectionKey() async {
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/saved.voycoll")
        let scrollKey = "collection:\(collectionURL.standardizedFileURL.path)"
        let savedOffset = CGPoint(x: 0, y: 480)
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "saved"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.entryViewLayout.currentPath = scrollKey

        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        }

        await store.send(.internal(.saveScrollOffset(savedOffset, forPath: scrollKey))) {
            $0.navigation.scrollPositions[scrollKey] = savedOffset
            $0.entryViewLayout.savedScrollOffset = savedOffset
        }
    }

    /// EVM-001-home_navigation_clears_hidden_entries: Home route 적용 시 숨은 folder selection 정리
    /// Home 화면 진입 후에도 이전 folder entry/selection이 메뉴 command projection에 남지 않도록 검증.
    /// - 검증 내용: applyNavigationState(.home)이 selection·entry list를 비우고 이전 generation batch를 무시함
    /// - 사전 조건: generation 1의 folder load와 선택된 entry가 남아 있는 상태
    /// - 기대 결과: generation을 무효화하고 Home 전환 뒤 도착한 generation 1 batch를 반영하지 않음
    func testHomeNavigationClearsHiddenEntrySelectionAndItems() async {
        let previousEntry = EntryModel.temporaryFolder(
            id: "/tmp/voyager-hidden-selection",
            name: "voyager-hidden-selection",
        )
        let staleEntry = EntryModel.temporaryFolder(
            id: "/tmp/voyager-stale-root-batch",
            name: "voyager-stale-root-batch",
        )
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/tmp")
        state.entryViewLayout.entries = [previousEntry]
        state.entryViewLayout.selectedIds = [previousEntry.id]
        state.entryViewLayout.lastSelectedId = previousEntry.id
        state.entryViewLayout.rangeAnchorId = previousEntry.id
        state.entryViewLayout.entryOperations.loadingContext.items = [previousEntry]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.loadingContext.sourceKind = .directory
        state.entryViewLayout.entryOperations.isLoading = true

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.home)))
        await store.receive(\.entryViewLayout.entryOperations.loading.cancelAndClearItems)
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive(\.entryViewLayout.internal.applyClearSelection)
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }
        await store.finish()

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [staleEntry], batchIndex: 0),
        ))))))

        XCTAssertEqual(store.state.entryViewLayout.currentPath, "Home")
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entries.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.loadingContext.items.isEmpty)
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.loadingContext.generation, 2)
        XCTAssertNil(store.state.entryViewLayout.entryOperations.loadingContext.sourceKind)
    }

    /// EVM-001-ai_chat_navigation_clears_hidden_entries: AI Chat route 적용 시 숨은 folder selection 정리
    /// AI Chat 화면 진입 후에도 이전 folder entry/selection이 command projection에 남지 않도록 검증.
    func testAiChatNavigationClearsHiddenEntrySelectionAndItems() async {
        await assertAiChatNavigationClearsHiddenEntrySelectionAndItems(.aiChat(Self.aiChatRouteSessionID))
    }

    /// EVM-001-ai_chat_sessions_navigation_clears_hidden_entries: AI Chat History route 적용 시 숨은 folder selection 정리
    /// AI Chat History 화면도 파일 command와 분리되어야 하므로 이전 entry projection을 비움.
    func testAiChatSessionsNavigationClearsHiddenEntrySelectionAndItems() async {
        await assertAiChatNavigationClearsHiddenEntrySelectionAndItems(.aiChatSessions(Self.aiChatRouteSessionID))
    }

    private static let aiChatRouteSessionID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"

    private func assertAiChatNavigationClearsHiddenEntrySelectionAndItems(
        _ navigationState: ContentPageNavigationRoute,
    ) async {
        let previousEntry = EntryModel.temporaryFolder(
            id: "/tmp/voyager-ai-chat-hidden-selection",
            name: "voyager-ai-chat-hidden-selection",
        )
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/tmp")
        state.entryViewLayout.entries = [previousEntry]
        state.entryViewLayout.selectedIds = [previousEntry.id]
        state.entryViewLayout.lastSelectedId = previousEntry.id
        state.entryViewLayout.rangeAnchorId = previousEntry.id
        state.entryViewLayout.entryOperations.loadingContext.items = [previousEntry]

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState)))
        await store.receive(\.entryViewLayout.entryOperations.loading.cancelAndClearItems)
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive(\.entryViewLayout.internal.applyClearSelection)
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }
        await store.finish()

        XCTAssertTrue(store.state.entryViewLayout.selectedIds.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entries.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.loadingContext.items.isEmpty)
    }

    private func makeStore(initialState: FileManagerContentState)
        -> TestStore<FileManagerContentState, FileManagerContentAction>
    {
        TestStore(initialState: initialState) {
            FileManagerContentSyncReducer()
        }
    }

    private func assertExternalFinderMutation(
        path: String,
        flags: UInt32,
        removesSource: Bool,
    ) async {
        let currentPath = "/tmp/voyager/current"
        let backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .home)]
        let forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/tmp/forward"))]
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(currentPath)
        state.navigation.backHistory = backHistory
        state.navigation.forwardHistory = forwardHistory
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([path], flags: flags)))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            ))) = action else { return false }
            let canonicalPath = Self.canonicalPath(path)
            let expectedParent = URL(fileURLWithPath: canonicalPath).deletingLastPathComponent().path
            let expectedRemovedPrefixes = removesSource ? [canonicalPath] : []
            return affectedPaths == [canonicalPath, expectedParent]
                && removedPrefixes == expectedRemovedPrefixes
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(path, showHidden, priority)))) =
                action
            else {
                return false
            }
            return path == currentPath && !showHidden && priority == .none
        }

        XCTAssertEqual(store.state.navigation.navigationState, .folder(currentPath))
        XCTAssertEqual(store.state.navigation.backHistory, backHistory)
        XCTAssertEqual(store.state.navigation.forwardHistory, forwardHistory)
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    // Fixture path helpers

    /// `fixtures/fixtures/` 하위 디렉토리의 절대 경로를 반환.
    private static func fixtureDir(_ subpath: String) -> String {
        guard let root = try? resolveRepoRoot() else {
            XCTFail("Repository fixture root could not be resolved")
            return FileManager.default.temporaryDirectory.path
        }
        return root.appendingPathComponent("fixtures/fixtures")
            .appendingPathComponent(subpath).path
    }

    private static func externalChangeEvents(
        _ paths: [String],
        flags: UInt32 = UInt32(kFSEventStreamEventFlagItemModified),
    ) -> [FileChangeGatewayEvent] {
        paths.map { FileChangeGatewayEvent(path: $0, flags: flags, emittedAt: .distantPast) }
    }

    /// `fixtures/fixtures/` 하위 파일의 절대 경로를 반환.
    private static func fixturePath(_ subpath: String) -> String {
        guard let root = try? resolveRepoRoot() else {
            XCTFail("Repository fixture root could not be resolved")
            return FileManager.default.temporaryDirectory.appendingPathComponent(subpath).path
        }
        return root.appendingPathComponent("fixtures/fixtures")
            .appendingPathComponent(subpath).path
    }

    /// CWD에서 위로 올라가며 repo root(`.git` 또는 `Package.swift`)를 찾고
    /// `fixtures/fixtures/` 존재를 교차 검증한다.
    /// `FixtureSandbox.resolveRepoRoot`와 동일한 탐지 정책을 사용한다.
    private static func resolveRepoRoot() throws -> URL {
        let cwd = FileManager.default.currentDirectoryPath
        var url = URL(fileURLWithPath: cwd)
        for _ in 0 ..< 10 {
            let hasRepoMarker = FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
                || FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
            if hasRepoMarker,
               FileManager.default.fileExists(atPath: url.appendingPathComponent("fixtures/fixtures").path)
            {
                return url
            }
            guard let parent = url.pathComponents.count > 1 ? url.deletingLastPathComponent() : nil else { break }
            url = parent
        }
        throw FixturePathError.repoRootNotFound(searchFrom: cwd)
    }

    // MARK: - EVM-001-reload_directory_page_on_external_change

    private let reducer = FileManagerContentFeature()

    struct LifecycleBridgeHarness: @MainActor Reducer {
        // swiftlint:disable:next nesting
        struct State: Equatable {
            var content: FileManagerContentState
        }

        // swiftlint:disable:next nesting
        enum Action {
            case bridge(EntryOperationsAction)
            case forwarded(FileManagerContentAction)
        }

        var body: some Reducer<State, Action> {
            Reduce { state, action in
                switch action {
                case let .bridge(entryAction):
                    FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
                        entryAction,
                        state: &state.content,
                    )
                    .map(Action.forwarded)
                case .forwarded:
                    .none
                }
            }
        }
    }

    @Reducer
    struct GatewayObservationHarness {
        let onExternalChange: @Sendable (Int) -> Void

        struct State: Equatable {
            var content = FileManagerContentState()
            var externalChangeCount = 0
        }

        enum Action {
            case content(FileManagerContentAction)
        }

        var body: some Reducer<State, Action> {
            Scope(state: \.content, action: \.content) {
                FileManagerContentNavigationBridgeReducer()
            }
            Reduce { state, action in
                guard case let .content(.externalFileSystemChanged(events, _)) = action else {
                    return .none
                }
                state.externalChangeCount += events.isEmpty ? 0 : 1
                onExternalChange(state.externalChangeCount)
                return .none
            }
        }
    }

    private func makeInitialState() -> LifecycleBridgeHarness.State {
        LifecycleBridgeHarness.State(content: FileManagerContentState())
    }

    private func makeInitialState(folderPath: String) -> LifecycleBridgeHarness.State {
        var state = makeInitialState()
        state.content.navigation.seedInitialFolderPath(folderPath)
        state.content.navigation.navigationState = .folder(folderPath)
        return state
    }

    private func makeCorrelationEntry(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: .distantPast,
            fileExtension: "",
            facets: EntryFacets(
                createdDate: .distantPast,
                addedDate: .distantPast,
                lastOpenedDate: nil,
                kind: "",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }

    private func makeCorrelationState(folderPath: String) -> CommandExternalRefreshHarness.State {
        var state = CommandExternalRefreshHarness.State()
        state.content.navigation.seedInitialFolderPath(folderPath)
        state.content.navigation.navigationState = .folder(folderPath)
        return state
    }

    private func makeExpandedChildTransitionFixture() -> ExpandedChildTransitionFixture {
        let rootPath = "/tmp/voyager-correlation"
        let folder = EntryModel.temporaryFolder(id: "\(rootPath)/folder", name: "folder")
        let before = makeCorrelationEntry(id: "\(folder.id)/before.txt", name: "before.txt")
        let after = makeCorrelationEntry(id: "\(folder.id)/after.txt", name: "after.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.navigation.navigationState = .folder(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.entryOperations.items = [folder]
        state.entryViewLayout.entryOperations.loadingContext.items = [folder]
        state.entryViewLayout.entryOperations.loadingContext.generation = 7
        state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[folder.id] = .init(
            children: [before],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 1,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: before.id, afterPath: after.id)],
        )
        _ = FileManagerContentEntryOpsCoordinator.recordIdentityTransitionIfEligible(record, state: &state)
        state.entryViewLayout.hierarchy.nodesByID[folder.id]?.generation = 2
        state.entryViewLayout.hierarchy.nodesByID[folder.id]?.loadPhase = .loadingCore
        state.entryViewLayout.hierarchy.nodesByID[folder.id]?.folder.coreFinished = false
        state.entryViewLayout.hierarchy.nodesByID[folder.id]?.folder.expectedBatchIndex = 0
        state.entryViewLayout.hierarchy.nodesByID[folder.id]?.folder.hasAppliedContentBatch = false
        return ExpandedChildTransitionFixture(state: state, folder: folder, before: before, after: after)
    }

    private func makeCrossFolderMoveFixture() -> CrossFolderMoveFixture {
        let rootPath = "/tmp/voyager-cross-move"
        let source = EntryModel.temporaryFolder(id: "\(rootPath)/src", name: "src")
        let destination = EntryModel.temporaryFolder(id: "\(rootPath)/dst", name: "dst")
        let before = makeCorrelationEntry(id: "\(source.id)/before.txt", name: "before.txt")
        let after = makeCorrelationEntry(id: "\(destination.id)/after.txt", name: "after.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.navigation.navigationState = .folder(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [source, destination]
        state.entryViewLayout.entryOperations.items = [source, destination]
        state.entryViewLayout.entryOperations.loadingContext.items = [source, destination]
        state.entryViewLayout.entryOperations.loadingContext.generation = 7
        state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            children: [before],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 1,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: before.id, afterPath: after.id)],
        )
        _ = FileManagerContentEntryOpsCoordinator.recordIdentityTransitionIfEligible(record, state: &state)
        for id in [source.id, destination.id] {
            state.entryViewLayout.hierarchy.nodesByID[id]?.generation = 2
            state.entryViewLayout.hierarchy.nodesByID[id]?.loadPhase = .loadingCore
            state.entryViewLayout.hierarchy.nodesByID[id]?.folder.coreFinished = false
            state.entryViewLayout.hierarchy.nodesByID[id]?.folder.expectedBatchIndex = 0
            state.entryViewLayout.hierarchy.nodesByID[id]?.folder.hasAppliedContentBatch = false
        }
        return CrossFolderMoveFixture(
            state: state,
            source: source,
            destination: destination,
            before: before,
            after: after,
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: folder route entry operation 완료 시 directory reload forwarding
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: folder route에서 entry operation 완료 액션이 현재 folder loader로 전달되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testOperationFinishedTriggersContentReload() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let folderPath = sandbox.fileURL.deletingLastPathComponent().path
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            sandbox.fileURL.path,
            .rename,
            .success(()),
        ))))

        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: 즉시 삭제 성공 시 hierarchy 제거 prefix 전달
    /// undo record가 없는 deleteImmediately도 삭제된 folder cache를 제거하는지 검증한다.
    /// - 검증 내용: operationFinished 성공 path가 parent invalidation과 removedPrefixes에 함께 전달됨
    /// - 사전 조건: folder route에서 중첩 folder 즉시 삭제가 성공함
    /// - 기대 결과: affectedPaths는 parent, removedPrefixes는 삭제된 folder path를 포함함
    func testDeleteImmediatelySuccessInvalidatesRemovedHierarchyPrefix() async {
        let folderPath = "/tmp/voyager"
        let deletedPath = "/tmp/voyager/deleted"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            deletedPath,
            .deleteImmediately,
            .success(()),
        ))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath] && removedPrefixes == [deletedPath]
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: paste 실패도 교체 선삭제 이후라면 reload한다.
    /// replace-existing 파이프라인은 목적지를 먼저 삭제한 뒤 move/copy하므로,
    /// 취소 아닌 실패는 이미 파일시스템이 변경됐을 수 있다.
    /// - 검증 내용: pasteFileMove system 실패 수신 시 현재 folder loader로 reload 전달
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: loadItems forwarding이 발생해 삭제된 목적지 항목이 화면에서 정리된다
    func testPasteMoveFailureReloadsContentForDestructivePreStep() async {
        let folderPath = "/tmp/voyager-paste-failure"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "\(folderPath)/source.txt",
            .pasteFileMove,
            .failure(.system(message: "post-delete failure")),
        ))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden,
                priority,
            ))))) =
                action else { return false }
            return path == folderPath && showHidden == false && priority == .none
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: 취소된 paste 실패는 mutation 전이므로 reload하지 않는다.
    /// - 검증 내용: pasteFileMove cancelled 실패 수신 시 forwarding 없음
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: reload effect 미발생
    func testCancelledPasteFailureDoesNotReloadContent() async {
        let folderPath = "/tmp/voyager-paste-cancel"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "\(folderPath)/source.txt",
            .pasteFileMove,
            .failure(.cancelled),
        ))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: drop 실패도 교체 선삭제 이후라면 reload한다.
    /// drop은 성공 시 entriesMutated impact로 갱신되지만, 전체 실패 배치는 impact가 없어
    /// operationFinished와 같은 destructive pre-step 분류로 보완한다.
    /// - 검증 내용: dropOperationFinished pasteFileMove system 실패 수신 시 reload 전달
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: loadItems forwarding이 발생한다
    func testDropMoveFailureReloadsContentForDestructivePreStep() async {
        let folderPath = "/tmp/voyager-drop-failure"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.dropOperationFinished(
            "\(folderPath)/source.txt",
            .pasteFileMove,
            .failure(.system(message: "post-delete failure")),
        ))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden,
                priority,
            ))))) =
                action else { return false }
            return path == folderPath && showHidden == false && priority == .none
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: 취소된 drop 실패는 reload하지 않는다.
    /// - 검증 내용: dropOperationFinished pasteFileCopy cancelled 실패 수신 시 forwarding 없음
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: reload effect 미발생
    func testCancelledDropFailureDoesNotReloadContent() async {
        let folderPath = "/tmp/voyager-drop-cancel"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.dropOperationFinished(
            "\(folderPath)/source.txt",
            .pasteFileCopy,
            .failure(.cancelled),
        ))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: 압축 해제 부분 실패도 mutation 전이므로 reload한다.
    /// extract는 대상 폴더 생성 후 항목을 하나씩 옮기므로 중간 실패 시 일부 결과가 남는다.
    /// - 검증 내용: operationFinished .extract system 실패 수신 시 reload 전달
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: loadItems forwarding이 발생한다
    func testExtractFailureReloadsContentForPartialMutation() async {
        let folderPath = "/tmp/voyager-extract-failure"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "\(folderPath)/archive.zip",
            .extract,
            .failure(.system(message: "mid-extract move failure")),
        ))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden,
                priority,
            ))))) =
                action else { return false }
            return path == folderPath && showHidden == false && priority == .none
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: 취소된 extract 실패는 reload하지 않는다.
    /// - 검증 내용: operationFinished .extract cancelled 수신 시 forwarding 없음
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: reload effect 미발생
    func testCancelledExtractFailureDoesNotReloadContent() async {
        let folderPath = "/tmp/voyager-extract-cancel"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "\(folderPath)/archive.zip",
            .extract,
            .failure(.cancelled),
        ))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: undo/redo rename도 folder route에서 root reload를 유지한다.
    /// replaySucceeded는 entryActionCompleted 없이 도착하므로 operationFinished에서 보류한
    /// reload를 이 경로가 대신 수행하지 않으면 목록이 이전 identity에 머문다.
    /// - 검증 내용: folder route replaySucceeded rename record가 loadItems forwarding을 내는지 검증
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: hierarchyInvalidated와 loadItems forwarding이 발생한다
    func testUndoRedoReplayKeepsRootReloadForIdentityOperations() async {
        let folderPath = "/tmp/voyager-undo-rename"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.undoRedo(.replaySucceeded(
            direction: .undo,
            sourceRecordID: UUID(),
            updatedRecord: EntryActionRecord(
                operationKind: .rename,
                targets: [
                    .init(beforePath: "\(folderPath)/new.txt", afterPath: "\(folderPath)/old.txt"),
                ],
            ),
        ))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == ["\(folderPath)/new.txt"]
        }
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden,
                priority,
            ))))) =
                action else { return false }
            return path == folderPath && showHidden == false && priority == .none
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: recents route entry operation 완료 시 recents reload forwarding
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: recents route에서 entry operation 완료 액션이 recents loader로 전달되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testOperationFinishedTriggersContentReloadForRecents() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .recents

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .moveToTrash,
            .success(()),
        ))))

        await store.receive { action in
            guard case .forwarded(.entryViewLayout(.entryOperations(.loading(.loadRecentItems(
                showHidden: false,
                priority: .none,
            ))))) =
                action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: 개별 setTags 완료는 최종 record 전에는 reload하지 않는다.
    func testSetTagsOperationFinishedDoesNotReloadBeforeFinalRecord() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .tags("Work")

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .setTags,
            .success(()),
        ))))

        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: setTags의 최종 성공 record는 일반 folder를 한 번 reload한다.
    func testSetTagsEntryActionCompletedReloadsFolderOnce() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let folderPath = sandbox.fileURL.deletingLastPathComponent().path
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off
        let record = EntryActionRecord(
            operationKind: .setTags,
            targets: [.init(beforePath: sandbox.fileURL.path, afterPath: sandbox.fileURL.path)],
        )

        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden,
                priority,
            ))))) =
                action else { return false }
            return path == folderPath && showHidden == false && priority == .none
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection setTags 최종 record는 성공 target만 stale 처리 후 refresh한다.
    func testSetTagsEntryActionCompletedRefreshesOnlySuccessfulCollectionTargets() async {
        let store = TestStore(initialState: makeCollectionInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off
        let record = EntryActionRecord(
            operationKind: .setTags,
            targets: [
                .init(beforePath: "/tmp/a.txt", afterPath: "/tmp/a.txt"),
                .init(beforePath: "/tmp/b.txt", afterPath: "/tmp/b.txt"),
            ],
        )

        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .forwarded(.collection(.externalPathsChanged(paths))) = action else { return false }
            return paths == ["/tmp/a.txt", "/tmp/b.txt"]
        }
        await store.receive { action in
            guard case .forwarded(.view(.refreshStaleCollection)) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection setTags undo/redo도 최종 성공 target만 같은 refresh seam으로
    /// 전달한다.
    func testSetTagsUndoAndRedoRefreshOnlySuccessfulCollectionTargets() async {
        let store = TestStore(initialState: makeCollectionInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off
        let record = EntryActionRecord(
            operationKind: .setTags,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/a.txt")],
        )

        for direction in [EntryActionDirection.undo, .redo] {
            await store.send(.bridge(.undoRedo(.replaySucceeded(
                direction: direction,
                sourceRecordID: record.id,
                updatedRecord: record,
            ))))
            await store.receive { action in
                guard case let .forwarded(.collection(.externalPathsChanged(paths))) = action else { return false }
                return paths == ["/tmp/a.txt"]
            }
            await store.receive { action in
                guard case .forwarded(.view(.refreshStaleCollection)) = action else { return false }
                return true
            }
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection route entry operation 완료 시 directory reload 차단
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: collection route에서 entry operation 완료가 directory loader로 전달되지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testOperationFinishedOnCollectionNavigationReturnsNone() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .rename,
            .success(()),
        ))))
        await store.finish()
    }

    private func makeCollectionInitialState() -> LifecycleBridgeHarness.State {
        var state = makeInitialState()
        state.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        state.content.entryViewLayout.isCollectionMode = true
        return state
    }

    /// EVM-001-reload_directory_page_on_external_change: empty trash 완료 시 window close delegate forwarding
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: empty trash 완료 lifecycle이 FileManager closeWindow delegate로 전달되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testEmptyTrashCompletedTriggersCloseWindow() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.emptyTrashCompleted)))

        await store.receive { action in
            guard case .forwarded(.delegate(.closeWindow)) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: entry action completed metrics-only lifecycle no-op
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: entryActionCompleted lifecycle이 reload나 closeWindow side effect를 만들지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testEntryActionCompletedReturnsNoneWithoutReload() async {
        let folderPath = "/tmp/voyager"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [EntryActionRecord.Target(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
        )

        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: source-preserving 완료 레코드는 parent만 무효화한다.
    /// 복사, 복제, 별칭, 태그, 생성은 원본을 현재 위치에서 제거하지 않으므로 expanded subtree를 제거하면 안 된다.
    /// - 검증 내용: before/after parent가 affectedPaths에 포함되고 removedPrefixes는 비어 있다.
    /// - 사전 조건: navigationState == .folder(/tmp/voyager), source-preserving EntryActionRecord 완료.
    /// - 기대 결과: hierarchyInvalidated가 parent refresh만 요청한다.
    func testSourcePreservingEntryActionCompletedInvalidatesParentsWithoutRemovedPrefixes() async {
        let folderPath = "/tmp/voyager"
        let records = [
            EntryActionRecord(
                operationKind: .createFolder,
                targets: [.init(beforePath: nil, afterPath: "\(folderPath)/new-folder")],
            ),
            EntryActionRecord(
                operationKind: .createAlias,
                targets: [.init(beforePath: "\(folderPath)/source.txt", afterPath: "\(folderPath)/source alias")],
            ),
            EntryActionRecord(
                operationKind: .pasteFileCopy,
                targets: [.init(beforePath: "\(folderPath)/source.txt", afterPath: "\(folderPath)/copy.txt")],
            ),
            EntryActionRecord(
                operationKind: .pasteFileDuplicate,
                targets: [.init(beforePath: "\(folderPath)/source.txt", afterPath: "\(folderPath)/duplicate.txt")],
            ),
            EntryActionRecord(
                operationKind: .setTags,
                targets: [.init(beforePath: "\(folderPath)/source.txt", afterPath: "\(folderPath)/source.txt")],
            ),
        ]

        for record in records {
            let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
                LifecycleBridgeHarness()
            }

            await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
            await store.receive { action in
                guard case let .forwarded(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                    affectedPaths,
                    removedPrefixes,
                )))) = action else { return false }
                return affectedPaths.allSatisfy { $0 == folderPath } && removedPrefixes.isEmpty
            }
            if record.operationKind == .setTags {
                await store.receive { action in
                    guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                        path,
                        showHidden,
                        priority,
                    ))))) = action else { return false }
                    return path == folderPath && showHidden == false && priority == .none
                }
            }
            await store.finish()
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: source-relocating 완료 레코드는 원래 subtree를 제거한다.
    /// 이동, 이름변경, 휴지통 이동, 복원은 원본 경로를 더 이상 유지하지 않으므로 stale expanded subtree를 제거해야 한다.
    /// - 검증 내용: before/after parent가 affectedPaths에 포함되고 beforePath가 removedPrefixes에 포함된다.
    /// - 사전 조건: navigationState == .folder(/tmp/voyager), source-relocating EntryActionRecord 완료.
    /// - 기대 결과: hierarchyInvalidated가 parent refresh와 원본 subtree 제거를 함께 요청한다.
    func testSourceRelocatingEntryActionCompletedInvalidatesParentsAndRemovedPrefixes() async {
        let folderPath = "/tmp/voyager"
        let sourcePath = "\(folderPath)/source.txt"
        let destinationPath = "/tmp/destination/source.txt"
        let records = [
            EntryActionRecord(
                operationKind: .pasteFileMove,
                targets: [.init(beforePath: sourcePath, afterPath: destinationPath)],
            ),
            EntryActionRecord(
                operationKind: .rename,
                targets: [.init(beforePath: sourcePath, afterPath: destinationPath)],
            ),
            EntryActionRecord(
                operationKind: .moveToTrash,
                targets: [.init(beforePath: sourcePath, afterPath: destinationPath)],
            ),
            EntryActionRecord(
                operationKind: .putBack,
                targets: [.init(beforePath: sourcePath, afterPath: destinationPath)],
            ),
        ]

        for record in records {
            let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
                LifecycleBridgeHarness()
            }

            await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
            await store.receive { action in
                guard case let .forwarded(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                    affectedPaths,
                    removedPrefixes,
                )))) = action else { return false }
                return affectedPaths == [folderPath, "/tmp/destination"]
                    && removedPrefixes == [sourcePath]
            }
            await store.finish()
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: collection route put back 완료 시 collection presentation restore
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: collection route에서 putBack 완료 후 collection presentation 복구 액션이 생성되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testPutBackEntryActionCompletedOnCollectionNavigationRestoresCollectionPresentation() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.content.entryViewLayout.isCollectionMode = true

        let restoredRecord = EntryActionRecord(
            operationKind: .putBack,
            targets: [EntryActionRecord.Target(beforePath: "/Users/me/.Trash/a.txt", afterPath: "/tmp/a.txt")],
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.entryActionCompleted(restoredRecord))))
        await store.receive { action in
            guard case .forwarded = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection route move-to-trash undo 시 collection presentation
    /// restore
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: collection route에서 moveToTrash undo 후 collection presentation 복구 액션이 생성되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testUndoAppliedMoveToTrashOnCollectionNavigationRestoresCollectionPresentation() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.content.entryViewLayout.isCollectionMode = true

        let trashedRecord = EntryActionRecord(
            operationKind: .moveToTrash,
            targets: [EntryActionRecord.Target(beforePath: "/tmp/a.txt", afterPath: "/Users/me/.Trash/a.txt")],
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.undoRedo(.replaySucceeded(
            direction: .undo,
            sourceRecordID: trashedRecord.id,
            updatedRecord: trashedRecord,
        ))))
        await store.receive { action in
            guard case .forwarded = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: loading 결과 액션 bridge no-op
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: itemsLoaded 액션이 FileManager content lifecycle bridge side effect를 만들지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testLoadingItemsLoadedReturnsNone() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded([]))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: windowIDChanged lifecycle bridge no-op
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: windowIDChanged lifecycle이 reload나 closeWindow side effect를 만들지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testWindowIDChangedDoesNotTriggerReloadOrCloseWindow() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.windowIDChanged(UUID()))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: raw pathsMutated는 원본과 대상 부모를 refresh하고 hierarchy를 제거하지 않는다.
    /// Copy, duplicate, drop-copy가 typed completion 전에 내보내는 원시 경로도 폴더 트리의 확장 상태를 유지하는지 검증한다.
    /// - 검증 내용: source와 destination의 parent가 affectedPaths에 순서대로 포함되고 removedPrefixes가 비어 있다.
    /// - 사전 조건: folder route와 source/destination raw mutation path를 가진 lifecycle bridge harness 구성.
    /// - 기대 결과: hierarchyInvalidated가 두 parent refresh만 요청하며 subtree prune을 요청하지 않는다.
    func testPathsMutatedInvalidatesParentsWithoutRemovedPrefixes() async {
        await assertPathsMutatedInvalidatesParentsWithoutRemovedPrefixes()
    }

    // MARK: - EVM-001-command_external_refresh_correlation

    /// EVM-001-command_external_refresh_correlation: 명령 완료 후 일치하는 외부 rename 이벤트가 중복 refresh를 예약한다(현행 고정).
    /// rename 명령 완료가 예약한 계층 무효화와 동일 identity 변경의 외부 이벤트 무효화가
    /// 현재는 별도의 visible refresh로 중복 예약되는 현행 동작을 고정한다.
    /// - 검증 내용: hierarchyInvalidation 총 2회(명령 1 + 외부 1)와 외부 root reload 1회 예약 수
    /// - 사전 조건: folder 라우트에서 old.txt 선택 후 rename 완료 기록, 같은 경로의 외부 renamed 이벤트
    /// - 기대 결과: 계층 무효화 2회, 외부 loadItems 1회로 중복 refresh 의도가 관측됨
    func testCommandCompletionThenMatchingExternalEventSchedulesDuplicateRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let store = TestStore(initialState: makeCorrelationState(folderPath: folderPath)) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([oldPath], flags: UInt32(kFSEventStreamEventFlagItemRenamed)),
            deliveryChainToken: nil,
        )))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(oldPath), Self.canonicalPath(folderPath)]
                && removedPrefixes == [Self.canonicalPath(oldPath)]
        }
        await store.receive { action in
            guard case let .content(.entryViewLayout(.entryOperations(.loading(.loadItems(path, _, _))))) =
                action else { return false }
            return path == folderPath
        }

        XCTAssertEqual(store.state.hierarchyInvalidations.count, 2, "명령과 외부 이벤트가 각각 계층 무효화를 예약한다")
        XCTAssertEqual(store.state.rootReloadCount, 1, "외부 이벤트가 root reload를 추가로 예약한다")
    }

    /// EVM-001-command_external_refresh_correlation: 일치하는 외부 rename 이벤트는 명령 refresh에 병합된다.
    /// consume-once 경로 전이가 있으면 동일 identity 변경의 외부 이벤트가 중복 계층 무효화와
    /// 중복 root reload를 예약하지 않는지 검증한다. 뒤이은 무관한 이벤트로 큐를 배출해 결정적으로 관측한다.
    /// - 검증 내용: 무관한 후속 이벤트 처리까지 마친 뒤 hierarchyInvalidation 총 2회, loadItems 총 1회
    /// - 사전 조건: folder 라우트에서 선택된 old.txt의 rename 완료 기록으로 생성된 대기 전이
    /// - 기대 결과: 일치 이벤트는 추가 refresh 의도를 만들지 않고 무관한 이벤트만 정상 예약된다
    func testCorrelatedExternalRenameMergesIntoCommandRefreshWithoutDuplicate() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "\(folderPath)/unrelated.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([oldPath], flags: UInt32(kFSEventStreamEventFlagItemRenamed)),
            deliveryChainToken: nil,
        )))
        // 큐를 배출할 후속 무관한 이벤트. 이것의 출력 수신이 끝났는데도 앞선 일치 이벤트의
        // 출력이 없었다면 병합(중복 억제)이 확정된다.
        await store.send(.content(.externalFileSystemChanged(Self.externalChangeEvents([unrelatedPath]))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(unrelatedPath), Self.canonicalPath(folderPath)]
                && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "일치하는 외부 이벤트는 계층 무효화를 추가하지 않고 무관한 이벤트만 추가한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "일치하는 외부 이벤트는 중복 root reload를 예약하지 않는다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 독립적인 수정 이벤트는 명령 refresh로 병합되지 않는다.
    /// 대기 전이 경로와 겹쳐도 ItemModified는 명령 snapshot 이후 변경일 수 있으므로
    /// 기존 refresh 경로로 통과해 표시가 stale해지지 않게 한다.
    /// - 검증 내용: after-path ItemModified 이벤트가 계층 무효화와 reload를 예약하는지 검증
    /// - 사전 조건: 현재 root에서 old→new rename 전이가 같은 generation으로 대기 중
    /// - 기대 결과: hierarchyInvalidated 1회와 loadItems forwarding이 발생한다
    func testCorrelatedModifiedEventStillSchedulesRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([newPath], flags: UInt32(kFSEventStreamEventFlagItemModified)),
            deliveryChainToken: nil,
        )))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(newPath), Self.canonicalPath(folderPath)]
                && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "독립 수정 이벤트는 계층 무효화를 예약해야 한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "독립 수정 이벤트는 root reload를 예약해야 한다",
        )
        XCTAssertNotNil(store.state.content.pendingIdentityTransition, "수정 이벤트는 전이를 소비하지 않는다")
    }

    /// EVM-001-command_external_refresh_correlation: 사용자가 before 선택을 포기하면 전이를 소비한다.
    /// 소유자 세대가 일치하는 batch에서 before 선택이 없으면 migration 대상이 없으므로
    /// 전이를 남겨두면 같은 경로의 실제 rename echo가 병합돼 목록 갱신이 누락된다.
    /// - 검증 내용: before 미선택 상태의 owning batch가 전이를 소비하고 사용자 선택을 유지하는지 검증
    /// - 사전 조건: 대기 전이와 무관한 행 선택
    /// - 기대 결과: 전이 nil, selectedIds는 사용자 선택 유지
    func testAbandonedBeforeSelectionConsumesPendingTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let otherPath = "\(folderPath)/other.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath(newPath),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
        )
        initialState.content.entryViewLayout.selectedIds = [otherPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded([
            makeCorrelationEntry(id: newPath, name: "new.txt"),
        ]))))
        XCTAssertNil(
            store.state.content.pendingIdentityTransition,
            "사용자가 before 선택을 포기했다면 owning batch에서 전이를 소비한다",
        )
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [otherPath],
            "사용자 선택은 대체 batch에 의해 되돌려지지 않는다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 상관 배치의 추가 경로는 같은 refresh 창에서 계속 전달된다.
    /// 전이와 겹치는 경로와 무관한 경로가 한 배치에 섞이면 무관한 경로만 기존 라우트 동작으로
    /// refresh를 예약하고 겹치는 경로는 명령 refresh에 병합되는지 검증한다.
    /// - 검증 내용: 혼합 배치 처리 후 마지막 무효화가 [other, root]만 포함하고 reload는 1회
    /// - 사전 조건: 대기 전이가 있고 외부 배치가 renamed old.txt와 modified other.txt를 함께 담음
    /// - 기대 결과: 계층 무효화 총 2회, root reload 1회, 무관한 경로의 이벤트는 폐기되지 않음
    func testCorrelatedExternalBatchKeepsUnrelatedPathRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let otherPath = "\(folderPath)/other.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        let mixedEvents = [
            FileChangeGatewayEvent(
                path: oldPath,
                flags: UInt32(kFSEventStreamEventFlagItemRenamed),
                emittedAt: .distantPast,
            ),
            FileChangeGatewayEvent(
                path: otherPath,
                flags: UInt32(kFSEventStreamEventFlagItemModified),
                emittedAt: .distantPast,
            ),
        ]
        await store.send(.content(.externalFileSystemChanged(mixedEvents, deliveryChainToken: nil)))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(otherPath), Self.canonicalPath(folderPath)]
                && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "무관한 경로의 refresh는 유지된다",
        )
        XCTAssertEqual(
            store.state.hierarchyInvalidations.last,
            [Self.canonicalPath(otherPath), Self.canonicalPath(folderPath)],
            "병합된 refresh에는 무관한 경로와 그 parent만 남는다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "무관한 경로의 root reload는 한 번 예약된다",
        )
    }

    // EVM-001-command_external_refresh_correlation: 일치 외부 이벤트는 전이를 소비하지 않고 중복 refresh를 억제한다.
    // 명령 완료가 예약한 reload 이후에 도달한 일치 이벤트는 그 refresh로 병합되어
    // selection migration을 위한 전이가 보존되는지 검증한다.
    // - 검증 내용: 일치 이벤트 뒤 pendingIdentityTransition 유지 + root reload 미예약
    // - 사전 조건: folder 라우트에서 선택된 old.txt의 rename 완료 기록과 그 reload 실행
    // - 기대 결과: 일치 이벤트는 전이를 보존하고 중복 refresh를 예약하지 않는다
    func testCorrelatedExternalEventRetainsPendingTransitionAndSuppressesRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        XCTAssertEqual(store.state.content.pendingIdentityTransition?.recordID, record.id)
        XCTAssertEqual(store.state.content.pendingIdentityTransition?.beforePath, Self.canonicalPath(oldPath))
        XCTAssertEqual(store.state.content.pendingIdentityTransition?.afterPath, Self.canonicalPath(newPath))
        XCTAssertEqual(store.state.content.pendingIdentityTransition?.rootPath, Self.canonicalPath(folderPath))

        let matchingEvents = Self.externalChangeEvents(
            [oldPath],
            flags: UInt32(kFSEventStreamEventFlagItemRenamed),
        )
        await store.send(.content(.externalFileSystemChanged(matchingEvents, deliveryChainToken: nil)))

        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "일치 이벤트는 전이를 소비하지 않고 보존한다",
        )
        XCTAssertEqual(store.state.hierarchyInvalidations.count, 1, "일치 이벤트는 계층 무효화를 추가하지 않는다")
        XCTAssertEqual(store.state.rootReloadCount, 1, "명령 완료가 예약한 reload만 남는다")

        // after-path projection이 도착하면 선택을 옮기고 전이를 소비한다.
        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        await store.send(.bridge(.loading(.itemsLoaded([renamedEntry]))))
        XCTAssertEqual(store.state.content.entryViewLayout.selectedIds, [newPath])
        XCTAssertNil(store.state.content.pendingIdentityTransition, "after-path projection이 전이를 소비한다")
    }

    /// EVM-001-command_external_refresh_correlation: coarse 외부 이벤트는 대기 전이와 겹쳐도 억제하지 않는다.
    /// 유실 복구 플래그가 붙은 event가 command refresh 병합으로 사라지지 않는지 검증한다.
    /// - 검증 내용: MustScanSubDirs/UserDropped/KernelDropped 각각 coarse hierarchy invalidation과 root reload를 생성
    /// - 사전 조건: 현재 root에서 old→new rename 전이가 같은 generation으로 대기 중이다.
    /// - 기대 결과: coarse event는 전이를 보존하면서 coarseHierarchyInvalidated와 loadItems를 실행한다.
    func testCorrelatedCoarseExternalEventsStillReloadCachedHierarchy() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let coarseFlags = [
            kFSEventStreamEventFlagMustScanSubDirs,
            kFSEventStreamEventFlagUserDropped,
            kFSEventStreamEventFlagKernelDropped,
        ].map(UInt32.init)
        let eventPaths = [folderPath, URL(fileURLWithPath: folderPath).deletingLastPathComponent().path]

        for (eventPath, flags) in eventPaths.flatMap({ path in coarseFlags.map { (path, $0) } }) {
            var initialState = makeCorrelationState(folderPath: folderPath)
            initialState.content.pendingIdentityTransition = .init(
                recordID: UUID(),
                beforePath: Self.canonicalPath(oldPath),
                afterPath: Self.canonicalPath("\(folderPath)/new.txt"),
                rootPath: Self.canonicalPath(folderPath),
                refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
            )
            let store = TestStore(initialState: initialState) {
                CommandExternalRefreshHarness()
            }
            store.exhaustivity = .off

            await store.send(.content(.externalFileSystemChanged(
                Self.externalChangeEvents([eventPath], flags: flags),
                deliveryChainToken: nil,
            )))
            await store.receive { action in
                guard case let .content(.entryViewLayout(.hierarchy(.coarseHierarchyInvalidated(removedPrefixes)))) =
                    action
                else { return false }
                return removedPrefixes.isEmpty
            }
            await store.receive { action in
                guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                    return false
                }
                return true
            }

            XCTAssertNotNil(store.state.content.pendingIdentityTransition)
        }
    }

    /// EVM-001-command_external_refresh_correlation: 명령 → 일치 이벤트 → 무관/빈 첫 배치 → after-path 배치가
    /// 하나의 correlated refresh로 수렴하고, after-path가 나타날 때까지 선택을 유지한 뒤
    /// 정확히 한 번 migration하고 전이를 소비한다.
    /// - 검증 내용: 일치 이벤트 후 refresh 미예약, 무관 첫 배치에서 선택·전이 보존, after-path 배치에서 1회 migration
    /// - 사전 조건: folder 라우트에서 선택된 old.txt의 rename 완료 + reload 실행 + 일치 이벤트
    /// - 기대 결과: reload 총 1회, after-path 도착 전 선택 유지, 도착 후 selectedIds == [newPath] + 전이 nil
    func testCommandMatchingEventEarlyBatchThenAfterPathMigratesOnce() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "\(folderPath)/unrelated.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        initialState.content.entryViewLayout.lastSelectedId = oldPath
        initialState.content.entryViewLayout.rangeAnchorId = oldPath
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        // 일치 외부 이벤트: 명령 refresh로 병합되어 중복 refresh를 예약하지 않고 전이를 보존한다.
        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([oldPath], flags: UInt32(kFSEventStreamEventFlagItemRenamed)),
            deliveryChainToken: nil,
        )))
        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations,
            "일치 이벤트는 refresh를 예약하지 않는다",
        )
        XCTAssertEqual(store.state.rootReloadCount, baselineReloads, "명령 완료가 예약한 reload만 남는다")
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        // 무관한 첫 projection batch: after-path가 없으므로 선택과 전이를 유지한다.
        let unrelatedEntry = makeCorrelationEntry(id: unrelatedPath, name: "unrelated.txt")
        await store.send(.bridge(.loading(.itemsLoaded([unrelatedEntry]))))
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [oldPath],
            "after-path가 도착하기 전까지 선택을 유지한다",
        )
        XCTAssertNotNil(store.state.content.pendingIdentityTransition, "무관 첫 배치는 전이를 소비하지 않는다")

        // after-path projection batch: 선택을 정확히 한 번 옮기고 전이를 소비한다.
        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        await store.send(.bridge(.loading(.itemsLoaded([unrelatedEntry, renamedEntry]))))
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [newPath],
            "선택은 after-path로 정확히 한 번 옮긴다",
        )
        XCTAssertNil(store.state.content.pendingIdentityTransition, "전이는 소비된다")
        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations,
            "correlated refresh는 명령 완료의 하나만 존재한다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 무관한 외부 이벤트는 대기 전이를 유지한다.
    /// 전이와 겹치지 않는 경로의 이벤트가 기존 refresh를 예약하면서도 전이를 소비하지 않는지 검증한다.
    /// - 검증 내용: 무관한 경로 이벤트 처리 후에도 pendingIdentityTransition이 남아 있음
    /// - 사전 조건: rename 완료 기록으로 생성된 대기 전이와 무관한 경로의 modified 이벤트
    /// - 기대 결과: 정상 refresh와 함께 전이 보존
    func testUnrelatedExternalEventDoesNotConsumePendingTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "\(folderPath)/unrelated.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))

        await store.send(.content(.externalFileSystemChanged(Self.externalChangeEvents([unrelatedPath]))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(unrelatedPath), Self.canonicalPath(folderPath)]
                && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertNotNil(store.state.content.pendingIdentityTransition, "무관한 이벤트는 전이를 소비하지 않는다")
        XCTAssertEqual(store.state.hierarchyInvalidations.count, 2)
        XCTAssertEqual(store.state.rootReloadCount, 1)
    }

    /// EVM-001-command_external_refresh_correlation: 무관 이벤트가 예약한 reload 뒤의 batch에서도 선택 migration이 산다.
    /// 예약된 root reload가 세대를 하나 올리므로 전이 root 소유자가 재기준화되지 않으면
    /// 후속 batch에서 세대 불일치로 전이가 만료되고 기존 선택이 해제된다.
    /// - 검증 내용: 무관 modified 이벤트 reload 후 after-path batch가 선택을 옮기는지 검증
    /// - 사전 조건: rename 완료 대기 전이와 무관 경로의 modified 이벤트
    /// - 기대 결과: 후속 itemsLoaded에서 selectedIds가 after-path로 이동하고 전이 소비
    func testUnrelatedEventReloadKeepsMigrationAliveThroughNextBatch() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "\(folderPath)/unrelated.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))

        await store.send(.content(.externalFileSystemChanged(Self.externalChangeEvents(
            [unrelatedPath],
            flags: UInt32(kFSEventStreamEventFlagItemModified),
        ))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(unrelatedPath), Self.canonicalPath(folderPath)]
                && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        await store.send(.bridge(.loading(.itemsLoaded([renamedEntry]))))
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [newPath],
            "reload이 올린 새 세대에서도 after-path 선택 migration이 유지된다",
        )
        XCTAssertNil(store.state.content.pendingIdentityTransition)
    }

    /// EVM-001-command_external_refresh_correlation: 실패한 명령도 대기 전이를 만료시키지 않는다.
    /// operationFinished는 record identity가 없어 이 실패가 전이의 원인 명령인지 확정할 수 없다.
    /// 경로·종류를 추측해 만료하면 무관한 실패가 성공한 전이를 파괴하므로, 같은 경로·종류의
    /// 실패라도 전이를 유지한다.
    /// - 검증 내용: rename 실패 수신 뒤에도 pendingIdentityTransition 유지 + reload 미발행
    /// - 사전 조건: rename 완료 기록으로 생성된 대기 전이
    /// - 기대 결과: 실패 시점에 전이가 유지되고 reload가 예약되지 않는다
    func testFailedOperationKeepsPendingTransitionWithoutReload() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: "\(folderPath)/new.txt")],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .failure(.system(message: "forced failure")),
        ))))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "실패는 record identity가 없어 전이를 만료시키지 않는다",
        )
        XCTAssertEqual(store.state.rootReloadCount, 0, "실패한 연산은 reload를 예약하지 않는다")
    }

    /// EVM-001-command_external_refresh_correlation: 취소된 rename은 완료된 대기 전이를 만료하지 않는다.
    /// cancelRename은 이미 성공해 기록된 identity 연산과 무관한 편집 취소이므로
    /// 대기 전이를 파괴하지 않는지 검증한다.
    /// - 검증 내용: cancelRename 수신 뒤에도 pendingIdentityTransition 유지
    /// - 사전 조건: rename 완료 기록으로 생성된 대기 전이
    /// - 기대 결과: 취소 시점에 전이가 유지됨
    func testCanceledRenameKeepsUnrelatedPendingTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: "\(folderPath)/new.txt")],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        await store.send(.bridge(.edit(.cancelRename)))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "cancelRename은 완료된 identity 연산과 무관해 전이를 유지한다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: itemsLoaded 시점에 경로 전이가 선택을 이후 경로로 옮기고 소비한다.
    /// rename/move 최종 데이터 도착 시 선택이 새 identity로 이어지는지 검증한다.
    /// - 검증 내용: 이전 경로가 선택된 상태에서 이후 경로가 포함된 itemsLoaded가 선택을 교체하고 전이를 소비한다.
    /// - 사전 조건: before→after 대기 전이와 before가 선택된 상태.
    /// - 기대 결과: selectedIds는 after만 포함하고 pendingIdentityTransition은 nil이다.
    func testItemsLoadedMigratesSelectionAlongIdentityTransitionAndConsumesIt() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        initialState.content.entryViewLayout.lastSelectedId = oldPath
        initialState.content.entryViewLayout.rangeAnchorId = oldPath
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: newPath,
            rootPath: folderPath,
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        let otherEntry = makeCorrelationEntry(id: "\(folderPath)/other.txt", name: "other.txt")
        await store.send(.bridge(.loading(.itemsLoaded([renamedEntry, otherEntry]))))

        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [newPath],
            "선택은 이후 경로로 이동한다",
        )
        XCTAssertEqual(store.state.content.entryViewLayout.lastSelectedId, newPath)
        XCTAssertNil(store.state.content.pendingIdentityTransition, "전이는 소비된다")
    }

    /// EVM-001-command_external_refresh_correlation: 이후 경로가 아직 도착하지 않으면 선택을 유지하고 전이를 보존한다.
    /// 실패·미도착 시 기존 stale-selection 정리가 이기는지 검증한다.
    /// - 검증 내용: after-path가 없는 itemsLoaded는 선택과 전이를 그대로 둔다.
    /// - 사전 조건: 대기 전이와 before 선택.
    /// - 기대 결과: selectedIds는 before 유지, 전이 미소비.
    func testItemsLoadedWithoutAfterPathKeepsSelectionAndTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let transition = FileManagerContentState.EntryIdentityTransition(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: newPath,
            rootPath: folderPath,
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
        )
        initialState.content.pendingIdentityTransition = transition
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let otherEntry = makeCorrelationEntry(id: "\(folderPath)/other.txt", name: "other.txt")
        await store.send(.bridge(.loading(.itemsLoaded([otherEntry]))))

        XCTAssertEqual(store.state.content.entryViewLayout.selectedIds, [oldPath])
        XCTAssertEqual(store.state.content.pendingIdentityTransition, transition)
    }

    /// EVM-001-command_external_refresh_correlation: 새 성공 기록은 대기 전이를 대체(supersede)한다.
    /// 두 번째 rename 완료 기록이 첫 번째 전이를 교체하는지 검증한다.
    /// - 검증 내용: 두 기록 전송 뒤 pendingIdentityTransition.recordID == 두 번째 기록 id
    /// - 사전 조건: 서로 다른 원본을 순차 rename한 두 완료 기록
    /// - 기대 결과: 슬롯은 하나이며 최신 기록으로 대체됨
    func testSupersedingRecordReplacesPendingTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let firstOldPath = "\(folderPath)/first-old.txt"
        let secondOldPath = "\(folderPath)/second-old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [firstOldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let firstRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: firstOldPath, afterPath: "\(folderPath)/first-new.txt")],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(firstRecord))))
        XCTAssertEqual(store.state.content.pendingIdentityTransition?.recordID, firstRecord.id)

        await store.send(.select(secondOldPath)) {
            $0.content.entryViewLayout.selectedIds = [secondOldPath]
        }
        let secondRecord = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: secondOldPath, afterPath: "\(folderPath)/moved/second-old.txt")],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(secondRecord))))
        XCTAssertEqual(
            store.state.content.pendingIdentityTransition?.recordID,
            secondRecord.id,
            "새 성공 기록이 이전 전이를 대체한다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 세대가 어긋난 전이는 만료되고 정상 refresh로 처리한다.
    /// 로딩 세대 불일치 시 겹치는 이벤트라도 중복 억제하지 않는지 검증한다.
    /// - 검증 내용: stale 세대 전이 상태에서 일치 모양 이벤트가 무효화+reload를 예약하고 전이를 만료
    /// - 사전 조건: refreshGeneration이 현재 로딩 세대보다 오래된 대기 전이
    /// - 기대 결과: 기존 라우트 동작 그대로 처리, 전이 소비
    func testGenerationSupersededTransitionExpiresWithNormalRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.entryOperations.loadingContext.generation = 7
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath("\(folderPath)/new.txt"),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: 5,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([oldPath], flags: UInt32(kFSEventStreamEventFlagItemRenamed)),
            deliveryChainToken: nil,
        )))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(oldPath), Self.canonicalPath(folderPath)]
                && removedPrefixes == [Self.canonicalPath(oldPath)]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertNil(store.state.content.pendingIdentityTransition, "세대 불일치 전이는 만료된다")
        XCTAssertEqual(store.state.hierarchyInvalidations.count, 1, "stale 전이는 중복 억제하지 않는다")
        XCTAssertEqual(store.state.rootReloadCount, 1)
    }

    /// EVM-001-command_external_refresh_correlation: 현재 root/포함 디렉터리 경로의 FSEvent도
    /// 전이와 상관되어 명령 refresh로 병합된다. FSEvents가 변경 파일 대신 폴더 경로를 보고해도
    /// 중복 refresh를 예약하지 않고, 같은 배치의 무관한 경로는 폐기하지 않는지 검증한다.
    /// - 검증 내용: root 경로+무관 경로 혼합 배치가 무관 경로만 남겨 계층 무효화·reload를 1회씩 예약
    /// - 사전 조건: folder 라우트에서 선택된 old.txt의 rename 완료 전이와 그 reload 실행
    /// - 기대 결과: root 이벤트는 병합되고 무관 경로의 refresh만 예약되며 전이는 유지된다
    func testCorrelatedParentRootEventMergesWithoutHidingUnrelatedPaths() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "\(folderPath)/unrelated.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        // 혼합 배치: 현재 root 경로 이벤트(renamed) + 무관한 sibling 이벤트(modified).
        let mixedEvents = [
            FileChangeGatewayEvent(
                path: folderPath,
                flags: UInt32(kFSEventStreamEventFlagItemRenamed),
                emittedAt: .distantPast,
            ),
            FileChangeGatewayEvent(
                path: unrelatedPath,
                flags: UInt32(kFSEventStreamEventFlagItemModified),
                emittedAt: .distantPast,
            ),
        ]
        await store.send(.content(.externalFileSystemChanged(mixedEvents, deliveryChainToken: nil)))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(unrelatedPath), Self.canonicalPath(folderPath)]
                && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "root 경로 이벤트는 병합되고 무관 경로만 계층 무효화를 예약한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "root 경로 이벤트는 중복 reload를 예약하지 않는다",
        )
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "root 경로 이벤트 병합 시 전이는 보존된다",
        )
        // 참고: 무관 경로 remainder가 예약한 reload는 세대를 연다. 그 세대 불일치로 전이가
        // 만료되는 것은 의도된 V20-P1-2 동작이며 testGenerationMismatchExpiresTransitionAtMigration에서
        // 별도로 검증한다.
    }

    /// EVM-001-command_external_refresh_correlation: 무관한 명령 실패·취소는 대기 전이를 파괴하지 않는다.
    /// 성공한 rename 전이가 있을 때 다른 경로·종류의 operationFinished 실패와 cancelRename이
    /// 전이를 유지하는지 검증한다.
    /// - 검증 내용: 무관 실패·취소 뒤에도 pendingIdentityTransition 유지
    /// - 사전 조건: 선택된 old.txt의 rename 완료 기록으로 생성된 대기 전이
    /// - 기대 결과: 전이는 유지되어 이후 동일 세대 projection에서 동작할 수 있다
    func testUnrelatedFailureAndCancelKeepPendingIdentityTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let otherPath = "\(folderPath)/other.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        // 무관한 경로·종류의 압축 실패: 전이와 무관하므로 만료하지 않고 reload도 예약하지 않는다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            otherPath,
            .compress,
            .failure(.system(message: "forced failure")),
        ))))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "무관한 종류·경로의 실패는 전이를 만료하지 않는다",
        )
        XCTAssertEqual(store.state.rootReloadCount, 0, "무관한 실패는 reload를 예약하지 않는다")

        // 같은 rename 종류라도 다른 경로의 실패는 전이와 무관하다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            otherPath,
            .rename,
            .failure(.system(message: "forced failure")),
        ))))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "다른 경로의 rename 실패는 전이를 만료하지 않는다",
        )
        XCTAssertEqual(store.state.rootReloadCount, 0, "무관한 rename 실패는 reload를 예약하지 않는다")

        // rename 편집 취소도 완료된 identity 연산과 무관하므로 전이를 유지한다.
        await store.send(.bridge(.edit(.cancelRename)))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "cancelRename은 완료된 전이를 만료하지 않는다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 세대가 어긋난 전이는 migration 시점에 만료된다.
    /// 같은 root라도 로딩 세대가 전이 생성 세대와 다르면 선택을 옮기지 않고 만료하는지 검증한다.
    /// - 검증 내용: after-path가 포함된 itemsLoaded에도 selectedIds 유지 + pendingIdentityTransition == nil
    /// - 사전 조건: refreshGeneration 3, 현재 loadingContext.generation 7인 대기 전이와 before 선택
    /// - 기대 결과: migration 미발생(선택 유지), 세대 불일치 전이 만료
    func testGenerationMismatchExpiresTransitionAtMigration() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        initialState.content.entryViewLayout.entryOperations.loadingContext.generation = 7
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath(newPath),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: 3,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        await store.send(.bridge(.loading(.itemsLoaded([renamedEntry]))))

        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [oldPath],
            "세대가 어긋난 전이는 선택을 옮기지 않는다",
        )
        XCTAssertNil(store.state.content.pendingIdentityTransition, "세대 불일치 전이는 만료된다")
    }

    /// EVM-001-command_external_refresh_correlation: expanded child 전이는 root 완료보다 owning folder 응답을 기다린다.
    /// root coreFinished가 먼저 투영되어도 child rename 선택과 전이가 조기 소비되지 않는지 검증한다.
    /// - 검증 내용: root 완료 projection 뒤 before 선택·전이 유지, matching folder batch 뒤 after로 1회 migration
    /// - 사전 조건: generation 1의 expanded folder child가 선택되고 root generation 7에서 rename 완료 전이가 기록된다.
    /// - 기대 결과: root 완료는 child 전이를 generation 3으로 넘기고 해당 folder 응답만 선택을 옮기고 소비한다.
    func testExpandedChildTransitionWaitsForOwningFolderResponseAfterRootCompletion() async {
        let fixture = makeExpandedChildTransitionFixture()
        let store = TestStore(initialState: fixture.state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 7,
            event: .coreFinished(batchCount: 1),
        ))))))
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }
        await store.receive(\.entryViewLayout.hierarchy.rootSnapshotCompleted)

        XCTAssertEqual(
            store.state.pendingIdentityTransition?.projectionOwner,
            .folder(id: fixture.folder.id, generation: 3),
        )
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.before.id])

        await store.receive { action in
            guard case let .entryViewLayout(.delegate(.expandRequested(id))) = action else { return false }
            return id == fixture.folder.id
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadFolderItems(request)))) = action
            else { return false }
            return request.id.folderID == fixture.folder.id && request.folderGeneration == 3
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.folderStreamFinished(request)))) = action
            else { return false }
            return request.id.folderID == fixture.folder.id && request.folderGeneration == 3
        }
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [fixture.after], batchIndex: 0)),
        ))))

        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNil(store.state.pendingIdentityTransition, "owning folder 응답이 전이를 한 번 소비한다")
    }

    /// EVM-001-command_external_refresh_correlation: owning folder 중간 batch가 before 선택을 보존한다.
    /// - 검증 내용: after-path 없는 batch 0 뒤 선택·전이 유지, batch 1에서 after로 단 한 번 migration
    /// - 사전 조건: expanded folder generation 2가 rename 전이를 소유하고 두 core batch를 순차 수신한다.
    /// - 기대 결과: stale generation은 무시되고 terminal 뒤에도 after 선택과 소비된 전이가 유지된다.
    func testExpandedChildTransitionSurvivesIntermediateOwningFolderBatch() async {
        let fixture = makeExpandedChildTransitionFixture()
        let unrelated = makeCorrelationEntry(id: "\(fixture.folder.id)/unrelated.txt", name: "unrelated.txt")
        let store = TestStore(initialState: fixture.state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 1,
            .event(.coreBatch(items: [fixture.after], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.before.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 2,
            .event(.coreBatch(items: [unrelated], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.before.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition, "중간 owning batch는 전이를 소비하지 않는다")

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 2,
            .event(.coreBatch(items: [fixture.after], batchIndex: 1)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 2,
            .event(.coreFinished(batchCount: 2)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNil(store.state.pendingIdentityTransition, "folder terminal은 소비된 전이를 되살리지 않는다")
    }

    /// EVM-001-command_external_refresh_correlation: 교차 폴더 move는 소스 폴더 배치에서 before 선택을 보존한다.
    /// - 검증 내용: 소스 폴더 replacement batch가 before 선택을 지우기 전 보존, 목적지 batch에서 1회 migration,
    ///   이후 terminal·stale sibling 이벤트가 전이를 되살리지 않음
    /// - 사전 조건: 두 expanded folder가 rename 전이를 source(보존)·destination(migration) 소유로 나눠 갖는다.
    /// - 기대 결과: 소스 배치 뒤에도 선택·전이 유지, 목적지 배치 뒤 after 선택과 소비 확정
    func testCrossFolderMoveSurvivesSourceFolderBatchBeforeDestinationMigration() async {
        let fixture = makeCrossFolderMoveFixture()
        let kept = makeCorrelationEntry(id: "\(fixture.source.id)/kept.txt", name: "kept.txt")
        let store = TestStore(initialState: fixture.state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            // root 완료 재시작의 자동 폴더 재로드가 실제 파일시스템(픽스처 경로 미존재)을
            // 읽지 않게 한다. 실패 스트림은 dst terminal(.failed) 브리지로 이어져 소유자
            // 세대 종료로 전이를 조기 만료시킨다. 배치는 본문의 수동 주입으로만 공급한다.
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in AsyncThrowingStream { $0.finish() } }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off
        let rootContextGeneration = fixture.state.entryViewLayout.hierarchy.rootContextGeneration

        await store.send(.entryViewLayout(.hierarchy(.rootSnapshotCompleted(
            rootContextGeneration: rootContextGeneration,
            rootFolders: [fixture.source, fixture.destination],
        ))))
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.projectionOwner,
            .folder(id: fixture.destination.id, generation: 3),
        )
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.preservationOwner,
            .folder(id: fixture.source.id, generation: 3),
        )
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.before.id])

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: fixture.source.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [kept], batchIndex: 0)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            [fixture.before.id],
            "소스 폴더 replacement batch는 before 선택을 보존해야 한다",
        )
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.projectionOwner,
            .folder(id: fixture.destination.id, generation: 3),
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: fixture.destination.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [fixture.after], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: fixture.destination.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: fixture.source.id,
            folderGeneration: 5,
            .event(.coreBatch(items: [fixture.after], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNil(store.state.pendingIdentityTransition, "stale sibling은 전이를 되살리거나 다시 소비하지 않는다")
    }

    /// EVM-001-reload_directory_page_on_external_change: symlink 이동의 projection owner는 lexical 부모로 판정한다.
    /// 완료 시점 afterPath는 존재하는 symlink라 canonical 해석 시 root 밖으로 빠질 수 있으므로
    /// destination folder가 expanded 상태면 해당 폴더 소유자가 유지되어야 한다.
    /// - 검증 내용: replace 대상이 symlink인 pasteFileMove 기록의 owner가 dst folder로 계산되는지 검증
    /// - 사전 조건: src/dst 확장 폴더와 dst/moved.txt symlink(outside 지시) 실제 생성
    /// - 기대 결과: projectionOwner = .folder(dst), preservationOwner = .folder(src)
    func testSymlinkMoveKeepsFolderProjectionOwnerFromLexicalParent() throws {
        let base = NSTemporaryDirectory().appending("voyager-symlink-owner-\(UUID().uuidString)")
        let rootPath = base + "root"
        let srcPath = rootPath + "/src"
        let dstPath = rootPath + "/dst"
        let outsidePath = base + "outside/target"
        let fm = FileManager.default
        try fm.createDirectory(atPath: srcPath, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dstPath, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: outsidePath, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: dstPath + "/moved.txt", withDestinationPath: outsidePath)
        defer { try? fm.removeItem(atPath: base) }

        let source = EntryModel.temporaryFolder(id: srcPath, name: "src")
        let destination = EntryModel.temporaryFolder(id: dstPath, name: "dst")
        let before = makeCorrelationEntry(id: "\(srcPath)/moved.txt", name: "moved.txt")
        let after = makeCorrelationEntry(id: "\(dstPath)/moved.txt", name: "moved.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.navigation.navigationState = .folder(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [source, destination]
        state.entryViewLayout.entryOperations.items = [source, destination]
        state.entryViewLayout.entryOperations.loadingContext.items = [source, destination]
        state.entryViewLayout.entryOperations.loadingContext.generation = 7
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            children: [before],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id

        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: before.id, afterPath: after.id)],
        )
        _ = FileManagerContentEntryOpsCoordinator.recordIdentityTransitionIfEligible(record, state: &state)

        XCTAssertEqual(
            state.pendingIdentityTransition?.projectionOwner,
            .folder(id: destination.id, generation: 2),
            "symlink after-path가 canonical 해석으로 벗어나도 lexical 부모의 folder 소유자를 유지한다",
        )
        XCTAssertEqual(
            state.pendingIdentityTransition?.preservationOwner,
            .folder(id: source.id, generation: 2),
        )
    }

    /// EVM-001-command_external_refresh_correlation: 포함 디렉터리(현재 root의 조상) 경로의
    /// FSEvent도 대기 전이가 겹치면 관련으로 판정되어 명령 refresh로 병합된다.
    /// FSEvents가 변경 파일 대신 root의 조상 디렉터리를 보고해도 상관관계 사전 gate가
    /// 이벤트를 버리지 않고, 같은 배치의 무관한 경로는 폐기하지 않는지 검증한다.
    /// - 검증 내용: root 조상 이벤트+무관 경로 혼합 배치가 무관 경로만 계층 무효화·reload를 예약
    /// - 사전 조건: folder 라우트에서 선택된 old.txt의 rename 완료 대기 전이
    /// - 기대 결과: 조상 이벤트는 병합되고 무관 경로의 refresh만 예약되며 전이는 유지된다
    func testCorrelatedContainingParentEventMergesWithoutHidingUnrelatedPaths() async {
        let folderPath = "/tmp/voyager-correlation"
        let parentPath = "/tmp"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "/tmp/voyager-other/unrelated.txt"
        let canonicalUnrelated = Self.canonicalPath(unrelatedPath)
        let unrelatedParent = URL(fileURLWithPath: canonicalUnrelated).deletingLastPathComponent().path
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        // 혼합 배치: root의 조상(포함 디렉터리) renamed 이벤트 + 무관한 sibling modified 이벤트.
        let mixedEvents = [
            FileChangeGatewayEvent(
                path: parentPath,
                flags: UInt32(kFSEventStreamEventFlagItemRenamed),
                emittedAt: .distantPast,
            ),
            FileChangeGatewayEvent(
                path: unrelatedPath,
                flags: UInt32(kFSEventStreamEventFlagItemModified),
                emittedAt: .distantPast,
            ),
        ]
        await store.send(.content(.externalFileSystemChanged(mixedEvents, deliveryChainToken: nil)))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [canonicalUnrelated, unrelatedParent] && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "조상 이벤트는 병합되고 무관한 경로만 계층 무효화를 예약한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "무관한 경로의 root reload는 한 번 예약된다",
        )
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "조상 이벤트 병합 시 전이는 보존된다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 성공한 rename 뒤 무관한 실패·취소가 와도
    /// 전이가 보존되고, 이후 같은 세대의 after-path projection에서 선택 migration이 완료된다.
    /// 무관 실패·취소가 직접(만료) 또는 간접(reload 세대 상승)으로 전이를 파괴하지 않는지 검증한다.
    /// - 검증 내용: 무관 실패·취소 뒤 전이 보존 + reload 미예약, after-path projection에서 1회 migration
    /// - 사전 조건: 선택된 old.txt의 rename 완료 전이와 동일 세대
    /// - 기대 결과: after-path 배치 도착 시 selectedIds == [newPath] + 전이 소비
    func testUnrelatedFailureAndCancelThenAfterPathMigratesOnce() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let otherPath = "\(folderPath)/other.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        initialState.content.entryViewLayout.lastSelectedId = oldPath
        initialState.content.entryViewLayout.rangeAnchorId = oldPath
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        // 무관한 경로·종류의 실패와 취소.
        await store.send(.bridge(.lifecycle(.operationFinished(
            otherPath,
            .rename,
            .failure(.system(message: "forced failure")),
        ))))
        await store.send(.bridge(.edit(.cancelRename)))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "무관 실패·취소는 전이를 만료하지 않는다",
        )
        XCTAssertEqual(store.state.rootReloadCount, 0, "무관 실패·취소는 reload를 예약하지 않는다")

        // after-path projection: 같은 세대에서 선택을 옮기고 전이를 소비한다.
        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        await store.send(.bridge(.loading(.itemsLoaded([renamedEntry]))))
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [newPath],
            "무관 실패·취소 후에도 선택은 after-path로 이동한다",
        )
        XCTAssertNil(store.state.content.pendingIdentityTransition, "전이는 소비된다")
    }
}

/// 명령 완료(coordinator)와 외부 변경(sync reducer)을 한 Store에서 이어 붙이고
/// 예약된 visible refresh 의도를 세는 harness. 상단 파일 레벨 선언으로 nesting lint를 피한다.
@Reducer
private struct CommandExternalRefreshHarness {
    struct State: Equatable {
        var content = FileManagerContentState()
        /// hierarchyInvalidated에 전달된 affectedPaths 기록 (명령/외부 refresh 의도 수집)
        var hierarchyInvalidations: [[String]] = []
        /// 외부 경로 root reload(loadItems) 예약 횟수
        var rootReloadCount = 0
    }

    enum Action {
        case bridge(EntryOperationsAction)
        case content(FileManagerContentAction)
        case select(String)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .bridge(entryAction):
                return FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
                    entryAction,
                    state: &state.content,
                )
                .map(Action.content)
            case let .select(path):
                state.content.entryViewLayout.selectedIds = [path]
                return .none
            case .content:
                return .none
            }
        }
        Scope(state: \.content, action: \.content) {
            FileManagerContentSyncReducer()
        }
        Reduce { state, action in
            switch action {
            case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, _)))):
                state.hierarchyInvalidations.append(affectedPaths)
                return .none
            case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))):
                state.rootReloadCount += 1
                // 명령 완료가 예약한 reload가 실행되면 실제 LoadingReducer가 세대를 +1 올린다.
                // 일치 이벤트가 그 이후에 도달해도 같은 세대로 판정되도록 여기서 세대를 맞춘다.
                state.content.entryViewLayout.entryOperations.loadingContext.generation &+= 1
                return .none
            default:
                return .none
            }
        }
    }
}

private extension EVM001FileManagerNavigationTests {
    func assertPathsMutatedInvalidatesParentsWithoutRemovedPrefixes() async {
        let folderPath = "/tmp/voyager"
        let sourcePath = "\(folderPath)/source-folder/child.txt"
        let destinationPath = "/tmp/voyager-destination/copied-folder/child.txt"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }

        await store.send(.bridge(.lifecycle(.pathsMutated([sourcePath, destinationPath]))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == ["\(folderPath)/source-folder", "/tmp/voyager-destination/copied-folder"]
                && removedPrefixes.isEmpty
        }
        await store.finish()
    }
}

extension EVM001FileManagerNavigationTests {
    /// EVM-001-reload_directory_page_on_external_change: dot-segment watch root의 canonical event 보존
    /// 표준화되지 않은 route root도 Shared canonical seam을 통해 FSEvent path와 같은 scope로 비교되는지 검증한다.
    /// - 검증 내용: `/var/tmp/../tmp` interest에 대한 `/private/var/tmp` child event relevance
    /// - 사전 조건: symlink와 parent dot-segment가 함께 포함된 visible-folder interest
    /// - 기대 결과: 원본 FileChangeGatewayEvent가 필터에서 제거되지 않음
    func testGatewayRelevanceStandardizesDotSegmentWatchRoot() {
        let interest = FileChangeWatchInterest(
            id: "visible-folder",
            owner: .fileManager,
            purpose: .visibleFolderReload,
            roots: ["/var/tmp/../tmp"],
            includeSubfolders: true,
        )
        let event = FileChangeGatewayEvent(
            path: "/private/var/tmp/voyager-changed.txt",
            flags: UInt32(kFSEventStreamEventFlagItemModified),
        )

        XCTAssertEqual(
            gatewayRelevantChangedEvents([event], interest: interest, openedURL: nil),
            [event],
        )
    }
}

private enum FixturePathError: Error, CustomStringConvertible {
    case repoRootNotFound(searchFrom: String)

    var description: String {
        switch self {
        case let .repoRootNotFound(searchFrom):
            "repo root not found while searching from \(searchFrom)"
        }
    }
}
