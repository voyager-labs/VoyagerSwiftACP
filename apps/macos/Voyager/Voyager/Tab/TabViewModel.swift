import Combine
import Foundation
import SwiftUI

@MainActor
class TabViewModel: ObservableObject, Identifiable {
    @Published private(set) var tab: TabModel

    var id: UUID { tab.id }
    var title: String { tab.title }
    var isPinned: Bool { tab.isPinned }
    var currentPath: String? { tab.currentPath }
    var navigationHistory: [String] { tab.navigationHistory }
    var currentHistoryIndex: Int { tab.currentHistoryIndex }

    init(tab: TabModel) {
        self.tab = tab
    }

    func updateTitle(_ newTitle: String) {
        TabStateManager.shared.updateTabTitle(for: &tab, newTitle: newTitle)
        objectWillChange.send()
    }

    func updatePath(_ newPath: String?) {
        TabStateManager.shared.updateTabPath(for: &tab, newPath: newPath)
        objectWillChange.send()
    }

    func togglePin() {
        TabStateManager.shared.toggleTabPin(for: &tab)
        objectWillChange.send()
    }

    func goBack() -> String? {
        let result = TabNavigationManager.shared.goBack(for: &tab)
        objectWillChange.send()
        return result
    }

    func goForward() -> String? {
        let result = TabNavigationManager.shared.goForward(for: &tab)
        objectWillChange.send()
        return result
    }

    func canGoBack() -> Bool {
        TabNavigationManager.shared.canGoBack(for: tab)
    }

    func canGoForward() -> Bool {
        TabNavigationManager.shared.canGoForward(for: tab)
    }

    func updateNavigationHistory(newPath: String) {
        TabNavigationManager.shared.updateNavigationHistory(for: &tab, newPath: newPath)
        objectWillChange.send()
    }

    func updateTabContent(currentPath: String, initialPath: String) {
        TabStateManager.shared.updateTabContent(for: &tab, currentPath: currentPath, initialPath: initialPath)
        objectWillChange.send()
    }

    func setCurrentHistoryIndexToLast() {
        TabNavigationManager.shared.setCurrentHistoryIndexToLast(for: &tab)
        objectWillChange.send()
    }

    func initializeTabContent(targetPath: String) {
        // TabStateManager에 초기화 로직 위임
        TabStateManager.shared.initializeTabContent(for: &tab, targetPath: targetPath)
        objectWillChange.send()
    }

    func snapshot() -> TabModel {
        tab
    }
}
