import ComposableArchitecture
import SwiftUI

struct AiChatModelSelectorButton: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState
    let isEditingDisabled: Bool

    var body: some View {
        Menu {
            switch state.modelSelectorContentState {
            case let .loaded(sections):
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row in
                            modelMenuItem(row)
                        }
                    }
                }

            case let .loading(status),
                 let .empty(status),
                 let .failed(status),
                 let .unsupported(status):
                modelStatusMenuItem(status)
            }
        } label: {
            AiChatHoverTextAffordance(
                title: AiChatSelectorLabels.modelSelectorLabel(for: state),
            )
        }
        .menuIndicator(.visible)
        .menuStyle(.borderlessButton)
        .disabled(isEditingDisabled || state.modelSelectorIsDisabled)
        .accessibilityLabel("Model")
        .accessibilityValue(AiChatSelectorLabels.modelSelectorAccessibilityValue(for: state))
    }

    @ViewBuilder
    private func modelMenuItem(_ row: AiChatModelCatalogRowDisplayModel) -> some View {
        if row.isEnabled {
            Button {
                store.send(.selectedModelChanged(row.handle))
            } label: {
                menuItemLabel(title: row.title, isSelected: row.isSelected)
            }
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityValue(row.accessibilityValue)
            .accessibilityAddTraits(row.isSelected ? .isSelected : [])
        } else {
            Text(row.title)
                .disabled(true)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityValue(row.accessibilityValue)
                .accessibilityHint(row.disabledReason ?? "")
        }
    }

    private func modelStatusMenuItem(_ status: AiChatModelSelectorStatusDisplayModel) -> some View {
        Text(status.title)
            .disabled(true)
            .accessibilityLabel(status.accessibilityLabel)
            .accessibilityValue(status.accessibilityValue)
            .accessibilityHint(status.disabledReason)
    }

    @ViewBuilder
    private func menuItemLabel(title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

enum AiChatSelectorLabels {
    static func modelSelectorLabel(for state: AiChatState) -> String {
        if let selectedModel = state.selectedModelDisplayModel {
            return selectedModel.title
        }

        return switch state.modelListState {
        case .loading, .idle:
            "Loading"
        case .failed:
            "Unavailable"
        case .empty:
            "No models"
        case .loaded:
            "Model"
        }
    }

    static func modelSelectorAccessibilityValue(for state: AiChatState) -> String {
        switch state.modelSelectorContentState {
        case .loading:
            "Loading"
        case .empty:
            "No models"
        case .failed:
            "Unavailable"
        case .unsupported:
            "Unsupported"
        case .loaded:
            state.selectedModelDisplayModel?.title ?? "No selection"
        }
    }

    static func thinkingSelectorLabel(for state: AiChatState, input: AiChatInputDisplayModel) -> String {
        guard let model = state.resolvedSelectedModel else {
            return "Thinking"
        }

        switch model.thinkingCapability {
        case .unsupported, .unknown:
            return "Unavailable"
        case .effort, .adaptive, .tokenBudget:
            return state.selectedThinking.map(AiChatState.thinkingLabel(for:)) ?? input.effortLabel
        }
    }

    static func thinkingSelectorAccessibilityValue(for state: AiChatState) -> String {
        guard let model = state.resolvedSelectedModel else { return "No selection" }

        switch model.thinkingCapability {
        case .unsupported, .unknown:
            return "Unavailable"
        case .effort, .adaptive, .tokenBudget:
            return state.selectedThinking.map(AiChatState.thinkingLabel(for:))
                ?? AiChatState.defaultThinkingLabel(for: model.thinkingCapability)
        }
    }
}
