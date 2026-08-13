import AppKit
import ComposableArchitecture
import SwiftUI

@ViewAction(for: MenuCommandsFeature.self)
struct AppMenuCommands: Commands {
    let store: StoreOf<MenuCommandsFeature>

    @ObservedObject private var viewStore: ViewStore<MenuCommandsState, MenuCommandsAction>

    init(appRootStore: StoreOf<AppRootFeature>) {
        let menuStore = appRootStore.scope(state: \.menuCommands, action: \.menuCommands)
        store = menuStore
        viewStore = ViewStore(
            menuStore,
            observe: { $0 },
        )
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                send(.app(.checkForUpdates))
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                send(.app(.newWindow(path: nil)))
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                send(.app(.newTab))
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(!viewStore.canOpenNewContentTab)

            Button("New Folder") {
                send(.app(.newFolder))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!viewStore.canPerformEntryCommands)

            Button("Open") {
                send(.app(.open))
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(!viewStore.canOpen)

            Button("Quick Look") {
                send(.app(.quickLook))
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!viewStore.canQuickLook)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Collection Filter Changes") {
                send(.app(.saveCollection))
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!viewStore.canSaveCollection)

            Button("Save Current Filter As New Collection") {
                send(.app(.saveCollectionAs))
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!viewStore.canSaveCollection)

            Divider()

            Button("Close Window") {
                send(.app(.closeFocusedWindow))
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(!viewStore.hasFocusedWindow)

            if viewStore.showsCloseTabCommand {
                Button(viewStore.closeTabTitle) {
                    send(.app(.closeTab))
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(!viewStore.canCloseTab)
            }

            Button(viewStore.pinTabTitle) {
                send(.app(.togglePinTab))
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(!viewStore.canPinTab)

            if viewStore.selectedContentTabCount > 1 {
                Button(viewStore.duplicateContentTabTitle) {
                    send(.app(.duplicateTab))
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!viewStore.canDuplicateSelectedContentTabs)
            } else {
                Button(viewStore.duplicateContentTabTitle) {
                    send(.app(.duplicateTab))
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!viewStore.canDuplicateActiveContentTab)
            }

            Button("Restore Last Closed Tab") {
                send(.app(.restoreLastClosedTab))
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!viewStore.canRestoreLastClosedTab)

            Button("Close All") {
                send(.app(.closeAllWindows))
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
        }

        CommandMenu("Go") {
            Button("Back") {
                send(.app(.goBack))
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!viewStore.canGoBack)

            Button("Forward") {
                send(.app(.goForward))
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!viewStore.canGoForward)

            Button("Enclosing Folder") {
                send(.app(.goToEnclosingDirectory))
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(!viewStore.canGoToEnclosingDirectory)
        }
    }
}
