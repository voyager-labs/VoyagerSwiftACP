import AppKit
import ComposableArchitecture
import SwiftUI

struct ViewToggleButton: View {
    let store: StoreOf<FileManagerFeature>
    @Environment(\.colorScheme)
    var colorScheme

    var body: some View {
        Menu {
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
        } label: {
            Image(systemName: store.viewLayout == .list ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .frame(width: 30, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(toolbarMenuButtonBackgroundColor)
                .allowsHitTesting(false),
        )
    }

    private var toolbarMenuButtonBackgroundColor: Color {
        if colorScheme == .dark {
            Color(nsColor: .controlBackgroundColor)
        } else {
            Color(red: 245 / 255.0, green: 245 / 255.0, blue: 245 / 255.0)
        }
    }
}
