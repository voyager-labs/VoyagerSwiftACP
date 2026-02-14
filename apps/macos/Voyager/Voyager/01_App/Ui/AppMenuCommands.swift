import AppKit
import ComposableArchitecture
import SwiftUI

struct AppMenuCommands: Commands {
    @ObservedObject private var viewStore: ViewStore<MenuCommandsState, MenuCommandsAction>

    init(appRootStore: StoreOf<AppRootFeature>) {
        viewStore = ViewStore(
            appRootStore.scope(state: \.menuCommands, action: \.menuCommands),
            observe: { $0 },
        )
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                viewStore.send(.perform(.app(.checkForUpdates)))
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                viewStore.send(.perform(.app(.newWindow(path: nil))))
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Folder") {
                viewStore.send(.perform(.app(.newFolder)))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!viewStore.hasFocusedWindow)

            Button("Open") {
                viewStore.send(.perform(.app(.open)))
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(!viewStore.canOpen)

            Button("Quick Look") {
                viewStore.send(.perform(.app(.quickLook)))
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!viewStore.canQuickLook)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Collection Filter Changes") {
                viewStore.send(.perform(.app(.saveCollection)))
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!viewStore.canSaveCollection)

            Button("Save Current Filter As New Collection") {
                viewStore.send(.perform(.app(.saveCollectionAs)))
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!viewStore.canSaveCollection)

            Divider()

            Button("Close Window") {
                viewStore.send(.perform(.app(.closeFocusedWindow)))
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(!viewStore.hasFocusedWindow)

            Button("Close All") {
                viewStore.send(.perform(.app(.closeAllWindows)))
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
        }

        CommandMenu("Go") {
            Button("Back") {
                viewStore.send(.perform(.app(.goBack)))
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!viewStore.canGoBack)

            Button("Forward") {
                viewStore.send(.perform(.app(.goForward)))
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!viewStore.canGoForward)

            Button("Enclosing Folder") {
                viewStore.send(.perform(.app(.goToEnclosingDirectory)))
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(!viewStore.canGoToEnclosingDirectory)
        }
    }
}
