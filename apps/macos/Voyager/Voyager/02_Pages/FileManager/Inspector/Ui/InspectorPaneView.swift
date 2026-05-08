import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesAiChat

struct InspectorPaneView: View {
    let store: StoreOf<FileManagerInspectorFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var isCloseButtonHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.activeMode == .chat {
                AiChatView(store: store.scope(state: \.aiChat, action: \.aiChat))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            Spacer()

            Button {
                store.send(.closeChat)
            } label: {
                closeButtonLabel
            }
            .buttonStyle(.borderless)
            .onHover { hovering in
                isCloseButtonHovered = hovering
            }
            .help("Close AI Chat")
            .accessibilityLabel("Close AI Chat")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var closeButtonLabel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton)
                .fill(closeButtonBackground)

            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }

    private var closeButtonBackground: Color {
        isCloseButtonHovered
            ? VoyagerDS.Surface.sidebarSelectionBackground(for: colorScheme)
            : .clear
    }
}
