import AppKit
import SwiftUI

struct FSItemsView: View {
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        if let currentTab = tabManager.currentTab, let currentPath = currentTab.currentPath {
            FSItemsContentView(
                tabId: currentTab.id,
                initialPath: currentPath,
                savedCurrentPath: currentPath
            )
            .environmentObject(tabManager)
        } else {
            Text("No tab selected")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FSItemsContentView: View {
    let tabId: UUID
    let initialPath: String
    let savedCurrentPath: String?
    @EnvironmentObject var tabManager: TabManager
    @StateObject private var viewModel = FileBrowserViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.folderContents, id: \.name) { item in
                    FileItemRowView(item: item) {
                        if item.isDirectory {
                            viewModel.navigateToFolder(path: item.fullPath)
                        } else {
                            FileItemManager.shared.openFile(filePath: item.fullPath)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            viewModel.configure(
                tabId: tabId,
                initialPath: initialPath,
                savedCurrentPath: savedCurrentPath,
                tabManager: tabManager
            )
            viewModel.initializeContent()
        }
        .onChange(of: viewModel.currentPath) { newPath in
            viewModel.onPathChanged(newPath: newPath)
        }
    }
}
