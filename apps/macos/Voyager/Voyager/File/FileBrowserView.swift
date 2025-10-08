import AppKit
import SwiftUI

struct FileBrowserView: View {
    let tabId: UUID
    let initialPath: String
    let savedCurrentPath: String?
    @EnvironmentObject var tabManager: TabManager
    @StateObject private var viewModel = FileBrowserViewModel()
    @Environment(\.isSidebarVisible)
    var isSidebarVisible

    var body: some View {
        VStack(spacing: 0) {
            pathBar

            Divider()

            if viewModel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                folderList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.22, green: 0.22, blue: 0.24))
        .edgesIgnoringSafeArea(.top)
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

    private var pathBar: some View {
        HStack(spacing: 8) {
            // Sidebar 없을 때 트래픽 라이트 공간
            if !isSidebarVisible {
                Spacer()
                    .frame(width: 70)
            }

            Button(action: {
                viewModel.navigateToHome()
            }, label: {
                Image(systemName: "house.fill")
                    .foregroundColor(.blue)
            })
            .buttonStyle(.plain)

            Button(action: {
                viewModel.goBack()
            }, label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.secondary)
            })
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoBack())

            Button(action: {
                viewModel.goForward()
            }, label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            })
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoForward())

            // 경로 표시
            Text(viewModel.currentPath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.22, green: 0.22, blue: 0.24))
    }

    private var folderList: some View {
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
