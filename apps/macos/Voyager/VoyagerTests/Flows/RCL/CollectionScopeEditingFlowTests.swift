// FLOW-ID: rcl.collection_scope_editing
@testable import VoyagerFeaturesComposer
import XCTest

@MainActor
final class CollectionScopeEditingFlowTests: XCTestCase {
    // FLOW-PATH: scope_picker_host

    func testScopePickerHostPolicyRetainsCustomPanel() {
        XCTAssertEqual(
            ComposerPickerHostPolicy.host(for: .scope),
            .customPanel,
        )
    }

    // FLOW-PATH: open_scope_composition

    func testOpenScopeHostRoutesThroughFileManagerComposerComposition() {
        XCTAssertEqual(
            ComposerPickerHostPolicy.presentationOwner(for: .scope),
            .fileManagerComposer,
        )
    }

    // FLOW-PATH: close_scope_composition

    func testCloseScopeHostPreservesComposerPresentationOwnership() {
        XCTAssertEqual(
            ComposerPickerHostPolicy.presentationOwner(for: .scope),
            .fileManagerComposer,
        )
    }
}
