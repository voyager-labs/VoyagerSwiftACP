import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
/// 정렬/헤더/메뉴 동작 회귀를 검증하는 테스트 모음이다.
final class EntryListHeaderSortTests: XCTestCase {
    /// 정렬 동기화 동작 회귀를 방지한다.
    func testDateModifiedColumnDefaultsToDescendingPrototype() {
        XCTAssertFalse(EntryListColumn.dateModified.defaultSortAscending)
    }

    /// 정렬 동기화 동작 회귀를 방지한다.
    func testNonDateColumnsDefaultToAscendingPrototype() {
        XCTAssertTrue(EntryListColumn.name.defaultSortAscending)
        XCTAssertTrue(EntryListColumn.size.defaultSortAscending)
        XCTAssertTrue(EntryListColumn.kind.defaultSortAscending)
    }
}
