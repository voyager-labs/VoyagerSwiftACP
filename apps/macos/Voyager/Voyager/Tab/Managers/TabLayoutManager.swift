import AppKit
import Combine
import Foundation
import SwiftUI

/// 탭 레이아웃 관리 (순서/위치/핀/제목)
@MainActor
class TabLayoutManager: ObservableObject {
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

    /// 탭 ID로 순서 이동
    func moveTab(tabs: inout [TabViewModel], id: UUID, to targetIndex: Int) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        moveTab(tabs: &tabs, from: sourceIndex, to: targetIndex)
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

    /// 탭을 다른 탭 앞/뒤로 이동
    func moveTab(tabs: inout [TabViewModel], id: UUID, before targetID: UUID) {
        moveTabRelative(tabs: &tabs, to: targetID, movingID: id, placeBefore: true)
    }

    func moveTab(tabs: inout [TabViewModel], id: UUID, after targetID: UUID) {
        moveTabRelative(tabs: &tabs, to: targetID, movingID: id, placeBefore: false)
    }

    /// 탭 핀/언핀 토글
    func togglePin(tabs: inout [TabViewModel], id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        // 탭의 핀 상태 토글
        tabs[index].togglePin()

        // 핀 상태에 따라 탭 재정렬
        let pinnedTabs = tabs.filter { $0.isPinned }
        let unpinnedTabs = tabs.filter { !$0.isPinned }
        tabs = pinnedTabs + unpinnedTabs
    }

    /// 탭 제목 업데이트 (경로 변경 시)
    func updateTabTitle(tabs: inout [TabViewModel], id: UUID, currentPath: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let newTitle = TabUtils.getDisplayName(for: currentPath ?? NSHomeDirectory())
        tabs[index].updateTitle(newTitle)
    }

    /// 핀된 탭들
    func pinnedTabs(from tabs: [TabViewModel]) -> [TabViewModel] {
        tabs.filter { $0.isPinned }
    }

    /// 일반 탭들
    func unpinnedTabs(from tabs: [TabViewModel]) -> [TabViewModel] {
        tabs.filter { !$0.isPinned }
    }
}
