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
                NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                NSApp.keyWindow?.newWindowForTab(nil)
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Close Tab") {
                NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Close Window") {
                NSApp.keyWindow?.close()
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

        CommandGroup(after: .windowArrangement) {
            Button("Select Previous Tab") {
                NSApp.keyWindow?.selectPreviousTab(nil)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button("Select Next Tab") {
                NSApp.keyWindow?.selectNextTab(nil)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
        }
    }
}
