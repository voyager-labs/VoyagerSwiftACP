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

        XCTAssertTrue(actions.allSatisfy(FileManagerContentFeature.shouldProjectContent))
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

    /// EVM-002-replacement_reload_snapshot_retention: 빈 대체 batch는 마지막 완전 root projection을 유지한다.
    /// - 검증 내용: reload 첫 batch가 비어도 ContentProjection entries와 선택이 기존 row를 유지한다.
    /// - 사전 조건: `/root/file.txt`가 선택된 complete root projection에서 generation 1 reload가 시작됐다.
    /// - 기대 결과: 빈 batchIndex 0 뒤에도 projection과 선택은 `/root/file.txt`다.
    func testEmptyReplacementBatchRetainsCompleteRootProjectionAndSelection() async {
        let rootPath = "/root"
        let oldEntry = makeSharedProjectionFile()
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [oldEntry]
        state.entryViewLayout.entries = [oldEntry]
        state.entryViewLayout.selectedIds = [oldEntry.id]
        state.entryViewLayout.lastSelectedId = oldEntry.id
        state.entryViewLayout.rangeAnchorId = oldEntry.id
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [], batchIndex: 0),
        ))))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [oldEntry]
        }

        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [oldEntry.id])
    }

    /// EVM-002-command_external_refresh_correlation: 무관한(비어 있지 않은) 첫 대체 batch가 와도
    /// 진행 중인 identity 전이가 after-path를 얻기 전까지 선택을 유지한다.
    /// - 검증 내용: after-path 없는 무관 batch 뒤에도 before-path 선택·전이 보존
    /// - 사전 조건: generation 1 reload 중인 root projection에 선택된 before→after 대기 전이
    /// - 기대 결과: 무관 batch에서 선택 유지, 이후 after-path batch에서 1회 migration + 전이 소비
    func testUnrelatedFirstReplacementBatchRetainsSelectionUntilAfterPath() async {
        let rootPath = "/root"
        let oldPath = "/root/old.txt"
        let newPath = "/root/new.txt"
        let oldEntry = hierarchyFile(id: oldPath, name: "old.txt")
        let unrelatedEntry = hierarchyFile(id: "/root/unrelated.txt", name: "unrelated.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [oldEntry]
        state.entryViewLayout.entries = [oldEntry]
        state.entryViewLayout.selectedIds = [oldPath]
        state.entryViewLayout.lastSelectedId = oldPath
        state.entryViewLayout.rangeAnchorId = oldPath
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: newPath,
            rootPath: rootPath,
            refreshGeneration: 1,
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        // 무관한 첫 대체 batch: after-path가 없으므로 선택과 전이를 유지해야 한다.
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [unrelatedEntry], batchIndex: 0),
        ))))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [oldEntry]
        }

        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            [oldPath],
            "after-path가 도착하기 전까지 before-path 선택을 유지한다",
        )
        XCTAssertNotNil(store.state.pendingIdentityTransition, "무관 첫 배치는 전이를 소비하지 않는다")

        // after-path 배치: 선택을 after-path로 옮기고 전이를 소비한다.
        let renamedEntry = hierarchyFile(id: newPath, name: "new.txt")
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [unrelatedEntry, renamedEntry], batchIndex: 1),
        ))))))
        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            [newPath],
            "선택은 after-path로 정확히 한 번 옮긴다",
        )
        XCTAssertNil(store.state.pendingIdentityTransition, "전이는 소비된다")
    }

    /// EVM-002-command_external_refresh_correlation: 사용자가 before-path를 이미 deselect하면
    /// 비종료 대체 batch가 선택을 되돌리지 않는다.
    /// - 검증 내용: 대기 전이 상태에서 applyClearSelection 후 무관 batch가 선택을 비운 채 유지
    /// - 사전 조건: 선택된 before-path와 대기 전이, 이후 사용자 deselect
    /// - 기대 결과: 비종료 batch 뒤에도 selectedIds는 빈 채로 유지되고 전이는 살아 있다
    func testUserDeselectDuringPendingTransitionIsNotUndoneByReplacementBatch() async {
        let rootPath = "/root"
        let oldPath = "/root/old.txt"
        let newPath = "/root/new.txt"
        let oldEntry = hierarchyFile(id: oldPath, name: "old.txt")
        let unrelatedEntry = hierarchyFile(id: "/root/unrelated.txt", name: "unrelated.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [oldEntry]
        state.entryViewLayout.entries = [oldEntry]
        state.entryViewLayout.selectedIds = [oldPath]
        state.entryViewLayout.lastSelectedId = oldPath
        state.entryViewLayout.rangeAnchorId = oldPath
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: newPath,
            rootPath: rootPath,
            refreshGeneration: 1,
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        // 사용자 deselect.
        await store.send(.entryViewLayout(.internal(.applyClearSelection)))
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.isEmpty)

        // 비종료 무관 batch: before 선택이 없어 전이는 같은 패스에서 소비되고,
        // 부분 batch가 정상 적용된다. deselect된 선택은 되돌려지지 않는다.
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [unrelatedEntry], batchIndex: 0),
        ))))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [unrelatedEntry]
        }

        XCTAssertTrue(
            store.state.entryViewLayout.selectedIds.isEmpty,
            "사용자 deselect는 비종료 batch에 의해 되돌려지지 않는다",
        )
        XCTAssertNil(store.state.pendingIdentityTransition, "before 선택 포기는 owning batch에서 전이를 소비한다")
    }

    /// EVM-002-command_external_refresh_correlation: 종료(accepted) projection에서 after-path가
    /// 끝내 없으면 전이를 소비하고 일반 선택 reconcile이 이긴다.
    /// - 검증 내용: coreFinished(빈) 후 selectedIds가 비워지고 pendingIdentityTransition == nil
    /// - 사전 조건: 선택된 before-path와 대기 전이, after-path 없는 reload 진행
    /// - 기대 결과: 종료 projection에서 선택이 사라지고 전이가 소비됨
    func testTerminalAcceptedProjectionWithoutAfterPathClearsTransition() async {
        let rootPath = "/root"
        let oldPath = "/root/old.txt"
        let newPath = "/root/new.txt"
        let oldEntry = hierarchyFile(id: oldPath, name: "old.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [oldEntry]
        state.entryViewLayout.entries = [oldEntry]
        state.entryViewLayout.selectedIds = [oldPath]
        state.entryViewLayout.lastSelectedId = oldPath
        state.entryViewLayout.rangeAnchorId = oldPath
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: newPath,
            rootPath: rootPath,
            refreshGeneration: 1,
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        // after-path 없는 종료(accepted) projection.
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreFinished(batchCount: 0),
        ))))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries.isEmpty
        }

        XCTAssertTrue(
            store.state.entryViewLayout.selectedIds.isEmpty,
            "종료 projection에서 일반 선택 reconcile이 이긴다",
        )
        XCTAssertNil(store.state.pendingIdentityTransition, "after-path 없는 종료 projection은 전이를 소비한다")
    }

    /// EVM-002-command_external_refresh_correlation: 실제 네비게이션(root 변경)으로 이동하면
    /// 대기 전이가 즉시 만료되고 선택을 옮기거나 되살리지 않는다(루트 불일치 만료).
    /// - 검증 내용: applyNavigationState(.folder(/other)) 전송 직후 전이 만료, 이후 배치에서 stale-migrate 없음
    /// - 사전 조건: /root에 대기 전이와 before 선택, 이후 실제 applyNavigationState로 /other 이동
    /// - 기대 결과: 네비게이션 즉시 전이 nil, after-path 배치가 와도 newPath로 선택 이동 없음
    func testNavigationAwayDoesNotStaleMigrateOrReselect() async {
        let rootPath = "/root"
        let otherRootPath = "/other"
        let oldPath = "/root/old.txt"
        let newPath = "/root/new.txt"
        let oldEntry = hierarchyFile(id: oldPath, name: "old.txt")
        let renamedEntry = hierarchyFile(id: newPath, name: "new.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [oldEntry]
        state.entryViewLayout.entries = [oldEntry]
        state.entryViewLayout.selectedIds = [oldPath]
        state.entryViewLayout.lastSelectedId = oldPath
        state.entryViewLayout.rangeAnchorId = oldPath
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: newPath,
            rootPath: rootPath,
            refreshGeneration: 1,
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        // 실제 네비게이션(root 변경) 액션으로 이동하면 전이가 즉시 만료된다.
        await store.send(.internal(.applyNavigationState(.folder(otherRootPath))))
        XCTAssertNil(
            store.state.pendingIdentityTransition,
            "다른 root로 이동하면 전이가 즉시 만료된다",
        )

        // after-path가 포함된 배치가 와도 root가 다르고 전이가 이미 만료되어
        // newPath로 stale-migrate되지 않는다.
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [renamedEntry], batchIndex: 0),
        ))))))

        XCTAssertFalse(
            store.state.entryViewLayout.selectedIds.contains(newPath),
            "다른 root에서는 after-path로 stale-migrate되지 않는다",
        )
        XCTAssertNil(store.state.pendingIdentityTransition, "전이는 만료된 채 유지된다")
    }

    /// EVM-002-replacement_reload_snapshot_retention: 대체 stream이 첫 batch 전에 실패해도 마지막 root row를 유지한다.
    /// - 검증 내용: streamFailed가 loading items를 비운 뒤 emitted ContentProjection payload를 확인한다.
    /// - 사전 조건: complete root projection에서 generation 1 reload가 진행 중이다.
    /// - 기대 결과: failure projection entries는 마지막 complete root entry다.
    func testReplacementFailureBeforeFirstBatchRetainsCompleteRootProjection() async {
        let rootPath = "/root"
        let oldEntry = makeSharedProjectionFile()
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [oldEntry]
        state.entryViewLayout.entries = [oldEntry]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFailed(generation: 1)))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [oldEntry]
        }
    }

    /// EVM-002-replacement_reload_snapshot_retention: 실제 operationFinished 재로드의 loadItems 시작도
    /// 완전한 같은-root projection을 유지한다.
    /// reload 시작 action이 items를 비운 시점(isReloading=false)에도 화면의 마지막 완전
    /// root projection이 유지되는지 검증한다.
    /// - 검증 내용: loadItems 시작 projection과 첫 batch 전 실패 projection 모두 기존 root entries 유지
    /// - 사전 조건: `/root/file.txt`가 표시된 완전 projection에서 isReloading=false 재로드 시작
    /// - 기대 결과: loadItems 시점과 streamFailed 시점 projection entries 모두 기존 항목이다.
    func testRealReloadLoadItemsStartRetainsCompleteSameRootProjection() async {
        let rootPath = "/root"
        let oldEntry = makeSharedProjectionFile()
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entryOperations.items = [oldEntry]
        state.entryViewLayout.entries = [oldEntry]
        state.entryViewLayout.selectedIds = [oldEntry.id]
        state.entryViewLayout.lastSelectedId = oldEntry.id
        state.entryViewLayout.rangeAnchorId = oldEntry.id
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = false
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: StubbedReloadFailure())
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.loadItems(
            path: rootPath,
            showHidden: false,
        )))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [oldEntry]
        }
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [oldEntry]
        }
        await store.finish()

        XCTAssertEqual(store.state.entryViewLayout.entries, [oldEntry])
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [oldEntry.id])
    }

    /// EVM-002-replacement_reload_snapshot_retention: root 안의 symlink entry도 같은-root projection으로 유지한다.
    /// 실제 target이 root 밖이어도 표시 entry의 lexical parent가 현재 root인지 검증한다.
    /// - 검증 내용: 외부 target을 가리키는 실제 symlink가 있는 root의 loadItems 시작·실패 projection
    /// - 사전 조건: 완전 projection의 유일한 entry는 current root 안의 symlink다.
    /// - 기대 결과: symlink-resolved target 위치와 무관하게 기존 entry와 selection을 유지한다.
    func testRealReloadRetainsInRootSymlinkWhoseTargetIsOutside() async throws {
        let sandboxRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerSameRootSymlink-\(UUID().uuidString)", isDirectory: true)
        let rootURL = sandboxRoot.appendingPathComponent("root", isDirectory: true)
        let outsideTargetURL = sandboxRoot.appendingPathComponent("outside.txt")
        let symlinkURL = rootURL.appendingPathComponent("linked.txt")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outsideTargetURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideTargetURL)
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        let symlinkEntry = makeSharedProjectionFile(path: symlinkURL.path)
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootURL.path)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entryOperations.items = [symlinkEntry]
        state.entryViewLayout.entries = [symlinkEntry]
        state.entryViewLayout.selectedIds = [symlinkEntry.id]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = false
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: StubbedReloadFailure())
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.loadItems(
            path: rootURL.path,
            showHidden: false,
        )))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [symlinkEntry]
        }
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [symlinkEntry]
        }
        await store.finish()

        XCTAssertEqual(store.state.entryViewLayout.entries, [symlinkEntry])
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [symlinkEntry.id])
    }

    /// EVM-002-replacement_reload_snapshot_retention: 실제 operationFinished → loadItems 액션 순서로
    /// 재로드를 시작해도 완전한 같은-root projection이 유지된다.
    /// V20-P1-1 회귀: loadItems를 직접 주입하지 않고, coordinator가 operationFinished 성공에
    /// 발행하는 실제 loadItems로 이어붙여 projection 보존을 검증한다.
    /// - 검증 내용: operationFinished 성공 → coordinator 발행 loadItems → 실패까지 projection 보존
    /// - 사전 조건: `/root/file.txt`가 표시된 완전 projection에서 isReloading=false 재로드
    /// - 기대 결과: loadItems 시작과 streamFailed 시점 projection entries 모두 기존 항목이다
    func testOperationFinishedEmittedLoadItemsRetainsCompleteSameRootProjection() async {
        let rootPath = "/root"
        let oldEntry = makeSharedProjectionFile()
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [oldEntry]
        state.entryViewLayout.entries = [oldEntry]
        state.entryViewLayout.selectedIds = [oldEntry.id]
        state.entryViewLayout.lastSelectedId = oldEntry.id
        state.entryViewLayout.rangeAnchorId = oldEntry.id
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = false
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: StubbedReloadFailure())
                }
            }
        }
        store.exhaustivity = .off

        // 실제 순서: operationFinished 성공 → entryActionCompleted가 전이를 만든 뒤
        // coordinator가 같은 root의 loadItems를 발행한다.
        await store.send(.entryViewLayout(.entryOperations(.lifecycle(.operationFinished(
            "\(rootPath)/file.txt",
            .rename,
            .success(()),
        )))))
        await store.send(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
            EntryActionRecord(
                operationKind: .rename,
                targets: [
                    .init(beforePath: "\(rootPath)/file.txt", afterPath: "\(rootPath)/renamed.txt"),
                ],
            ),
        )))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [oldEntry]
        }
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries == [oldEntry]
        }
        await store.finish()

        XCTAssertEqual(store.state.entryViewLayout.entries, [oldEntry])
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [oldEntry.id])
    }

    /// EVM-002-command_external_refresh_correlation: 비종료 대체 batch의 선택 복원은 원본 lexical ID를
    /// 정확히 재삽입한다.
    /// 선택 ID의 lexical 표기가 canonical 경로와 달라도(여기서는 dot-segment 표기) 화면 표기의
    /// lexical 선택 ID가 복원되는지 검증한다.
    /// - 검증 내용: 무관 첫 batch 후 selectedIds/lastSelectedId/rangeAnchorId가 lexical before ID 그대로
    /// - 사전 조건: `/root` route에서 lexical(`/root/./old.txt`) 선택과 canonical(`/root/old.txt`) 전이
    /// - 기대 결과: 복원 선택은 lexical ID이며 이후 after-path batch에서 lexical after로 이동한다
    func testReplacementBatchRestoresExactLexicalSelectedBeforeID() async {
        let rootPath = "/root"
        let lexicalOld = "/root/./old.txt"
        let canonicalOld = URL(fileURLWithPath: lexicalOld).standardizedFileURL.resolvingSymlinksInPath().path
        let lexicalNew = "/root/new.txt"
        let unrelatedEntry = hierarchyFile(id: "/root/unrelated.txt", name: "unrelated.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [hierarchyFile(id: lexicalOld, name: "old.txt")]
        state.entryViewLayout.entries = [hierarchyFile(id: lexicalOld, name: "old.txt")]
        state.entryViewLayout.selectedIds = [lexicalOld]
        state.entryViewLayout.lastSelectedId = lexicalOld
        state.entryViewLayout.rangeAnchorId = lexicalOld
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: canonicalOld,
            afterPath: lexicalNew,
            rootPath: rootPath,
            refreshGeneration: 1,
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        // 무관한 첫 batch: 선택 복원은 canonical 경로가 아닌 원본 lexical ID를 재삽입해야 한다.
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [unrelatedEntry], batchIndex: 0),
        ))))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries.map(\.id) == [lexicalOld]
        }

        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            [lexicalOld],
            "복원된 선택은 canonical 경로가 아니라 원본 lexical ID여야 한다",
        )
        XCTAssertEqual(store.state.entryViewLayout.lastSelectedId, lexicalOld)
        XCTAssertEqual(store.state.entryViewLayout.rangeAnchorId, lexicalOld)
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        // after-path batch: lexical after ID로 선택을 옮기고 전이를 소비한다.
        let renamedEntry = hierarchyFile(id: lexicalNew, name: "new.txt")
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [unrelatedEntry, renamedEntry], batchIndex: 1),
        ))))))
        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            [lexicalNew],
            "선택은 lexical after-path ID로 이동한다",
        )
        XCTAssertNil(store.state.pendingIdentityTransition, "전이는 소비된다")
    }

    /// EVM-002-command_external_refresh_correlation: 실제 임시 symlink 경로의 lexical 선택 ID가
    /// 비종료 대체 batch에서 정확히 보존된다.
    /// 선택 ID가 실제 파일시스템 symlink(`link/<file> → real/<file>`)를 거쳐 canonical 경로와
    /// 달라도 화면 표기의 lexical 선택 ID가 복원되는지 검증한다.
    /// - 검증 내용: 무관 첫 batch 후 selectedIds/lastSelectedId/rangeAnchorId가 symlink lexical before ID 그대로
    /// - 사전 조건: real 폴더 route에서 lexical(`.../link/11.txt`) 선택과 canonical(`.../real/11.txt`) 전이
    /// - 기대 결과: 복원 선택은 canonical이 아닌 원본 symlink lexical ID다
    func testReplacementBatchRestoresRealSymlinkLexicalSelectedBeforeID() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let rootPath = sandbox.fileURL.deletingLastPathComponent().path
        let lexicalBefore = sandbox.symlinkedFileURL.path
        let canonicalBefore = URL(fileURLWithPath: lexicalBefore)
            .standardizedFileURL.resolvingSymlinksInPath().path
        let afterPath = "\(rootPath)/renamed.txt"
        let unrelatedEntry = hierarchyFile(id: "\(rootPath)/unrelated.txt", name: "unrelated.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [hierarchyFile(id: lexicalBefore, name: "11.txt")]
        state.entryViewLayout.entries = [hierarchyFile(id: lexicalBefore, name: "11.txt")]
        state.entryViewLayout.selectedIds = [lexicalBefore]
        state.entryViewLayout.lastSelectedId = lexicalBefore
        state.entryViewLayout.rangeAnchorId = lexicalBefore
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: canonicalBefore,
            afterPath: afterPath,
            rootPath: rootPath,
            refreshGeneration: 1,
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        // 무관한 첫 batch: 선택 복원은 canonical 경로가 아니라 원본 symlink lexical ID를 재삽입해야 한다.
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [unrelatedEntry], batchIndex: 0),
        ))))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else {
                return false
            }
            return projection.entries.map(\.id) == [lexicalBefore]
        }

        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            [lexicalBefore],
            "복원된 선택은 canonical 경로가 아니라 원본 symlink lexical ID여야 한다",
        )
        XCTAssertEqual(store.state.entryViewLayout.lastSelectedId, lexicalBefore)
        XCTAssertEqual(store.state.entryViewLayout.rangeAnchorId, lexicalBefore)
        XCTAssertNotNil(store.state.pendingIdentityTransition)
    }

    /// EVM-002-replacement_reload_snapshot_retention: expanded child 교체는 같은 reducer cycle에서 선택을 after-path로 옮긴다.
    /// - 검증 내용: retained before child가 첫 새 batch의 after child로 교체될 때 selection과 transition을 함께 확인한다.
    /// - 사전 조건: generation 4 loading folder와 선택된 before→after 대기 전이가 있다.
    /// - 기대 결과: folder children과 selectedIds는 after-path만 포함하고 transition은 소비된다.
    func testExpandedReplacementBatchMigratesSelectionAndConsumesTransition() {
        let rootPath = "/root"
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let before = hierarchyFile(id: "/root/folder/before.txt", name: "before.txt")
        let after = hierarchyFile(id: "/root/folder/after.txt", name: "after.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[folder.id] = FolderNodeState(
            folder: FolderSnapshot(children: [before]),
            expansionIntent: true,
            generation: 4,
            loadPhase: .loadingCore,
        )
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        // 프로덕션과 동일하게 전이 생성 세대(3)와 root 로딩 세대를 일치시킨다.
        state.entryViewLayout.entryOperations.loadingContext.generation = 3
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: after.id,
            rootPath: rootPath,
            refreshGeneration: 3,
            projectionOwner: .folder(id: folder.id, generation: 4),
        )
        _ = FileManagerContentFeature().reduce(
            into: &state,
            action: .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
                folderID: folder.id,
                folderGeneration: 4,
                .event(.coreBatch(items: [after], batchIndex: 0)),
            ))),
        )

        XCTAssertEqual(state.entryViewLayout.hierarchy.nodesByID[folder.id]?.folder.children, [after])
        XCTAssertEqual(state.entryViewLayout.selectedIds, [after.id])
        XCTAssertNil(state.pendingIdentityTransition)
    }

    /// EVM-002-command_external_refresh_correlation: source folder의 중간 batch가 destination owner보다 먼저 와도
    /// cross-folder move의 before 선택을 유지한다.
    /// - 검증 내용: source A 교체 batch 뒤 before 선택 보존, destination B owner batch에서 after로 migration
    /// - 사전 조건: source/destination이 모두 expanded이고 destination folder가 transition projection owner다.
    /// - 기대 결과: 중간 projection은 전이를 소비하지 않으며 owner batch가 선택을 after로 옮기고 전이를 소비한다.
    func testCrossFolderMovePreservesSelectionThroughSourceBatchBeforeDestinationOwner() {
        let source = EntryModel.temporaryFolder(id: "/root/source", name: "source")
        let destination = EntryModel.temporaryFolder(id: "/root/destination", name: "destination")
        let before = hierarchyFile(id: "/root/source/before.txt", name: "before.txt")
        let sibling = hierarchyFile(id: "/root/source/sibling.txt", name: "sibling.txt")
        let after = hierarchyFile(id: "/root/destination/after.txt", name: "after.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [source, destination]
        state.entryViewLayout.hierarchy.replaceRoot(path: "/root")
        state.entryViewLayout.hierarchy.nodesByID[source.id] = makeExpandedLoadingFolderNode(children: [before])
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = makeExpandedLoadingFolderNode(children: [])
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: after.id,
            rootPath: "/root",
            refreshGeneration: 3,
            projectionOwner: .folder(id: destination.id, generation: 4),
            preservationOwner: .folder(id: source.id, generation: 4),
        )
        let feature = FileManagerContentFeature()
        let rootGeneration = state.entryViewLayout.hierarchy.rootContextGeneration

        _ = feature.reduce(into: &state, action: makeCrossMoveFolderBatch(source.id, [sibling], rootGeneration))
        XCTAssertEqual(state.entryViewLayout.selectedIds, [before.id], "source 중간 batch는 before 선택을 보존한다")
        XCTAssertEqual(
            state.pendingIdentityTransition?.projectionOwner,
            .folder(id: destination.id, generation: 4),
            "non-owner batch는 destination owner 전이를 소비하지 않는다",
        )

        _ = feature.reduce(into: &state, action: makeCrossMoveFolderBatch(destination.id, [after], rootGeneration))

        XCTAssertEqual(state.entryViewLayout.selectedIds, [after.id])
        XCTAssertNil(state.pendingIdentityTransition)
    }

    /// EVM-002-command_external_refresh_correlation: nested source의 중간 batch가 root owner보다 먼저 와도
    /// nested-to-root move의 before 선택을 유지한다.
    /// - 검증 내용: nested source 교체 batch 뒤 before 선택 보존, root owner batch에서 after로 migration
    /// - 사전 조건: expanded source child가 선택되어 있고 root loading generation이 transition owner다.
    /// - 기대 결과: 중간 folder projection은 전이를 유지하고 root batch가 선택을 after로 옮겨 소비한다.
    func testNestedToRootMovePreservesSelectionThroughSourceBatchBeforeRootOwner() {
        let rootPath = "/root"
        let source = EntryModel.temporaryFolder(id: "/root/source", name: "source")
        let before = hierarchyFile(id: "/root/source/before.txt", name: "before.txt")
        let sourceSibling = hierarchyFile(id: "/root/source/sibling.txt", name: "sibling.txt")
        let after = hierarchyFile(id: "/root/after.txt", name: "after.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [source]
        state.entryViewLayout.entryOperations.items = [source]
        state.entryViewLayout.entryOperations.loadingContext.generation = 7
        state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex = 0
        state.entryViewLayout.entryOperations.isReloading = true
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[source.id] = FolderNodeState(
            folder: FolderSnapshot(children: [before]),
            expansionIntent: true,
            generation: 4,
            loadPhase: .loadingCore,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: after.id,
            rootPath: rootPath,
            refreshGeneration: 7,
            projectionOwner: .root(generation: 7),
            preservationOwner: .folder(id: source.id, generation: 4),
        )
        let feature = FileManagerContentFeature()

        _ = feature.reduce(
            into: &state,
            action: .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
                folderID: source.id,
                folderGeneration: 4,
                .event(.coreBatch(items: [sourceSibling], batchIndex: 0)),
            ))),
        )

        XCTAssertEqual(state.entryViewLayout.hierarchy.nodesByID[source.id]?.folder.children, [sourceSibling])
        XCTAssertEqual(state.entryViewLayout.selectedIds, [before.id], "nested 중간 batch는 before 선택을 보존한다")
        XCTAssertEqual(state.pendingIdentityTransition?.projectionOwner, .root(generation: 7))

        _ = withDependencies {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        } operation: {
            feature.reduce(
                into: &state,
                action: .entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
                    generation: 7,
                    event: .coreBatch(items: [source, after], batchIndex: 0),
                ))))),
            )
        }

        XCTAssertEqual(state.entryViewLayout.selectedIds, [after.id])
        XCTAssertNil(state.pendingIdentityTransition)
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

private func makeExpandedLoadingFolderNode(children: [EntryModel]) -> FolderNodeState {
    FolderNodeState(
        folder: FolderSnapshot(children: children),
        expansionIntent: true,
        generation: 4,
        loadPhase: .loadingCore,
    )
}

private func makeCrossMoveFolderBatch(
    _ folderID: String,
    _ items: [EntryModel],
    _ rootContextGeneration: Int,
) -> FileManagerContentAction {
    .entryViewLayout(.hierarchy(.folderChildrenResponse(
        rootContextGeneration: rootContextGeneration,
        folderID: folderID,
        folderGeneration: 4,
        .event(.coreBatch(items: items, batchIndex: 0)),
    )))
}

private func makeSharedProjectionFile(path: String = "/root/file.txt", tags: [Tag]? = nil) -> EntryModel {
    EntryModel(
        name: "file.txt",
        fullPath: path,
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

/// 재로드 stream을 즉시 실패시키는 테스트용 오류.
private struct StubbedReloadFailure: Error {}
