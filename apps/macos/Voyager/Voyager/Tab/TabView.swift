import Inject
import SwiftUI

struct TabView: View {
    let tab: TabViewModel
    @EnvironmentObject var tabManager: TabManager
    @ObserveInjection var inject

    var body: some View {
        Group {
            if let currentPath = tab.currentPath {
                FileBrowserView(
                    tabId: tab.id,
                    initialPath: currentPath,
                    savedCurrentPath: currentPath
                )
                .environmentObject(tabManager)
            } else {
                emptyView
            }
        }
        .id(tab.id)
        .enableInjection()
    }

    private var emptyView: some View {
        VStack {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Empty Tab")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
