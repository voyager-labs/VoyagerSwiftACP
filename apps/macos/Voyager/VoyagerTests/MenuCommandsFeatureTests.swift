import ComposableArchitecture
@testable import Voyager
import XCTest

@Reducer
private struct MenuCommandsHarnessFeature {
    @ObservableState
    struct State: Equatable {
        var menu = MenuCommandsFeature.State()
        var lastRoute: Route?
    }

    enum Action {
        case menu(MenuCommandsAction)
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
            guard case let .menu(.delegate(delegateAction)) = action else {
                return .none
            }

            switch delegateAction {
            case .windowManager(.newFolder):
                state.lastRoute = .windowManagerNewFolder
            case .updater(.checkForUpdates):
                state.lastRoute = .updaterCheckForUpdates
            case .windowManager(.toggleSidebar):
                state.lastRoute = .windowManagerToggleSidebar
            case .windowManager(.copy):
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

        await store.send(.menu(.view(.app(.newFolder))))
        await store.finish()

        XCTAssertEqual(store.state.lastRoute, .windowManagerNewFolder)
    }

    func testAppCommandRoutesToUpdaterDelegate() async {
        let store = TestStore(initialState: MenuCommandsHarnessFeature.State()) {
            MenuCommandsHarnessFeature()
        }

        await store.send(.menu(.view(.app(.checkForUpdates))))
        await store.finish()

        XCTAssertEqual(store.state.lastRoute, .updaterCheckForUpdates)
    }

    func testViewCommandRoutesToWindowManagerDelegate() async {
        let store = TestStore(initialState: MenuCommandsHarnessFeature.State()) {
            MenuCommandsHarnessFeature()
        }

        await store.send(.menu(.view(.viewCommand(.toggleSidebar))))
        await store.finish()

        XCTAssertEqual(store.state.lastRoute, .windowManagerToggleSidebar)
    }

    func testEditCommandRoutesToWindowManagerDelegate() async {
        let store = TestStore(initialState: MenuCommandsHarnessFeature.State()) {
            MenuCommandsHarnessFeature()
        }

        await store.send(.menu(.view(.edit(.copy))))
        await store.finish()

        XCTAssertEqual(store.state.lastRoute, .windowManagerCopy)
    }
}
