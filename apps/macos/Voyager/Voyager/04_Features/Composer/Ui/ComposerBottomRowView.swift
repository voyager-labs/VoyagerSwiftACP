import AppKit
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

    @State private var chipSizes: [String: CGSize] = [:]
    @State private var calculatedHeight: CGFloat = 0
    @State private var scopeOverlayCoordinator = ComposerScopeOverlayCoordinator()
    @State private var isAddButtonHovering: Bool = false
    @State private var isScopeEditButtonHovering: Bool = false

    private let chipHorizontalPadding: CGFloat = 16
    private let chipSpacing: CGFloat = 8
    private let chipVerticalPadding: CGFloat = 8
    private let maxChipAreaHeight: CGFloat = 200
    private let defaultChipHeight: CGFloat = 28
    private let scopeRowVerticalPadding: CGFloat = 0
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
}

private extension ComposerBottomRowView {
    private func secondRowContent(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        geometry: GeometryProxy,
    ) -> some View {
        let isLocked = viewStore.isLoadingSearch || viewStore.isFilteringInFlight
        let availableWidth = geometry.size.width - chipHorizontalPadding * 2
        let pickerStore = store.scope(state: \.propertyPicker, action: \.propertyPicker)
        let isScopePickerPresentedBinding = viewStore.binding(
            get: { $0.scopeEditor.isPresented },
            send: ComposerAction.scopeEditorSetPresented,
        )

        let layout = rowLayoutInput(viewStore: viewStore, availableWidth: availableWidth)

        return VStack(alignment: .leading, spacing: chipSpacing) {
            scopeRow(
                rows: layout.scopeRows,
                historyPaths: historyPaths,
                isPresented: isScopePickerPresentedBinding,
            )

            conditionRow(
                rows: layout.conditionRows,
                pickerStore: pickerStore,
                conditionDisplayByKey: viewStore.conditionDisplayByKey,
                operatorOptionsByKey: viewStore.operatorOptionsByKey,
                historyPaths: historyPaths,
            )
            .frame(maxWidth: .infinity, minHeight: defaultChipHeight, alignment: .leading)
        }
        .allowsHitTesting(!isLocked)
        .onPreferenceChange(ChipSizePreferenceKey.self) { sizes in
            handleChipSizeChange(
                sizes: sizes,
                scopeChips: layout.scopeChips,
                conditionChips: layout.conditionChips,
                scopeAvailableWidth: layout.scopeRowWidth,
                conditionAvailableWidth: layout.conditionRowWidth,
            )
        }
        .onAppear {
            updateCalculatedHeight(layout: layout)
        }
        .onChange(of: geometry.size.width) { _ in
            updateCalculatedHeight(layout: layout)
        }
        .onAppear {
            updateScopeOverlayCoordinator(isPresented: viewStore.scopeEditor.isPresented)
        }
        .onChange(of: viewStore.scopeEditor.isPresented) { isPresented in
            updateScopeOverlayCoordinator(isPresented: isPresented)
        }
        .onDisappear {
            scopeOverlayCoordinator.dismiss()
        }
        .padding(.horizontal, chipHorizontalPadding)
        .padding(.vertical, chipVerticalPadding)
    }

    private var scopeEditButtonWidth: CGFloat {
        defaultChipHeight + chipSpacing
    }

    private struct RowLayoutInput {
        let scopeChips: [ChipItemType]
        let conditionChips: [ChipItemType]
        let scopeRows: [[ChipItemType]]
        let conditionRows: [[ChipItemType]]
        let scopeRowWidth: CGFloat
        let conditionRowWidth: CGFloat
    }

    private func rowLayoutInput(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        availableWidth: CGFloat,
    ) -> RowLayoutInput {
        let scopeChips = scopeChipItems(for: viewStore.scopeEditor.selection)
        let conditionChips: [ChipItemType] = viewStore.conditions.map { .condition($0) } + [.conditionAdd]
        let scopeRowWidth = max(0, availableWidth - scopeEditButtonWidth)
        let conditionRowWidth = availableWidth

        return RowLayoutInput(
            scopeChips: scopeChips,
            conditionChips: conditionChips,
            scopeRows: calculateRows(
                chips: scopeChips,
                params: RowCalculationParams(
                    availableWidth: scopeRowWidth,
                    spacing: chipSpacing,
                    chipSizes: chipSizes,
                ),
            ),
            conditionRows: calculateRows(
                chips: conditionChips,
                params: RowCalculationParams(
                    availableWidth: conditionRowWidth,
                    spacing: chipSpacing,
                    chipSizes: chipSizes,
                ),
            ),
            scopeRowWidth: scopeRowWidth,
            conditionRowWidth: conditionRowWidth,
        )
    }

