import Inject
import SwiftUI

struct FileManagerView: View {
    @StateObject private var tabManager = TabManager()
    @ObserveInjection var inject
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .environmentObject(tabManager)
        } detail: {
            ContentPaneView()
                .environmentObject(tabManager)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .focusedSceneValue(\.tabManager, tabManager)
        .focusedSceneValue(\.columnVisibility, $columnVisibility)
        .enableInjection()
        .onChange(of: columnVisibility) { newValue in
            UserDefaults.standard.set(newValue == .all, forKey: "sidebarVisible")
        }
        .onAppear {
            let savedVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true
            columnVisibility = savedVisible ? .all : .detailOnly
        }
        .onDisappear {
            // 윈도우 닫힐 때 핀 탭 저장
            PinnedTabsManager.shared.saveToPlist()
        }
    }
}
