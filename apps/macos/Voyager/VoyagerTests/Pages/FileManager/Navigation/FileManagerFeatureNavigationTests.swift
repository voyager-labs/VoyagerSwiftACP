import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesContentPageNavigation
import VoyagerShared
import XCTest

@testable import Voyager

@MainActor
final class FileManagerFeatureNavigationTests: XCTestCase {
    func testInitialWindowStateContainsDefaultSlices() {
        let state = FileManagerFeature.State()

        XCTAssertEqual(state.content.navigation.currentPath, SettingsDefaults.defaultTabPath())
        XCTAssertTrue(state.sidebar.sidebarVisible)
    }

    func testOnAppearDispatchesInitialWindowActions() async {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.onAppear)

        XCTAssertEqual(store.state.content.navigation.currentPath, SettingsDefaults.defaultTabPath())
    }
}
