import Foundation

class TabStateManager {
    static let shared = TabStateManager()

    private init() {}

    func updateTabTitle(for tabModel: inout TabModel, newTitle: String) {
        tabModel.title = newTitle
    }

    func updateTabPath(for tabModel: inout TabModel, newPath: String?) {
        tabModel.currentPath = newPath
    }

    func toggleTabPin(for tabModel: inout TabModel) {
        tabModel.isPinned.toggle()
    }

    func updateTabContent(for tabModel: inout TabModel, currentPath: String, initialPath: String) {
        let savedPath = currentPath != initialPath ? currentPath : initialPath
        tabModel.currentPath = savedPath
        tabModel.title = TabUtils.getDisplayName(for: savedPath)
    }

    func initializeTabContent(for tabModel: inout TabModel, targetPath: String) {
        if tabModel.isPinned, tabModel.currentPath != nil {
            return
        }

        // 새로운 탭이거나 히스토리가 비어있는 경우
        if tabModel.backHistory.isEmpty, tabModel.forwardHistory.isEmpty {
            TabNavigationManager.shared.initializeHistory(for: &tabModel, initialPath: targetPath)
        } else {
            // 복원된 탭 - currentPath가 설정되어 있으면 그대로 사용
            if tabModel.currentPath == nil {
                tabModel.currentPath = targetPath
            }
        }
    }
}
