import ComposableArchitecture
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared
import XCTest

// MARK: - VOY-201 Task 5: Sidebar-Local Guardrail Tests

// These tests lock down local owner behavior for sidebar width clamping and restore-selection cleanup.
// Focused on sidebar-local concern regression guardrails only.
// NOT testing: parent navigation/content routing, delegate migration (handled in Task 4).

@MainActor
final class FileManagerSidebarFeatureTests: XCTestCase {
    // MARK: - Width Clamp Tests

    /// Test that sidebar width is clamped to lower bound (150) when value is below minimum.
    /// Guardrail: Values below 150 must be clamped to 150.
    func testSetSidebarWidth_ClampsToLowerBound() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // Send width below minimum (100), expect clamp to 150
        await store.send(.view(.setSidebarWidth(100))) { state in
            state.sidebarWidth = 150
        }

        await store.finish()
    }

    /// Test that sidebar width is clamped to upper bound (400) when value is above maximum.
    /// Guardrail: Values above 400 must be clamped to 400.
    func testSetSidebarWidth_ClampsToUpperBound() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // Send width above maximum (500), expect clamp to 400
        await store.send(.view(.setSidebarWidth(500))) { state in
            state.sidebarWidth = 400
        }

        await store.finish()
    }

    /// Test that width change within 0.5 of current value is ignored (no state change).
    /// Guardrail: Early return for sub-threshold changes prevents unnecessary state churn.
    func testSetSidebarWidth_IgnoresSmallChanges() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // Send width within 0.5 of current (220.3), expect no state change
        await store.send(.view(.setSidebarWidth(220.3)))

        await store.finish()
    }

    /// Test that valid width within bounds is preserved.
    /// Guardrail: Values in 150...400 range are preserved.
    func testSetSidebarWidth_PreservesValidWidth() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // Send valid width (300), expect state change
        await store.send(.view(.setSidebarWidth(300))) { state in
            state.sidebarWidth = 300
        }

        await store.finish()
    }

    // MARK: - Restore Selection Tests

    /// Test that restoreSidebarSelection clears pending flag after restoring.
    /// Guardrail: pendingSidebarSelectionRestore must be nil after restore action.
    func testRestoreSidebarSelection_ClearsPendingRestore() async {
        var initialState = FileManagerSidebarState()
        initialState.pendingSidebarSelectionRestore = "favorite:/Users/test"

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // Send restore action, expect state changes
        await store.send(.internal(.restoreSidebarSelection)) { state in
            state.selectedSidebarItem = "favorite:/Users/test"
            state.pendingSidebarSelectionRestore = nil
        }

        await store.finish()
    }

    /// Test that restoreSidebarSelection does nothing when pending is nil.
    /// Guardrail: No crash or unexpected state change when pending is nil.
    func testRestoreSidebarSelection_DoesNothingWhenPendingIsNil() async {
        let initialState = FileManagerSidebarState()

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // Send restore action when pending is nil, expect no state change
        await store.send(.internal(.restoreSidebarSelection))

        await store.finish()
    }

    /// Test that restoreSidebarSelection preserves existing selection when pending is nil.
    /// Guardrail: Existing selectedSidebarItem must not be overwritten when pending is nil.
    func testRestoreSidebarSelection_PreservesExistingSelectionWhenPendingIsNil() async {
        var initialState = FileManagerSidebarState()
        initialState.selectedSidebarItem = "location:/Applications"
        initialState.pendingSidebarSelectionRestore = nil

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // Send restore action when pending is nil, expect no state change
        await store.send(.internal(.restoreSidebarSelection))

        await store.finish()
    }

    // MARK: - Tag Loading Tests (VOY-208 Task 1)

    /// Test that loadTags action updates state.tags with favoriteTags from client.
    /// Expected: loadTags → tagsLoaded → state.tags updated
    func testLoadTags_UpdatesStateWithFavoriteTags() async {
        let initialState = FileManagerSidebarState()

        // Mock favoriteTags to return specific tags with color codes
        let expectedTags = [
            Tag(name: "Important", colorCode: 1),
            Tag(name: "Work", colorCode: 6),
            Tag(name: "Personal", colorCode: 5),
        ]
        let expectedTagNames = expectedTags.map { tag in tag.name }

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { expectedTagNames },
                favoriteTags: { expectedTags },
            )
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // loadTags triggers tagsLoaded synchronously with the result from favoriteTags()
        await store.send(.internal(.loadTags)) { state in
            state.tags = expectedTags
        }

        await store.finish()
    }

    /// Test that loadTags with empty favoriteTags results in empty state.tags.
    /// Expected: Empty tags → state.tags = []
    func testLoadTags_WithEmptyFavoriteTags_SetsEmptyTags() async {
        let initialState = FileManagerSidebarState()

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { [] },
                favoriteTags: { [] },
            )
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.internal(.loadTags)) { state in
            state.tags = []
        }

        await store.finish()
    }

    /// Test that loadTags preserves color codes from favoriteTags client.
    /// Expected: Tags with color codes are preserved exactly
    func testLoadTags_PreservesColorCodes() async {
        let initialState = FileManagerSidebarState()

        // TagColor.rawValue: Red=6, Orange=7, Yellow=5, Green=2, Blue=4, Purple=3, Gray=1
        let expectedTags = [
            Tag(name: "Red", colorCode: 6),
            Tag(name: "Orange", colorCode: 7),
            Tag(name: "Yellow", colorCode: 5),
            Tag(name: "Green", colorCode: 2),
            Tag(name: "Blue", colorCode: 4),
            Tag(name: "Purple", colorCode: 3),
            Tag(name: "Gray", colorCode: 1),
        ]
        let expectedTagNames = expectedTags.map { tag in tag.name }

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { expectedTagNames },
                favoriteTags: { expectedTags },
            )
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.internal(.loadTags)) { state in
            state.tags = expectedTags
            // Verify color codes are preserved
            XCTAssertEqual(state.tags.map(\.colorCode), [6, 7, 5, 2, 4, 3, 1])
        }

        await store.finish()
    }

    /// Test that tagsLoaded action directly sets state.tags.
    /// Expected: tagsLoaded with tags → state.tags = tags
    func testTagsLoaded_SetsStateTags() async {
        var initialState = FileManagerSidebarState()
        initialState.tags = [Tag(name: "Old", colorCode: 0)]

        let newTags = [
            Tag(name: "New1", colorCode: 3),
            Tag(name: "New2", colorCode: 4),
        ]

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.internal(.tagsLoaded(newTags))) { state in
            state.tags = newTags
        }

        await store.finish()
    }

    // MARK: - Seam Separation Tests (VOY-335 Task 2)

    /// Verify preference seam only affects preference fields.
    /// Sends .view(.setSidebarVisible(false)) and confirms only sidebarVisible changed.
    func testPreferenceSeamOnlyAffectsPreferenceFields() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = true
        initialState.sidebarWidth = 220
        initialState.favorites = [
            SidebarItems.FavoriteItem(
                name: "Test",
                url: URL(fileURLWithPath: "/Test"),
                iconName: "folder",
            ),
        ]
        initialState.contextMenuTargetId = "some-id"
        initialState.contextMenuTargetWasSelected = true

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
            XCTAssertEqual(state.sidebarWidth, 220)
            XCTAssertEqual(state.favorites.count, 1)
            XCTAssertEqual(state.contextMenuTargetId, "some-id")
            XCTAssertTrue(state.contextMenuTargetWasSelected)
        }

        await store.finish()
    }

    /// Verify source loading seam only affects source fields.
    /// Sends .internal(.favoritesLoaded) and confirms only favorites changed.
    func testSourceLoadingSeamOnlyAffectsSourceFields() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = false
        initialState.sidebarWidth = 300
        initialState.contextMenuTargetId = "target-x"
        initialState.contextMenuTargetWasSelected = true

        let newFavorite = SidebarItems.FavoriteItem(
            name: "Loaded",
            url: URL(fileURLWithPath: "/Loaded"),
            iconName: "folder",
        )

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.internal(.favoritesLoaded([newFavorite]))) { state in
            state.favorites = [newFavorite]
            // Verify preference/interaction fields untouched
            XCTAssertFalse(state.sidebarVisible)
            XCTAssertEqual(state.sidebarWidth, 300)
            XCTAssertEqual(state.contextMenuTargetId, "target-x")
            XCTAssertTrue(state.contextMenuTargetWasSelected)
        }

        await store.finish()
    }

    /// Verify interaction seam only affects interaction fields.
    /// Sends .view(.setContextMenuTarget) and confirms only context menu state changed.
    func testInteractionSeamOnlyAffectsInteractionFields() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = true
        initialState.sidebarWidth = 250
        initialState.favorites = [
            SidebarItems.FavoriteItem(
                name: "Fav",
                url: URL(fileURLWithPath: "/Fav"),
                iconName: "folder",
            ),
        ]

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.view(.setContextMenuTarget(id: "ctx-42", wasSelected: true))) { state in
            state.contextMenuTargetId = "ctx-42"
            state.contextMenuTargetWasSelected = true
            // Verify preference/source fields untouched
            XCTAssertTrue(state.sidebarVisible)
            XCTAssertEqual(state.sidebarWidth, 250)
            XCTAssertEqual(state.favorites.count, 1)
        }

        await store.finish()
    }

    /// Verify shell contract fields remain accessible after decomposition.
    /// Confirms sidebarVisible and sidebarWidth are readable/writable via state.
    func testShellContractFieldsRemainAccessible() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = false
        initialState.sidebarWidth = 180

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // Verify initial values are readable
        XCTAssertEqual(store.state.sidebarVisible, false)
        XCTAssertEqual(store.state.sidebarWidth, 180)

        await store.finish()
    }
}
