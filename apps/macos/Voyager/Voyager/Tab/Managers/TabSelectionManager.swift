import Combine
import Foundation
import SwiftUI

enum TabDirection {
    case next
    case previous
}

@MainActor
class TabSelectionManager: ObservableObject {
    static let shared = TabSelectionManager()

    @Published var selectedTabID: UUID?

    private init() {}

    func selectTab(id: UUID, tabs: [TabViewModel]) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

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

    func currentTab(from tabs: [TabViewModel]) -> TabViewModel? {
        tabs.first { $0.id == selectedTabID }
    }

    func adjustSelectionAfterTabRemoval(removedTabID: UUID, removedTabIndex: Int, tabs: [TabViewModel]) {
        if selectedTabID == removedTabID {
            if tabs.isEmpty {
                selectedTabID = nil
            } else {
                let targetIndex: Int

                if removedTabIndex >= tabs.count {
                    targetIndex = tabs.count - 1
                } else {
                    targetIndex = removedTabIndex
                }

                selectedTabID = tabs[targetIndex].id
            }
        }
    }
}
