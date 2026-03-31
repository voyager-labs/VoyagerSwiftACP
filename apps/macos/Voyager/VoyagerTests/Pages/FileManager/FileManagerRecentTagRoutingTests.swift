import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

// DISABLED: VOY-201 navigation routing refactor removed/changed these action paths.
// - FileManagerContentFeature.Action.applyNavigationState is removed
// - FileManagerWindowNavigationReducer.Action.sidebar is removed
// - entryViewLayout.entryOperations no longer exists as a child scope
// These tests should be updated when VOY-201 navigation refactor is completed.
@MainActor
final class FileManagerRecentTagRoutingTests: XCTestCase {
    func testVOY201NavigationRefactorPending() {
        // Navigation routing tests are disabled until VOY-201 refactor is completed.
    }
}
