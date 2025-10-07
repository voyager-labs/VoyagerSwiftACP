import AppKit
import Combine
import Foundation
import SwiftUI

/// 탭 관리 통합 인터페이스 (Facade)
@MainActor
class TabManager: ObservableObject {
    private let lifecycleManager = TabLifecycleManager()
    private let layoutManager = TabLayoutManager()
    private let historyManager = TabHistoryManager()

    private var cancellables = Set<AnyCancellable>()

    // Published 프로퍼티들 (서브 매니저의 상태를 노출)
    @Published var tabs: [TabViewModel] = []
    @Published var selectedTabID: UUID?
    @Published var recentlyClosedTabs: [TabModel] = []

    var currentTab: TabViewModel? {
        TabSelectionManager.shared.currentTab(from: tabs)
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

        lifecycleManager.restorePinnedTabs()

        // 언핀 탭 무조건 생성
        createTab()
    }

    private func setupBindings() {
        lifecycleManager.$tabs
            .assign(to: &$tabs)

        // 전역 핀 상태 변경 감지 (다른 윈도우에서 핀 상태 변경 시)
        PinnedTabsManager.shared.$pinStateChanged
            .sink { [weak self] _ in
                self?.syncPinnedTabsFromGlobal()
            }
            .store(in: &cancellables)

        TabSelectionManager.shared.$selectedTabID
            .assign(to: &$selectedTabID)

        historyManager.$recentlyClosedTabs
            .assign(to: &$recentlyClosedTabs)

        // 탭 변경 시 전역 메모리 동기화
        $tabs
            .sink { [weak self] tabs in
                guard let self = self else { return }
                for tab in tabs {
                    PinnedTabsManager.shared.updateTab(tab.snapshot())
                }
            }
            .store(in: &cancellables)
    }

    @discardableResult
    func createTab(currentPath: String? = nil) -> TabViewModel {
        let path = currentPath ?? Settings.shared.defaultTabPath
        return lifecycleManager.createTab(currentPath: path)
    }

    func closeTab(id: UUID) {
        let success = lifecycleManager.closeTab(
            id: id,
            historyManager: historyManager
        )

        if success {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    @discardableResult
    func duplicateTab(id: UUID) -> TabViewModel? {
        lifecycleManager.duplicateTab(id: id)
    }

    func selectTab(id: UUID) {
        TabSelectionManager.shared.selectTab(id: id, tabs: tabs)
    }

    func selectTab(direction: TabDirection) {
        TabSelectionManager.shared.selectTab(direction: direction, tabs: tabs)
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        layoutManager.moveTab(tabs: &tabs, from: sourceIndex, to: destinationIndex)
    }

    func handleTabDragDrop(draggedTabId: UUID, translation: CGSize) {
        layoutManager.handleTabDragDrop(
            tabs: &tabs,
            draggedTabId: draggedTabId,
            translation: translation,
            pinnedTabs: pinnedTabs,
            unpinnedTabs: unpinnedTabs
        )
    }

    func moveTab(id: UUID, before targetID: UUID) {
        layoutManager.moveTab(tabs: &tabs, id: id, before: targetID)
    }

    func moveTab(id: UUID, after targetID: UUID) {
        layoutManager.moveTab(tabs: &tabs, id: id, after: targetID)
    }

    func togglePin(id: UUID) {
        layoutManager.togglePin(tabs: &tabs, id: id)
        objectWillChange.send()

        // 핀 상태 변경을 다른 윈도우에 알림
        PinnedTabsManager.shared.notifyPinStateChanged()
    }

    @discardableResult
    func restoreRecentlyClosedTab() -> TabViewModel? {
        guard let restoredTabModel = historyManager.restoreRecentlyClosedTab() else { return nil }

        let restoredVM = TabViewModel(tab: restoredTabModel)

        tabs.append(restoredVM)
        selectedTabID = restoredVM.id

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        return restoredVM
    }

    private func syncPinnedTabsFromGlobal() {
        let globalPinnedTabs = PinnedTabsManager.shared.getPinnedTabs()

        for tab in tabs where tab.isPinned {
            let globalTab = globalPinnedTabs.first { $0.id == tab.id }
            if globalTab == nil {
                tab.togglePin()
            }
        }

        for globalTab in globalPinnedTabs where !tabs.contains(where: { $0.id == globalTab.id }) {
            let vm = TabViewModel(tab: globalTab)
            tabs.append(vm)
        }
    }
}
