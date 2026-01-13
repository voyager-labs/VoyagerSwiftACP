import AppKit
import ComposableArchitecture
import SwiftUI

struct AppMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                AppDelegate.shared?.checkForUpdates()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                AppDelegate.shared?.createNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Folder") {
                if let currentPath = AppDelegate.shared?.currentFileManagerStore?.currentPath {
                    AppDelegate.shared?.currentFileManagerStore?
                        .send(.fsItems(.createNewFolder(currentPath: currentPath)))
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open") {
                AppDelegate.shared?.currentFileManagerStore?.send(.openSelectedItem)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(AppDelegate.shared?.currentFileManagerStore?.canOpenSelectedItem == false)

            Button("Quick Look") {
                AppDelegate.shared?.currentFileManagerStore?.send(.quickLookSelectedItem)
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(AppDelegate.shared?.currentFileManagerStore?.canQuickLookSelectedItem == false)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Collection Filter Changes") {
                AppDelegate.shared?.currentFileManagerStore?.send(.composer(.saveCollection))
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled({
                guard let store = AppDelegate.shared?.currentFileManagerStore else { return true }
                guard store.fsItems.isCollectionMode, store.openedCollectionURL != nil else { return true }
                return !store.isOpenedCollectionDirty
            }())

            Button("Save Current Filter As New Collection") {
                AppDelegate.shared?.currentFileManagerStore?.send(.composer(.saveCollectionAs))
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled({
                guard let store = AppDelegate.shared?.currentFileManagerStore else { return true }
                guard store.fsItems.isCollectionMode, store.collectionContext != nil else { return true }
                if store.openedCollectionURL == nil { return false }
                return !store.isOpenedCollectionDirty
            }())

            Divider()

            Button("Close Window") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut("w", modifiers: .command)

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
                AppDelegate.shared?.currentFileManagerStore?.send(.goBack)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(AppDelegate.shared?.currentFileManagerStore?.canGoBack == false)

            Button("Forward") {
                AppDelegate.shared?.currentFileManagerStore?.send(.goForward)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(AppDelegate.shared?.currentFileManagerStore?.canGoForward == false)

            Button("Enclosing Folder") {
                AppDelegate.shared?.currentFileManagerStore?.send(.goToEnclosingDirectory)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(AppDelegate.shared?.currentFileManagerStore?.canGoToEnclosingDirectory == false)
        }
    }
}
