import ComposableArchitecture
@testable import Voyager
import XCTest

// MARK: - VOY-201 Task 6: FileManagerContentAction Normalization Tests

// These tests verify that FileManagerContentAction no longer exposes the
// legacy .entries(EntryCommandAction) facade and that all actions are
// properly routed through child features.

@MainActor
final class FileManagerContentActionNormalizationTests: XCTestCase {
    // MARK: - Action Structure Tests

    /// Test that FileManagerContentAction has the expected child action cases
    func testActionHasChildCases() async {
        let state = FileManagerContentState()

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.collectionAlertClient = .testValue
            $0.fileManagerClient = .testValue
            $0.thumbnailGeneratorClient = .testValue
            $0.entryThumbnailCacheClient = .testValue
            $0.notificationCenterClient = .testValue
        }
        store.exhaustivity = .off

        // Verify child action cases exist and can be sent
        await store.send(.entryArrangements(.reapply))
        await store.send(.entryViewLayout(.view(.toggleShowHiddenFiles)))
        await store.send(.entryOperations(.loadComputerItems))
        await store.send(.composer(.delegate(.toggle)))

        await store.finish()
    }

    /// Test that selectAllEntries routes to entryViewLayout
    func testSelectAllEntriesRoutesToEntryViewLayout() async {
        var state = FileManagerContentState()
        state.entryViewLayout.entries = [
            EntryModel.stub(path: "/tmp/file1.txt"),
            EntryModel.stub(path: "/tmp/file2.txt"),
        ]

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.collectionAlertClient = .testValue
            $0.fileManagerClient = .testValue
            $0.thumbnailGeneratorClient = .testValue
            $0.entryThumbnailCacheClient = .testValue
            $0.notificationCenterClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.selectAllEntries)

        await store.finish()

        // Verify selection was applied through entryViewLayout
        XCTAssertEqual(store.state.entryViewLayout.selectedIds.count, 2)
    }

    /// Test that toggleShowHiddenFilesAndReload routes correctly
    func testToggleShowHiddenFilesAndReloadRoutesCorrectly() async {
        var state = FileManagerContentState()
        state.entryViewLayout.showHiddenFiles = false
        state.navigation.navigationState = .folder(path: "/tmp")

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.collectionAlertClient = .testValue
            $0.fileManagerClient = .testValue
            $0.thumbnailGeneratorClient = .testValue
            $0.entryThumbnailCacheClient = .testValue
            $0.notificationCenterClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.toggleShowHiddenFilesAndReload)

        await store.finish()

        // Verify showHiddenFiles was toggled
        XCTAssertTrue(store.state.entryViewLayout.showHiddenFiles)
    }

    /// Test that thumbnail actions are routed through entryOperations
    func testThumbnailActionsRoutedThroughEntryOperations() async {
        var state = FileManagerContentState()
        state.entryThumbnails.thumbnailsReady = []
        state.entryThumbnails.thumbnailRequestsInFlight = []

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.collectionAlertClient = .testValue
            $0.fileManagerClient = .testValue
            $0.thumbnailGeneratorClient = .testValue
            $0.entryThumbnailCacheClient = .testValue
            $0.notificationCenterClient = .testValue
        }
        store.exhaustivity = .off

        // Send thumbnail ready action through entryOperations
        await store.send(.entryOperations(.thumbnailsReady(paths: ["/tmp/file1.txt"])))

        await store.finish()

        // Verify thumbnail state was updated
        XCTAssertTrue(store.state.entryThumbnails.thumbnailsReady.contains("/tmp/file1.txt"))
    }
}
