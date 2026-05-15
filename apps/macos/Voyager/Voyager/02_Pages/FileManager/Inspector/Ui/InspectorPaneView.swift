import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesAiChat

struct InspectorPaneView: View {
    let store: StoreOf<FileManagerInspectorFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.activeMode == .chat {
                AiChatView(store: store.scope(state: \.aiChat, action: \.aiChat))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.thickMaterial)
        .overlay(inspectorMaterialTint)
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
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help("Close AI Chat")
            .accessibilityLabel("Close AI Chat")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var closeButtonLabel: some View {
        ToolbarHoverButtonLabel(
            systemName: "sidebar.trailing",
            isEnabled: true,
            font: nil,
        )
    }

    @ViewBuilder private var inspectorMaterialTint: some View {
        if colorScheme == .dark {
            Color.white.opacity(0.06)
                .allowsHitTesting(false)
        } else {
            Color.clear
                .allowsHitTesting(false)
        }
    }
}
