import Inject
import SwiftUI

struct FileManagerView: View {
    @StateObject private var tabManager = TabManager()
    @ObserveInjection var inject
    @State private var isSidebarVisible: Bool = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarView()
                    .frame(width: 220)
                    .background(Color(red: 0.18, green: 0.18, blue: 0.20))
                    .environmentObject(tabManager)

                Divider()
            }

            ContentView()
                .environmentObject(tabManager)
                .environment(\.isSidebarVisible, isSidebarVisible)
        }
        .frame(minWidth: 800, minHeight: 600)
        .focusedSceneValue(\.tabManager, tabManager)
        .focusedSceneValue(\.isSidebarVisible, $isSidebarVisible)
        .enableInjection()
        .onChange(of: isSidebarVisible) { newValue in
            UserDefaults.standard.set(newValue, forKey: "sidebarVisible")
        }
        .onDisappear {
            // 윈도우 닫힐 때 핀 탭 저장
            PinnedTabsManager.shared.saveToPlist()
        }
    }
}
