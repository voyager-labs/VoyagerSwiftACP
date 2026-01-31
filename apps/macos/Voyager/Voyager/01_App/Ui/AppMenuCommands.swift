import AppKit
import ComposableArchitecture
import SwiftUI

struct AppMenuCommands: Commands {
    @ObservedObject private var fileManagerWindowCoordinator: FileManagerWindowCoordinator
    private let appDelegate: AppDelegate?

    init() {
        fileManagerWindowCoordinator = FileManagerWindowCoordinator.shared
        appDelegate = AppDelegate.shared
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                appDelegate?.checkForUpdates()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                fileManagerWindowCoordinator.createNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Folder") {
                if let currentPath = fileManagerWindowCoordinator.currentFileManagerStore?.currentPath {
                    fileManagerWindowCoordinator.currentFileManagerStore?
                        .send(.entries(.createNewFolder(currentPath: currentPath)))
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open") {
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.entries(.openSelectedItem))
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(fileManagerWindowCoordinator.currentFileManagerStore?.canOpenSelectedItem == false)

            Button("Quick Look") {
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.entries(.quickLookSelectedItem))
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(fileManagerWindowCoordinator.currentFileManagerStore?.canQuickLookSelectedItem == false)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Collection Filter Changes") {
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.composer(.saveCollection))
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled({
                guard let store = fileManagerWindowCoordinator.currentFileManagerStore else { return true }
                guard store.entries.isCollectionMode else { return true }
                return !store.canSaveCollection
            }())

            Button("Save Current Filter As New Collection") {
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.composer(.saveCollectionAs))
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled({
                guard let store = fileManagerWindowCoordinator.currentFileManagerStore else { return true }
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
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.goBack)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(fileManagerWindowCoordinator.currentFileManagerStore?.canGoBack == false)

            Button("Forward") {
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.goForward)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(fileManagerWindowCoordinator.currentFileManagerStore?.canGoForward == false)

            Button("Enclosing Folder") {
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.goToEnclosingDirectory)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(fileManagerWindowCoordinator.currentFileManagerStore?.canGoToEnclosingDirectory == false)
        }
    }
}
