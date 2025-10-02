import Combine
import Foundation
import SwiftUI

/// 탭 이동 방향
enum TabDirection {
    case next
    case previous
}

/// 탭 네비게이션 관리 (선택/이동)
@MainActor
class TabNavigationManager: ObservableObject {
    @Published var selectedTabID: UUID?

    /// 탭 선택
    func selectTab(id: UUID, tabs: [TabViewModel]) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    /// 탭 이동 (다음/이전)
    func selectTab(direction: TabDirection, tabs: [TabViewModel]) {
        guard !tabs.isEmpty else { return }

        if let currentID = selectedTabID,
           let currentIndex = tabs.firstIndex(where: { $0.id == currentID })
        {
            let targetIndex: Int
            switch direction {
            case .next:
                targetIndex = (currentIndex + 1) % tabs.count
            case .previous:
                targetIndex = currentIndex > 0 ? currentIndex - 1 : tabs.count - 1
            }
            selectedTabID = tabs[targetIndex].id
        } else {
            // 선택된 탭이 없으면 방향에 따라 첫 번째 또는 마지막 탭 선택
            switch direction {
            case .next:
                selectedTabID = tabs.first?.id
            case .previous:
                selectedTabID = tabs.last?.id
            }
        }
    }

    /// 현재 선택된 탭
    func currentTab(from tabs: [TabViewModel]) -> TabViewModel? {
        tabs.first { $0.id == selectedTabID }
    }

    /// 탭이 삭제될 때 선택 상태 조정
    func adjustSelectionAfterTabRemoval(removedTabID: UUID, removedTabIndex: Int, tabs: [TabViewModel]) {
        if selectedTabID == removedTabID {
            if tabs.isEmpty {
                selectedTabID = nil
            } else {
                // 이전에 보고 있던 탭을 선택하도록 로직 개선
                let targetIndex: Int

                if removedTabIndex >= tabs.count {
                    // 제거된 탭이 마지막이었으면 이전 탭 선택
                    targetIndex = tabs.count - 1
                } else {
                    // 제거된 탭의 다음 탭 선택 (제거된 탭이 있던 자리의 탭)
                    targetIndex = removedTabIndex
                }

                selectedTabID = tabs[targetIndex].id
            }
        }
    }
}
