@testable import Voyager
import XCTest

@MainActor
final class ScopePickerCandidateFallbackTests: XCTestCase {
    func testApplyCandidateDisambiguationPolicyFallsBackToAbsoluteParentWhenSameStorageSuffixCollides() {
        let items = [
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Work/Projects/Docs",
                path: "/Users/me/Work/Projects/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Users/me/Work/Projects",
            ),
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Work/Projects/Docs Copy",
                path: "/Users/me/Work/Projects/Docs Copy",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Users/me/Work/Projects",
            ),
        ]

        let result = ComposerScopeUtils.applyCandidateDisambiguationPolicy(items)

        XCTAssertEqual(result.map(\.secondaryText), ["/Users/me/Work/Projects", "/Users/me/Work/Projects"])
    }

    func testApplyCandidateDisambiguationPolicyHandlesRootParentWithoutEmptyParentKey() {
        let items = [
            ComposerScopeUtils.DirectoryItem(
                id: "/Downloads-A",
                path: "/Downloads-A",
                name: "Downloads",
                iconName: "folder",
                locationIdentifier: "/",
            ),
            ComposerScopeUtils.DirectoryItem(
                id: "/Downloads-B",
                path: "/Downloads-B",
                name: "Downloads",
                iconName: "folder",
                locationIdentifier: "/",
            ),
        ]

        let result = ComposerScopeUtils.applyCandidateDisambiguationPolicy(items)

        XCTAssertEqual(result.map(\.secondaryText), ["/", "/"])
    }
}
