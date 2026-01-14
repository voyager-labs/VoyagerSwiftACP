import AppKit
import ComposableArchitecture
import SwiftUI

struct ViewToggleButton: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        ToolbarMenuButton(
            systemName: store.viewLayout == .list ? "list.bullet" : "square.grid.2x2",
            isEnabled: true,
            font: ToolbarButtonLabel.Metrics.iconFont,
            menuContent: {
                Button(
                    action: { store.send(.changeLayout(.list)) },
                    label: {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("List")
                        }
                    },
                )
                .disabled(store.viewLayout == .list)

                Button(
                    action: { store.send(.changeLayout(.grid)) },
                    label: {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                            Text("Grid")
                        }
                    },
                )
                .disabled(store.viewLayout == .grid)
            },
        )
    }
}
