import AppKit
import SwiftUI

struct FileBrowserView: View {
    let tabId: UUID
    let initialPath: String
    let savedCurrentPath: String?
    @EnvironmentObject var tabManager: TabManager
    @StateObject private var viewModel = FileBrowserViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Text("FileBrowserView (deprecated)")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.22, green: 0.22, blue: 0.24))
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
