// FLOW-ID: rcl.collection_condition_editing
@testable import VoyagerFeaturesComposer
import XCTest

@MainActor
final class CollectionConditionEditingFlowTests: XCTestCase {
    // FLOW-PATH: property_picker_host

    func testPropertyPickerHostPolicyUsesNativeMenu() {
        XCTAssertEqual(
            ComposerPickerHostPolicy.host(for: .property),
            .nativeMenu,
        )
    }

    // FLOW-PATH: operator_boolean_unit_hosts

    func testOperatorBooleanUnitHostPolicyUsesNativeMenus() {
        XCTAssertEqual(ComposerPickerHostPolicy.host(for: .operator), .nativeMenu)
        XCTAssertEqual(ComposerPickerHostPolicy.host(for: .boolean), .nativeMenu)
        XCTAssertEqual(ComposerPickerHostPolicy.host(for: .unit), .nativeMenu)
    }

    // FLOW-PATH: token_picker_host

    func testTokenPickerHostPolicyUsesAnchoredDropdown() {
        XCTAssertEqual(
            ComposerPickerHostPolicy.host(for: .token),
            .anchoredDropdown,
        )
    }

    // FLOW-PATH: date_picker_host

    func testDatePickerHostPolicyUsesAnchoredDropdown() {
        XCTAssertEqual(
            ComposerPickerHostPolicy.host(for: .date),
            .anchoredDropdown,
        )
    }

    // FLOW-PATH: ordinary_value_picker_host

    func testOrdinaryValuePickerHostPolicyUsesInlineEditing() {
        XCTAssertEqual(
            ComposerPickerHostPolicy.host(for: .value),
            .inline,
        )
    }

    // FLOW-PATH: condition_picker_composition

    func testOpenConditionPickerHostRoutesThroughFileManagerComposer() {
        XCTAssertEqual(
            ComposerPickerHostPolicy.presentationOwner(for: .property),
            .fileManagerComposer,
        )
    }
}
