import Foundation
@testable import Voyager
import XCTest

@MainActor
final class EntryListSortSyncTests: XCTestCase {
    func testSortDescriptorMapperDerivesTcaChange() {
        let descriptors = [NSSortDescriptor(key: EntryListColumn.size.rawValue, ascending: false)]
        let change = EntryListSortDescriptorMapper.change(from: descriptors)
        XCTAssertNotNil(change)
        guard let change else { return }

        XCTAssertEqual(change.sortKey, .size)
        XCTAssertEqual(change.sortOrder, .descending)

        let needed = EntryListSortDescriptorMapper.actionsNeeded(
            currentSortKey: .name,
            currentSortOrder: .ascending,
            change: change,
        )
        XCTAssertEqual(needed.sortKey, .size)
        XCTAssertEqual(needed.sortOrder, .descending)
    }

    func testSortSyncGateConsumesSuppressedSignature() {
        var gate = EntryListSortSyncGate()
        let descriptors = [NSSortDescriptor(key: EntryListColumn.kind.rawValue, ascending: true)]
        let signature = EntryListSortDescriptorSignature(descriptors: descriptors)

        gate.beginApply(signature)
        let didConsumeFirst = gate.consumeIfSuppressed(signature)
        let didConsumeSecond = gate.consumeIfSuppressed(signature)
        XCTAssertTrue(didConsumeFirst)
        XCTAssertFalse(didConsumeSecond)
        gate = EntryListSortSyncGate()
    }
}
