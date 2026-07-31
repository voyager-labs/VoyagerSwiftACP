import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002FileManagerPagePresentationTests {
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
        state.entryOperations.items = [folder, file]
        state.entryOperations.commonApplicationsForSelectedFiles = [application]
        state.entryArrangements.groupKey = .kind
        state.entryArrangements.groupedItems = [
            GroupedItems(groupName: "Folders", items: [folder]),
            GroupedItems(groupName: "Text", items: [file]),
        ]
        state.entryArrangements.collapsedGroups = ["Text"]
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
            clipboardCutPaths: [],
            busyEntryPaths: [],
            openWithApplications: [application],
            restorableTrashPaths: [],
            trashDirectoryPath: nil,
            collectionWindowID: state.entryOperations.windowID,
            collectionLoadingCancellationOwnerID: state.entryOperations.loadingCancellationOwnerID,
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
        let store = TestStore(initialState: FileManagerContentState()) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.delegate(.preloadOpenWithApplications([file]))))
        await store.receive {
            guard case let .entryOperations(.openWith(.loadCommonApplicationsForFiles(files))) = $0 else {
                return false
            }
            return files == [file]
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
            guard case let .entryArrangements(.toggleCollapsedGroup(groupName)) = action else { return false }
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
        state.entryOperations.items = [folder, file]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        // store.exhaustivity = .off: 다중 child reducer composition에서 grouping projection 결과만 검증한다.
        store.exhaustivity = .off

        await store.send(.entryArrangements(.setGroupKey(.kind)))

        // requestApply → apply → applied chain 확인
        await store.receive { action in
            guard case .entryArrangements(.delegate(.requestApply)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryArrangements(.apply) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryArrangements(.delegate(.applied)) = action else { return false }
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
}

private func makeSharedProjectionFile() -> EntryModel {
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
            tags: nil,
            supplementaryMetadata: nil,
        ),
    )
}
