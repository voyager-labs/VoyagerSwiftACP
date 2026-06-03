import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ComposerScopeCanonicalizationTests: XCTestCase {
    func testCanonicalScopeRuleKeepsNestedBasesAndPrunesInvalidExceptions() {
        let canonical = ComposerScopeUtils.canonicalizeScopeRule(
            bases: ["  /Users/test/Documents/  ", "/Users/test/Documents/Receipts", ""],
            exceptions: [
                "/Users/test/Documents/Receipts/2024",
                "/Users/test/Documents/Receipts",
                "/Users/test/Downloads",
            ],
            includeSubfolders: true,
        )

        XCTAssertEqual(canonical.bases, ["/Users/test/Documents", "/Users/test/Documents/Receipts"])
        XCTAssertEqual(canonical.exceptions, ["/Users/test/Documents/Receipts/2024"])
    }

    func testCanonicalScopeRuleDropsExceptionsOutsideBasesAndOnExactFolderMode() {
        let canonical = ComposerScopeUtils.canonicalizeScopeRule(
            bases: ["/Users/test/Documents"],
            exceptions: ["/Users/test/Documents/Receipts", "/Users/test/Downloads"],
            includeSubfolders: false,
        )

        XCTAssertEqual(canonical.bases, ["/Users/test/Documents"])
        XCTAssertEqual(canonical.exceptions, [])
    }

    func testSelectionFactoryPreservesRootOnlyWhenNoExplicitBasesRemain() {
        let selection = ComposerScopeSelection.fromCanonicalScopes(
            bases: ["/", "/Users/test/Documents"],
            exceptions: ["/Users/test/Documents/Receipts"],
            includeSubfolders: true,
        )

        XCTAssertEqual(selection, .rootOnly)
    }
}
