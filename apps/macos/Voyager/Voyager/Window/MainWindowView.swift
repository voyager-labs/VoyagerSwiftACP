import Inject
import SwiftUI

/// 메인 윈도우 컨테이너 (Arc Browser 스타일)
struct MainWindowView: View {
    @StateObject private var tabManager = TabManager()
    @ObserveInjection var inject

    var body: some View {
        ZStack(alignment: .leading) {
            sidebarBackground
            sidebarContent
            mainContent
        }
        .frame(minWidth: 800, minHeight: 600)
        .focusedSceneValue(\.tabManager, tabManager)
        .enableInjection()
        .onDisappear {
            // 윈도우 닫힐 때 핀 탭 저장
            PinnedTabsManager.shared.saveToPlist()
        }
    }

    private var sidebarBackground: some View {
        Color(red: 0.18, green: 0.18, blue: 0.20)
            .ignoresSafeArea()
    }

    private var sidebarContent: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 220)
                .environmentObject(tabManager)
            Spacer()
        }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 220)
            contentCard
        }
    }

    @ViewBuilder private var contentCard: some View {
        if let currentTab = tabManager.currentTab {
            TabView(tab: currentTab)
                .environmentObject(tabManager)
                .background(Color(red: 0.22, green: 0.22, blue: 0.24))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: -2, y: 0)
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .padding(.top, -20) // 트래픽 라이트 원 위까지 올리기
        } else {
            Text("No tab selected")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.22, green: 0.22, blue: 0.24))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: -2, y: 0)
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .padding(.top, -20) // 트래픽 라이트 원 위까지 올리기
        }
    }
}