    private func updateCalculatedHeight(layout: RowLayoutInput) {
        updateCalculatedHeight(
            scopeChips: layout.scopeChips,
            conditionChips: layout.conditionChips,
            scopeAvailableWidth: layout.scopeRowWidth,
            conditionAvailableWidth: layout.conditionRowWidth,
        )
    }

    @ViewBuilder
    private func scopeRow(
        rows: [[ChipItemType]],
        historyPaths: [String],
        isPresented: Binding<Bool>,
    ) -> some View {
        HStack(alignment: .center, spacing: chipSpacing) {
            VStack(alignment: .leading, spacing: chipSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowChips in
                    HStack(spacing: chipSpacing) {
                        ForEach(Array(rowChips.enumerated()), id: \.element.id) { chipIndex, chip in
                            scopeChipView(chip: chip)
                                .background(
                                    GeometryReader { chipGeometry in
                                        Color.clear.preference(
                                            key: ChipSizePreferenceKey.self,
                                            value: [AnyHashable(chip.id): chipGeometry.size],
                                        )
                                    },
                                )
                                .if(rowIndex == 0 && chipIndex == 0) { view in
                                    view.accessibilityIdentifier("composer.scopeRow.firstChip")
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            scopeEditButton(historyPaths: historyPaths)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, scopeRowVerticalPadding)
        .frame(height: scopeRowHeight(rowCount: rows.count))
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .fill(VoyagerDS.Surface.chipContainerBackground(for: colorScheme)),
        )
        .background(
            ComposerAnchorFrameReader { frame, window in
                scopeOverlayCoordinator.updateAnchorScreenFrame(frame)
                if isPresented.wrappedValue {
                    updateScopeOverlayCoordinator(isPresented: true, parentWindow: window)
                }
            },
        )
        .accessibilityIdentifier("composer.scopeRow")
    }

    private func updateScopeOverlayCoordinator(
        isPresented: Bool,
        parentWindow: NSWindow? = nil,
    ) {
        scopeOverlayCoordinator.update(
            isPresented: isPresented,
            parentWindow: parentWindow,
            content: { height in
                AnyView(
                    ScopePickerView(store: store)
                        .frame(width: 420, height: height),
                )
            },
            onDismiss: {
                store.send(.scopeEditorSetPresented(false))
            },
        )
    }

    private func scopeEditButton(historyPaths: [String]) -> some View {
        Button {
            store.send(.scopeEditorOpen(editingPath: nil, favorites: favorites, backHistory: historyPaths))
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isScopeEditButtonHovering ? VoyagerDS.Interaction
                            .controlHoverFill(for: colorScheme) : .clear),
                )
                .frame(width: defaultChipHeight, height: defaultChipHeight)
        }
        .buttonStyle(.borderless)
        .onHover { hovering in
            isScopeEditButtonHovering = hovering
        }
        .accessibilityLabel("Edit scopes")
    }

    @ViewBuilder
    private func conditionRow(
        rows: [[ChipItemType]],
        pickerStore: StoreOf<ConditionPropertyPickerFeature>,
        conditionDisplayByKey: [String: ConditionDisplayState],
        operatorOptionsByKey: [String: [String]],
        historyPaths: [String],
    ) -> some View {
        VStack(alignment: .leading, spacing: chipSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowChips in
                HStack(spacing: chipSpacing) {
                    ForEach(Array(rowChips.enumerated()), id: \.element.id) { _, chip in
                        chipView(
                            chip: chip,
                            pickerStore: pickerStore,
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
                }
            }
        }
        .accessibilityIdentifier("composer.conditionRow")
    }

    private func scopeChipItems(for selection: ComposerScopeSelection) -> [ChipItemType] {
        switch selection {
        case .rootOnly:
            [.scopeRoot]
        case let .explicit(bases, _):
            bases.map { .scopeBase(path: $0.path) }
        }
    }

    @ViewBuilder
    private func scopeChipView(chip: ChipItemType) -> some View {
        switch chip {
        case .scopeRoot:
            ScopeTokenChipView(title: "This Mac", path: nil, onRemove: nil)
        case let .scopeBase(path):
            ScopeTokenChipView(
                title: scopeDisplayName(for: path),
                path: path,
                onRemove: { store.send(.currentScope(.remove(path: path))) },
            )
        case .condition, .conditionAdd:
            EmptyView()
        }
    }

    private func scopeDisplayName(for path: String) -> String {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let displayName = URL(fileURLWithPath: normalizedPath).lastPathComponent
        return displayName.isEmpty ? normalizedPath : displayName
    }

    @ViewBuilder
    private func chipView(
        chip: ChipItemType,
        pickerStore: StoreOf<ConditionPropertyPickerFeature>,
        conditionDisplayByKey: [String: ConditionDisplayState],
        operatorOptionsByKey: [String: [String]],
        historyPaths _: [String],
    ) -> some View {
        switch chip {
        case .scopeRoot, .scopeBase:
            scopeChipView(chip: chip)

        case .conditionAdd:
            conditionAddButton(pickerStore: pickerStore)

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
        scopeChips: [ChipItemType],
        conditionChips: [ChipItemType],
        scopeAvailableWidth: CGFloat,
        conditionAvailableWidth: CGFloat,
    ) {
        for chip in scopeChips + conditionChips {
            let anyId = AnyHashable(chip.id)
            if let size = sizes[anyId] {
                chipSizes[chip.id] = size
            }
        }
        updateCalculatedHeight(
            scopeChips: scopeChips,
            conditionChips: conditionChips,
            scopeAvailableWidth: scopeAvailableWidth,
            conditionAvailableWidth: conditionAvailableWidth,
        )
    }

    private func scopeRowHeight(rowCount: Int) -> CGFloat {
        let safeRowCount = max(rowCount, 1)
        let chipsHeight = CGFloat(safeRowCount) * defaultChipHeight
        let spacingHeight = CGFloat(max(0, safeRowCount - 1)) * chipSpacing
        return chipsHeight + spacingHeight + scopeRowVerticalPadding * 2
    }

    private func updateCalculatedHeight(
        scopeChips: [ChipItemType],
        conditionChips: [ChipItemType],
        scopeAvailableWidth: CGFloat,
        conditionAvailableWidth: CGFloat,
    ) {
        let scopeRows = calculateRows(
            chips: scopeChips,
            params: RowCalculationParams(
                availableWidth: scopeAvailableWidth,
                spacing: chipSpacing,
                chipSizes: chipSizes,
            ),
        )
        let conditionRows = calculateRows(
            chips: conditionChips,
            params: RowCalculationParams(
                availableWidth: conditionAvailableWidth,
                spacing: chipSpacing,
                chipSizes: chipSizes,
            ),
        )
        let scopeHeight = scopeRowHeight(rowCount: scopeRows.count)
        let conditionHeight = max(
            calculateTotalHeight(rows: conditionRows, chipSizes: chipSizes, spacing: chipSpacing),
            defaultChipHeight,
        )
        let contentHeight = scopeHeight + chipSpacing + conditionHeight
        let paddingHeight = chipVerticalPadding * 2
        calculatedHeight = min(contentHeight + paddingHeight, maxChipAreaHeight)
    }

    private func calculateTotalHeight(
        rows: [[ChipItemType]],
        chipSizes: [String: CGSize],
        spacing: CGFloat,
    ) -> CGFloat {
        let rowsHeight = rows.reduce(CGFloat.zero) { partialHeight, row in
            let rowHeight = row.map { chipSizes[$0.id]?.height ?? defaultChipHeight }.max() ?? 0
            return partialHeight + rowHeight
        }
        return rowsHeight + CGFloat(max(0, rows.count - 1)) * spacing
    }

    private struct RowCalculationParams {
        let availableWidth: CGFloat, spacing: CGFloat, chipSizes: [String: CGSize]
    }

    private func calculateRows(
        chips: [ChipItemType],
        params: RowCalculationParams,
    ) -> [[ChipItemType]] {
        var rows: [[ChipItemType]] = []
        var currentRow: [ChipItemType] = []
        var currentRowWidth: CGFloat = 0

        for chip in chips {
            let chipWidth = params.chipSizes[chip.id]?.width ?? defaultChipWidth
            let chipSpacing = currentRow.isEmpty ? 0 : params.spacing
            let chipsOnlyWidth = currentRowWidth + chipSpacing + chipWidth

            if chipsOnlyWidth > params.availableWidth, !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = [chip]
                currentRowWidth = chipWidth
            } else {
                currentRow.append(chip)
                currentRowWidth = chipsOnlyWidth
            }
        }

        if !currentRow.isEmpty { rows.append(currentRow) }
        return rows
    }
}
