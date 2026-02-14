import AppKit
import ComposableArchitecture
import SwiftUI

struct ViewToggleButton: View {
    let store: StoreOf<FileManagerContentFeature>

    var body: some View {
        ToolbarMenuButton(
            // TODO: 아이콘 상수화
            systemName: store.viewLayout == .list ? "list.bullet" : "square.grid.2x2",
            isEnabled: true,
            font: nil,
            menuContent: {
                Button(
                    action: { store.send(.changeLayout(.list)) },
                    label: {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("as List")
                        }
                    },
                )
                .disabled(store.viewLayout == .list)

                Button(
                    action: { store.send(.changeLayout(.grid)) },
                    label: {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                            Text("as Icon")
                        }
                    },
                )
                .disabled(store.viewLayout == .grid)
            },
        )
    }
}
