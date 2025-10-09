import Inject
import SwiftUI

struct FileManagerView: View {
    @StateObject private var tabManager = TabManager()
    @ObserveInjection var inject
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isHoveringLeftEdge: Bool = false

    var body: some View {
        ZStack(alignment: .leading) {
            mainLayout

            if columnVisibility == .detailOnly {
                hoverDetectionArea
            }

            if columnVisibility == .detailOnly && isHoveringLeftEdge {
                SidebarView(isFloating: true, onHoverChange: { hovering in
                    isHoveringLeftEdge = hovering
                })
                .environmentObject(tabManager)
            }
        }
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

    private var mainLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .environmentObject(tabManager)
        } detail: {
            ContentPaneView(isSidebarVisible: columnVisibility == .all)
                .environmentObject(tabManager)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var hoverDetectionArea: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    isHoveringLeftEdge = true
                }
            }
    }
}
