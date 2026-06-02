import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryGridSelectionSyncTests: XCTestCase {
    func testInitialBindAppliesStoreSelectionToCollectionView() {
        let selectedEntry = EntryModel.temporaryFolder(id: "/seed/selected", name: "selected")
        let otherEntry = EntryModel.temporaryFolder(id: "/seed/other", name: "other")
        var state = EntryViewLayoutState()
        state.entries = [selectedEntry, otherEntry]
        state.selectedIds = [selectedEntry.id]

        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)

        coordinator.bind(to: view)

        XCTAssertEqual(
            view.collectionView.selectionIndexPaths,
            [IndexPath(item: 0, section: 0)],
            "Grid가 처음 bind될 때 store.selectedIds를 NSCollectionView selection으로 반영해야 함",
        )
    }

    func testGridItemCreatedAfterSelectionReflectsSelectedAppearanceState() {
        let selectedEntry = EntryModel.temporaryFolder(id: "/seed/selected", name: "selected")
        var state = EntryViewLayoutState()
        state.entries = [selectedEntry]
        state.selectedIds = [selectedEntry.id]

        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)
        let indexPath = IndexPath(item: 0, section: 0)

        coordinator.bind(to: view)
        let item = coordinator.collectionView(
            view.collectionView,
            itemForRepresentedObjectAt: indexPath,
        )

        XCTAssertTrue(
            item.isSelected,
            "Grid item이 selection 적용 뒤 생성되어도 현재 collection selection을 시각 상태로 반영해야 함",
        )
    }
}
