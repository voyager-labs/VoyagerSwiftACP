import AppKit
import ComposableArchitecture
import SwiftUI

struct ViewToggleButton: View {
    let store: StoreOf<FileManagerFeature>
    @Environment(\.colorScheme)
    var colorScheme
    @State private var isHovered: Bool = false

    var body: some View {
        ZStack {
            Image(systemName: store.viewLayout == .list ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Group {
                        if isHovered {
                            ZStack {
                                RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton)
                                    .fill(VoyagerDS.Surface.toolbarMenuButtonBackground(for: colorScheme))
                                RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton)
                                    .fill(VoyagerDS.Interaction.toolbarButtonHoverFill(for: colorScheme))
                            }
                        }
                    }
                    .allowsHitTesting(false),
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton))
        .overlay(
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
                Color.clear
                    .frame(width: 24, height: 24)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless),
        )
        .overlay(
            HoverTrackingOverlay(isHovered: $isHovered)
                .frame(width: 24, height: 24),
        )
    }
}
