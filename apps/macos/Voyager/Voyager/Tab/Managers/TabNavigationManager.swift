import Foundation

class TabNavigationManager {
    static let shared = TabNavigationManager()

    private init() {}

    func updateNavigationHistory(for tabModel: inout TabModel, newPath: String) {
        // 현재 인덱스 이후의 히스토리 제거 (새로운 경로로 분기하는 경우)
        if tabModel.currentHistoryIndex < tabModel.navigationHistory.count - 1 {
            let keepCount = tabModel.currentHistoryIndex + 1
            tabModel.navigationHistory = Array(tabModel.navigationHistory.prefix(keepCount))
        }

        // 중복 방지: 현재 경로와 같으면 추가하지 않음
        if tabModel.navigationHistory.last != newPath {
            tabModel.navigationHistory.append(newPath)
            tabModel.currentHistoryIndex = tabModel.navigationHistory.count - 1
        }
    }

    func canGoBack(for tabModel: TabModel) -> Bool {
        // 히스토리 기반 뒤로가기 우선
        if tabModel.navigationHistory.count > 1 && tabModel.currentHistoryIndex > 0 {
            return true
        }

        // 히스토리가 없으면 부모 디렉토리 기반 뒤로가기
        return tabModel.currentPath != NSHomeDirectory()
    }

    func goBack(for tabModel: inout TabModel) -> String? {
        guard tabModel.currentHistoryIndex > 0 else { return nil }

        tabModel.currentHistoryIndex -= 1
        updateCurrentPathFromHistory(for: &tabModel)
        return getCurrentHistoryPath(for: tabModel)
    }

    func canGoForward(for tabModel: TabModel) -> Bool {
        tabModel.currentHistoryIndex < tabModel.navigationHistory.count - 1
    }

    func goForward(for tabModel: inout TabModel) -> String? {
        guard tabModel.currentHistoryIndex < tabModel.navigationHistory.count - 1 else { return nil }

        tabModel.currentHistoryIndex += 1
        updateCurrentPathFromHistory(for: &tabModel)
        return getCurrentHistoryPath(for: tabModel)
    }

    func setCurrentHistoryIndexToLast(for tabModel: inout TabModel) {
        if !tabModel.navigationHistory.isEmpty {
            tabModel.currentHistoryIndex = tabModel.navigationHistory.count - 1
        }
    }

    private func getCurrentHistoryPath(for tabModel: TabModel) -> String? {
        guard tabModel.currentHistoryIndex >= 0, tabModel.currentHistoryIndex < tabModel.navigationHistory.count else {
            return nil
        }
        return tabModel.navigationHistory[tabModel.currentHistoryIndex]
    }

    private func updateCurrentPathFromHistory(for tabModel: inout TabModel) {
        if let newPath = getCurrentHistoryPath(for: tabModel) {
            tabModel.currentPath = newPath
        }
    }
}
