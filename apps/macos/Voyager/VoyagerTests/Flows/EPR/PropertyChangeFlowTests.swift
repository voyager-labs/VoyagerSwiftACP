// FLOW-ID: epr.property_change
import ComposableArchitecture
import VoyagerFeaturesEntryProperties
import XCTest

@MainActor
final class PropertyChangeFlowTests: XCTestCase {
    // FLOW-PATH: public_feature_composition

    func testPublicFeatureConstructsAndComposes() {
        let selection = EntryPropertiesSelection(
            targets: [EntryPropertiesTarget(localPath: "/tmp/example")],
            propertyID: EntryPropertiesPropertyID(rawValue: "0198f7f8-81d8-7d25-b17a-81feaa76a1c4"),
        )
        let store = TestStore(
            initialState: EntryPropertiesFeature.State(selection: selection),
        ) {
            EntryPropertiesFeature()
        }

        XCTAssertEqual(store.state.selection, selection)
        XCTAssertEqual(store.state.status, .idle)
    }
}
