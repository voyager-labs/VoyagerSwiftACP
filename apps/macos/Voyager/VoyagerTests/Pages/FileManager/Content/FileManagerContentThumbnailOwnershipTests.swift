import ComposableArchitecture
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentThumbnailOwnershipTests: XCTestCase {
    func testEntryViewLayoutThumbnailActionUsesCanonicalThumbnailHost() async {
        var state = FileManagerContentState()
        let reducer = FileManagerContentFeature()

        _ = reducer.reduce(
            into: &state,
            action: .entryViewLayout(.entryThumbnail(.thumbnailsReady(paths: ["/tmp/file1.txt"]))),
        )

        XCTAssertEqual(state.entryViewLayout.entryThumbnail.readyPaths, ["/tmp/file1.txt"])
        XCTAssertEqual(state.entryViewLayout.entryThumbnail.renderVersion, 1)
    }
}
