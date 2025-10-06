import AppKit
import Combine
import Foundation
import SwiftUI

/// 탭 생명주기 관리 (생성/삭제/복제)
@MainActor
class TabLifecycleManager: ObservableObject {
    @Published var tabs: [TabViewModel] = []

    @discardableResult
    func createTab(currentPath: String?) -> TabViewModel {
        let initialPath = currentPath ?? Settings.shared.defaultTabPath
        let tabTitle = TabUtils.getDisplayName(for: initialPath)

        let newTab = TabModel(title: tabTitle, currentPath: currentPath)
        let vm = TabViewModel(tab: newTab)

        tabs.append(vm)

        TabSelectionManager.shared.selectTab(id: vm.id, tabs: tabs)

        return vm
    }

    func closeTab(id: UUID, historyManager: TabHistoryManager) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }

        let closedTab = tabs[index].snapshot() // ViewModel의 snapshot 사용
        tabs.remove(at: index)

        historyManager.addToHistory(closedTab)

        TabSelectionManager.shared.adjustSelectionAfterTabRemoval(
            removedTabID: id,
            removedTabIndex: index,
            tabs: tabs
        )

        return true
    }

    @discardableResult
    func duplicateTab(id: UUID) -> TabViewModel? {
        guard let originalTabVM = tabs.first(where: { $0.id == id }) else { return nil }

        let duplicatedTab = TabModel(
            title: originalTabVM.title,
            currentPath: originalTabVM.currentPath,
            isPinned: originalTabVM.isPinned
        )
        let duplicatedVM = TabViewModel(tab: duplicatedTab)

        // 원본 탭 다음 위치에 삽입
        if let originalIndex = tabs.firstIndex(where: { $0.id == id }) {
            let insertIndex = originalIndex + 1
            if insertIndex < tabs.count {
                tabs.insert(duplicatedVM, at: insertIndex)
            } else {
                tabs.append(duplicatedVM)
            }
        } else {
            tabs.append(duplicatedVM)
        }

        // 복제된 탭을 선택
        TabSelectionManager.shared.selectTab(id: duplicatedVM.id, tabs: tabs)

        return duplicatedVM
    }

    func restorePinnedTabs() {
        let pinnedTabs = PinnedTabsManager.shared.loadPinnedTabs()

        for pinnedTab in pinnedTabs {
            let vm = TabViewModel(tab: pinnedTab)
            tabs.append(vm)
        }
    }
}
