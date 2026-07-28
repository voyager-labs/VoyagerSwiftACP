import ComposableArchitecture
import SwiftUI
import VoyagerShared

struct ComposerBottomRowChipSizePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static let defaultValue: [AnyHashable: CGSize] = [:]

    static func reduce(value: inout [AnyHashable: CGSize], nextValue: () -> [AnyHashable: CGSize]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ComposerBottomConditionRowView: View {
    let store: StoreOf<ComposerFeature>
    let pickerStore: StoreOf<ConditionPropertyPickerFeature>
    let rows: [[ChipItemType]]
    let colorScheme: ColorScheme
    let chipSpacing: CGFloat
    let rowHeight: CGFloat
    let chipHeight: CGFloat

    @State private var isAddButtonHovering = false

    private let hoverFillOpacity: Double = 0.06

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: chipSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowChips in
                HStack(spacing: chipSpacing) {
                    ForEach(Array(rowChips.enumerated()), id: \.element.id) { _, chip in
                        chipView(chip: chip)
                            .background(
                                GeometryReader { chipGeometry in
                                    Color.clear.preference(
                                        key: ComposerBottomRowChipSizePreferenceKey.self,
                                        value: [AnyHashable(chip.id): chipGeometry.size],
                                    )
                                },
                            )
                    }
                }
                .frame(height: rowHeight)
            }
        }
        .accessibilityIdentifier("composer.conditionRow")
    }

    @ViewBuilder
    private func chipView(chip: ChipItemType) -> some View {
        switch chip {
        case .scopeRoot, .scopeBase:
            EmptyView()

        case .conditionAdd:
            conditionAddButton

        case let .condition(id):
            if let editorStore = store.scope(
                state: \.conditionEditors[id: id],
                action: \.conditionEditor[id: id],
            ) {
                ConditionChipView(
                    store: editorStore,
                    isDark: isDark,
                    hoverFillOpacity: hoverFillOpacity,
                    defaultChipHeight: chipHeight,
                    onRemove: { store.send(.removeCondition(id: id)) },
                )
            }
        }
    }

    private var conditionAddButton: some View {
        WithViewStore(
            pickerStore,
            observe: { $0 },
            content: { viewStore in
                if ComposerPickerHostPolicy.host(for: .property) == .nativeMenu {
                    ComposerNativeMenuButton(
                        title: "",
                        accessibilityIdentifier: "composer.condition.add",
                        minimumWidth: chipHeight,
                        isPlaceholder: false,
                        onOpen: {
                            pickerStore.send(.onAppear)
                            pickerStore.send(.setPresented(true))
                        },
                        menuItems: {
                            ConditionPropertyPickerDisplay.nativeMenuItems(
                                configuration: .init(
                                    properties: viewStore.properties,
                                    existingKeys: viewStore.existingKeys,
                                    editingKey: viewStore.editingConditionKey,
                                    defaults: viewStore.propertyDefaults,
                                    categories: viewStore.propertyCategories,
                                    labels: viewStore.propertyLabels,
                                    selectedKey: nil,
                                ),
                                onSelect: { pickerStore.send(.propertyTapped($0)) },
                            )
                        },
                        onDismiss: {
                            pickerStore.send(.setPresented(false))
                        },
                        imageName: "plus",
                        accessibilityLabel: "Add condition",
                    )
                    .frame(minWidth: chipHeight, minHeight: chipHeight)
                }
            },
        )
    }
}
