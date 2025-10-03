import AppKit
import Combine
import Foundation
import SwiftUI

/// 탭 관리 통합 인터페이스 (Facade)
@MainActor
class TabManager: ObservableObject {
    // 서브 매니저들
    private let lifecycleManager = TabLifecycleManager()
    private let navigationManager = TabNavigationManager()
    private let layoutManager = TabLayoutManager()
    private let historyManager = TabHistoryManager()

    // Published 프로퍼티들 (서브 매니저의 상태를 노출)
    @Published var tabs: [TabViewModel] = []
    @Published var selectedTabID: UUID?
    @Published var recentlyClosedTabs: [TabModel] = []

    var currentTab: TabViewModel? {
        navigationManager.currentTab(from: tabs)
    }

    var pinnedTabs: [TabViewModel] {
        layoutManager.pinnedTabs(from: tabs)
    }

    var unpinnedTabs: [TabViewModel] {
        layoutManager.unpinnedTabs(from: tabs)
    }

    var hasRecentlyClosedTabs: Bool {
        historyManager.hasRecentlyClosedTabs
    }

    init() {
        // 서브 매니저들의 상태를 메인 매니저에 동기화
        setupBindings()

        // 초기 탭 생성
        createTab()
    }

    /// 서브 매니저들의 상태를 메인 매니저에 바인딩
    private func setupBindings() {
        // lifecycleManager의 tabs 변경을 감지하여 메인 tabs에 반영
        lifecycleManager.$tabs
            .assign(to: &$tabs)

        // navigationManager의 selectedTabID 변경을 감지하여 메인 selectedTabID에 반영
        navigationManager.$selectedTabID
            .assign(to: &$selectedTabID)

        // historyManager의 recentlyClosedTabs 변경을 감지하여 메인 recentlyClosedTabs에 반영
        historyManager.$recentlyClosedTabs
            .assign(to: &$recentlyClosedTabs)
    }

    /// 새 탭 생성
    @discardableResult
    func createTab(currentPath: String? = nil) -> TabViewModel {
        let path = currentPath ?? SettingManager.shared.defaultTabPath
        return lifecycleManager.createTab(navigationManager: navigationManager, currentPath: path)
    }

    /// 탭 닫기
    func closeTab(id: UUID) {
        // LifecycleManager에서 전체 close 플로우 처리
        let success = lifecycleManager.closeTab(
            id: id,
            historyManager: historyManager,
            navigationManager: navigationManager
        )

        // UI 업데이트 트리거
        if success {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    /// 탭 복제
    @discardableResult
    func duplicateTab(id: UUID) -> TabViewModel? {
        lifecycleManager.duplicateTab(id: id, navigationManager: navigationManager)
    }

    /// 탭 선택
    func selectTab(id: UUID) {
        navigationManager.selectTab(id: id, tabs: tabs)
    }

    /// 탭 이동 (다음/이전)
    func selectTab(direction: TabDirection) {
        navigationManager.selectTab(direction: direction, tabs: tabs)
    }

    /// 탭 순서 이동 (드래그 앤 드롭용)
    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        layoutManager.moveTab(tabs: &tabs, from: sourceIndex, to: destinationIndex)
    }

    /// 탭 ID로 순서 이동
    func moveTab(id: UUID, to targetIndex: Int) {
        layoutManager.moveTab(tabs: &tabs, id: id, to: targetIndex)
    }

    /// 탭을 다른 탭 앞/뒤로 이동
    func moveTab(id: UUID, before targetID: UUID) {
        layoutManager.moveTab(tabs: &tabs, id: id, before: targetID)
    }

    func moveTab(id: UUID, after targetID: UUID) {
        layoutManager.moveTab(tabs: &tabs, id: id, after: targetID)
    }

    /// 탭 핀/언핀 토글
    func togglePin(id: UUID) {
        layoutManager.togglePin(tabs: &tabs, id: id)
    }

    /// 탭 제목 업데이트 (경로 변경 시)
    func updateTabTitle(id: UUID, currentPath: String?) {
        layoutManager.updateTabTitle(tabs: &tabs, id: id, currentPath: currentPath)

        // TabManager 레벨에서 UI 업데이트 트리거
        objectWillChange.send()
    }

    /// 최근 닫은 탭을 복원
    @discardableResult
    func restoreRecentlyClosedTab() -> TabViewModel? {
        guard let restoredTabModel = historyManager.restoreRecentlyClosedTab() else { return nil }

        let restoredVM = TabViewModel(tab: restoredTabModel)

        // 복원된 탭을 현재 탭 목록에 추가
        tabs.append(restoredVM)
        selectedTabID = restoredVM.id

        // 메뉴 즉시 업데이트
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        return restoredVM
    }
}
