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

            Divider()

            Button("Open") {
                fileManagerStore?.send(.openSelectedItem)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(fileManagerStore?.canOpenSelectedItem == false)

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

        CommandGroup(after: .sidebar) {
            Button("as List") {
                fileManagerStore?.send(.changeLayout(.list))
            }
            .disabled(fileManagerStore?.viewLayout == .list)

            Button("as Icons") {
                fileManagerStore?.send(.changeLayout(.grid))
            }
            .disabled(fileManagerStore?.viewLayout == .grid)

            Divider()

            Button(fileManagerStore?.showHiddenFiles == true ? "Hide Hidden Files" : "Show Hidden Files") {
                fileManagerStore?.send(.toggleShowHiddenFiles)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Menu("Group By") {
                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.none)) },
                    label: {
                        HStack {
                            Text("None")
                            if fileManagerStore?.fsItems.groupKey == GroupKey.none {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Divider()

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.name)) },
                    label: {
                        HStack {
                            Text("Name")
                            if fileManagerStore?.fsItems.groupKey == .name {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.kind)) },
                    label: {
                        HStack {
                            Text("Kind")
                            if fileManagerStore?.fsItems.groupKey == .kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.dateAdded)) },
                    label: {
                        HStack {
                            Text("Date Added")
                            if fileManagerStore?.fsItems.groupKey == .dateAdded {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.dateModified)) },
                    label: {
                        HStack {
                            Text("Date Modified")
                            if fileManagerStore?.fsItems.groupKey == .dateModified {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.dateCreated)) },
                    label: {
                        HStack {
                            Text("Date Created")
                            if fileManagerStore?.fsItems.groupKey == .dateCreated {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.size)) },
                    label: {
                        HStack {
                            Text("Size")
                            if fileManagerStore?.fsItems.groupKey == .size {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )
            }

            Menu("Sort By") {
                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.name)) },
                    label: {
                        HStack {
                            Text("Name")
                            if fileManagerStore?.sortKey == .name {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.kind)) },
                    label: {
                        HStack {
                            Text("Kind")
                            if fileManagerStore?.sortKey == .kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.dateAdded)) },
                    label: {
                        HStack {
                            Text("Date Added")
                            if fileManagerStore?.sortKey == .dateAdded {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.dateModified)) },
                    label: {
                        HStack {
                            Text("Date Modified")
                            if fileManagerStore?.sortKey == .dateModified {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.dateCreated)) },
                    label: {
                        HStack {
                            Text("Date Created")
                            if fileManagerStore?.sortKey == .dateCreated {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.size)) },
                    label: {
                        HStack {
                            Text("Size")
                            if fileManagerStore?.sortKey == .size {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Divider()

                Button(
                    action: { fileManagerStore?.send(.changeSortOrder(.ascending)) },
                    label: {
                        HStack {
                            Text("Ascending")
                            if fileManagerStore?.sortOrder == .ascending {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortOrder(.descending)) },
                    label: {
                        HStack {
                            Text("Descending")
                            if fileManagerStore?.sortOrder == .descending {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )
            }
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
