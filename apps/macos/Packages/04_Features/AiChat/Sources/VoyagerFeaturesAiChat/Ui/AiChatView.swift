import ComposableArchitecture
import Perception
import SwiftUI

public struct AiChatView: View {
    let store: StoreOf<AiChatFeature>

    public init(store: StoreOf<AiChatFeature>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            let state = store.state

            VStack(alignment: .leading, spacing: 12) {
                Text("AI Chat")
                    .font(.headline)

                Text(state.modelFieldLabel)
                    .font(.subheadline)

                if let selectedModel = state.modelCatalogState.selectedModel {
                    Text(selectedModel.label.title)
                    if let subtitle = selectedModel.label.subtitle {
                        Text(subtitle)
                            .font(.caption)
                    }
                }

                if let statusText = state.requestStatusText {
                    Text(statusText)
                        .font(.caption)
                }

                if let statusText = state.sessionStatusText {
                    Text(statusText)
                        .font(.caption)
                }

                Text(state.currentContextSummaryDisplayModel.title)
                if let detail = state.currentContextSummaryDisplayModel.detail {
                    Text(detail)
                        .font(.caption)
                }

                switch state.surfaceState {
                case let .unconnected(connection, _):
                    surfaceBlock(title: connection.title, detail: connection.detail, actionLabel: connection.fixLabel)

                case let .error(connection, _):
                    surfaceBlock(title: connection.title, detail: connection.detail, actionLabel: connection.fixLabel)

                case let .empty(_, selectedModel):
                    Text("No messages yet")
                    Text("Type a message to start chatting with this context.")
                        .font(.caption)
                    Text(selectedModel?.label.title ?? "No model selected")

                case let .ready(_, selectedModel):
                    Text(selectedModel?.label.title ?? "No model selected")

                case let .processing(processing, _, selectedModel):
                    Text(processing.lockedModel.label.title)
                    if let selectedModel {
                        Text("Next request: \(selectedModel.label.title)")
                            .font(.caption)
                    }
                    Button(processing.cancelAffordance.title) {
                        store.send(.cancelTapped)
                    }
                    .disabled(!processing.cancelAffordance.isEnabled)
                }

                if state.isProcessing, !state.streamDraftText.isEmpty {
                    Text(state.streamDraftText)
                        .font(.body)
                }

                ForEach(Array(state.transcriptHistory.enumerated()), id: \.offset) { item in
                    Text("\(item.element.role.rawValue): \(item.element.content)")
                        .font(.caption)
                }

                TextField(
                    "Draft message",
                    text: Binding(
                        get: { state.draftText },
                        set: { store.send(.draftTextChanged($0)) },
                    ),
                )

                ForEach(state.modelCatalogState.rows) { row in
                    Button {
                        store.send(.selectedModelChanged(row.handle))
                    } label: {
                        Text(row.label.title)
                    }
                    .disabled(row.isSelected)
                }

                Button("Submit") {
                    store.send(.submitTapped)
                }
                .disabled(!state.canSubmit)

                Button("Regenerate") {
                    store.send(.regenerateTapped)
                }
                .disabled(!state.canRegenerate)

                Button("Reset draft") {
                    store.send(.resetTapped)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private func surfaceBlock(title: String, detail: String, actionLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(detail)
                .font(.caption)
            Text(actionLabel)
                .font(.caption)
        }
    }
}
