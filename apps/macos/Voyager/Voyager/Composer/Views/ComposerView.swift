import AppKit
import ComposableArchitecture
import SwiftUI

private struct ChipSizePreferenceKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGSize] = [:]

    static func reduce(value: inout [AnyHashable: CGSize], nextValue: () -> [AnyHashable: CGSize]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// swiftlint:disable type_body_length file_length
struct ComposerView: View {
    let store: StoreOf<ComposerFeature>
    let favorites: [ScopeFavoriteItem]
    let historyPaths: [String]
    let isDiscardEnabled: Bool
    let canSaveCollection: Bool
    let isTemporaryCollection: Bool
    let onDiscardCollectionChanges: () -> Void
    let onExitComposer: () -> Void
    @State private var isComposeFieldFirstResponder: Bool = true
    @Environment(\.colorScheme)
    private var colorScheme: ColorScheme
    @State private var keyDownMonitor: Any?
    @State private var flagsChangedMonitor: Any?
    @State private var isOptionKeyPressed: Bool = false
    @State private var isAddButtonHovering: Bool = false
    @State private var isScopePickerPresented: Bool = false
    @State private var isUndoHovering: Bool = false
    @State private var isRedoHovering: Bool = false
    @State private var isStopHovering: Bool = false
    @State private var isSubmitHovering: Bool = false
    @State private var isClearHovering: Bool = false
    @State private var isSaveHovering: Bool = false

    private let escapeKeyCode: UInt16 = 53
    private let zKeyCode: UInt16 = 6

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        WithViewStore(store, observe: { $0.isPresented }, content: { viewStore in
            mainContent
                .onAppear {
                    setupOnAppear()
                }
                .onDisappear {
                    cleanupKeyMonitor()
                }
                .onChange(of: viewStore.state) { isPresented in
                    if !isPresented {
                        cleanupKeyMonitor()
                    }
                }
        })
    }

    private var mainContent: some View {
        let composerStore = store

        return VStack(spacing: 0) {
            WithViewStore(composerStore, observe: { $0 }, content: { viewStore in
                firstRow(viewStore: viewStore)
                    .fixedSize(horizontal: false, vertical: true)
                horizontalSeparator
                secondRow(viewStore: viewStore, composerStore: composerStore)
                    .fixedSize(horizontal: false, vertical: true)
            })
        }
        .background(
            VisualEffectBackgroundView(
                material: .popover,
                blendingMode: .withinWindow,
                tintColor: NSColor(VoyagerDS.Interaction.composerBackground(for: colorScheme)),
                tintOpacity: isDark ? 0.15 : 0.15,
            )
            .clipShape(RoundedRectangle(cornerRadius: VoyagerDS.Radius.composer))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.composer)
                    .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.12), lineWidth: 1),
            )
            .shadow(
                color: Color.black.opacity(isDark ? 0.45 : 0.18),
                radius: isDark ? 18 : 12,
                x: 0,
                y: isDark ? 10 : 6,
            )
            .allowsHitTesting(false),
        )
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func firstRow(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        let isLocked = viewStore.isLoadingSearch || viewStore.isFilteringInFlight
        HStack(spacing: 8) {
            undoButton(viewStore: viewStore, isLocked: isLocked)
            redoButton(viewStore: viewStore, isLocked: isLocked)
            textField(viewStore: viewStore, isLocked: isLocked)
                .frame(maxWidth: .infinity, alignment: .leading)
            clearButton(viewStore: viewStore, isLocked: isLocked)
            saveButton(viewStore: viewStore, isLocked: isLocked)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(height: 40)
    }

    @ViewBuilder
    private func undoButton(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool,
    ) -> some View {
        let isEnabled = viewStore.canUndo && !isLocked
        Button {
            store.send(.undo)
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 13))
                .foregroundColor(isEnabled ? .primary : .secondary)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isEnabled && isUndoHovering ? VoyagerDS.Interaction
                            .controlHoverFill(for: colorScheme) : .clear),
                )
        }
        .disabled(!isEnabled)
        .buttonStyle(.borderless)
        .onHover { hovering in
            isUndoHovering = hovering
        }
    }

    @ViewBuilder
    private func redoButton(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool,
    ) -> some View {
        let isEnabled = viewStore.canRedo && !isLocked
        Button {
            store.send(.redo)
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 13))
                .foregroundColor(isEnabled ? .primary : .secondary)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isEnabled && isRedoHovering ? VoyagerDS.Interaction
                            .controlHoverFill(for: colorScheme) : .clear),
                )
        }
        .disabled(!isEnabled)
        .buttonStyle(.borderless)
        .onHover { hovering in
            isRedoHovering = hovering
        }
    }

    private func textField(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool,
    ) -> some View {
        ZStack(alignment: .trailing) {
            let isSubmitDisabled = viewStore.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            queryInputField(viewStore: viewStore, isSubmitDisabled: isSubmitDisabled, isLocked: isLocked)

            if viewStore.isLoadingSearch || viewStore.isFilteringInFlight {
                stopButton(viewStore: viewStore)
            } else {
                submitButton(viewStore: viewStore, isLocked: isLocked, isSubmitDisabled: isSubmitDisabled)
            }
        }
        .frame(minHeight: 30)
    }

    @ViewBuilder
    private func stopButton(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        let buttonBackground = Circle().fill(VoyagerDS.BrandSecondaryColor.c500)
        Button {
            if viewStore.isLoadingSearch {
                viewStore.send(.cancelSearch)
            } else {
                viewStore.send(.cancelFilters)
            }
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(.black)
                .frame(width: 16, height: 16)
                .background(buttonBackground)
        }
        .buttonStyle(.borderless)
        .background(
            Circle()
                .fill(isStopHovering ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme) : .clear)
                .frame(width: 20, height: 20),
        )
        .padding(.trailing, 8)
        .onHover { hovering in
            isStopHovering = hovering
        }
    }

    @ViewBuilder
    private func submitButton(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool,
        isSubmitDisabled: Bool,
    ) -> some View {
        let submitButtonBackground = Circle().fill(
            isSubmitDisabled
                ? VoyagerDS.BrandSecondaryColor.c500.opacity(0.5)
                : VoyagerDS.BrandSecondaryColor.c500,
        )
        Button {
            viewStore.send(.submit)
        } label: {
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(isSubmitDisabled ? .secondary : .black)
                .frame(width: 16, height: 16)
                .background(submitButtonBackground)
        }
        .buttonStyle(.borderless)
        .disabled(isSubmitDisabled || isLocked)
        .background(
            Circle()
                .fill(!isSubmitDisabled && !isLocked && isSubmitHovering
                    ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme)
                    : .clear)
                .frame(width: 20, height: 20),
        )
        .background(
            Circle()
                .fill(
                    isSubmitDisabled
                        ? Color(red: 0.843, green: 0.714, blue: 0.322).opacity(0.5)
                        : Color(red: 0.843, green: 0.714, blue: 0.322),
                )
                .allowsHitTesting(false),
        )
        .padding(.trailing, 8)
        .onHover { hovering in
            isSubmitHovering = hovering
        }
    }

    private func queryInputField(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isSubmitDisabled _: Bool,
        isLocked: Bool,
    ) -> some View {
        let placeholderText = "Enter your request..."

        return ZStack(alignment: .leading) {
            if viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholderText)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                    .padding(.leading, 12)
            }

            FocusedTextField(
                text: viewStore.binding(get: \.text, send: ComposerFeature.Action.setText),
                isFirstResponder: Binding(
                    get: { isComposeFieldFirstResponder },
                    set: { isComposeFieldFirstResponder = $0 },
                ),
                onCommit: {
                    let trimmed = viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { viewStore.send(.submit) }
                },
            )
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .padding(.trailing, 28)
            .disabled(isLocked)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(VoyagerDS.Surface.inputBackground(for: colorScheme)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(VoyagerDS.Surface.inputBorder(for: colorScheme), lineWidth: 1),
        )
        .onSubmit {
            let trimmed = viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { viewStore.send(.submit) }
        }
        .onChange(of: viewStore.isPresented) { presented in
            if presented {
                isComposeFieldFirstResponder = true
            }
        }
        .onChange(of: viewStore.focusRequestID) { _ in
            isComposeFieldFirstResponder = true
        }
    }

    private func clearButton(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool,
    ) -> some View {
        let trimmedText = viewStore.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRootScopeOnly = viewStore.scopes == [ComposerScopeUtils.rootScopePath]
        let isAllEmpty = trimmedText.isEmpty && viewStore.conditions.isEmpty
            && (viewStore.scopes.isEmpty || isRootScopeOnly)
        let isDiscard = isDiscardEnabled
        let isEnabled = isDiscard
            ? !isLocked
            : (!isLocked && !isAllEmpty)
        return Button {
            if isDiscard {
                onDiscardCollectionChanges()
            } else {
                viewStore.send(.clearAll)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.square")
                Text(isDiscard ? "Discard" : "Clear")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    .allowsHitTesting(false),
            )
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isEnabled && isClearHovering ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme) : .clear)
                .allowsHitTesting(false),
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                .allowsHitTesting(false),
        )
        .onHover { hovering in
            isClearHovering = hovering
        }
    }

    private func saveButton(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isLocked: Bool,
    ) -> some View {
        let isEnabled = canSaveCollection && !isLocked
        let isSaveAs = !isTemporaryCollection && isOptionKeyPressed
        return Button {
            viewStore.send(isSaveAs ? .saveCollectionAs : .saveCollection)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSaveAs ? "square.and.arrow.down" : "tray.and.arrow.down")
                Text(isSaveAs ? "Save As" : "Save")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    .allowsHitTesting(false),
            )
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isEnabled && isSaveHovering ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme) : .clear)
                .allowsHitTesting(false),
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                .allowsHitTesting(false),
        )
        .onHover { hovering in
            isSaveHovering = hovering
        }
    }

    private var horizontalSeparator: some View {
        Rectangle()
            .fill(VoyagerDS.SystemColor.separator)
            .frame(height: 1)
            .padding(.horizontal, 16)
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

    @State private var chipSizes: [String: CGSize] = [:]
    @State private var calculatedHeight: CGFloat = 0

    private let chipHorizontalPadding: CGFloat = 16
    private let chipSpacing: CGFloat = 8
    private let chipVerticalPadding: CGFloat = 8
    private let conditionButtonWidth: CGFloat = 20
    private let maxChipAreaHeight: CGFloat = 200
    private let defaultChipHeight: CGFloat = 28
    private let defaultChipWidth: CGFloat = 120
    private let hoverFillOpacity: Double = 0.06

    private func secondRow(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        composerStore: StoreOf<ComposerFeature>,
    ) -> some View {
        GeometryReader { geometry in
            secondRowContent(
                viewStore: viewStore,
                composerStore: composerStore,
                geometry: geometry,
            )
        }
        .frame(height: calculatedHeight)
    }

    private func secondRowContent(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        composerStore: StoreOf<ComposerFeature>,
        geometry: GeometryProxy,
    ) -> some View {
        let isLocked = viewStore.isLoadingSearch || viewStore.isFilteringInFlight
        let availableWidth = geometry.size.width - chipHorizontalPadding * 2
        let pickerStore = composerStore.scope(state: \.propertyPicker, action: \.propertyPicker)

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
            composerStore: composerStore,
            pickerStore: pickerStore,
            operatorOptionsByKey: viewStore.operatorOptionsByKey,
            historyPaths: historyPaths,
        )
        .allowsHitTesting(!isLocked)
        .opacity(isLocked ? 0.6 : 1)
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
        composerStore: StoreOf<ComposerFeature>,
        operatorOptionsByKey: [String: [String]],
        historyPaths: [String],
    ) -> some View {
        switch chip {
        case let .scope(paths):
            ScopeChipView(
                paths: paths,
                store: composerStore,
                favorites: favorites,
                backHistory: historyPaths,
                isComboBoxPresented: $isScopePickerPresented,
            )
        case let .condition(condition):
            conditionChipView(condition: condition, operatorOptionsByKey: operatorOptionsByKey)
        }
    }

    private func chipRowsView(
        rows: [[ChipItemType]],
        composerStore: StoreOf<ComposerFeature>,
        pickerStore: StoreOf<ConditionPropertyPickerFeature>,
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
                            composerStore: composerStore,
                            operatorOptionsByKey: operatorOptionsByKey,
                            historyPaths: historyPaths,
                        )
                        .background(
                            GeometryReader { chipGeometry in
                                Color.clear
                                    .preference(
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

    private func conditionChipView(
        condition: Condition,
        operatorOptionsByKey: [String: [String]],
    ) -> some View {
        ConditionChipView(
            propertyPickerStore: store.scope(state: \.propertyPicker, action: \.propertyPicker),
            condition: condition,
            isDark: isDark,
            hoverFillOpacity: hoverFillOpacity,
            operatorPickerStore: store.scope(state: \.operatorPicker, action: \.operatorPicker),
            valuePickerStore: store.scope(state: \.valuePicker, action: \.valuePicker),
            operatorOptions: operatorOptionsByKey[condition.propertyKey] ?? [],
            defaultChipHeight: defaultChipHeight,
            onPropertyTap: {
                store.send(.propertyPicker(.startEditing(condition.propertyKey)))
            },
            onRemove: {
                store.send(.removeCondition(propertyKey: condition.propertyKey))
            },
        )
    }

    private func conditionAddButton(pickerStore: StoreOf<ConditionPropertyPickerFeature>) -> some View {
        WithViewStore(pickerStore, observe: { $0 }, content: { viewStore in
            addButton {
                viewStore.send(.setPresented(true))
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
        })
    }

    private func setupOnAppear() {
        DispatchQueue.main.async {
            isComposeFieldFirstResponder = true
        }
        isOptionKeyPressed = NSEvent.modifierFlags.contains(.option)

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == escapeKeyCode {
                if isScopePickerPresented {
                    isScopePickerPresented = false
                    return nil
                }
                if store.propertyPicker.isPresented {
                    store.send(.propertyPicker(.setPresented(false)))
                    return nil
                }
                if store.operatorPicker.isPresented {
                    store.send(.operatorPicker(.setPresented(false)))
                    return nil
                }
                if store.valuePicker.isPresented {
                    store.send(.valuePicker(.setPresented(false)))
                    return nil
                }
                onExitComposer()
                return nil
            }
            if event.keyCode == zKeyCode, event.modifierFlags.contains(.command) {
                if event.modifierFlags.contains(.shift) {
                    if store.canRedo {
                        store.send(.redo)
                    }
                } else {
                    if store.canUndo {
                        store.send(.undo)
                    }
                }
                return nil
            }
            return event
        }

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            isOptionKeyPressed = event.modifierFlags.contains(.option)
            return event
        }
    }

    private func addButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: defaultChipHeight, height: defaultChipHeight)
                .background(
                    RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                        .fill(isAddButtonHovering ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme) : .clear),
                )
        }
        .buttonStyle(.borderless)
        .onHover { hovering in
            isAddButtonHovering = hovering
        }
    }

    private func cleanupKeyMonitor() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
    }
}

// swiftlint:enable type_body_length
