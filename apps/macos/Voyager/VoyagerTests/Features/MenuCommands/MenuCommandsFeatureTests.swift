import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
@Reducer
private struct MenuCommandsHarnessFeature {
    @MainActor
    @ObservableState
    struct State: Equatable {
        var menu = MenuCommandsFeature.State()
        var lastRoute: Route?
    }

    enum Action: Equatable {
        case menu(MenuCommandsAction)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.menu(.delegate(.windowManager(.newFolder))), .menu(.delegate(.windowManager(.newFolder)))):
                true
            case (.menu(.delegate(.updater(.checkForUpdates))), .menu(.delegate(.updater(.checkForUpdates)))):
                true
            case (.menu(.delegate(.windowManager(.toggleSidebar))), .menu(.delegate(.windowManager(.toggleSidebar)))):
                true
            case (.menu(.delegate(.windowManager(.copy))), .menu(.delegate(.windowManager(.copy)))):
                true
            default:
                false
            }
        }
    }

    enum Route: Equatable {
        case windowManagerNewFolder
        case updaterCheckForUpdates
        case windowManagerToggleSidebar
        case windowManagerCopy
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.menu, action: \.menu) {
            MenuCommandsFeature()
        }

        Reduce { state, action in
            switch action {
            case .menu(.view(.app(.newFolder))):
                state.lastRoute = .windowManagerNewFolder
            case .menu(.view(.app(.checkForUpdates))):
                state.lastRoute = .updaterCheckForUpdates
            case .menu(.view(.viewCommand(.toggleSidebar))):
                state.lastRoute = .windowManagerToggleSidebar
            case .menu(.view(.edit(.copy))):
                state.lastRoute = .windowManagerCopy
            default:
                break
            }

            return .none
        }
    }
}

@MainActor
final class MenuCommandsFeatureTests: XCTestCase {
    func testAppCommandRoutesToWindowManagerDelegate() async {
        let store = TestStore(initialState: MenuCommandsHarnessFeature.State()) {
            MenuCommandsHarnessFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.menu(.view(.app(.newFolder))))
        await store.receive(.menu(.delegate(.windowManager(.newFolder))))

        XCTAssertEqual(store.state.lastRoute, .windowManagerNewFolder)
    }

    func testAppCommandRoutesToUpdaterDelegate() async {
        let store = TestStore(initialState: MenuCommandsHarnessFeature.State()) {
            MenuCommandsHarnessFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.menu(.view(.app(.checkForUpdates))))
        await store.receive(.menu(.delegate(.updater(.checkForUpdates))))

        XCTAssertEqual(store.state.lastRoute, .updaterCheckForUpdates)
    }

    func testViewCommandRoutesToWindowManagerDelegate() async {
        let store = TestStore(initialState: MenuCommandsHarnessFeature.State()) {
            MenuCommandsHarnessFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.menu(.view(.viewCommand(.toggleSidebar))))
        await store.receive(.menu(.delegate(.windowManager(.toggleSidebar))))

        XCTAssertEqual(store.state.lastRoute, .windowManagerToggleSidebar)
    }

    func testEditCommandRoutesToWindowManagerDelegate() async {
        let store = TestStore(initialState: MenuCommandsHarnessFeature.State()) {
            MenuCommandsHarnessFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.menu(.view(.edit(.copy))))
        await store.receive(.menu(.delegate(.windowManager(.copy))))

        XCTAssertEqual(store.state.lastRoute, .windowManagerCopy)
    }
}
