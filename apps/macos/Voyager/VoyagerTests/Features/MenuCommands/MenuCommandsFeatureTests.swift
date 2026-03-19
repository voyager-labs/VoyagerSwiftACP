import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class MenuCommandsFeatureTests: XCTestCase {
    func testAppCommandRoutesToWindowManagerDelegate() async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.view(.app(.newFolder)))
        await store.receive {
            guard case .delegate(.windowManager(.newFolder)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    func testAppCommandRoutesToUpdaterDelegate() async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.view(.app(.checkForUpdates)))
        await store.receive {
            guard case .delegate(.updater(.checkForUpdates)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    func testViewCommandRoutesToWindowManagerDelegate() async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.view(.viewCommand(.toggleSidebar)))
        await store.receive {
            guard case .delegate(.windowManager(.toggleSidebar)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    func testEditCommandRoutesToWindowManagerDelegate() async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.view(.edit(.copy)))
        await store.receive {
            guard case .delegate(.windowManager(.copy)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    func testTask3EntryCommandsRouteToWindowManagerDelegate() async {
        let appCases: [(MenuCommandItem.AppCommand, WindowManagerAction)] = [
            (.open, .open),
            (.quickLook, .quickLook),
        ]

        for (command, expected) in appCases {
            let store = TestStore(initialState: MenuCommandsFeature.State()) {
                MenuCommandsFeature()
            }
            store.exhaustivity = .off

            await store.send(.view(.app(command)))
            await store.receive {
                guard case let .delegate(.windowManager(action)) = $0 else { return false }
                return action == expected
            }
            await store.finish()
        }

        let editCases: [(MenuCommandItem.EditCommand, WindowManagerAction)] = [
            (.cut, .cut),
            (.copy, .copy),
            (.paste, .paste),
            (.duplicate, .duplicate),
            (.makeAlias, .makeAlias),
            (.copyAbsolutePaths, .copyAbsolutePaths),
            (.copyURLs, .copyURLs),
        ]

        for (command, expected) in editCases {
            let store = TestStore(initialState: MenuCommandsFeature.State()) {
                MenuCommandsFeature()
            }
            store.exhaustivity = .off

            await store.send(.view(.edit(command)))
            await store.receive {
                guard case let .delegate(.windowManager(action)) = $0 else { return false }
                return action == expected
            }
            await store.finish()
        }

        let viewStore = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        viewStore.exhaustivity = .off

        await viewStore.send(.view(.viewCommand(.toggleShowHiddenFiles)))
        await viewStore.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            return action == .toggleShowHiddenFiles
        }
        await viewStore.finish()
    }
}
