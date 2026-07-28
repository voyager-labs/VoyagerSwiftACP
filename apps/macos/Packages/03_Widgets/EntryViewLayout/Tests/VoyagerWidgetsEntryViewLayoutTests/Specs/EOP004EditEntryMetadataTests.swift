import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EOP004EditEntryMetadataTests: XCTestCase {
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
}
