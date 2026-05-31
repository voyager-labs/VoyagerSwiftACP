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
    let conditionDisplayByKey: [String: ConditionDisplayState]
    let operatorOptionsByKey: [String: [String]]
    let colorScheme: ColorScheme
    let chipSpacing: CGFloat
    let rowHeight: CGFloat
    let chipHeight: CGFloat

    @State private var isAddButtonHovering = false

    private let hoverFillOpacity: Double = 0.06

    private var isDark: Bool { colorScheme == .dark }

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

        case let .condition(condition):
            let displayState = conditionDisplayByKey[condition.propertyKey]
            ConditionChipView(
                propertyPickerStore: store.scope(state: \.propertyPicker, action: \.propertyPicker),
                condition: condition,
                isDark: isDark,
                hoverFillOpacity: hoverFillOpacity,
                operatorPickerStore: store.scope(state: \.operatorPicker, action: \.operatorPicker),
                valuePickerStore: store.scope(state: \.valuePicker, action: \.valuePicker),
                operatorOptions: operatorOptionsByKey[condition.propertyKey] ?? [],
                displayState: displayState,
                defaultChipHeight: chipHeight,
                onPropertyTap: {
                    store.send(.propertyPicker(.startEditing(condition.propertyKey)))
                },
                onRemove: {
                    store.send(.removeCondition(propertyKey: condition.propertyKey))
                },
                onDisplayUnitChange: { propertyKey, unitCode in
                    store.send(.setDisplayUnit(propertyKey: propertyKey, unitCode: unitCode))
                },
            )
        }
    }

    private var conditionAddButton: some View {
        WithViewStore(
            pickerStore,
            observe: { $0 },
            content: { viewStore in
                Button {
                    viewStore.send(.setPresented(true))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: chipHeight, height: chipHeight)
                        .background(
                            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                                .fill(isAddButtonHovering ? VoyagerDS.Interaction
                                    .controlHoverFill(for: colorScheme) : .clear),
                        )
                }
                .buttonStyle(.borderless)
                .onHover { hovering in
                    isAddButtonHovering = hovering
                }
                .popover(
                    isPresented: viewStore.binding(
                        get: { $0.isPresented && $0.editingConditionKey == nil },
                        send: ConditionPropertyPickerFeature.Action.setPresented,
                    ),
                    arrowEdge: .bottom,
                ) {
                    ConditionPropertyPickerView(store: pickerStore)
                }
            },
        )
    }
}
