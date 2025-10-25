import AppKit
import ComposableArchitecture
import SwiftUI

struct MenuCommands: Commands {
    @FocusedValue(\.fileManagerStore)
    var fileManagerStore: StoreOf<FileManagerFeature>?

    @FocusedValue(\.columnVisibility)
    var columnVisibility: Binding<NavigationSplitViewVisibility>?

    @State private var hasClosedTabs: Bool = false
    @State private var hasFocusHistory: Bool = false

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
