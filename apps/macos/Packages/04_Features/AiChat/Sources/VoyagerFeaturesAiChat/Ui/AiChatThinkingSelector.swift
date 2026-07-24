import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi

struct AiChatThinkingSelectorButton: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState
    let input: AiChatInputDisplayModel

    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            AiChatHoverTextAffordance(
                title: AiChatSelectorLabels.thinkingSelectorLabel(for: state, input: input),
                systemName: "chevron.down",
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AiChatSelectorPopoverContainer {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(AiChatThinkingSelectorOptions.options(for: state.resolvedSelectedModel),
                            id: \.id)
                    { option in
                        AiChatThinkingSelectorRow(
                            store: store,
                            option: option,
                            isSelected: state.selectedThinking == option.selection,
                            isPresented: $isPresented,
                        )
                    }
                }
            }
        }
        .disabled(AiChatSelectorLabels.thinkingSelectorIsDisabled(for: state))
        .accessibilityLabel("Thinking")
        .accessibilityValue(AiChatSelectorLabels.thinkingSelectorAccessibilityValue(for: state))
    }
}

private struct AiChatThinkingSelectorRow: View {
    let store: StoreOf<AiChatFeature>
    let option: AiThinkingOption
    let isSelected: Bool

    @Binding var isPresented: Bool

    var body: some View {
        Button {
            store.send(.selectedThinkingChanged(option.selection))
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Text(option.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear),
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
    }
}

private enum AiChatThinkingSelectorOptions {
    static func options(for model: AiProviderModel?) -> [AiThinkingOption] {
        guard let model else { return [] }
        return AiThinkingSelectionPolicy.options(
            capability: model.thinkingCapability,
            supportsNone: model.supportsThinkingNone,
        )
    }
}
