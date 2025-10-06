import Combine
import Foundation
import SwiftUI

/// 탭 히스토리 관리 (최근 닫은 탭)
@MainActor
class TabHistoryManager: ObservableObject {
    @Published var recentlyClosedTabs: [TabModel] = []
    private let maxRecentTabs = 10

    func addToHistory(_ tab: TabModel) {
        recentlyClosedTabs.insert(tab, at: 0)

        // 최대 개수 초과 시 오래된 것 제거
        if recentlyClosedTabs.count > maxRecentTabs {
            recentlyClosedTabs.removeLast()
        }
    }

    @discardableResult
    func restoreRecentlyClosedTab() -> TabModel? {
        guard !recentlyClosedTabs.isEmpty else { return nil }

        let restoredTab = recentlyClosedTabs.removeFirst()
        return restoredTab
    }

    /// 최근 닫은 탭이 있는지 확인
    var hasRecentlyClosedTabs: Bool {
        !recentlyClosedTabs.isEmpty
    }
}
