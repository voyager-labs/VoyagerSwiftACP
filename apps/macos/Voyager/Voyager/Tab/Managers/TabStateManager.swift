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
        // 히스토리가 비어있으면 새 탭 - 초기 경로를 히스토리에 추가
        if tabModel.navigationHistory.isEmpty {
            tabModel.navigationHistory.append(targetPath)
            tabModel.currentHistoryIndex = 0
            tabModel.currentPath = targetPath
        } else {
            // 복원된 탭 - 히스토리 인덱스에 맞는 경로로 설정
            if tabModel.currentHistoryIndex >= 0, tabModel.currentHistoryIndex < tabModel.navigationHistory.count {
                tabModel.currentPath = tabModel.navigationHistory[tabModel.currentHistoryIndex]
            }
        }
    }
}
