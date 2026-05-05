import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared
import XCTest

// MARK: - VOY-201 Task 5: FileManagerSidebarAction Normalization Tests

// These tests verify that FileManagerSidebarAction uses the normalized action structure
// with view/internal/delegate cases following the TCA action taxonomy conventions.

@MainActor
final class FileManagerSidebarActionNormalizationTests: XCTestCase {
    // MARK: - Action Structure Tests

    /// Test that FileManagerSidebarAction has the expected view/internal/delegate cases
    func testActionHasViewInternalDelegateCases() async {
        let state = FileManagerSidebarState()

        let store = TestStore(initialState: state) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }
        store.exhaustivity = .off

        // Verify view actions exist and can be sent
        await store.send(.view(.setSidebarVisible(true)))
        await store.send(.view(.toggleFavoritesSection))
        await store.send(.view(.toggleLocationsSection))
        await store.send(.view(.toggleTagsSection))

        await store.finish()
    }

    /// Test that sidebar width is clamped to 150...400 range
    func testSidebarWidthClamp() async {
        let state = FileManagerSidebarState()

        let store = TestStore(initialState: state) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }
        store.exhaustivity = .off

        // Test width below minimum (should clamp to 150)
        await store.send(.view(.setSidebarWidth(50)))
        await store.finish()
        XCTAssertEqual(store.state.sidebarWidth, 150, "Width should be clamped to minimum 150")

        // Test width above maximum (should clamp to 400)
        await store.send(.view(.setSidebarWidth(500)))
        await store.finish()
        XCTAssertEqual(store.state.sidebarWidth, 400, "Width should be clamped to maximum 400")

        // Test valid width (should remain unchanged)
        await store.send(.view(.setSidebarWidth(250)))
        await store.finish()
        XCTAssertEqual(store.state.sidebarWidth, 250, "Valid width should be preserved")
    }

    /// Test that pendingSidebarSelectionRestore is properly handled
    func testPendingSidebarSelectionRestore() async {
        var state = FileManagerSidebarState()
        state.pendingSidebarSelectionRestore = "favorite:/Users/test"

        let store = TestStore(initialState: state) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }
        store.exhaustivity = .off

        // Send restore action
        await store.send(.internal(.restoreSidebarSelection))
        await store.finish()

        // Verify selection was restored and pending flag cleared
        XCTAssertEqual(store.state.selectedSidebarItem, "favorite:/Users/test", "Selection should be restored")
        XCTAssertNil(store.state.pendingSidebarSelectionRestore, "Pending restore should be cleared after restore")
    }

    /// Test that delegate actions exist for parent-owned intents
    func testDelegateActionsExist() async {
        let state = FileManagerSidebarState()

        let store = TestStore(initialState: state) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }
        store.exhaustivity = .off

        // Verify delegate actions can be sent (actual routing is handled by parent)
        let favoriteItem = SidebarItems.FavoriteItem(
            name: "Test",
            url: URL(fileURLWithPath: "/tmp"),
            iconName: "folder",
        )
        await store.send(.delegate(.openFavorite(favoriteItem)))

        await store.send(.delegate(.showRecents))
        await store.send(.delegate(.showComputer))

        await store.finish()
    }

    /// Test that internal actions for loading exist
    func testInternalLoadingActions() async {
        let state = FileManagerSidebarState()

        let store = TestStore(initialState: state) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }
        store.exhaustivity = .off

        // Test favorites loading flow
        await store.send(.internal(.loadFavorites))
        await store.finish()

        // Test locations loading flow
        await store.send(.internal(.loadLocations))
        await store.finish()

        // Test tags loading flow
        await store.send(.internal(.loadTags))
        await store.finish()
    }
}
