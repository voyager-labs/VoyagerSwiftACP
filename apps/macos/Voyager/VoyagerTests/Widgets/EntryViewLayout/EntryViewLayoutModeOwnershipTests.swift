import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class EntryViewLayoutModeOwnershipTests: XCTestCase {
    // MARK: - Mode Raw Value Tests

    func testModeRawValues() {
        XCTAssertEqual(EntryViewLayoutState.Mode.list.rawValue, "list")
        XCTAssertEqual(EntryViewLayoutState.Mode.grid.rawValue, "grid")
    }

    func testModeFromRawValue() {
        XCTAssertEqual(EntryViewLayoutState.Mode.from("list"), .list)
        XCTAssertEqual(EntryViewLayoutState.Mode.from("grid"), .grid)
        XCTAssertNil(EntryViewLayoutState.Mode.from("invalid"))
        XCTAssertNil(EntryViewLayoutState.Mode.from(nil))
    }

    // MARK: - Mode isGridLayout Tests

    func testModeIsGridLayout() {
        XCTAssertFalse(EntryViewLayoutState.Mode.list.isGridLayout)
        XCTAssertTrue(EntryViewLayoutState.Mode.grid.isGridLayout)
    }

    // MARK: - State Mode Ownership Tests

    func testEntryViewLayoutStateDefaultModeIsList() {
        let state = EntryViewLayoutState()
        XCTAssertEqual(state.mode, .list)
        XCTAssertFalse(state.mode.isGridLayout)
    }

    func testEntryViewLayoutStateModeCanBeChanged() {
        var state = EntryViewLayoutState()
        state.mode = .grid
        XCTAssertEqual(state.mode, .grid)
        XCTAssertTrue(state.mode.isGridLayout)

        state.mode = .list
        XCTAssertEqual(state.mode, .list)
        XCTAssertFalse(state.mode.isGridLayout)
    }

    // MARK: - FileManagerContentState Projection Tests

    func testFileManagerContentStateViewLayoutProjection() {
        var state = FileManagerContentState()
        XCTAssertEqual(state.viewLayout, .list)

        // Test via projection setter
        state.viewLayout = .grid
        XCTAssertEqual(state.viewLayout, .grid)
        XCTAssertEqual(state.entryViewLayout.mode, .grid)

        // Test direct mode access
        state.entryViewLayout.mode = .list
        XCTAssertEqual(state.viewLayout, .list)
    }

    // MARK: - Codable Tests

    func testModeCodable() throws {
        let modes: [EntryViewLayoutState.Mode] = [.list, .grid]

        for mode in modes {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(EntryViewLayoutState.Mode.self, from: encoded)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testModeDecodesFromRawValue() throws {
        let listJson = "\"list\"".data(using: .utf8)!
        let gridJson = "\"grid\"".data(using: .utf8)!

        let listMode = try JSONDecoder().decode(EntryViewLayoutState.Mode.self, from: listJson)
        let gridMode = try JSONDecoder().decode(EntryViewLayoutState.Mode.self, from: gridJson)

        XCTAssertEqual(listMode, .list)
        XCTAssertEqual(gridMode, .grid)
    }

    // MARK: - Equatable Tests

    func testModeEquatable() {
        XCTAssertEqual(EntryViewLayoutState.Mode.list, EntryViewLayoutState.Mode.list)
        XCTAssertEqual(EntryViewLayoutState.Mode.grid, EntryViewLayoutState.Mode.grid)
        XCTAssertNotEqual(EntryViewLayoutState.Mode.list, EntryViewLayoutState.Mode.grid)
    }
}
