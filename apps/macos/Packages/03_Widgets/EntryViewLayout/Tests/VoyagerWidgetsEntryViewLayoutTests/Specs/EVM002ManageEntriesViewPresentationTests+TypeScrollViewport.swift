import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    /// EVM-002-manage_entries_view_type_scroll: grid는 mounted positive viewport에서만 첫 physical layout을 완료한다.
    ///
    /// - 검증 내용: unmounted/0×0 layout은 pending과 readiness를 보존하고, positive viewport layout만 scroll/reset한다.
    ///   이후 target은 즉시 소비되며 view replacement는 readiness를 다시 초기화한다.
    /// - 사전 조건: offscreen pending target이 bind 전에 설정되고 첫 layout들은 scroll 불가능한 geometry다.
    /// - 기대 결과: 유효 viewport 전에는 pending 유지, 유효 layout 후 실제 이동/reset, replacement 후 다시 지연된다.
    func testGridWaitsForMountedPositiveViewportBeforeCompletingPhysicalLayout() {
        let entries = (0 ..< 80).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        let initialTarget = entries[70]
        let nextTarget = entries[50]
        var state = EntryViewLayoutState()
        state.entries = entries
        state.pendingTypeScrollTargetId = initialTarget.id
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false

        view.layoutSubtreeIfNeeded()
        assertDeferred(initialTarget.id, store: store, coordinator: coordinator, view: view)

        let window = makeZeroViewportWindow(containing: view)
        view.layoutSubtreeIfNeeded()
        assertDeferred(initialTarget.id, store: store, coordinator: coordinator, view: view)

        window.setContentSize(NSSize(width: 320, height: 240))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let initialTargetOrigin = viewportOrigin(view)
        XCTAssertNil(store.state.pendingTypeScrollTargetId)
        XCTAssertTrue(coordinator.hasCompletedFirstPhysicalLayout)
        XCTAssertNotEqual(initialTargetOrigin, .zero, "positive viewport must scroll to the pending target")

        sendTypeScrollTarget(nextTarget.id, state: state, store: store, coordinator: coordinator)
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "post-layout target must consume immediately")
        XCTAssertNotEqual(viewportOrigin(view), initialTargetOrigin)

        let replacement = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.updateView(replacement)
        XCTAssertFalse(coordinator.hasCompletedFirstPhysicalLayout, "view replacement must reset readiness")
        sendTypeScrollTarget(initialTarget.id, state: state, store: store, coordinator: coordinator)
        XCTAssertEqual(store.state.pendingTypeScrollTargetId, initialTarget.id)
    }

    private func makeZeroViewportWindow(containing view: EntryGridView) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = .zero
        view.needsLayout = true
        return window
    }

    private func assertDeferred(
        _ targetID: EntryModel.ID,
        store: StoreOf<EntryViewLayoutFeature>,
        coordinator: EntryGridCoordinator,
        view: EntryGridView,
    ) {
        XCTAssertEqual(store.state.pendingTypeScrollTargetId, targetID)
        XCTAssertFalse(coordinator.hasCompletedFirstPhysicalLayout)
        XCTAssertEqual(viewportOrigin(view), .zero)
    }

    private func sendTypeScrollTarget(
        _ targetID: EntryModel.ID,
        state: EntryViewLayoutState,
        store: StoreOf<EntryViewLayoutFeature>,
        coordinator: EntryGridCoordinator,
    ) {
        store.send(.view(.setTypeScrollTarget(targetID)))
        var previousState = state
        previousState.pendingTypeScrollTargetId = nil
        var currentState = state
        currentState.pendingTypeScrollTargetId = targetID
        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: currentState),
        )
    }

    private func viewportOrigin(_ view: EntryGridView) -> CGPoint {
        view.scrollView.contentView.bounds.origin
    }
}
