import AppKit
import Foundation
import SwiftUI

/// 탭 레이아웃 관리 (순서/위치/핀/제목)
class TabLayoutManager {
    /// 탭 순서 이동 (드래그 앤 드롭용)
    func moveTab(tabs: inout [TabViewModel], from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex <= tabs.count
        else {
            return
        }

        let movingTab = tabs[sourceIndex]
        // 먼저 제거하고, 인덱스 보정 후 삽입
        tabs.remove(at: sourceIndex)
        var insertIndex = destinationIndex
        if sourceIndex < destinationIndex { insertIndex -= 1 }
        insertIndex = max(0, min(insertIndex, tabs.count))
        tabs.insert(movingTab, at: insertIndex)
    }

    /// 내부 헬퍼: 대상 탭 앞/뒤로 이동 (제거 후 대상 인덱스 재탐색)
    private func moveTabRelative(tabs: inout [TabViewModel], to targetID: UUID, movingID: UUID, placeBefore: Bool) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == movingID }) else { return }
        let moving = tabs[sourceIndex]
        tabs.remove(at: sourceIndex)

        guard let targetIndexNow = tabs.firstIndex(where: { $0.id == targetID }) else {
            // 대상이 사라졌으면 맨 끝으로
            tabs.append(moving)
            return
        }

        let insertIndex = placeBefore ? targetIndexNow : min(targetIndexNow + 1, tabs.count)
        tabs.insert(moving, at: insertIndex)
    }

    func moveTab(tabs: inout [TabViewModel], id: UUID, before targetID: UUID) {
        moveTabRelative(tabs: &tabs, to: targetID, movingID: id, placeBefore: true)
    }

    func moveTab(tabs: inout [TabViewModel], id: UUID, after targetID: UUID) {
        moveTabRelative(tabs: &tabs, to: targetID, movingID: id, placeBefore: false)
    }

    func togglePin(tabs: inout [TabViewModel], id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        tabs[index].togglePin()

        // 핀 상태로 변경 시 현재 경로를 히스토리에 추가하고 마지막 인덱스로 설정
        if tabs[index].isPinned {
            // 현재 경로를 히스토리에 추가 (중복 방지)
            if let currentPath = tabs[index].currentPath,
               tabs[index].navigationHistory.last != currentPath
            {
                tabs[index].updateNavigationHistory(newPath: currentPath)
            }
            tabs[index].setCurrentHistoryIndexToLast()
        }

        // 핀 상태에 따라 탭 재정렬
        let pinnedTabs = tabs.filter { $0.isPinned }
        let unpinnedTabs = tabs.filter { !$0.isPinned }
        tabs = pinnedTabs + unpinnedTabs

        // 핀 상태를 UserDefaults에 저장
        let tabModels = tabs.map { $0.snapshot() }
        PinnedTabsManager.shared.savePinnedTabs(tabModels)
    }

    func pinnedTabs(from tabs: [TabViewModel]) -> [TabViewModel] {
        tabs.filter { $0.isPinned }
    }

    func unpinnedTabs(from tabs: [TabViewModel]) -> [TabViewModel] {
        tabs.filter { !$0.isPinned }
    }

    /// 드래그 앤 드롭으로 탭 이동 처리
    func handleTabDragDrop(
        tabs: inout [TabViewModel],
        draggedTabId: UUID,
        translation: CGSize,
        pinnedTabs: [TabViewModel],
        unpinnedTabs: [TabViewModel]
    ) {
        let allTabs = pinnedTabs + unpinnedTabs
        guard let currentIndex = allTabs.firstIndex(where: { $0.id == draggedTabId }) else {
            return
        }

        // 드래그 거리가 충분한지 확인 (최소 20px)
        guard abs(translation.height) > 20 else {
            return
        }

        // 드래그 방향에 따라 이동할 위치 계산
        let targetIndex: Int
        if translation.height > 0 {
            // 아래로 드래그: 다음 탭 앞으로 이동
            targetIndex = min(currentIndex + 1, allTabs.count - 1)
        } else {
            // 위로 드래그: 이전 탭 앞으로 이동
            targetIndex = max(currentIndex - 1, 0)
        }

        // 같은 위치면 무시
        guard targetIndex != currentIndex else {
            return
        }

        let draggedTab = allTabs[currentIndex]
        let targetTab = allTabs[targetIndex]

        // 핀 상태가 다르면 핀 상태 변경
        if targetTab.isPinned != draggedTab.isPinned {
            togglePin(tabs: &tabs, id: draggedTabId)
        }

        // 탭 순서 이동
        moveTab(
            tabs: &tabs,
            from: currentIndex,
            to: translation.height > 0 ? targetIndex : targetIndex
        )
    }
}
