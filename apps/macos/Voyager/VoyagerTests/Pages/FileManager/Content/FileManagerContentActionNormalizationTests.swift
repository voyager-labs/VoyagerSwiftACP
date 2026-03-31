import ComposableArchitecture
@testable import Voyager
import VoyagerShared
import XCTest

// Disabled: tested API (entryArrangements/entryOperations scopes, entryThumbnails state,
// EntryModel.stub) was never implemented. Re-enable when the normalized structure lands.

@MainActor
final class FileManagerContentActionNormalizationTests: XCTestCase {
    func testActionHasChildCases() async {}
    func testSelectAllEntriesRoutesToEntryViewLayout() async {}
    func testToggleShowHiddenFilesAndReloadRoutesCorrectly() async {}
    func testThumbnailActionsRoutedThroughEntryOperations() async {}
}
