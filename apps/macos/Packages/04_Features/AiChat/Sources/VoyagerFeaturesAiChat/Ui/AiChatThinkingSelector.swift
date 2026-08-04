import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi
import VoyagerShared

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
        .onChange(of: input.isComposerEditingDisabled) { isDisabled in
            if isDisabled {
                isPresented = false
            }
        }
        .disabled(input.isComposerEditingDisabled || AiChatSelectorLabels.thinkingSelectorIsDisabled(for: state))
        .accessibilityLabel("Thinking")
        .accessibilityValue(AiChatSelectorLabels.thinkingSelectorAccessibilityValue(for: state))
    }
}

private struct AiChatThinkingSelectorRow: View {
    @Environment(\.colorScheme)
    private var colorScheme
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
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                    .fill(isSelected ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme) : Color.clear),
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
    }
}

private enum AiChatThinkingSelectorOptions {
    static func options(for model: AiProviderModel?) -> [ThinkingSelectorOption] {
        guard let model else { return [] }
        let defaults = defaultOptions(supportsNone: model.supportsThinkingNone)
        switch model.thinkingCapability {
        case let .effort(values, _):
            return defaults + values.map { effortOption($0) }
        case let .adaptive(effortValues, _):
            return defaults + effortValues.map { effortOption($0) }
        case let .tokenBudget(min, max, defaultValue):
            return defaults + budgetValues(min: min, max: max, defaultValue: defaultValue)
                .map { tokenBudgetOption($0) }
        case .unsupported, .unknown:
            return []
        }
    }

    private static func defaultOptions(supportsNone: Bool) -> [ThinkingSelectorOption] {
        var options = [ThinkingSelectorOption(selection: nil, title: "Provider default")]
        if supportsNone {
            options.append(
                ThinkingSelectorOption(
                    selection: AiThinkingSelection.none,
                    title: AiChatState.thinkingLabel(for: .none),
                ),
            )
        }
        return options
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
