import Foundation
import VoyagerEntitiesCollection
@testable import VoyagerPagesFileManager
import XCTest

final class BuiltInContentTabPinnedRecordSeedPolicyTests: XCTestCase {
    func testSemanticPresenceAndClassificationOwnStableIdentity() {
        let applicationSupportURL = URL(fileURLWithPath: "/Application Support", isDirectory: true)
        let descriptor = BuiltInContentTabPinnedRecordSeedPolicy.VerifiedDescriptor(
            identity: .recents,
            canonicalPackageURL: BuiltInCollectionIdentity.recents.canonicalPackageURL(
                applicationSupportURL: applicationSupportURL,
            ),
        )
        let stableRecord = ContentTabPinnedRecord(
            id: "built-in-collection-recents",
            page: .collection,
            anchor: .collectionFile(url: descriptor.canonicalPackageURL),
            title: "Recents",
            iconName: "clock",
            pinnedAt: Date(timeIntervalSince1970: 443),
        )
        let canonicalURLResidue = ContentTabPinnedRecord(
            id: "legacy",
            page: .collection,
            anchor: .collectionFile(url: descriptor.canonicalPackageURL),
            title: nil,
            iconName: nil,
            pinnedAt: Date(timeIntervalSince1970: 443),
        )
        let store = ContentTabPinnedRecordStore(records: [stableRecord])

        XCTAssertTrue(BuiltInContentTabPinnedRecordSeedPolicy.containsCanonicalRecord(
            in: store,
            descriptor: descriptor,
        ))
        XCTAssertEqual(
            BuiltInContentTabPinnedRecordSeedPolicy.classify(
                stableRecord,
                applicationSupportURL: nil,
            ),
            .recents,
        )
        XCTAssertEqual(
            BuiltInContentTabPinnedRecordSeedPolicy.classify(
                canonicalURLResidue,
                applicationSupportURL: applicationSupportURL,
            ),
            .recents,
        )
    }
}
