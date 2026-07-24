import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection

struct ConditionChipPropertyOperatorView: View {
    let store: StoreOf<ConditionEditorFeature>
    let condition: Condition
    let isDark: Bool
    let hoverFillOpacity: Double

    @State private var isPropertyHovering = false

    var body: some View {
        HStack(spacing: 2) {
            propertyLabelView
            operatorButtonView
        }
    }

    private var propertyPickerStore: StoreOf<ConditionPropertyPickerFeature> {
        store.scope(state: \.propertyPicker, action: \.propertyPicker)
    }

    private var propertyLabelView: some View {
        WithViewStore(
            propertyPickerStore,
            observe: { $0 },
            content: { propertyStore in
                if ComposerPickerHostPolicy.host(for: .property) == .nativeMenu {
                    ComposerNativeMenuButton(
                        title: condition.property.label,
                        accessibilityIdentifier: "composer.property.edit.trigger",
                        minimumWidth: 0,
                        isPlaceholder: false,
                        onOpen: {
                            store.send(.view(.setPropertyPickerPresented(true)))
                            propertyPickerStore.send(.onAppear)
                        },
                        menuItems: { [] },
                        onDismiss: {
                            propertyPickerStore.send(.setPresented(false))
                        },
                        imageName: ConditionPropertyIcon.iconName(
                            forKey: condition.property.key,
                            category: nil,
                            type: condition.property.type.rawValue,
                        ),
                        showsBorder: false,
                        searchableItems: { searchText in
                            ConditionPropertyPickerDisplay.nativeMenuItems(
                                configuration: .init(
                                    properties: propertyStore.properties,
                                    existingKeys: propertyStore.existingKeys,
                                    editingKey: propertyStore.editingConditionKey,
                                    defaults: propertyStore.propertyDefaults,
                                    categories: propertyStore.propertyCategories,
                                    labels: propertyStore.propertyLabels,
                                    types: propertyStore.propertyTypes,
                                    selectedKey: condition.property.key,
                                    searchText: searchText,
                                ),
                                onSelect: { propertyPickerStore.send(.propertyTapped($0)) },
                            )
                        },
                        searchPlaceholder: "Search attributes",
                    )
                    .frame(minHeight: 22)
                    .fixedSize(horizontal: true, vertical: false)
                }
            },
        )
    }

    private var operatorButtonView: some View {
        let operation = condition.operation
        let label = operation?.label ?? "Operator"

        return Group {
            if ComposerPickerHostPolicy.host(for: .operator) == .nativeMenu {
                ComposerNativeMenuButton(
                    title: label,
                    accessibilityIdentifier: "composer.operator.trigger",
                    minimumWidth: 28,
                    isPlaceholder: operation == nil,
                    onOpen: {
                        store.send(.view(.setOperatorMenuPresented(true)))
                    },
                    menuItems: {
                        condition.property.operatorOptions.map { option in
                            ComposerNativeMenuItem(
                                title: option.label,
                                isSelected: option.code == operation?.code,
                                isEnabled: true,
                                action: { store.send(.view(.selectOperator(option.code))) },
                            )
                        }
                    },
                    onDismiss: {
                        store.send(.view(.setOperatorMenuPresented(false)))
                    },
                    showsBorder: false,
                )
                .frame(minHeight: 22)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
