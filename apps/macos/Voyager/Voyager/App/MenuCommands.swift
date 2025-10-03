import AppKit
import SwiftUI

/// 메뉴바 커맨드 정의
struct MenuCommands: Commands {
    @FocusedValue(\.tabManager)
    var tabManager: TabManager?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                tabManager?.createTab()
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            // 기본 Close/Close All 메뉴들 제거
        }

        CommandGroup(after: .newItem) {
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

        CommandMenu("Tab") {
            Button("Previous Tab") {
                tabManager?.selectTab(direction: .previous)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Next Tab") {
                tabManager?.selectTab(direction: .next)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider()

            Button("Reopen Recently Closed Tab") {
                tabManager?.restoreRecentlyClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(tabManager?.hasRecentlyClosedTabs == false)
        }
    }
}

struct TabManagerKey: FocusedValueKey {
    typealias Value = TabManager
}

extension FocusedValues {
    var tabManager: TabManager? {
        get { self[TabManagerKey.self] }
        set { self[TabManagerKey.self] = newValue }
    }
}
