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
                    ForEach(AiChatThinkingSelectorOptions.options(for: capability), id: \.id) { option in
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

    private var capability: AiModelThinkingCapability? {
        state.resolvedSelectedModel?.thinkingCapability
    }
}

private struct AiChatThinkingSelectorRow: View {
    let store: StoreOf<AiChatFeature>
    let option: ThinkingSelectorOption
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
    private static var defaultOptions: [ThinkingSelectorOption] {
        [
            ThinkingSelectorOption(selection: nil, title: "default"),
            ThinkingSelectorOption(
                selection: AiThinkingSelection.none,
                title: AiChatState.thinkingLabel(for: .none),
            )
        ]
    }

    static func options(for capability: AiModelThinkingCapability?) -> [ThinkingSelectorOption] {
        switch capability {
        case let .effort(values, _):
            defaultOptions + values.map { effortOption($0) }
        case let .adaptive(effortValues, _):
            defaultOptions + effortValues.map { effortOption($0) }
        case let .tokenBudget(min, max, defaultValue):
            defaultOptions + budgetValues(min: min, max: max, defaultValue: defaultValue)
                .map { tokenBudgetOption($0) }
        case .unsupported, .unknown, nil:
            []
        }
    }

    private static func effortOption(_ effort: AiThinkingEffort) -> ThinkingSelectorOption {
        ThinkingSelectorOption(
            selection: .effort(effort),
            title: AiChatState.thinkingLabel(for: .effort(effort)),
        )
    }

    private static func tokenBudgetOption(_ value: Int) -> ThinkingSelectorOption {
        ThinkingSelectorOption(
            selection: .tokenBudget(value),
            title: AiChatState.thinkingLabel(for: .tokenBudget(value)),
        )
    }

    private static func budgetValues(min: Int, max: Int, defaultValue: Int?) -> [Int] {
        var values: [Int] = [min]
        if let defaultValue, defaultValue != min, defaultValue != max {
            values.append(defaultValue)
        }
        if max != min {
            values.append(max)
        }
        return values
    }
}

private struct ThinkingSelectorOption: Identifiable {
    let selection: AiThinkingSelection?
    let title: String

    var id: String {
        selection.map(AiChatState.thinkingLabel(for:)) ?? "provider-default"
    }
}
