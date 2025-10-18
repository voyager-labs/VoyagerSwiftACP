import AppKit
import ComposableArchitecture
import SwiftUI

struct MenuCommands: Commands {
    @FocusedValue(\.fileManagerStore)
    var fileManagerStore: StoreOf<FileManagerFeature>?

    @FocusedValue(\.columnVisibility)
    var columnVisibility: Binding<NavigationSplitViewVisibility>?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                AppDelegate.shared?.createNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                AppDelegate.shared?.createNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Duplicate Tab") {
                AppDelegate.shared?.duplicateCurrentTab()
            }
            .keyboardShortcut("d", modifiers: .command)

            Divider()

            Button("Close Tab") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Close Window") {
                if let window = NSApp.keyWindow,
                   let tabGroup = window.tabGroup
                {
                    for tabWindow in tabGroup.windows {
                        tabWindow.close()
                    }
                } else {
                    NSApp.keyWindow?.close()
                }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .sidebar) {
            Button(columnVisibility?.wrappedValue == .all ? "Hide Sidebar" : "Show Sidebar") {
                let current = columnVisibility?.wrappedValue
                columnVisibility?.wrappedValue = (current == .all) ? .detailOnly : .all
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(columnVisibility == nil)
        }

        CommandMenu("Go") {
            Button("Back") {
                fileManagerStore?.send(.goBack)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(fileManagerStore?.canGoBack == false)

            Button("Forward") {
                fileManagerStore?.send(.goForward)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(fileManagerStore?.canGoForward == false)
        }
    }
}
