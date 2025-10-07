import Combine
import Foundation
import SwiftUI

@MainActor
class FileBrowserViewModel: ObservableObject {
    @Published var currentPath: String = ""
    @Published var folderContents: [FileItemModel] = []
    @Published var isLoading = false

    private var tabId: UUID?
    private var initialPath: String?
    private var savedCurrentPath: String?
    private var tabManager: TabManager?

    init() {}

    func configure(tabId: UUID, initialPath: String, savedCurrentPath: String?, tabManager: TabManager) {
        self.tabId = tabId
        self.initialPath = initialPath
        self.savedCurrentPath = savedCurrentPath
        self.tabManager = tabManager
    }

    private var currentTab: TabViewModel? {
        guard let tabManager = tabManager, let tabId = tabId else { return nil }
        return tabManager.tabs.first { $0.id == tabId }
    }

    func initializeContent() {
        guard let savedCurrentPath = savedCurrentPath, let initialPath = initialPath else { return }
        let targetPath = savedCurrentPath.isEmpty ? initialPath : savedCurrentPath
        if currentPath.isEmpty || currentPath != targetPath {
            currentPath = targetPath
            folderContents = []
            isLoading = false

            // TabViewModel에 초기화 로직 위임
            currentTab?.initializeTabContent(targetPath: targetPath)
            loadFolderContents()
        }
    }

    func onPathChanged(newPath: String) {
        loadFolderContents()
        guard let initialPath = initialPath else { return }
        updateTabContent(currentPath: newPath, initialPath: initialPath)
    }

    func navigateToHome() {
        let homePath = NSHomeDirectory()
        currentTab?.navigateTo(newPath: homePath)
        currentPath = homePath
        updateTabContent(currentPath: homePath, initialPath: initialPath ?? "")
        loadFolderContents()
    }

    func navigateToFolder(path: String) {
        currentTab?.navigateTo(newPath: path)
        currentPath = path
        updateTabContent(currentPath: path, initialPath: initialPath ?? "")
        loadFolderContents()
    }

    func goBack() {
        guard let tab = currentTab else { return }
        if let previousPath = tab.goBack() {
            currentPath = previousPath
            updateTabContent(currentPath: previousPath, initialPath: initialPath ?? "")
            loadFolderContents()
        }
    }

    func goForward() {
        guard let tab = currentTab else { return }
        if let nextPath = tab.goForward() {
            currentPath = nextPath
            updateTabContent(currentPath: nextPath, initialPath: initialPath ?? "")
            loadFolderContents()
        }
    }

    func canGoBack() -> Bool {
        currentTab?.canGoBack() ?? false
    }

    func canGoForward() -> Bool {
        currentTab?.canGoForward() ?? false
    }

    private func updateTabContent(currentPath: String, initialPath: String) {
        currentTab?.updateTabContent(currentPath: currentPath, initialPath: initialPath)
        tabManager?.objectWillChange.send()
    }

    private func loadFolderContents() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let contents = FileItemManager.shared.getFolderContents(at: self.currentPath)

            DispatchQueue.main.async {
                self.folderContents = contents
                self.isLoading = false
            }
        }
    }
}
