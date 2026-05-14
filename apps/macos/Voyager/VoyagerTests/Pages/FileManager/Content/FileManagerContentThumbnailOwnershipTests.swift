import ComposableArchitecture
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryThumbnail
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentThumbnailOwnershipTests: XCTestCase {
    func testEntryViewLayoutThumbnailActionUsesCanonicalThumbnailHost() async {
        let store = TestStore(initialState: FileManagerContentState()) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.collectionAlertClient = .testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.notificationCenterClient = .testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = .testValue
        }

        await store.send(.entryViewLayout(.entryThumbnail(.thumbnailsReady(paths: ["/tmp/file1.txt"])))) {
            $0.entryViewLayout.entryThumbnail.readyPaths = ["/tmp/file1.txt"]
            $0.entryViewLayout.entryThumbnail.renderVersion = 1
        }
        await store.finish()

        XCTAssertEqual(store.state.entryViewLayout.entryThumbnail.readyPaths, ["/tmp/file1.txt"])
    }
}
