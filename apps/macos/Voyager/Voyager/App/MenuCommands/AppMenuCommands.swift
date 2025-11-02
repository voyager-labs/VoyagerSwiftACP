import AppKit
import ComposableArchitecture
import SwiftUI

struct AppMenuCommands: Commands {
    @FocusedValue(\.fileManagerStore)
    var fileManagerStore: StoreOf<FileManagerFeature>?

    @State private var hasClosedTabs: Bool = false
    @State private var hasFocusHistory: Bool = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                AppDelegate.shared?.createNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Folder") {
                if let currentPath = fileManagerStore?.currentPath {
                    fileManagerStore?.send(.fsItems(.operations(.createNewFolder(path: currentPath))))
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Tab") {
                AppDelegate.shared?.createNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Duplicate Tab") {
                AppDelegate.shared?.duplicateCurrentTab()
            }

            Divider()

            Button("Open") {
                fileManagerStore?.send(.openSelectedItem)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(fileManagerStore?.canOpenSelectedItem == false)

            Button("Quick Look") {
                fileManagerStore?.send(.quickLookSelectedItem)
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(fileManagerStore?.canQuickLookSelectedItem == false)

            Button("Reopen Recently Closed Tab") {
                AppDelegate.shared?.reopenLastClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!hasClosedTabs)
            .onReceive(NotificationCenter.default.publisher(for: .closedTabsChanged)) { _ in
                hasClosedTabs = !(AppDelegate.shared?.closedTabHistory.isEmpty ?? true)
            }
            .onAppear {
                hasClosedTabs = !(AppDelegate.shared?.closedTabHistory.isEmpty ?? true)
            }

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

            Divider()
        }

        CommandMenu("Go") {
            Button("Back") {
                fileManagerStore?.send(.goBack)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(fileManagerStore?.canGoBack == false)

            Button("Forward") {
                fileManagerStore?.send(.goForward)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(fileManagerStore?.canGoForward == false)

            Divider()

            Button("Enclosing Folder") {
                fileManagerStore?.send(.goToEnclosingDirectory)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(fileManagerStore?.canGoToEnclosingDirectory == false)
        }

        CommandGroup(after: .windowList) {
            Button("Switch Focus to Last Focused Tab") {
                AppDelegate.shared?.switchToLastFocusedTab()
            }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled(!hasFocusHistory)
            .onReceive(NotificationCenter.default.publisher(for: .focusHistoryChanged)) { _ in
                hasFocusHistory = AppDelegate.shared?.hasValidFocusHistory ?? false
            }
            .onAppear {
                hasFocusHistory = AppDelegate.shared?.hasValidFocusHistory ?? false
            }
        }
    }
}
