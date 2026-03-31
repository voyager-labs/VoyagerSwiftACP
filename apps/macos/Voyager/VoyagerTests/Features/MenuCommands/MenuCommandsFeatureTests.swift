import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class MenuCommandsFeatureTests: XCTestCase {
    func testAppCommandRoutesToWindowManagerDelegate() async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.app(.newFolder)))
        await store.receive {
            guard case .delegate(.windowManager(.file(.newFolder))) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    func testAppCommandRoutesToUpdaterDelegate() async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
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
        store.exhaustivity = .off

        await store.send(.view(.viewCommand(.toggleSidebar)))
        await store.receive {
            guard case .delegate(.windowManager(.window(.toggleSidebar))) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    func testEditCommandRoutesToWindowManagerDelegate() async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.edit(.copy)))
        await store.receive {
            guard case .delegate(.windowManager(.edit(.copy))) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    func testTask3EntryCommandsRouteToWindowManagerDelegate() async {
        let appCases: [(MenuCommandItem.AppCommand, WindowManagerAction)] = [
            (.open, .file(.open)),
            (.quickLook, .file(.quickLook)),
        ]

        for (command, expected) in appCases {
            await assertAppCommand(command, routesTo: expected)
        }

        let editCases: [(MenuCommandItem.EditCommand, WindowManagerAction)] = [
            (.cut, .edit(.cut)),
            (.copy, .edit(.copy)),
            (.paste, .edit(.paste)),
            (.duplicate, .edit(.duplicate)),
            (.makeAlias, .edit(.makeAlias)),
            (.copyAbsolutePaths, .edit(.copyAbsolutePaths)),
            (.copyURLs, .edit(.copyURLs)),
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
            guard case .window(.toggleShowHiddenFiles) = action else { return false }
            return true
        }
        await store.finish()
    }

    private func assertAppCommand(
        _ command: MenuCommandItem.AppCommand,
        routesTo expected: WindowManagerAction,
    ) async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.app(command)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            switch (action, expected) {
            case (.file(.open), .file(.open)),
                 (.file(.quickLook), .file(.quickLook)),
                 (.file(.newFolder), .file(.newFolder)),
                 (.file(.newWindow), .file(.newWindow)),
                 (.file(.newTab), .file(.newTab)),
                 (.window(.closeFocusedWindow), .window(.closeFocusedWindow)),
                 (.window(.closeAllWindows), .window(.closeAllWindows)),
                 (.window(.goBack), .window(.goBack)),
                 (.window(.goForward), .window(.goForward)),
                 (.window(.goToEnclosingDirectory), .window(.goToEnclosingDirectory)),
                 (.window(.toggleSidebar), .window(.toggleSidebar)),
                 (.window(.toggleShowHiddenFiles), .window(.toggleShowHiddenFiles)),
                 (.edit(.cut), .edit(.cut)),
                 (.edit(.copy), .edit(.copy)),
                 (.edit(.paste), .edit(.paste)),
                 (.edit(.duplicate), .edit(.duplicate)),
                 (.edit(.makeAlias), .edit(.makeAlias)),
                 (.edit(.copyAbsolutePaths), .edit(.copyAbsolutePaths)),
                 (.edit(.copyURLs), .edit(.copyURLs)):
                return true
            default:
                return false
            }
        }
        await store.finish()
    }

    private func assertEditCommand(
        _ command: MenuCommandItem.EditCommand,
        routesTo expected: WindowManagerAction,
    ) async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.edit(command)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            switch (action, expected) {
            case (.edit(.cut), .edit(.cut)),
                 (.edit(.copy), .edit(.copy)),
                 (.edit(.paste), .edit(.paste)),
                 (.edit(.duplicate), .edit(.duplicate)),
                 (.edit(.makeAlias), .edit(.makeAlias)),
                 (.edit(.copyAbsolutePaths), .edit(.copyAbsolutePaths)),
                 (.edit(.copyURLs), .edit(.copyURLs)):
                return true
            default:
                return false
            }
        }
        await store.finish()
    }
}
