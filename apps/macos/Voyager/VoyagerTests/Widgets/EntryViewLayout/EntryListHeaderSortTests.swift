import Foundation
@testable import Voyager
import XCTest

@MainActor
final class EntryListHeaderSortTests: XCTestCase {
    func testDateModifiedColumnDefaultsToDescendingPrototype() {
        XCTAssertFalse(EntryListColumn.dateModified.defaultSortAscending)
    }

    func testNonDateColumnsDefaultToAscendingPrototype() {
        XCTAssertTrue(EntryListColumn.name.defaultSortAscending)
        XCTAssertTrue(EntryListColumn.size.defaultSortAscending)
        XCTAssertTrue(EntryListColumn.kind.defaultSortAscending)
    }
}
