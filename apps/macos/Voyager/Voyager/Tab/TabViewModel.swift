import Combine
import Foundation
import SwiftUI

/// 개별 탭의 어댑터 (Model ↔ View 연결)
@MainActor
class TabViewModel: ObservableObject, Identifiable {
    @Published private(set) var tab: TabModel

    var id: UUID { tab.id }
    var title: String { tab.title }
    var isPinned: Bool { tab.isPinned }
    var currentPath: String? { tab.currentPath }

    init(tab: TabModel) {
        self.tab = tab
    }

    /// 탭 제목 업데이트
    func updateTitle(_ newTitle: String) {
        tab.title = newTitle
        objectWillChange.send()
    }

    /// 탭 경로 업데이트
    func updatePath(_ newPath: String?) {
        tab.currentPath = newPath
        objectWillChange.send()
    }

    /// 탭 핀 상태 토글
    func togglePin() {
        tab.isPinned.toggle()
        objectWillChange.send()
    }

    /// 현재 스냅샷을 반환 (히스토리 저장용)
    func snapshot() -> TabModel {
        tab
    }
}
