import AppKit
import SwiftUI

/// 메뉴바 커맨드 정의
struct MenuCommands: Commands {
    @FocusedValue(\.tabManager)
    var tabManager: TabManager?

    @FocusedValue(\.isSidebarVisible)
    var isSidebarVisible: Binding<Bool>?

    private func getPinTabTitle(for tabManager: TabManager?) -> String {
        guard let tabManager = tabManager,
              let currentTab = tabManager.currentTab
        else {
            return "Pin Tab"
        }
        return currentTab.isPinned ? "Unpin Tab" : "Pin Tab"
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                tabManager?.createTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Close Window") {
                NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Button("Close Tab") {
                if let selectedID = tabManager?.selectedTabID {
                    tabManager?.closeTab(id: selectedID)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            // 기본 Close/Close All 메뉴들 제거
        }

        CommandMenu("Tabs") {
            Button("Previous Tab") {
                tabManager?.selectTab(direction: .previous)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Next Tab") {
                tabManager?.selectTab(direction: .next)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider()

            Button("Go Back") {
                if let currentTab = tabManager?.currentTab {
                    _ = currentTab.goBack()
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

            Button("Go Forward") {
                if let currentTab = tabManager?.currentTab {
                    _ = currentTab.goForward()
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])

            Divider()

            Button(getPinTabTitle(for: tabManager)) {
                if let selectedID = tabManager?.selectedTabID {
                    tabManager?.togglePin(id: selectedID)
                }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(tabManager?.selectedTabID == nil)

            Divider()

            Button("Reopen Recently Closed Tab") {
                tabManager?.restoreRecentlyClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(tabManager?.hasRecentlyClosedTabs == false)
        }

        // View 메뉴
        CommandMenu("View") {
            Button(isSidebarVisible?.wrappedValue == true ? "Hide Sidebar" : "Show Sidebar") {
                isSidebarVisible?.wrappedValue.toggle()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isSidebarVisible == nil)
        }
    }
}
