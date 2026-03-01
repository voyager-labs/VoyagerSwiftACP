import ComposableArchitecture
@testable import Voyager
import XCTest

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
        store.exhaustivity = .off

        await store.send(.onAppear)

        XCTAssertEqual(store.state.content.navigation.currentPath, SettingsDefaults.defaultTabPath())
    }
}
