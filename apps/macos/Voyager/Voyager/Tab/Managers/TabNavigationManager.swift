import Foundation

class TabNavigationManager {
    static let shared = TabNavigationManager()

    private init() {}

    func navigateTo(for tabModel: inout TabModel, newPath: String) {
        if let currentPath = tabModel.currentPath, currentPath != newPath {
            tabModel.backHistory.append(currentPath)
        }

        // 새 경로로 이동하면 forwardHistory 초기화
        tabModel.forwardHistory.removeAll()
        tabModel.currentPath = newPath
    }

    func canGoBack(for tabModel: TabModel) -> Bool {
        if !tabModel.backHistory.isEmpty {
            return true
        }

        // backHistory가 비어있으면 홈이 아닌 경우에만 뒤로가기 가능
        return tabModel.currentPath != NSHomeDirectory()
    }

    func goBack(for tabModel: inout TabModel) -> String? {
        guard let previousPath = tabModel.backHistory.popLast() else { return nil }

        if let currentPath = tabModel.currentPath {
            tabModel.forwardHistory.append(currentPath)
        }

        tabModel.currentPath = previousPath
        return previousPath
    }

    func canGoForward(for tabModel: TabModel) -> Bool {
        !tabModel.forwardHistory.isEmpty
    }

    func goForward(for tabModel: inout TabModel) -> String? {
        guard let nextPath = tabModel.forwardHistory.popLast() else { return nil }

        if let currentPath = tabModel.currentPath {
            tabModel.backHistory.append(currentPath)
        }

        tabModel.currentPath = nextPath
        return nextPath
    }

    func initializeHistory(for tabModel: inout TabModel, initialPath: String) {
        tabModel.currentPath = initialPath
        tabModel.backHistory.removeAll()
        tabModel.forwardHistory.removeAll()
    }
}
