import Foundation
@testable import VoyagerPagesFileManager
import XCTest

final class FileManagerFavoritesPinnedRecordMapperTests: XCTestCase {
    func testCollectionPackageFavoriteMapsToCollectionBeforeDirectory() throws {
        let collectionURL = URL(fileURLWithPath: "/Users/test/Research.voycoll")
        let favorite = SidebarItems.FavoriteItem(
            name: "Research.voycoll",
            url: collectionURL,
            iconName: "folder",
        )

        let record = try XCTUnwrap(
            FileManagerFavoritesPinnedRecordMapper.pinnedRecords(
                from: [favorite],
                pinnedAt: Date(timeIntervalSince1970: 1_234_567_890),
                fileExistsWithIsDirectory: { _, isDirectory in
                    isDirectory?.pointee = ObjCBool(true)
                    return true
                },
            ).first,
        )

        XCTAssertEqual(record.page, .collection)
        XCTAssertEqual(record.anchor, .collectionFile(url: collectionURL))
    }
}
