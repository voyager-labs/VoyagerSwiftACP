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
            await assertAppCommand(command, routesTo: expected)
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
            await assertEditCommand(command, routesTo: expected)
        }

        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.viewCommand(.toggleShowHiddenFiles)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            guard case .toggleShowHiddenFiles = action else { return false }
            return true
        }
        await store.finish()
    }

    private func assertAppCommand(
        _ command: MenuCommandItem.AppCommand,
        routesTo expected: WindowManagerAction
    ) async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.app(command)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            switch (action, expected) {
            case (.open, .open), (.quickLook, .quickLook):
                return true
            default:
                return false
            }
        }
        await store.finish()
    }

    private func assertEditCommand(
        _ command: MenuCommandItem.EditCommand,
        routesTo expected: WindowManagerAction
    ) async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.edit(command)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            switch (action, expected) {
            case (.cut, .cut),
                 (.copy, .copy),
                 (.paste, .paste),
                 (.duplicate, .duplicate),
                 (.makeAlias, .makeAlias),
                 (.copyAbsolutePaths, .copyAbsolutePaths),
                 (.copyURLs, .copyURLs):
                return true
            default:
                return false
            }
        }
        await store.finish()
    }
}
