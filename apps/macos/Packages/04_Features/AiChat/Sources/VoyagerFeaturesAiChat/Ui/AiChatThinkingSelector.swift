import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi

struct AiChatThinkingSelectorButton: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState
    let input: AiChatInputDisplayModel

    var body: some View {
        let displayModel = AiChatStateDisplayModelBuilder(state: state)

        Menu {
            ForEach(displayModel.thinkingMenuItems, id: \.selection) { item in
                thinkingMenuItem(item)
            }
        } label: {
            AiChatHoverTextAffordance(
                title: AiChatSelectorLabels.thinkingSelectorLabel(for: state, input: input),
            )
        }
        .menuIndicator(.visible)
        .menuStyle(.borderlessButton)
        .disabled(input.isComposerEditingDisabled || displayModel.thinkingMenuIsDisabled)
        .accessibilityLabel("Thinking")
        .accessibilityValue(AiChatSelectorLabels.thinkingSelectorAccessibilityValue(for: state))
    }

    @ViewBuilder
    private func thinkingMenuItem(_ item: AiChatThinkingMenuItemDisplayModel) -> some View {
        if item.isEnabled {
            Button {
                store.send(.selectedThinkingChanged(item.selection))
            } label: {
                menuItemLabel(title: item.title, isSelected: item.isSelected)
            }
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityValue(item.accessibilityValue)
            .accessibilityAddTraits(item.isSelected ? .isSelected : [])
        } else {
            Text(item.title)
                .disabled(true)
                .accessibilityLabel(item.accessibilityLabel)
                .accessibilityValue(item.accessibilityValue)
                .accessibilityHint(item.disabledReason ?? "")
        }
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
