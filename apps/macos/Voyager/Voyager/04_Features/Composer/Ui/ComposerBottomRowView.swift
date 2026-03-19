import ComposableArchitecture
import SwiftUI

private struct ChipSizePreferenceKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGSize] = [:]

    static func reduce(value: inout [AnyHashable: CGSize], nextValue: () -> [AnyHashable: CGSize]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ComposerBottomRowView: View {
    let store: StoreOf<ComposerFeature>
    let favorites: [ScopeFavoriteItem]
    let historyPaths: [String]
    let colorScheme: ColorScheme
    @Binding var isScopePickerPresented: Bool

    @State private var chipSizes: [String: CGSize] = [:]
    @State private var calculatedHeight: CGFloat = 0
    @State private var isAddButtonHovering: Bool = false

    private let chipHorizontalPadding: CGFloat = 16
    private let chipSpacing: CGFloat = 8
    private let chipVerticalPadding: CGFloat = 8
    private let conditionButtonWidth: CGFloat = 20
    private let maxChipAreaHeight: CGFloat = 200
    private let defaultChipHeight: CGFloat = 28
    private let defaultChipWidth: CGFloat = 120
    private let hoverFillOpacity: Double = 0.06

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        WithViewStore(
            store,
            observe: { $0 },
            content: { viewStore in
                GeometryReader { geometry in
                    secondRowContent(viewStore: viewStore, geometry: geometry)
                }
                .frame(height: calculatedHeight)
            },
        )
    }

    private func secondRowContent(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        geometry: GeometryProxy,
    ) -> some View {
        let isLocked = viewStore.isLoadingSearch || viewStore.isFilteringInFlight
        let availableWidth = geometry.size.width - chipHorizontalPadding * 2
        let pickerStore = store.scope(state: \.propertyPicker, action: \.propertyPicker)

        let scopeChips: [ChipItemType] = [.scope(paths: viewStore.scopes)]
        let conditionChips: [ChipItemType] = viewStore.conditions.map { .condition($0) }
        let allChips: [ChipItemType] = scopeChips + conditionChips

        let params = RowCalculationParams(
            availableWidth: availableWidth,
            spacing: chipSpacing,
            chipSizes: chipSizes,
            conditionButtonWidth: conditionButtonWidth,
            buttonSpacing: chipSpacing,
        )
        let rows = calculateRowsWithButtons(chips: allChips, params: params)

        return chipRowsView(
            rows: rows,
            pickerStore: pickerStore,
            conditionDisplayByKey: viewStore.conditionDisplayByKey,
            operatorOptionsByKey: viewStore.operatorOptionsByKey,
            historyPaths: historyPaths,
        )
        .allowsHitTesting(!isLocked)
        .onPreferenceChange(ChipSizePreferenceKey.self) { sizes in
            handleChipSizeChange(sizes: sizes, allChips: allChips, availableWidth: availableWidth)
        }
        .onAppear {
            updateCalculatedHeight(chips: allChips, availableWidth: availableWidth)
        }
        .padding(.horizontal, chipHorizontalPadding)
        .padding(.vertical, chipVerticalPadding)
    }

    @ViewBuilder
    private func chipView(
        chip: ChipItemType,
        conditionDisplayByKey: [String: ConditionDisplayState],
        operatorOptionsByKey: [String: [String]],
        historyPaths: [String],
    ) -> some View {
        switch chip {
        case let .scope(paths):
            ScopeChipView(
                paths: paths,
                store: store,
                favorites: favorites,
                backHistory: historyPaths,
                isComboBoxPresented: $isScopePickerPresented,
            )

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
                defaultChipHeight: defaultChipHeight,
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

    private func chipRowsView(
        rows: [[ChipItemType]],
        pickerStore: StoreOf<ConditionPropertyPickerFeature>,
        conditionDisplayByKey: [String: ConditionDisplayState],
        operatorOptionsByKey: [String: [String]],
        historyPaths: [String],
    ) -> some View {
        VStack(alignment: .leading, spacing: chipSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowChips in
                let isLastRow = rowIndex == rows.count - 1

                HStack(spacing: chipSpacing) {
                    ForEach(Array(rowChips.enumerated()), id: \.element.id) { _, chip in
                        chipView(
                            chip: chip,
                            conditionDisplayByKey: conditionDisplayByKey,
                            operatorOptionsByKey: operatorOptionsByKey,
                            historyPaths: historyPaths,
                        )
                        .background(
                            GeometryReader { chipGeometry in
                                Color.clear.preference(
                                    key: ChipSizePreferenceKey.self,
                                    value: [AnyHashable(chip.id): chipGeometry.size],
                                )
                            },
                        )
                    }

                    if isLastRow {
                        conditionAddButton(pickerStore: pickerStore)
                    }
                }
            }
        }
    }

    private func conditionAddButton(pickerStore: StoreOf<ConditionPropertyPickerFeature>) -> some View {
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
                        .frame(width: defaultChipHeight, height: defaultChipHeight)
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

    private func handleChipSizeChange(
        sizes: [AnyHashable: CGSize],
        allChips: [ChipItemType],
        availableWidth: CGFloat,
    ) {
        for chip in allChips {
            let anyId = AnyHashable(chip.id)
            if let size = sizes[anyId] {
                chipSizes[chip.id] = size
            }
        }
        updateCalculatedHeight(chips: allChips, availableWidth: availableWidth)
    }

    private func updateCalculatedHeight(chips: [ChipItemType], availableWidth: CGFloat) {
        let params = RowCalculationParams(
            availableWidth: availableWidth,
            spacing: chipSpacing,
            chipSizes: chipSizes,
            conditionButtonWidth: conditionButtonWidth,
            buttonSpacing: chipSpacing,
        )
        let updatedRows = calculateRowsWithButtons(chips: chips, params: params)
        let contentHeight = calculateTotalHeight(rows: updatedRows, chipSizes: chipSizes, spacing: chipSpacing)
        let paddingHeight = chipVerticalPadding * 2
        calculatedHeight = min(contentHeight + paddingHeight, maxChipAreaHeight)
    }

    private func calculateTotalHeight(
        rows: [[ChipItemType]],
        chipSizes: [String: CGSize],
        spacing: CGFloat,
    ) -> CGFloat {
        guard !rows.isEmpty else { return 0 }

        var totalHeight: CGFloat = 0
        for row in rows {
            var maxRowHeight: CGFloat = 0
            for chip in row {
                if let chipHeight = chipSizes[chip.id]?.height {
                    maxRowHeight = max(maxRowHeight, chipHeight)
                } else {
                    maxRowHeight = max(maxRowHeight, defaultChipHeight)
                }
            }
            totalHeight += maxRowHeight
        }

        totalHeight += CGFloat(max(0, rows.count - 1)) * spacing
        return totalHeight
    }

    private struct RowCalculationParams {
        let availableWidth: CGFloat
        let spacing: CGFloat
        let chipSizes: [String: CGSize]
        let conditionButtonWidth: CGFloat
        let buttonSpacing: CGFloat
    }

    private func calculateRowsWithButtons(
        chips: [ChipItemType],
        params: RowCalculationParams,
    ) -> [[ChipItemType]] {
        var rows: [[ChipItemType]] = []
        var currentRow: [ChipItemType] = []
        var currentRowWidth: CGFloat = 0

        for chip in chips {
            let chipWidth = params.chipSizes[chip.id]?.width ?? defaultChipWidth
            let chipSpacing = currentRow.isEmpty ? 0 : params.spacing
            let rowButtonSpace = params.conditionButtonWidth
            let chipsOnlyWidth = currentRowWidth + chipSpacing + chipWidth
            let effectiveAvailableWidth = params.availableWidth - rowButtonSpace

            if chipsOnlyWidth > effectiveAvailableWidth, !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = [chip]
                currentRowWidth = chipWidth
            } else {
                currentRow.append(chip)
                currentRowWidth = chipsOnlyWidth
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }
}

private enum ChipItemType: Identifiable, Hashable {
    case scope(paths: [String])
    case condition(Condition)

    var id: String {
        switch self {
        case let .scope(paths):
            "scope-\(paths.joined(separator: "-"))"
        case let .condition(condition):
            "condition-\(condition.propertyKey)"
        }
    }
}
