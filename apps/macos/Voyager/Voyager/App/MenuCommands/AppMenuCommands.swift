import AppKit
import ComposableArchitecture
import SwiftUI

struct AppMenuCommands: Commands {
    @ObservedObject private var appDelegate: AppDelegate

    init() {
        appDelegate = AppDelegate.shared ?? AppDelegate()
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                appDelegate.checkForUpdates()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                appDelegate.createNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Folder") {
                if let currentPath = appDelegate.currentFileManagerStore?.currentPath {
                    appDelegate.currentFileManagerStore?
                        .send(.entries(.createNewFolder(currentPath: currentPath)))
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open") {
                appDelegate.currentFileManagerStore?.send(.openSelectedItem)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(appDelegate.currentFileManagerStore?.canOpenSelectedItem == false)

            Button("Quick Look") {
                appDelegate.currentFileManagerStore?.send(.quickLookSelectedItem)
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(appDelegate.currentFileManagerStore?.canQuickLookSelectedItem == false)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Collection Filter Changes") {
                appDelegate.currentFileManagerStore?.send(.composer(.saveCollection))
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled({
                guard let store = appDelegate.currentFileManagerStore else { return true }
                guard store.entries.isCollectionMode else { return true }
                return !store.canSaveCollection
            }())

            Button("Save Current Filter As New Collection") {
                appDelegate.currentFileManagerStore?.send(.composer(.saveCollectionAs))
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled({
                guard let store = appDelegate.currentFileManagerStore else { return true }
                guard store.entries.isCollectionMode else { return true }
                return !store.canSaveCollection
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
