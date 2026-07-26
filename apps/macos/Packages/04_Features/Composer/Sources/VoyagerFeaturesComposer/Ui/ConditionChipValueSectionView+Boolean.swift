import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection

extension ConditionChipValueSectionView {
    func booleanValueButton(
        placeholderText: String,
        currentText: String,
        index: Int,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        contract _: Condition.ValueContract,
    ) -> some View {
        let label = currentText.isEmpty
            ? (placeholderText.isEmpty ? "Value" : placeholderText.capitalized)
            : currentText.capitalized

        return Group {
            if ComposerPickerHostPolicy.host(for: .boolean) == .nativeMenu {
                ComposerNativeMenuButton(
                    title: label,
                    accessibilityIdentifier: "composer.boolean.trigger",
                    minimumWidth: 50,
                    isPlaceholder: currentText.isEmpty,
                    onOpen: {
                        prepare(editingIndex: index, existingValues: condition.values, includeDisplayState: false)
                    },
                    menuItems: {
                        ["True", "False"].map { title in
                            ComposerNativeMenuItem(
                                title: title,
                                isSelected: currentText.caseInsensitiveCompare(title) == .orderedSame,
                                isEnabled: true,
                                action: {
                                    valueViewStore.send(.setValue(index: 0, text: title))
                                    valuePickerStore.send(.commit)
                                },
                            )
                        }
                    },
                    onDismiss: {},
                )
                .fixedSize(horizontal: true, vertical: true)
            }
        }
    }
}
