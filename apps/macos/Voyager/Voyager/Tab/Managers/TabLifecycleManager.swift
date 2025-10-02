import AppKit
import Combine
import Foundation
import SwiftUI

/// 탭 생명주기 관리 (생성/삭제/복제)
@MainActor
class TabLifecycleManager: ObservableObject {
    @Published var tabs: [TabViewModel] = []

    /// 새 탭 생성 (전체 플로우 관리)
    @discardableResult
    func createTab(navigationManager: TabNavigationManager, currentPath: String? = NSHomeDirectory()) -> TabViewModel {
        // 초기 경로를 기반으로 탭 제목 생성
        let initialPath = currentPath ?? NSHomeDirectory()
        let tabTitle = TabUtils.getDisplayName(for: initialPath)

        let newTab = TabModel(title: tabTitle, currentPath: currentPath)
        let vm = TabViewModel(tab: newTab)
        tabs.append(vm)

        // 새 탭을 선택
        navigationManager.selectTab(id: vm.id, tabs: tabs)

        return vm
    }

    /// 탭 닫기 (전체 플로우 관리)
    func closeTab(id: UUID, historyManager: TabHistoryManager, navigationManager: TabNavigationManager) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }

        let closedTab = tabs[index].snapshot() // ViewModel의 snapshot 사용
        tabs.remove(at: index)

        // 히스토리에 추가
        historyManager.addToHistory(closedTab)

        // 선택 상태 조정
        navigationManager.adjustSelectionAfterTabRemoval(
            removedTabID: id,
            removedTabIndex: index,
            tabs: tabs
        )

        return true
    }

    /// 탭 복제 (전체 플로우 관리)
    @discardableResult
    func duplicateTab(id: UUID, navigationManager: TabNavigationManager) -> TabViewModel? {
        guard let originalTabVM = tabs.first(where: { $0.id == id }) else { return nil }

        // TabModel을 직접 복제하여 새로운 TabViewModel 생성
        let duplicatedTab = TabModel(
            title: originalTabVM.title,
            currentPath: originalTabVM.currentPath,
            isPinned: originalTabVM.isPinned // 원본 탭의 핀 상태 그대로 복제
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
        navigationManager.selectTab(id: duplicatedVM.id, tabs: tabs)

        return duplicatedVM
    }
}
