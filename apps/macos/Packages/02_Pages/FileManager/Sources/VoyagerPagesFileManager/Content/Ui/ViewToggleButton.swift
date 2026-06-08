import AppKit
import ComposableArchitecture
import SwiftUI

struct ViewToggleButton: View {
    let store: StoreOf<FileManagerContentFeature>

    var body: some View {
        ToolbarMenuButton(
            // TODO: 아이콘 상수화
            systemName: store.entryViewLayout.mode == .list ? "list.bullet" : "square.grid.2x2",
            isEnabled: true,
            font: nil,
            menuContent: {
                Button(
                    action: { store.send(.view(.changeLayout(.list))) },
                    label: {
                        HStack {
                            Image(systemName: "list.bullet")
                                .accessibilityHidden(true)
                            Text("as List")
                        }
                    },
                )
                .disabled(store.entryViewLayout.mode == .list)

                Button(
                    action: { store.send(.view(.changeLayout(.grid))) },
                    label: {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                                .accessibilityHidden(true)
                            Text("as Icon")
                        }
                    },
                )
                .disabled(store.entryViewLayout.mode == .grid)
            },
        )
    }
}
