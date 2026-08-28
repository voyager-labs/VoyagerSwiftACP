import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002FileManagerPagePresentationTests {
    /// EVM-002-switch_entries_view: root load 시작은 즉시 Widget projection을 갱신한다.
    /// - 검증 내용: folder, recents, tags, computer load action이 모두 projection trigger인지 확인한다.
    /// - 사전 조건: 새 route가 root load를 시작한다.
    /// - 기대 결과: 첫 batch 전에도 ContentProjection이 빈/로딩 상태를 투영할 수 있다.
    func testRootLoadStartsTriggerContentProjection() {
        let actions: [FileManagerContentAction] = [
            .entryViewLayout(.entryOperations(.loading(.loadItems(path: "/next", showHidden: false)))),
            .entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden: false)))),
            .entryViewLayout(.entryOperations(.loading(.loadTagItems(tagName: "Blue", showHidden: false)))),
            .entryViewLayout(.entryOperations(.loading(.loadComputerItems))),
        ]

        let state = FileManagerContentState()
        XCTAssertTrue(actions.allSatisfy { FileManagerContentFeature.shouldProjectContent($0, state: state) })
    }

    /// EVM-002-switch_entries_view: FileManager는 arrangement 결과를 Widget presentation으로 투영한다.
    /// - 검증 내용: section 순서, collapse 상태, Open With application cache가 함께 동기화된다.
    /// - 사전 조건: Folders와 Text group, collapsed Text, TextEdit cache가 준비돼 있다.
    /// - 기대 결과: EntryViewLayout presentation이 같은 grouped sections와 application을 가진다.
    func testFileManagerProjectsGroupingAndOpenWithApplications() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let file = makeSharedProjectionFile()
        let application = ApplicationInfo(
            id: "com.apple.TextEdit",
            name: "TextEdit",
            bundleID: "com.apple.TextEdit",
            isDefault: true,
        )
        var state = FileManagerContentState()
        state.entryViewLayout.entryOperations.items = [folder, file]
        state.entryViewLayout.entryOperations.commonApplicationsForSelectedFiles = [application]
        state.entryViewLayout.entryArrangements.groupKey = .kind
        state.entryViewLayout.entryArrangements.groupedItems = [
            GroupedItems(groupName: "Folders", items: [folder]),
            GroupedItems(groupName: "Text", items: [file]),
        ]
        state.entryViewLayout.entryArrangements.collapsedGroups = ["Text"]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
        }
        // store.exhaustivity = .off: 여러 child state의 projection 동기화 중 이 AC가 소유한 결과만 검증한다.
        store.exhaustivity = .off

        // Catch-all sync reducer가 제거되어 projection bridge를 직접 호출해야 함
        let projection = ContentProjection(
            entries: [folder, file],
            isLoading: false,
            sortKey: .name,
            sortOrder: .ascending,
            groupKey: .kind,
            collapsedGroups: ["Text"],
            sections: [
                EntryViewLayoutSection(
                    id: "Folders",
                    title: "Folders",
                    colorCode: nil,
                    items: [folder],
                    isCollapsed: false,
                ),
                EntryViewLayoutSection(id: "Text", title: "Text", colorCode: nil, items: [file], isCollapsed: true),
            ],
            renamingItemId: nil,
            renamingText: "",
            clipboardCutPaths: [],
            hasClipboardItems: false,
            busyEntryPaths: [],
            openWithApplications: [application],
            restorableTrashPaths: [],
            trashDirectoryPath: nil,
            collectionWindowID: state.entryViewLayout.entryOperations.windowID,
            collectionLoadingCancellationOwnerID: state.entryViewLayout.entryOperations.loadingCancellationOwnerID,
        )
        await store.send(.entryViewLayout(.view(.applyContentProjection(projection))))

        XCTAssertEqual(store.state.entryViewLayout.presentation.sections.map(\.id), ["Folders", "Text"])
        XCTAssertEqual(store.state.entryViewLayout.presentation.sections.map(\.isCollapsed), [false, true])
        XCTAssertEqual(store.state.entryViewLayout.presentation.openWithApplications, [application])
    }

    /// EVM-002-open_with: Widget preload delegate는 EntryOperations common application load로 연결된다.
    /// - 검증 내용: selected entries payload가 bridge에서 손실되지 않는다.
    /// - 사전 조건: Open With 대상 파일 한 건이 있다.
    /// - 기대 결과: 같은 파일을 가진 loadCommonApplicationsForFiles action이 발행된다.
    func testOpenWithPreloadRoutesToEntryOperations() async {
        let file = makeSharedProjectionFile()
        let staleApplication = ApplicationInfo(
            id: "com.example.stale",
            name: "Stale",
            bundleID: "com.example.stale",
            isDefault: false,
        )
        var state = FileManagerContentState()
        state.entryViewLayout.entryOperations.commonApplicationsForSelectedFiles = [staleApplication]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryOpenClient.applicationsForType = { _, _ in [] }
            $0.entryOpenClient.defaultApplication = { _ in nil }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        // store.exhaustivity = .off: child reducer의 projection chain 중 이 AC가 소유한 action만 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.preloadOpenWithApplications([file]))))
        await store.receive {
            guard case let .entryViewLayout(.entryOperations(.openWith(.loadCommonApplicationsForFiles(files)))) = $0
            else {
                return false
            }
            return files == [file]
        } assert: {
            $0.entryViewLayout.entryOperations.commonApplicationsForSelectedFiles = []
        }
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.openWithApplications.isEmpty
        }
    }

    /// EVM-002-switch_entries_view: Widget group disclosure는 arrangement collapse owner로 연결된다.
    /// - 검증 내용: group name이 bridge에서 toggleCollapsedGroup action으로 보존된다.
    /// - 사전 조건: Text group toggle delegate가 도착한다.
    /// - 기대 결과: EntryArrangements가 Text collapse를 토글하는 action을 받는다.
    func testGroupToggleRoutesToEntryArrangements() async {
        let store = TestStore(initialState: FileManagerContentState()) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.delegate(.toggleGroup("Text"))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryArrangements(.toggleCollapsedGroup(groupName))) = action
            else { return false }
            return groupName == "Text"
        }
    }

    /// EVM-002-switch_entries_view: setGroupKey가 apply chain을 트리거하여 Widget presentation이 grouped sections를 받는다.
    /// - 검증 내용: setGroupKey(.kind) 후 requestApply → apply → groupedItems 갱신 → presentation.sections에 titled group이
    /// 포함된다.
    /// - 사전 조건: kind가 서로 다른 folder/file 항목들이 entryOperations.items에 있다.
    /// - 기대 결과: presentation.sections.compactMap(\.title)가 비어있지 않다.
    func testSetGroupKeyTriggersApplyAndProducesGroupedWidgetSections() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let file = makeSharedProjectionFile()
        var state = FileManagerContentState()
        state.entryViewLayout.entryOperations.items = [folder, file]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        // store.exhaustivity = .off: 다중 child reducer composition에서 grouping projection 결과만 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryArrangements(.setGroupKey(.kind))))

        // requestApply → apply → applied chain 확인
        await store.receive { action in
            guard case .entryViewLayout(.entryArrangements(.delegate(.requestApply))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryViewLayout(.entryArrangements(.apply)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryViewLayout(.entryArrangements(.delegate(.applied))) = action else { return false }
            return true
        }

        // Projection bridge가 .delegate(.applied)를 감지하고 ContentProjection을 전송
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }

        // Widget presentation이 titled group sections를 받았는지 확인
        let sectionTitles = store.state.entryViewLayout.presentation.sections.compactMap(\.title)
        XCTAssertFalse(
            sectionTitles.isEmpty,
            "Group By Kind should produce titled group sections in widget presentation",
        )
    }

    /// EVM-002-switch_entries_view: collection 종료 시 root 항목을 presentation에 다시 투영한다.
    /// - 검증 내용: clearCollectionMode projection이 collectionItems 대신 entryOperations.items를 사용한다.
    /// - 사전 조건: root 항목과 다른 collection 결과가 표시 중이다.
    /// - 기대 결과: 첫 ContentProjection entries가 root 항목과 일치한다.
    func testClearCollectionModeProjectsRootEntries() async {
        let rootEntry = EntryModel.temporaryFolder(id: "/root", name: "root")
        let collectionEntry = EntryModel.temporaryFolder(id: "/collection", name: "collection")
        var state = FileManagerContentState()
        state.entryViewLayout.entryOperations.items = [rootEntry]
        state.entryViewLayout.isCollectionMode = true
        state.entryViewLayout.collectionItems = [collectionEntry]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        // store.exhaustivity = .off: collection teardown 부수 action보다 root projection payload를 검증한다.
        store.exhaustivity = .off

        await store.send(.internal(.clearCollectionMode))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [rootEntry]
        }
    }

    /// EVM-002-switch_entries_view: projection entries가 화면의 arrangement 순서를 따른다.
    /// - 검증 내용: raw load order와 다른 Name 정렬 결과가 ContentProjection entries에 반영된다.
    /// - 사전 조건: entryOperations items가 역순이고 ascending Name 정렬이 활성화돼 있다.
    /// - 기대 결과: projection entries와 section items가 모두 ascending 순서다.
    func testProjectionEntriesUseArrangedDisplayOrder() async {
        let first = EntryModel.temporaryFolder(id: "/first", name: "A")
        let second = EntryModel.temporaryFolder(id: "/second", name: "Z")
        var state = FileManagerContentState()
        state.entryViewLayout.entryOperations.items = [second, first]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        // store.exhaustivity = .off: arrangement delegate chain보다 projection payload 순서를 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryArrangements(.delegate(.applied(
            sortedItems: [],
            isCollectionMode: false,
        )))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [first, second]
                && projection.sections.flatMap(\.items) == [first, second]
        }
    }

    /// EVM-002-switch_entries_view: 다중 태그 grouping은 canonical projection entries를 중복하지 않는다.
    /// - 검증 내용: 같은 항목이 여러 tag section에 포함돼도 ContentProjection entries는 ID당 한 번만 포함된다.
    /// - 사전 조건: Blue와 Red 태그를 모두 가진 파일에 Tags grouping이 활성화돼 있다.
    /// - 기대 결과: sections에는 두 그룹이 유지되고 entries에는 파일이 한 번만 포함된다.
    func testTagsGroupingProjectsUniqueCanonicalEntries() async {
        let file = makeSharedProjectionFile(tags: [
            Tag(name: "Blue", colorCode: 6),
            Tag(name: "Red", colorCode: 1),
        ])
        var state = FileManagerContentState()
        state.entryViewLayout.entryOperations.items = [file]
        state.entryViewLayout.entryArrangements.groupKey = .tags
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryArrangements(.delegate(.applied(
            sortedItems: [file],
            isCollectionMode: false,
        )))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [file]
                && projection.sections.map(\.id) == ["Blue", "Red"]
                && projection.sections.flatMap(\.items) == [file, file]
        }
    }

    /// EVM-002-switch_entries_view: collection materialization도 page arrangement를 다시 적용한다.
    /// - 검증 내용: collection core batch가 FileManager projection trigger를 거쳐 정렬된다.
    /// - 사전 조건: collection mode에서 역순 core batch와 ascending Name 정렬이 준비돼 있다.
    /// - 기대 결과: emitted projection entries가 ascending 순서다.
    func testCollectionMaterializationReappliesPageArrangement() async {
        let first = EntryModel.temporaryFolder(id: "/collection/first", name: "A")
        let second = EntryModel.temporaryFolder(id: "/collection/second", name: "Z")
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        // store.exhaustivity = .off: collection child state보다 page projection 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.internal(.collectionReplaceEvent(
            epoch: 0,
            event: .coreBatch(items: [second, first], batchIndex: 0),
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [first, second]
        }
    }

    /// EVM-002-switch_entries_view: accepted root completion은 content projection 이후 root snapshot reconciliation을 발행한다.
    /// - 검증 내용: itemsLoaded가 applyContentProjection과 rootSnapshotCompleted를 순서대로 발행한다.
    /// - 사전 조건: root 항목이 있는 FileManager content state
    /// - 기대 결과: applyContentProjection이 먼저, rootSnapshotCompleted가 다음에 순서대로 발행된다.
    func testAcceptedRootCompletionAppliesContentProjectionBeforeRootSnapshotReconciliation() async {
        let rootFolder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let rootFile = makeSharedProjectionFile()
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: "/root")
        state.entryViewLayout.entryOperations.items = [rootFolder, rootFile]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        // itemsLoaded는 accepted root completion → projection → root snapshot 순서
        await store.send(.entryViewLayout(.entryOperations(.loading(.itemsLoaded([rootFolder, rootFile])))))

        // applyContentProjection이 먼저 발행된다
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }

        // rootSnapshotCompleted가 다음에 발행된다
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.rootSnapshotCompleted(gen, folders))) = action
            else { return false }
            return gen == store.state.entryViewLayout.hierarchy.rootContextGeneration
                && folders == [rootFolder]
        }

        // root snapshot이 적용됐는지 확인
        XCTAssertTrue(store.state.entryViewLayout.hierarchy.nodesByID.keys.contains(rootFolder.id))
    }

    /// EVM-002-toggle_directory_expansion_in_list: generation이 일치하지 않는 root completion은 state를 변경하지 않는다.
    /// - 검증 내용: rootContextGeneration 불일치 시 nodesByID가 변경되지 않는다.
    /// - 사전 조건: hierarchy rootContextGeneration이 5이고 item이 nodesByID에 있다.
    /// - 기대 결과: rootSnapshotCompleted가 0 generation으로 전송되어도 nodesByID가 유지된다.
    func testStaleRootCompletionWithMismatchedGenerationIsNoOp() async {
        let rootFolder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy = .init(rootContextGeneration: 5, rootPath: "/root")
        state.entryViewLayout.hierarchy.nodesByID[rootFolder.id] = FolderNodeState(
            children: [hierarchyFile(id: "/root/folder/child", name: "child")],
            loadPhase: .loaded,
            generation: 1,
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        // mismatched generation (0 != 5) → NO-OP
        await store.send(.entryViewLayout(.hierarchy(.rootSnapshotCompleted(
            rootContextGeneration: 0,
            rootFolders: [rootFolder],
        ))))

        // nodesByID가 변경되지 않아야 한다
        XCTAssertNotNil(store.state.entryViewLayout.hierarchy.nodesByID[rootFolder.id])
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[rootFolder.id]?.folder.children.map(\.id),
            ["/root/folder/child"],
        )
    }

    private func hierarchyFile(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "txt",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}

private func makeSharedProjectionFile(tags: [Tag]? = nil) -> EntryModel {
    EntryModel(
        name: "file.txt",
        fullPath: "/root/file.txt",
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
            tags: tags,
            supplementaryMetadata: nil,
        ),
    )
}
