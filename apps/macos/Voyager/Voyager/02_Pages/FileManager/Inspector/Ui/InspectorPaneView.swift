import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesAiChat

struct InspectorPaneView: View {
    let store: StoreOf<FileManagerInspectorFeature>

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
                store.send(.setInspectorVisible(false))
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
