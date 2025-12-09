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
                    fileManagerStore?.send(.fsItems(.createNewFolder(currentPath: currentPath)))
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Tab") {
                AppDelegate.shared?.createNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Duplicate Tab") {
                if let fileManagerStore = fileManagerStore,
                   !fileManagerStore.fsItems.selectedIds.isEmpty
                {
                    fileManagerStore.send(.duplicateSelectedItems)
                } else {
                    AppDelegate.shared?.duplicateCurrentTab()
                }
            }
            .keyboardShortcut("d", modifiers: .command)

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
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled({
                guard let window = NSApp.keyWindow,
                      let tabGroup = window.tabGroup
                else { return true }
                return tabGroup.windows.count <= 1
            }())

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

            Button("Close All") {
                var processedTabGroups = Set<NSWindow>()

                for window in NSApp.windows {
                    if let tabGroup = window.tabGroup,
                       let firstWindow = tabGroup.windows.first
                    {
                        guard !processedTabGroups.contains(firstWindow) else { continue }
                        processedTabGroups.insert(firstWindow)
                        for tabWindow in tabGroup.windows {
                            tabWindow.close()
                        }
                    } else {
                        window.close()
                    }
                }
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
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
