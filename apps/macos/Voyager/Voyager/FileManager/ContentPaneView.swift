import SwiftUI

struct ContentPaneView: View {
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        FSItemsView()
            .environmentObject(tabManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.22, green: 0.22, blue: 0.24))
            .ignoresSafeArea(.all, edges: .top)
            .navigationTitle(tabManager.currentTab?.currentPath ?? "")
            .navigationSubtitle("")
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: {}, label: {
                        Label("Home", systemImage: "house.fill")
                    })

                    Button(action: {}, label: {
                        Label("Back", systemImage: "chevron.left")
                    })

                    Button(action: {}, label: {
                        Label("Forward", systemImage: "chevron.right")
                    })
                }
            }
    }
}
