import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesEntryOperations
import VoyagerShared
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EOP004EditEntryMetadataTests: XCTestCase {
    /// EOP-004-open_with_loading: unresolved applications render a disabled loading placeholder.
    /// - 검증 내용: loading 상태 메뉴 생성이 즉시 반환되고 Loading Applications…가 disabled인지 확인한다.
    /// - 사전 조건: openWithApplications가 비어 있고 loading 상태가 true이다.
    /// - 기대 결과: placeholder가 존재하고 Other…는 하나이며 마지막에 위치한다.
    func testOpenWithMenuShowsLoadingPlaceholderAndSingleBottomOther() {
        let menu = buildOpenWithMenu(apps: [], workspaceClient: .testValue, isLoading: true)
        XCTAssertEqual(menu.items.first?.title, "Loading Applications…")
        XCTAssertFalse(menu.items.first?.isEnabled ?? true)
        XCTAssertEqual(menu.items.last?.title, "Other…")
        XCTAssertEqual(menu.items.count(where: { $0.title == "Other…" }), 1)
    }

    /// EOP-004-open_with_loading: 열린 Open With submenu는 discovery 완료 즉시 앱 목록으로 갱신된다.
    /// - 검증 내용: 같은 submenu 인스턴스가 loading item을 앱 item으로 교체하는지 확인한다.
    /// - 사전 조건: plain-text 타입 조회가 in-flight인 선택 파일과 열린 context menu가 있다.
    /// - 기대 결과: 메뉴를 다시 만들지 않아도 Preview와 단일 하단 Other…가 표시된다.
    func testOpenWithMenuRefreshesInPlaceWhenApplicationsLoad() async throws {
        let file = makeOpenWithFile(name: "document.txt")
        let typeID = "public.plain-text"
        var state = EntryViewLayoutState()
        state.entries = [file]
        state.selectedIds = [file.id]
        state.entryOperations.openWithTypeRequestGenerations[typeID] = 1
        state.entryOperations.openWithInFlightTypeIDs = [typeID]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(
            displayEntries: [file],
            selectedIds: [file.id],
            rowEntry: file,
        )
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)
        let menu = EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: 1,
            rowEntryPathForOpenInNewWindow: nil,
            openInNewTabPaths: nil,
            serviceNames: [],
            canPaste: false,
            showCompress: false,
            showExtract: false,
            isTrashFolder: false,
            canPutBack: false,
            openWithApplications: [],
            showOpenWith: true,
            paletteTags: [],
            knownTags: [],
            canPerformEntryCommands: true,
            isOpenWithApplicationsLoading: true,
        ))
        let submenu = try XCTUnwrap(menu.item(withTitle: "Open With")?.submenu)
        coordinator.observeOpenWithMenu(menu)

        store.send(.entryOperations(.openWith(.applicationsLoaded(
            typeID: typeID,
            generation: 1,
            [ApplicationInfo(id: "preview", name: "Preview", bundleID: "preview")],
        ))))
        for _ in 0 ..< 100 where submenu.item(withTitle: "Preview") == nil {
            await Task.yield()
        }

        XCTAssertNotNil(submenu.item(withTitle: "Preview"))
        XCTAssertNil(submenu.item(withTitle: "Loading Applications…"))
        XCTAssertEqual(submenu.items.last?.title, "Other…")
        XCTAssertEqual(submenu.items.count(where: { $0.title == "Other…" }), 1)
    }

    /// EOP-004-open_with_loading: 열린 다중 선택 submenu도 common discovery 완료 즉시 갱신된다.
    /// - 검증 내용: common completion 후 같은 submenu가 교집합 앱을 표시하고 close 후 관찰을 중단하는지 확인한다.
    /// - 사전 조건: 동일 타입 파일 두 개의 common 조회가 in-flight인 열린 context menu가 있다.
    /// - 기대 결과: Shared가 즉시 나타나고 메뉴 close 이후 후속 상태 변화는 반영되지 않는다.
    func testOpenWithCommonMenuRefreshesInPlaceUntilMenuCloses() async throws {
        let first = makeOpenWithFile(name: "first.txt")
        let second = makeOpenWithFile(name: "second.txt")
        let typeID = "public.plain-text"
        var state = EntryViewLayoutState()
        state.entries = [first, second]
        state.selectedIds = [first.id, second.id]
        state.entryOperations.openWithCommonRequestGeneration = 1
        state.entryOperations.openWithCommonTypeGenerations[typeID] = 1
        state.entryOperations.openWithInFlightTypeIDs = [typeID]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(
            displayEntries: [first, second],
            selectedIds: [first.id, second.id],
            rowEntry: first,
        )
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)
        let menu = EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: 2,
            rowEntryPathForOpenInNewWindow: nil,
            openInNewTabPaths: nil,
            serviceNames: [],
            canPaste: false,
            showCompress: false,
            showExtract: false,
            isTrashFolder: false,
            canPutBack: false,
            openWithApplications: [],
            showOpenWith: true,
            paletteTags: [],
            knownTags: [],
            canPerformEntryCommands: true,
            isOpenWithApplicationsLoading: true,
        ))
        let submenu = try XCTUnwrap(menu.item(withTitle: "Open With")?.submenu)
        coordinator.observeOpenWithMenu(menu)
        let shared = ApplicationInfo(id: "shared", name: "Shared", bundleID: "shared")

        store.send(.entryOperations(.openWith(.commonApplicationsLoaded(
            generation: 1,
            typeIDs: [typeID],
            applicationsByType: [typeID: [shared]],
            [shared],
        ))))
        for _ in 0 ..< 100 where submenu.item(withTitle: "Shared") == nil {
            await Task.yield()
        }
        XCTAssertNotNil(submenu.item(withTitle: "Shared"))

        coordinator.menuDidClose(menu)
        store.send(.entryOperations(.openWith(.loadCommonApplicationsForFiles(files: [first, second]))))
        await Task.yield()
        XCTAssertNotNil(submenu.item(withTitle: "Shared"))
        XCTAssertNil(submenu.item(withTitle: "Loading Applications…"))
    }

    private func makeOpenWithFile(name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: "/tmp/\(name)",
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: .distantPast,
            fileExtension: "txt",
            facets: .init(
                createdDate: .distantPast,
                addedDate: .distantPast,
                lastOpenedDate: nil,
                kind: "Document",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }

    /// EOP-004-open_with_icons: blocked asynchronous icon resolution does not block menu creation.
    /// - 검증 내용: resolver gate가 닫힌 동안 메뉴가 반환되고 gate 해제 후 item image가 채워지는지 확인한다.
    /// - 사전 조건: WorkspaceClient.iconForFileAsync가 continuation gate에 대기한다.
    /// - 기대 결과: 메뉴 생성 시점 resolver 호출은 완료를 기다리지 않고, 해제 후 16x16 image가 설정된다.
    func testOpenWithMenuDoesNotWaitForBlockedIconResolver() async throws {
        let gate = DispatchSemaphore(value: 0)
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        var workspaceClient = WorkspaceClient.testValue
        workspaceClient.iconForFile = { _ in
            gate.wait()
            return icon
        }
        let menu = buildOpenWithMenu(apps: [ApplicationInfo(
            id: "preview",
            name: "Preview",
            bundleID: "preview",
            applicationURL: URL(fileURLWithPath: "/Applications/Blocked-\(UUID().uuidString).app"),
        )], workspaceClient: workspaceClient)
        let item = try XCTUnwrap(menu.item(withTitle: "Preview"))
        XCTAssertNil(item.image)
        gate.signal()
        for _ in 0 ..< 20 where item.image == nil {
            await Task.yield()
        }
        XCTAssertEqual(item.image?.size, NSSize(width: 16, height: 16))
    }

    // MARK: - EOP-004-edit_entry_tags

    /// EOP-004-edit_entry_tags: entry context menu가 기존 command shortcut을 AppKit key equivalent로 표현한다.
    /// 메뉴 title의 장식 문자가 아니라 실행 가능한 keyEquivalent와 modifier mask가 app command parity를 유지해야 한다.
    /// - 검증 내용: Open, Quick Look, Cut, Copy, Paste, Select All, Duplicate, Rename, Move to Trash의 key equivalent를 확인한다.
    /// - 사전 조건: 단일 display entry와 유효한 context-menu coordinator가 있다.
    /// - 기대 결과: 각 command가 기존 app menu와 key handler의 실행 가능한 shortcut을 렌더링한다.
    func testEntryContextMenuUsesExecutableExistingShortcuts() {
        let entry = EntryModel.temporaryFolder(id: "/tmp/entry", name: "entry")
        var state = EntryViewLayoutState()
        state.entries = [entry]
        state.selectedIds = [entry.id]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(
            displayEntries: [entry],
            selectedIds: [entry.id],
            rowEntry: entry,
        )
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)
        let menu = EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: 1,
            rowEntryPathForOpenInNewWindow: entry.fullPath,
            openInNewTabPaths: nil,
            serviceNames: [],
            canPaste: true,
            showCompress: false,
            showExtract: false,
            isTrashFolder: false,
            canPutBack: false,
            openWithApplications: [],
            showOpenWith: false,
            paletteTags: [],
            knownTags: [],
            canPerformEntryCommands: true,
        ))

        XCTAssertEqual(menu.items.first { $0.title == "Open" }?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(menu.items.first { $0.title == "Quick Look" }?.keyEquivalent, " ")
        XCTAssertEqual(menu.items.first { $0.title == "Quick Look" }?.keyEquivalentModifierMask, [])
        XCTAssertIdentical(menu.delegate, coordinator)
        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertFalse(menu.items.contains { $0.view is EntryFavoriteTagsPaletteView })
        for title in ["Cut", "Copy", "Paste", "Select All", "Duplicate"] {
            XCTAssertEqual(menu.items.first { $0.title == title }?.keyEquivalentModifierMask, .command)
        }
        XCTAssertEqual(menu.items.first { $0.title == "Rename" }?.keyEquivalent, "\r")
        XCTAssertEqual(menu.items.first { $0.title == "Rename" }?.keyEquivalentModifierMask, [])
        XCTAssertEqual(menu.items.first { $0.title == "Move to Trash" }?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(menu.items.first { $0.title == "Get Info" }?.keyEquivalent, "i")
        XCTAssertEqual(menu.items.first { $0.title == "Get Info" }?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(menu.items.first { $0.title == "Copy Absolute Paths" }?.keyEquivalent, "c")
        XCTAssertEqual(
            menu.items.first { $0.title == "Copy Absolute Paths" }?.keyEquivalentModifierMask,
            [.command, .option],
        )
        XCTAssertEqual(menu.items.first { $0.title == "Copy URL" }?.keyEquivalent, "u")
        XCTAssertEqual(menu.items.first { $0.title == "Copy URL" }?.keyEquivalentModifierMask, [.command, .option])
        XCTAssertNil(menu.items.first { $0.title == "Copy URLs" })
    }

    /// EOP-004-edit_entry_tags: Finder favorite palette는 처음 일곱 개만 표시하고 known tags는 선택 전용 tag까지 보존한다.
    /// 빠른 palette는 Finder가 정한 favorite만 표시하고 searchable picker는 현재 선택 entry의 tag도 찾아야 한다.
    /// - 검증 내용: paletteTags는 favorite prefix(7)이고 knownTags는 stable-deduped favorite와 selection tag의 합집합을 반환한다.
    /// - 사전 조건: 순서가 있는 2개의 Finder favorite와 선택 entry에만 있는 tag 하나가 있다.
    /// - 기대 결과: paletteTags에는 2개의 favorite만 있고 knownTags에는 선택 전용 tag까지 같은 순서로 포함된다.
    func testContextMenuTagSpecKeepsSelectionOnlyTagOutOfFavoritePalette() {
        let favorites = (1 ... 2).map { Tag(name: "Tag \($0)", colorCode: $0) }
        let selected = EntryModel(
            name: "selected",
            fullPath: "/tmp/selected",
            isFolder: true,
            isHidden: false,
            size: 0,
            modifiedDate: .distantPast,
            fileExtension: "",
            facets: .init(
                createdDate: .distantPast,
                addedDate: .distantPast,
                lastOpenedDate: nil,
                kind: "Folder",
                creatorApplication: nil,
                tags: [Tag(name: "Selection Only", colorCode: 6)],
                supplementaryMetadata: nil,
            ),
        )

        let spec = EntryContextMenuSpecFactory.make(
            selectedIds: [selected.id],
            selectedEntries: [selected],
            rowEntry: selected,
            isTrashFolder: false,
            restorableTrashPaths: [],
            canPaste: false,
            favoriteTags: favorites,
            openWithApplications: [],
        )

        XCTAssertEqual(spec.paletteTags.map(\.name), favorites.map(\.name))
        XCTAssertEqual(spec.knownTags.map(\.name), ["Tag 1", "Tag 2", "Selection Only"])
    }

    /// EOP-004-edit_entry_tags: 빈 context-menu 대상에는 tag UI를 표시하지 않는다.
    /// 대상 entry가 없으면 tag palette나 picker가 실행될 수 없어야 한다.
    /// - 검증 내용: selectedCount가 0인 메뉴가 Tags… item과 favorite palette view를 만들지 않는지 확인한다.
    /// - 사전 조건: known tag가 있지만 선택 및 row target이 없는 context-menu coordinator가 있다.
    /// - 기대 결과: 메뉴에 Tags… item과 EntryFavoriteTagsPaletteView가 없다.
    func testContextMenuOmitsTagsForEmptyTarget() {
        let store = Store(initialState: EntryViewLayoutState()) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(
            displayEntries: [],
            selectedIds: [],
            rowEntry: nil,
        )
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)
        let tag = EntryContextMenuTagSpec(name: "Red", colorCode: 6, selection: .off)

        let menu = EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: 0,
            rowEntryPathForOpenInNewWindow: nil,
            openInNewTabPaths: nil,
            serviceNames: [],
            canPaste: false,
            showCompress: false,
            showExtract: false,
            isTrashFolder: false,
            canPutBack: false,
            openWithApplications: [],
            showOpenWith: false,
            paletteTags: [tag],
            knownTags: [tag],
            canPerformEntryCommands: true,
        ))

        XCTAssertFalse(menu.items.contains { $0.title == "Tags…" })
        XCTAssertFalse(menu.items.contains { $0.view is EntryFavoriteTagsPaletteView })
    }

    /// EOP-004-edit_entry_tags: known tag가 없어도 선택 대상은 Tags… popover로 새 tag를 만들 수 있다.
    /// Finder favorite와 기존 tag가 비어 있어도 tag mutation의 진입점은 유지되어야 한다.
    /// - 검증 내용: 선택된 entry의 빈 tag 목록이 Tags… menu item을 렌더링한다.
    /// - 사전 조건: selectedCount가 1이고 paletteTags와 knownTags가 모두 비어 있다.
    /// - 기대 결과: Tags… item은 존재하며 AppKit auto-enable을 사용하지 않는다.
    func testContextMenuShowsTagsForSelectedTargetWithoutKnownTags() {
        let entry = EntryModel.temporaryFolder(id: "/tmp/entry", name: "entry")
        var state = EntryViewLayoutState()
        state.entries = [entry]
        state.selectedIds = [entry.id]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(
            displayEntries: [entry],
            selectedIds: [entry.id],
            rowEntry: entry,
        )
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)

        // RED: selected target with no known tags omitted Tags… before the guard changed.
        let menu = EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: 1,
            rowEntryPathForOpenInNewWindow: entry.fullPath,
            openInNewTabPaths: nil,
            serviceNames: [],
            canPaste: false,
            showCompress: false,
            showExtract: false,
            isTrashFolder: false,
            canPutBack: false,
            openWithApplications: [],
            showOpenWith: false,
            paletteTags: [],
            knownTags: [],
            canPerformEntryCommands: true,
        ))

        // GREEN: selected targets retain the searchable/new-tag popover entry point.
        XCTAssertNotNil(menu.items.first { $0.title == "Tags…" })
        XCTAssertFalse(menu.autoenablesItems)
    }

    /// EOP-004-edit_entry_tags: Put Back은 선택된 Trash entry 모두에 metadata가 있을 때만 활성화한다.
    /// 하나라도 metadata가 없으면 reducer failure 전의 UI에서 명령을 막아야 한다.
    /// - 검증 내용: menu spec의 all-target eligibility와 Put Back menu item enablement.
    /// - 사전 조건: Trash 안의 두 선택 entry 중 하나만 restorable path 집합에 있다.
    /// - 기대 결과: mixed selection의 canPutBack과 menu item isEnabled가 모두 false다.
    func testContextMenuDisablesPutBackWhenAnySelectedTrashEntryLacksMetadata() {
        let first = EntryModel.temporaryFolder(id: "/trash/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/trash/second", name: "second")
        let spec = EntryContextMenuSpecFactory.make(
            selectedIds: [first.id, second.id],
            selectedEntries: [first, second],
            rowEntry: first,
            isTrashFolder: true,
            restorableTrashPaths: [first.fullPath],
            canPaste: false,
            favoriteTags: [],
            openWithApplications: [],
        )
        var state = EntryViewLayoutState()
        state.entries = [first, second]
        state.selectedIds = [first.id, second.id]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(
            displayEntries: [first, second],
            selectedIds: [first.id, second.id],
            rowEntry: first,
        )
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)

        // RED: Trash menus previously enabled Put Back solely from folder location.
        let menu = EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: spec.selectedCount,
            rowEntryPathForOpenInNewWindow: nil,
            openInNewTabPaths: nil,
            serviceNames: [],
            canPaste: spec.canPaste,
            showCompress: spec.showCompress,
            showExtract: spec.showExtract,
            isTrashFolder: spec.isTrashFolder,
            canPutBack: spec.canPutBack,
            openWithApplications: spec.openWithApplications,
            showOpenWith: spec.showOpenWith,
            paletteTags: spec.paletteTags,
            knownTags: spec.knownTags,
            canPerformEntryCommands: true,
        ))

        // GREEN: all selected Trash paths must be restorable before the item enables.
        XCTAssertFalse(spec.canPutBack)
        XCTAssertEqual(menu.items.first { $0.title == "Put Back" }?.isEnabled, false)
    }

    /// EOP-004-edit_entry_tags: 캡처한 context-menu target은 현재 표시 selection과 일치할 때만 유효하다.
    /// 메뉴가 열린 뒤 selection 또는 display entry가 바뀌면 이전 대상 명령이 현재 항목에 실행되면 안 된다.
    /// - 검증 내용: EntryContextMenuTarget의 현재성 검증이 current, stale selection, missing display entry를 구분한다.
    /// - 사전 조건: 하나의 display entry와 그 entry를 캡처한 context-menu target이 있다.
    /// - 기대 결과: 동일 selection/display만 true이고 selection 변경 또는 display 제거는 false다.
    func testContextMenuTargetValidatesCapturedSelectionAndDisplayEntry() {
        let entry = EntryModel.temporaryFolder(id: "/tmp/entry", name: "entry")
        let replacement = EntryModel.temporaryFolder(id: "/tmp/replacement", name: "replacement")
        let target = EntryContextMenuTarget.resolve(
            displayEntries: [entry],
            selectedIds: [entry.id],
            rowEntry: entry,
        )

        XCTAssertTrue(target.isCurrent(displayEntries: [entry], selectedIds: [entry.id]))
        XCTAssertFalse(target.isCurrent(displayEntries: [entry], selectedIds: [replacement.id]))
        XCTAssertFalse(target.isCurrent(displayEntries: [replacement], selectedIds: [entry.id]))
    }

    /// EOP-004-edit_entry_tags: tag mutation 중인 대상의 context menu는 entry 명령을 비활성화한다.
    /// 겹치는 read-modify-write 요청을 reducer에서 거부하는 것과 함께 UI도 진행 중 상태를 명확히 표현해야 한다.
    /// - 검증 내용: target 경로 중 하나라도 busy이면 busy target으로 판정한다.
    /// - 사전 조건: 두 선택 항목 중 하나의 item operation state가 busy이다.
    /// - 기대 결과: target이 busy entry 포함 상태를 반환한다.
    func testContextMenuTargetDetectsBusySelectedEntry() {
        let first = EntryModel.temporaryFolder(id: "/tmp/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/tmp/second", name: "second")
        let target = EntryContextMenuTarget.resolve(
            displayEntries: [first, second],
            selectedIds: [first.id, second.id],
            rowEntry: first,
        )

        XCTAssertFalse(target.containsBusyEntry(busyEntryPaths: []))
        XCTAssertTrue(target.containsBusyEntry(busyEntryPaths: [second.fullPath]))
    }

    /// EOP-004-edit_entry_tags: ordinary loading 또는 busy target의 entry menu는 AppKit이 다시 활성화할 수 없다.
    /// 표시 시점의 capability가 false라면 모든 entry command가 disabled 상태를 유지해야 한다.
    /// - 검증 내용: autoenablesItems false와 disabled entry command menu item.
    /// - 사전 조건: 선택된 target이 있으나 canPerformEntryCommands가 false다.
    /// - 기대 결과: Open, Tags…, Move to Trash가 모두 비활성이다.
    func testContextMenuDisablesEntryCommandsForLoadingOrBusyTarget() {
        let entry = EntryModel.temporaryFolder(id: "/tmp/entry", name: "entry")
        var state = EntryViewLayoutState()
        state.entries = [entry]
        state.selectedIds = [entry.id]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(
            displayEntries: [entry],
            selectedIds: [entry.id],
            rowEntry: entry,
        )
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)

        // RED: NSMenu's default automatic validation could re-enable these disabled commands.
        let menu = EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: 1,
            rowEntryPathForOpenInNewWindow: entry.fullPath,
            openInNewTabPaths: nil,
            serviceNames: [],
            canPaste: false,
            showCompress: false,
            showExtract: false,
            isTrashFolder: false,
            canPutBack: false,
            openWithApplications: [],
            showOpenWith: false,
            paletteTags: [],
            knownTags: [],
            canPerformEntryCommands: false,
        ))

        // GREEN: menu policy remains disabled without AppKit auto-enablement.
        XCTAssertFalse(menu.autoenablesItems)
        for title in ["Open", "Tags…", "Move to Trash"] {
            XCTAssertEqual(menu.items.first { $0.title == title }?.isEnabled, false)
        }
    }

    /// EOP-004-edit_entry_tags: Favorite Tag swatch는 이름과 선택 상태를 접근성 정보와 동작으로 제공한다.
    /// 마우스를 사용할 수 없는 사용자도 색상만이 아니라 tag 이름과 상태를 확인하고 같은 mutation을 실행할 수 있어야 한다.
    /// - 검증 내용: swatch tooltip, accessibility label/value, press action이 동일한 tag spec을 전달한다.
    /// - 사전 조건: mixed 상태의 Favorite Tag 하나로 활성 palette를 구성한다.
    /// - 기대 결과: swatch가 tag 이름과 Mixed 상태를 노출하고 accessibility press가 selection callback을 한 번 실행한다.
    func testFavoriteTagPaletteSwatchIsAccessibleAndActionable() {
        let tag = EntryContextMenuTagSpec(name: "Red", colorCode: 6, selection: .mixed)
        var selectedTag: EntryContextMenuTagSpec?
        let palette = EntryFavoriteTagsPaletteView(tags: [tag], isEnabled: true) {
            selectedTag = $0
        }
        palette.layoutSubtreeIfNeeded()

        guard let swatch = palette.subviews.first else {
            XCTFail("Expected a Favorite Tag swatch")
            return
        }
        swatch.layoutSubtreeIfNeeded()
        XCTAssertEqual(swatch.toolTip, "Red")
        XCTAssertEqual(swatch.frame.size, NSSize(width: 28, height: 28))
        XCTAssertEqual(swatch.layer?.sublayers?.first?.frame.size, NSSize(width: 12, height: 12))
        XCTAssertEqual(swatch.accessibilityLabel(), "Red")
        XCTAssertEqual(swatch.accessibilityValue() as? String, "Mixed")
        XCTAssertTrue(swatch.accessibilityPerformPress())
        XCTAssertEqual(selectedTag?.name, "Red")
    }

    /// EOP-004-edit_entry_tags: 메뉴 폭이 커져도 Favorite Tag 버튼 간격은 고정된다.
    /// NSMenuItem.view가 메뉴 폭으로 늘어나도 tag row가 균등 분산되지 않아야 한다.
    /// - 검증 내용: palette layout 후 인접한 28px hit area 사이 간격이 2px인지 확인한다.
    /// - 사전 조건: 두 개의 Favorite Tag를 가진 palette를 메뉴 view로 사용할 수 있는 상태다.
    /// - 기대 결과: 버튼은 중앙에 배치되고 인접 버튼 간 실제 간격은 2px이다.
    func testFavoriteTagPaletteKeepsFixedSpacingWhenContainerExpands() {
        let tags = [
            EntryContextMenuTagSpec(name: "Red", colorCode: 6, selection: .off),
            EntryContextMenuTagSpec(name: "Blue", colorCode: 4, selection: .off),
        ]
        let palette = EntryFavoriteTagsPaletteView(tags: tags, isEnabled: true) { _ in }
        palette.frame.size.width = 300
        palette.layoutSubtreeIfNeeded()

        let first = palette.subviews[0].frame
        let second = palette.subviews[1].frame
        XCTAssertEqual(first.size, NSSize(width: 28, height: 28))
        XCTAssertEqual(second.minX - first.maxX, 2)
    }

    // MARK: - EOP-004-open_with_icons

    /// EOP-004-open_with_icons: 앱 URL이 있으면 Open With 메뉴 항목에 16x16 non-template 아이콘이 설정된다.
    /// applicationURL이 있는 앱은 WorkspaceClient.iconForFile로 조회한 아이콘을 메뉴에 표시해야 한다.
    /// - 검증 내용: URL 있는 앱 항목의 image가 nil이 아니고 non-template이며 16x16 크기다.
    /// - 사전 조건: applicationURL을 가진 앱 하나를 openWithApplications로 전달하고 workspaceClient.iconForFile을 mock한다.
    /// - 기대 결과: 해당 메뉴 항목에 아이콘이 설정되고 name/bundleID/state는 보존된다.
    func testOpenWithIconSetWhenApplicationURLPresent() async throws {
        let iconImage = NSImage(size: NSSize(width: 32, height: 32))
        var workspaceClient = WorkspaceClient.testValue
        workspaceClient.iconForFile = { _ in iconImage }

        let menu = buildOpenWithMenu(
            apps: [
                ApplicationInfo(
                    id: "com.apple.preview",
                    name: "Preview",
                    bundleID: "com.apple.preview",
                    isDefault: true,
                    applicationURL: URL(fileURLWithPath: "/Applications/Preview.app"),
                ),
            ],
            workspaceClient: workspaceClient,
        )

        let item = try XCTUnwrap(menu.item(withTitle: "Preview"))
        await waitForImage(on: item)
        XCTAssertNotNil(item.image)
        XCTAssertEqual(item.image?.isTemplate, false)
        XCTAssertEqual(item.image?.size, NSSize(width: 16, height: 16))
        XCTAssertEqual(item.representedObject as? String, "com.apple.preview")
        XCTAssertEqual(item.state, .on)
    }

    /// EOP-004-open_with_icons: 앱 URL이 없으면 Open With 메뉴 항목이 text-only로 남는다.
    /// applicationURL이 nil인 앱은 아이콘 조회 없이 이름만 표시해야 한다.
    /// - 검증 내용: URL 없는 앱 항목의 image가 nil이고 iconForFile이 호출되지 않는다.
    /// - 사전 조건: applicationURL이 nil인 앱을 openWithApplications로 전달하고 resolver 호출을 기록한다.
    /// - 기대 결과: 해당 메뉴 항목은 image가 없고 resolver 호출 횟수가 0이다.
    func testOpenWithIconOmittedWhenApplicationURLNil() throws {
        let resolverCallCount = LockIsolated(0)
        var workspaceClient = WorkspaceClient.testValue
        workspaceClient.iconForFile = { _ in
            resolverCallCount.withValue { $0 += 1 }
            return NSImage(size: NSSize(width: 32, height: 32))
        }

        let menu = buildOpenWithMenu(
            apps: [
                ApplicationInfo(
                    id: "com.apple.preview",
                    name: "Preview",
                    bundleID: "com.apple.preview",
                ),
            ],
            workspaceClient: workspaceClient,
        )

        let item = try XCTUnwrap(menu.item(withTitle: "Preview"))
        XCTAssertNil(item.image)
        XCTAssertEqual(resolverCallCount.value, 0)
    }

    /// EOP-004-open_with_icons: 같은 앱 URL로 메뉴를 다시 만들면 캐시된 아이콘을 재사용한다.
    /// 프로세스 수명 내 같은 standardized URL의 아이콘은 한 번만 조회하고 이후 캐시에서 재사용해야 한다.
    /// - 검증 내용: 동일 URL로 메뉴를 두 번 만들 때 iconForFile 호출 횟수가 1회로 유지된다.
    /// - 사전 조건: applicationURL을 가진 앱으로 첫 메뉴를 만들고 resolver 호출 횟수를 기록한다.
    /// - 기대 결과: 두 번째 메뉴 빌드 후에도 resolver 호출 횟수가 여전히 1이고 같은 이미지 인스턴스를 사용한다.
    func testOpenWithIconReusedFromCacheAcrossMenuBuilds() async throws {
        let iconImage = NSImage(size: NSSize(width: 32, height: 32))
        let resolverCallCount = LockIsolated(0)
        var workspaceClient = WorkspaceClient.testValue
        workspaceClient.iconForFile = { _ in
            resolverCallCount.withValue { $0 += 1 }
            return iconImage
        }
        let app = ApplicationInfo(
            id: "com.apple.preview",
            name: "Preview",
            bundleID: "com.apple.preview",
            isDefault: true,
            applicationURL: URL(fileURLWithPath: "/Applications/Preview.app"),
        )

        let firstMenu = buildOpenWithMenu(apps: [app], workspaceClient: workspaceClient)
        let firstItem = try XCTUnwrap(firstMenu.item(withTitle: "Preview"))
        await waitForImage(on: firstItem)

        let secondMenu = buildOpenWithMenu(apps: [app], workspaceClient: workspaceClient)
        let secondItem = try XCTUnwrap(secondMenu.item(withTitle: "Preview"))

        XCTAssertEqual(resolverCallCount.value, 1)
        XCTAssertIdentical(secondItem.image, firstItem.image)
    }

    /// EOP-004-open_with_icons: Open With 메뉴의 이름·정렬·Other… action은 아이콘 추가 후에도 그대로 유지된다.
    /// 아이콘 추가가 기존 Open With 계약(첫 항목 Other…, bundle ID representedObject, default checkmark)을 깨뜨리면 안 된다.
    /// - 검증 내용: Open With submenu에 Other…가 먼저 오고 앱 항목 순서와 상태가 보존된다.
    /// - 사전 조건: URL 있는 앱과 URL 없는 앱이 섞인 목록을 전달한다.
    /// - 기대 결과: Other…가 첫 항목이고 앱 항목들의 representedObject/state/image가 기대대로 유지된다.
    func testOpenWithMenuStructurePreservedWithIcons() async throws {
        let iconImage = NSImage(size: NSSize(width: 32, height: 32))
        var workspaceClient = WorkspaceClient.testValue
        workspaceClient.iconForFile = { _ in iconImage }

        let menu = buildOpenWithMenu(
            apps: [
                ApplicationInfo(
                    id: "com.apple.preview",
                    name: "Preview",
                    bundleID: "com.apple.preview",
                    isDefault: true,
                    applicationURL: URL(fileURLWithPath: "/Applications/Preview.app"),
                ),
                ApplicationInfo(id: "com.apple.textedit", name: "TextEdit", bundleID: "com.apple.textedit"),
            ],
            workspaceClient: workspaceClient,
        )

        XCTAssertEqual(menu.items.last?.title, "Other…")
        XCTAssertEqual(menu.items.count(where: { $0.title == "Other…" }), 1)
        let preview = try XCTUnwrap(menu.item(withTitle: "Preview"))
        await waitForImage(on: preview)
        XCTAssertNotNil(preview.image)
        XCTAssertEqual(preview.representedObject as? String, "com.apple.preview")
        XCTAssertEqual(preview.state, .on)
        let textEdit = try XCTUnwrap(menu.item(withTitle: "TextEdit"))
        XCTAssertNil(textEdit.image)
        XCTAssertEqual(textEdit.representedObject as? String, "com.apple.textedit")
        XCTAssertEqual(textEdit.state, .off)
    }

    private func buildOpenWithMenu(
        apps: [ApplicationInfo],
        workspaceClient: WorkspaceClient,
        isLoading: Bool = false,
    ) -> NSMenu {
        let store = Store(initialState: EntryViewLayoutState()) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(displayEntries: [], selectedIds: [], rowEntry: nil)
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)

        var menu = NSMenu()
        withDependencies {
            $0.workspaceClient = workspaceClient
        } operation: {
            let builtMenu = EntryContextMenuBuilder.makeMenu(configuration: .init(
                target: coordinator,
                selectedCount: 1,
                rowEntryPathForOpenInNewWindow: nil,
                openInNewTabPaths: nil,
                serviceNames: [],
                canPaste: false,
                showCompress: false,
                showExtract: false,
                isTrashFolder: false,
                canPutBack: false,
                openWithApplications: apps,
                showOpenWith: true,
                paletteTags: [],
                knownTags: [],
                canPerformEntryCommands: true,
                isOpenWithApplicationsLoading: isLoading,
            ))
            menu = builtMenu
        }

        guard let openWithItem = menu.items.first(where: { $0.title == "Open With" }),
              let submenu = openWithItem.submenu
        else {
            XCTFail("Expected an Open With submenu")
            return NSMenu()
        }
        return submenu
    }

    private func waitForImage(on item: NSMenuItem) async {
        for _ in 0 ..< 100 where item.image == nil {
            await Task.yield()
        }
    }

    // MARK: - EOP-004-open_in_new_tab

    /// EOP-004-open_in_new_tab: 단일 선택 폴더는 Open in New Tab 항목을 폴더 경로 payload로 표시한다
    /// 모든 선택 항목이 폴더인 유효 target에서는 Open in New Window 뒤에 New Tab 항목이 표시되어야 한다.
    /// - 검증 내용: New Tab item 존재, representedObject가 폴더 경로 배열, Open/New Window 보존
    /// - 사전 조건: 선택된 단일 폴더를 spec과 menu로 투영한다.
    /// - 기대 결과: New Tab item이 폴더 경로 payload로 렌더링되고 Open/New Window는 유지된다.
    func testContextMenuShowsOpenInNewTabForSingleFolder() throws {
        let folder = EntryModel.temporaryFolder(id: "/tmp/folder", name: "folder")
        let spec = EntryContextMenuSpecFactory.make(
            selectedIds: [folder.id],
            selectedEntries: [folder],
            rowEntry: folder,
            isTrashFolder: false,
            restorableTrashPaths: [],
            canPaste: false,
            favoriteTags: [],
            openWithApplications: [],
        )

        XCTAssertEqual(spec.openInNewTabPaths, [folder.fullPath])

        let menu = makeMenu(for: spec, folderPath: folder.fullPath)
        let newTabItem = try XCTUnwrap(menu.items.first { $0.title == "Open in New Tab" })
        XCTAssertEqual(newTabItem.representedObject as? [String], [folder.fullPath])
        XCTAssertEqual(
            newTabItem.action,
            #selector(EntryContextMenuCoordinator.contextMenuOpenInNewTab(_:)),
        )
        XCTAssertNotNil(menu.items.first { $0.title == "Open" })
        XCTAssertNotNil(menu.items.first { $0.title == "Open in New Window" })
    }

    /// EOP-004-open_in_new_tab: 여러 선택 폴더는 display 순서 그대로 Open in New Tab payload로 전달된다
    /// 복수 선택 폴더의 New Tab 항목은 선택 순서(display order)를 그대로 유지해야 한다.
    /// - 검증 내용: spec.openInNewTabPaths가 display 순서로 전달되고 menu payload도 동일하다.
    /// - 사전 조건: display 순서 [b, a]의 두 폴더가 선택되어 있다.
    /// - 기대 결과: openInNewTabPaths가 [b, a] 순서를 유지한다.
    func testContextMenuShowsOpenInNewTabForMultipleFoldersInOrder() throws {
        let folderB = EntryModel.temporaryFolder(id: "/tmp/b", name: "b")
        let folderA = EntryModel.temporaryFolder(id: "/tmp/a", name: "a")
        let spec = EntryContextMenuSpecFactory.make(
            selectedIds: [folderB.id, folderA.id],
            selectedEntries: [folderB, folderA],
            rowEntry: folderB,
            isTrashFolder: false,
            restorableTrashPaths: [],
            canPaste: false,
            favoriteTags: [],
            openWithApplications: [],
        )

        XCTAssertEqual(spec.openInNewTabPaths, [folderB.fullPath, folderA.fullPath])

        let menu = makeMenu(for: spec, folderPath: nil)
        let newTabItem = try XCTUnwrap(menu.items.first { $0.title == "Open in New Tab" })
        XCTAssertEqual(newTabItem.representedObject as? [String], [folderB.fullPath, folderA.fullPath])
    }

    /// EOP-004-open_in_new_tab: 파일 전용·혼합·빈 선택은 Open in New Tab 항목을 표시하지 않는다
    /// 모든 선택 항목이 폴더일 때만 New Tab이 유효하므로 파일/혼합/빈 target은 nil이어야 한다.
    /// - 검증 내용: file-only, mixed, empty selection 모두 openInNewTabPaths == nil이고 menu에 New Tab item이 없다.
    /// - 사전 조건: 각 케이스에 맞는 선택/entry 목록을 구성한다.
    /// - 기대 결과: 어떤 케이스도 New Tab item을 렌더링하지 않는다.
    func testContextMenuOmitsOpenInNewTabForFileMixedAndEmpty() {
        let file = EntryModel(
            name: "file.txt",
            fullPath: "/tmp/file.txt",
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: .distantPast,
            fileExtension: "txt",
            facets: .init(
                createdDate: .distantPast,
                addedDate: .distantPast,
                lastOpenedDate: nil,
                kind: "Document",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
        let folder = EntryModel.temporaryFolder(id: "/tmp/folder", name: "folder")

        let fileOnly = EntryContextMenuSpecFactory.make(
            selectedIds: [file.id],
            selectedEntries: [file],
            rowEntry: file,
            isTrashFolder: false,
            restorableTrashPaths: [],
            canPaste: false,
            favoriteTags: [],
            openWithApplications: [],
        )
        XCTAssertNil(fileOnly.openInNewTabPaths)

        let mixed = EntryContextMenuSpecFactory.make(
            selectedIds: [file.id, folder.id],
            selectedEntries: [file, folder],
            rowEntry: file,
            isTrashFolder: false,
            restorableTrashPaths: [],
            canPaste: false,
            favoriteTags: [],
            openWithApplications: [],
        )
        XCTAssertNil(mixed.openInNewTabPaths)

        let empty = EntryContextMenuSpecFactory.make(
            selectedIds: [],
            selectedEntries: [],
            rowEntry: nil,
            isTrashFolder: false,
            restorableTrashPaths: [],
            canPaste: false,
            favoriteTags: [],
            openWithApplications: [],
        )
        XCTAssertNil(empty.openInNewTabPaths)

        let menu = makeMenu(for: empty, folderPath: nil)
        XCTAssertNil(menu.items.first { $0.title == "Open in New Tab" })
    }

    // MARK: - EOP-004-show_services

    /// EOP-004-show_services: 최신 actionable Services 이름을 순서대로 context menu submenu로 투영한다.
    /// native Services menu를 reparent하지 않고 주입된 제목을 새 submenu item의 payload로 보존해야 한다.
    /// - 검증 내용: separator와 action/title 없는 후보를 제외하고 Services root 위치, 순서, title, action, representedObject를 확인한다.
    /// - 사전 조건: native menu extraction 결과를 대체하는 ordered serviceNames와 선택 target이 있다.
    /// - 기대 결과: Share…와 Reveal in Finder 사이에 exact service submenu가 표시된다.
    func testContextMenuProjectsActionableServicesInNativeOrder() throws {
        let menu = makeMenu(serviceNames: ["Mail/Compose", "Shorten", "Translate"])

        let shareIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Share…" })
        let servicesIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Services" })
        let revealIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Reveal in Finder" })
        XCTAssertEqual(servicesIndex, shareIndex + 1)
        XCTAssertEqual(revealIndex, servicesIndex + 1)

        let servicesItem = menu.items[servicesIndex]
        let submenu = try XCTUnwrap(servicesItem.submenu)
        XCTAssertEqual(submenu.items.map(\.title), ["Mail/Compose", "Shorten", "Translate"])
        for item in submenu.items {
            XCTAssertEqual(item.action, #selector(EntryContextMenuCoordinator.contextMenuPerformService(_:)))
            XCTAssertEqual(item.representedObject as? String, item.title)
        }
    }

    /// EOP-004-show_services: 서비스 후보가 없거나 target이 비어 있으면 Services root를 생략한다.
    /// 빈 projection은 native menu가 nil 또는 actionable item 없음인 상태와 동일하게 취급해야 한다.
    /// - 검증 내용: empty serviceNames와 empty target 각각 Services root가 없는지 확인한다.
    /// - 사전 조건: 서비스 제목 목록이 비어 있거나 selected target 없이 메뉴를 빌드한다.
    /// - 기대 결과: 두 메뉴 모두 Services root를 표시하지 않는다.
    func testContextMenuOmitsServicesWithoutNamesOrTarget() {
        XCTAssertNil(makeMenu(serviceNames: []).items.first { $0.title == "Services" })

        let store = Store(initialState: EntryViewLayoutState()) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(displayEntries: [], selectedIds: [], rowEntry: nil)
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)
        let menu = EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: 0,
            rowEntryPathForOpenInNewWindow: nil,
            openInNewTabPaths: nil,
            serviceNames: ["Mail/Compose"],
            canPaste: false,
            showCompress: false,
            showExtract: false,
            isTrashFolder: false,
            canPutBack: false,
            openWithApplications: [],
            showOpenWith: false,
            paletteTags: [],
            knownTags: [],
            canPerformEntryCommands: true,
        ))
        XCTAssertNil(menu.items.first { $0.title == "Services" })
    }

    /// EOP-004-show_services: 메뉴를 다시 만들면 최신 serviceNames projection을 사용한다.
    /// Services 후보를 캐시하지 않고 매 build 입력을 그대로 반영해야 한다.
    /// - 검증 내용: 서로 다른 두 serviceNames 입력이 각각 독립된 submenu를 만드는지 확인한다.
    /// - 사전 조건: 동일한 메뉴 target으로 두 번 빌드하되 서비스 제목 목록을 변경한다.
    /// - 기대 결과: 두 번째 메뉴는 첫 번째 목록이 아닌 최신 목록과 순서를 표시한다.
    func testContextMenuServicesReflectLatestBuildInput() throws {
        let first = makeMenu(serviceNames: ["First Service"])
        let second = makeMenu(serviceNames: ["Second Service", "Another Service"])

        let firstSubmenu = try XCTUnwrap(first.item(withTitle: "Services")?.submenu)
        let secondSubmenu = try XCTUnwrap(second.item(withTitle: "Services")?.submenu)
        XCTAssertEqual(firstSubmenu.items.map(\.title), ["First Service"])
        XCTAssertEqual(secondSubmenu.items.map(\.title), ["Second Service", "Another Service"])
    }

    private func makeMenu(for spec: EntryContextMenuSpec, folderPath: String?) -> NSMenu {
        let store = Store(initialState: EntryViewLayoutState()) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(displayEntries: [], selectedIds: [], rowEntry: nil)
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)
        return EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: spec.selectedCount,
            rowEntryPathForOpenInNewWindow: folderPath,
            openInNewTabPaths: spec.openInNewTabPaths,
            serviceNames: spec.serviceNames,
            canPaste: spec.canPaste,
            showCompress: spec.showCompress,
            showExtract: spec.showExtract,
            isTrashFolder: spec.isTrashFolder,
            canPutBack: spec.canPutBack,
            openWithApplications: spec.openWithApplications,
            showOpenWith: spec.showOpenWith,
            paletteTags: spec.paletteTags,
            knownTags: spec.knownTags,
            canPerformEntryCommands: true,
        ))
    }

    private func makeMenu(serviceNames: [String]) -> NSMenu {
        let store = Store(initialState: EntryViewLayoutState()) { EntryViewLayoutFeature() }
        let target = EntryContextMenuTarget.resolve(displayEntries: [], selectedIds: [], rowEntry: nil)
        let coordinator = EntryContextMenuCoordinator(store: store, target: target, anchorView: nil)
        return EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: 1,
            rowEntryPathForOpenInNewWindow: nil,
            openInNewTabPaths: nil,
            serviceNames: serviceNames,
            canPaste: false,
            showCompress: false,
            showExtract: false,
            isTrashFolder: false,
            canPutBack: false,
            openWithApplications: [],
            showOpenWith: false,
            paletteTags: [],
            knownTags: [],
            canPerformEntryCommands: true,
        ))
    }
}
