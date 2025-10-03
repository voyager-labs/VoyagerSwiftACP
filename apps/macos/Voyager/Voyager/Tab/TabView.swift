import Inject
import SwiftUI

/// 개별 탭의 내용을 표시하는 뷰
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
        .id(tab.id) // 탭별 독립적인 뷰 인스턴스 보장
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
