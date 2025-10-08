import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        if let currentTab = tabManager.currentTab {
            TabView(tab: currentTab)
                .environmentObject(tabManager)
        } else {
            Text("No tab selected")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.22, green: 0.22, blue: 0.24))
        }
    }
}
