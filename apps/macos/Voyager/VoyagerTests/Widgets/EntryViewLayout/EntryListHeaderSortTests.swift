import Foundation
@testable import Voyager
@testable import VoyagerWidgetsEntryViewLayout
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
