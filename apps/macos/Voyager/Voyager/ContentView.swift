import Inject
import SwiftData
import SwiftUI

struct ContentView: View {
    @ObserveInjection var inject
    @Environment(\.modelContext)
    private var modelContext
    @Query private var items: [Item]

    var body: some View {
        // 메인 UI (기본 SwiftUI 템플릿)
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text(
                            "Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))"
                        )
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
        .enableInjection()
    }

    private func addItem() {
        // 새 아이템 추가
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        // 선택된 아이템들 삭제
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
