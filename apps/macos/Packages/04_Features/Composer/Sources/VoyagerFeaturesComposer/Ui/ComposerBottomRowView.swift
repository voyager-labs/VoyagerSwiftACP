import AppKit
import ComposableArchitecture
import SwiftUI

struct ComposerBottomRowView: View {
    let store: StoreOf<ComposerFeature>
    let favorites: [ScopeFavoriteItem]
    let historyPaths: [String]
    let colorScheme: ColorScheme

    @State private var chipSizes: [String: CGSize] = [:]
    @State private var calculatedHeight: CGFloat = 0
    @State private var scopeOverlayCoordinator = ComposerScopeOverlayCoordinator()
    @State private var isScopeEditButtonHovering: Bool = false

    private let chipHorizontalPadding: CGFloat = 16
    private let chipSpacing: CGFloat = 8
    private let chipVerticalPadding: CGFloat = 8
    private let maxChipAreaHeight: CGFloat = 200
    private let defaultChipHeight: CGFloat = 28
    private var conditionChipHeight: CGFloat { defaultChipHeight }
    private let scopeRowVerticalPadding: CGFloat = 0
    private let defaultChipWidth: CGFloat = 120
    private let conditionRowVerticalPadding: CGFloat = 0
    private let conditionRowHorizontalPadding: CGFloat = 0

    private var conditionRowHeight: CGFloat { defaultChipHeight }

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
            scopeSection(
                rows: layout.scopeRows,
                historyPaths: historyPaths,
                isPresented: isScopePickerPresentedBinding,
            )

            conditionSection(
                rows: layout.conditionRows,
                pickerStore: pickerStore,
                conditionDisplayByKey: viewStore.conditionDisplayByKey,
                operatorOptionsByKey: viewStore.operatorOptionsByKey,
            )
        }
        .allowsHitTesting(!isLocked)
        .onPreferenceChange(ComposerBottomRowChipSizePreferenceKey.self) { sizes in
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

    @ViewBuilder
    private func scopeSection(
        rows: [[ChipItemType]],
        historyPaths: [String],
        isPresented: Binding<Bool>,
    ) -> some View {
        scopeRow(rows: rows, historyPaths: historyPaths, isPresented: isPresented)
    }

    @ViewBuilder
    private func conditionSection(
        rows: [[ChipItemType]],
        pickerStore: StoreOf<ConditionPropertyPickerFeature>,
        conditionDisplayByKey: [String: ConditionDisplayState],
        operatorOptionsByKey: [String: [String]],
    ) -> some View {
        ComposerBottomConditionRowView(
            store: store,
            pickerStore: pickerStore,
            rows: rows,
            conditionDisplayByKey: conditionDisplayByKey,
            operatorOptionsByKey: operatorOptionsByKey,
            colorScheme: colorScheme,
            chipSpacing: chipSpacing,
            rowHeight: conditionRowHeight,
            chipHeight: conditionChipHeight,
        )
        .padding(.horizontal, conditionRowHorizontalPadding)
        .padding(.vertical, conditionRowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: conditionRowHeight, alignment: .leading)
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
                availableWidth: scopeRowWidth,
            ),
            conditionRows: calculateRows(
                chips: conditionChips,
                availableWidth: conditionRowWidth,
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
                                            key: ComposerBottomRowChipSizePreferenceKey.self,
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

    private func calculateTotalHeight(
        rows: [[ChipItemType]],
        minimumRowHeight: CGFloat = 0,
    ) -> CGFloat {
        let rowsHeight = rows.reduce(CGFloat.zero) { partialHeight, row in
            let rowHeight = row.map { chipSizes[$0.id]?.height ?? defaultChipHeight }.max() ?? 0
            return partialHeight + max(rowHeight, minimumRowHeight)
        }
        return rowsHeight + CGFloat(max(0, rows.count - 1)) * chipSpacing
    }

    private func calculateRows(
        chips: [ChipItemType],
        availableWidth: CGFloat,
    ) -> [[ChipItemType]] {
        var rows: [[ChipItemType]] = []
        var currentRow: [ChipItemType] = []
        var currentRowWidth: CGFloat = 0

        for chip in chips {
            let chipWidth = chipSizes[chip.id]?.width ?? defaultChipWidth
            let spacing = currentRow.isEmpty ? 0 : chipSpacing
            let chipsOnlyWidth = currentRowWidth + spacing + chipWidth

            if chipsOnlyWidth > availableWidth, !currentRow.isEmpty {
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

    private func updateCalculatedHeight(
        scopeChips: [ChipItemType],
        conditionChips: [ChipItemType],
        scopeAvailableWidth: CGFloat,
        conditionAvailableWidth: CGFloat,
    ) {
        let scopeRows = calculateRows(
            chips: scopeChips,
            availableWidth: scopeAvailableWidth,
        )
        let conditionRows = calculateRows(
            chips: conditionChips,
            availableWidth: conditionAvailableWidth,
        )
        let scopeHeight = scopeRowHeight(rowCount: scopeRows.count)
        let conditionHeight = max(
            calculateTotalHeight(
                rows: conditionRows,
                minimumRowHeight: conditionRowHeight,
            )
                + conditionRowVerticalPadding * 2,
            conditionRowHeight,
        )
        let contentHeight = scopeHeight + chipSpacing + conditionHeight
        let paddingHeight = chipVerticalPadding * 2
        calculatedHeight = min(contentHeight + paddingHeight, maxChipAreaHeight)
    }
}
