import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryThumbnail
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
/// FileManager 썸네일 액션이 엔트리 뷰레벨 소유권을 통해 전달되는지 검증한다.
final class FileManagerContentThumbnailOwnershipTests: XCTestCase {
    /// testEntryViewLayoutThumbnailActionUsesCanonicalThumbnailHost 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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
