import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryListSortSyncTests: XCTestCase {
    func testSortDescriptorMapperDerivesTcaChange() {
        let descriptors = [NSSortDescriptor(key: EntryListColumn.size.rawValue, ascending: false)]
        let change = EntryListSortDescriptorMapper.change(from: descriptors)
        XCTAssertNotNil(change)
        guard let change else { return }

        XCTAssertEqual(change.sortKey, .size)
        XCTAssertEqual(change.sortOrder, .descending)

        let needed = EntryListSortDescriptorMapper.actionsNeeded(
            currentSortKey: .name,
            currentSortOrder: .ascending,
            change: change,
        )
        XCTAssertEqual(needed.sortKey, .size)
        XCTAssertEqual(needed.sortOrder, .descending)
    }

    func testSortSyncGateConsumesSuppressedSignature() {
        var gate = EntryListSortSyncGate()
        let descriptors = [NSSortDescriptor(key: EntryListColumn.kind.rawValue, ascending: true)]
        let signature = EntryListCoordinatorSortSignature(descriptors: descriptors)

        gate.beginApply(signature)
        let didConsumeFirst = gate.consumeIfSuppressed(signature)
        let didConsumeSecond = gate.consumeIfSuppressed(signature)
        XCTAssertTrue(didConsumeFirst)
        XCTAssertFalse(didConsumeSecond)
        gate = EntryListSortSyncGate()
    }

    func testVOY211SameIndexMoveIsNoOp() async {
        let initialColumns = EntryListColumn.defaultVisibleColumns

        let store = TestStore(initialState: {
            var state = EntryViewLayoutState()
            state.listVisibleColumns = initialColumns
            return state
        }()) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.moveListColumn(from: 1, to: 1))) { state in
            XCTAssertEqual(state.listVisibleColumns, initialColumns)
        }
    }

    func testVOY211RapidMovesKeepSingleCanonicalOrder() async {
        let store = TestStore(initialState: {
            var state = EntryViewLayoutState()
            state.listVisibleColumns = [.name, .dateModified, .size, .kind]
            return state
        }()) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.moveListColumn(from: 3, to: 1))) { state in
            XCTAssertEqual(state.listVisibleColumns, [.name, .kind, .dateModified, .size])
        }

        await store.send(.internal(.moveListColumn(from: 2, to: 4))) { state in
            XCTAssertEqual(state.listVisibleColumns, [.name, .kind, .size, .dateModified])
        }

        await store.send(.internal(.moveListColumn(from: 3, to: 0))) { state in
            XCTAssertEqual(state.listVisibleColumns, [.dateModified, .name, .kind, .size])
            XCTAssertEqual(Set(state.listVisibleColumns), Set(EntryListColumn.defaultVisibleColumns))
        }
    }

    func testVOY211RightmostDropUsesFinalAppKitIndex() async {
        let store = TestStore(initialState: {
            var state = EntryViewLayoutState()
            state.listVisibleColumns = [.name, .dateModified, .size, .kind]
            return state
        }()) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.moveListColumn(from: 1, to: 3))) { state in
            XCTAssertEqual(state.listVisibleColumns, [.name, .size, .kind, .dateModified])
        }
    }

    func testVOY211AdjacentRightMoveIsNotSwallowed() async {
        let store = TestStore(initialState: {
            var state = EntryViewLayoutState()
            state.listVisibleColumns = [.name, .dateModified, .size, .kind]
            return state
        }()) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.moveListColumn(from: 1, to: 2))) { state in
            XCTAssertEqual(state.listVisibleColumns, [.name, .size, .dateModified, .kind])
        }
    }

    func testVOY211DateModifiedDefaultsToDescendingSortPrototype() {
        XCTAssertFalse(EntryListColumn.dateModified.defaultSortAscending)
    }

    func testVOY211NonDateColumnsDefaultToAscendingSortPrototype() {
        XCTAssertTrue(EntryListColumn.name.defaultSortAscending)
        XCTAssertTrue(EntryListColumn.size.defaultSortAscending)
        XCTAssertTrue(EntryListColumn.kind.defaultSortAscending)
    }
}
