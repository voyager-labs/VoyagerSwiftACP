import ComposableArchitecture
@testable import Voyager
import XCTest

final class CollectionStalenessClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: CollectionKeys.stalenessRecords)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CollectionKeys.stalenessRecords)
        super.tearDown()
    }

    func testInvalidateAndConsumeClosedCollectionRecord() {
        let client = CollectionStalenessClient.liveValue
        client.registerCollection("/tmp/voyager/sample.voycoll", ["/tmp/voyager"])

        client.invalidateRecords(["/tmp/voyager/sub/a.txt"])
        XCTAssertTrue(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
        XCTAssertFalse(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
    }

    func testUnrelatedPathDoesNotInvalidateClosedCollectionRecord() {
        let client = CollectionStalenessClient.liveValue
        client.registerCollection("/tmp/voyager/sample.voycoll", ["/tmp/voyager"])

        client.invalidateRecords(["/tmp/other/a.txt"])
        XCTAssertFalse(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
    }

    func testCollectionDocumentPathDoesNotInvalidateClosedCollectionRecord() {
        let client = CollectionStalenessClient.liveValue
        client.registerCollection("/tmp/voyager/sample.voycoll", ["/tmp/voyager"])

        client.invalidateRecords(["/tmp/voyager/sample.voycoll"])
        XCTAssertFalse(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
    }

    func testCollectionPackagePayloadWriteDoesNotInvalidateClosedCollectionRecord() {
        let client = CollectionStalenessClient.liveValue
        client.registerCollection("/tmp/voyager/sample.voycoll", ["/tmp/voyager"])

        client.invalidateRecords(["/tmp/voyager/sample.voycoll/collection.plist"])
        XCTAssertFalse(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
    }
}
