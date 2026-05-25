import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import XCTest

@MainActor
/// 레이아웃 모드 상태 인코딩 회귀를 검증하는 테스트 모음이다.
final class EntryViewLayoutModeOwnershipTests: XCTestCase {
    // MARK: - 모드 원시값 테스트

    func testModeRawValues() {
        XCTAssertEqual(EntryViewLayoutState.Mode.list.rawValue, "list")
        XCTAssertEqual(EntryViewLayoutState.Mode.grid.rawValue, "grid")
    }

    /// 모드/상태 동작 회귀를 방지한다.
    func testModeFromRawValue() {
        XCTAssertEqual(EntryViewLayoutState.Mode.from("list"), .list)
        XCTAssertEqual(EntryViewLayoutState.Mode.from("grid"), .grid)
        XCTAssertNil(EntryViewLayoutState.Mode.from("invalid"))
        XCTAssertNil(EntryViewLayoutState.Mode.from(nil))
    }

    // MARK: - isGridLayout 테스트

    func testModeIsGridLayout() {
        XCTAssertFalse(EntryViewLayoutState.Mode.list.isGridLayout)
        XCTAssertTrue(EntryViewLayoutState.Mode.grid.isGridLayout)
    }

    // MARK: - 상태 모드 소유권 테스트

    func testEntryViewLayoutStateDefaultModeIsList() {
        let state = EntryViewLayoutState()
        XCTAssertEqual(state.mode, .list)
        XCTAssertFalse(state.mode.isGridLayout)
    }

    /// 모드/상태 동작 회귀를 방지한다.
    func testEntryViewLayoutStateModeCanBeChanged() {
        var state = EntryViewLayoutState()
        state.mode = .grid
        XCTAssertEqual(state.mode, .grid)
        XCTAssertTrue(state.mode.isGridLayout)

        state.mode = .list
        XCTAssertEqual(state.mode, .list)
        XCTAssertFalse(state.mode.isGridLayout)
    }

    // MARK: - FileManagerContentState 프로젝션 테스트

    func testFileManagerContentStateEntryViewLayoutModeAccess() {
        var state = FileManagerContentState()
        XCTAssertEqual(state.entryViewLayout.mode, .list)

        state.entryViewLayout.mode = .grid
        XCTAssertEqual(state.entryViewLayout.mode, .grid)

        state.entryViewLayout.mode = .list
        XCTAssertEqual(state.entryViewLayout.mode, .list)
    }

    // MARK: - Codable 테스트

    func testModeCodable() throws {
        let modes: [EntryViewLayoutState.Mode] = [.list, .grid]

        for mode in modes {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(EntryViewLayoutState.Mode.self, from: encoded)
            XCTAssertEqual(decoded, mode)
        }
    }

    /// 모드/상태 동작 회귀를 방지한다.
    func testModeDecodesFromRawValue() throws {
        let listJson = Data("\"list\"".utf8)
        let gridJson = Data("\"grid\"".utf8)

        let listMode = try JSONDecoder().decode(EntryViewLayoutState.Mode.self, from: listJson)
        let gridMode = try JSONDecoder().decode(EntryViewLayoutState.Mode.self, from: gridJson)

        XCTAssertEqual(listMode, .list)
        XCTAssertEqual(gridMode, .grid)
    }

    // MARK: - Equatable 테스트

    func testModeEquatable() {
        XCTAssertEqual(EntryViewLayoutState.Mode.list, EntryViewLayoutState.Mode.list)
        XCTAssertEqual(EntryViewLayoutState.Mode.grid, EntryViewLayoutState.Mode.grid)
        XCTAssertNotEqual(EntryViewLayoutState.Mode.list, EntryViewLayoutState.Mode.grid)
    }
}
