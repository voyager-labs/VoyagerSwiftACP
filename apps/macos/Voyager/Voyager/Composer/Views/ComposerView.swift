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
    let store: StoreOf<FileManagerFeature>
    @State private var isComposeFieldFirstResponder: Bool = true
    @Environment(\.colorScheme)
    private var colorScheme: ColorScheme
    @State private var keyDownMonitor: Any?
    @State private var flagsChangedMonitor: Any?
    @State private var isOptionKeyPressed: Bool = false
    @State private var isAddButtonHovering: Bool = false

    private let trafficLightAreaWidth: CGFloat = 80
    private let escapeKeyCode: UInt16 = 53
    private let zKeyCode: UInt16 = 6

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        mainContent
            .onAppear {
                setupOnAppear()
            }
            .onDisappear {
                cleanupKeyMonitor()
            }
            .onChange(of: store.composer.isPresented) { isPresented in
                if !isPresented {
                    cleanupKeyMonitor()
                }
            }
    }

    private var mainContent: some View {
        let composerStore = store.scope(state: \.composer, action: \.composer)

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
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard)
                .fill(VoyagerDS.Surface.overlayBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard)
                        .stroke(VoyagerDS.Surface.overlayBorder, lineWidth: 1),
                )
                .shadow(
                    color: VoyagerDS.Shadow.overlayColor(for: colorScheme),
                    radius: VoyagerDS.Shadow.overlayRadius(for: colorScheme),
                    y: VoyagerDS.Shadow.overlayYOffset(for: colorScheme),
                )
                .allowsHitTesting(false),
        )
    }

    private func firstRow(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        HStack(spacing: 8) {
            undoButton(viewStore: viewStore)
            redoButton(viewStore: viewStore)
            textField(viewStore: viewStore)
            clearButton(viewStore: viewStore)
            saveButton(viewStore: viewStore)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.leading, store.sidebarVisible ? 0 : trafficLightAreaWidth)
        .padding(.vertical, 6)
        .frame(height: 40)
    }

    @ViewBuilder
    private func undoButton(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        let isEnabled = viewStore.canUndo && !viewStore.isLoadingSearch
        Button {
            store.send(.composer(.undo))
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 13))
                .foregroundColor(isEnabled ? .primary : .secondary)
        }
        .disabled(!isEnabled)
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func redoButton(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        let isEnabled = viewStore.canRedo && !viewStore.isLoadingSearch
        Button {
            store.send(.composer(.redo))
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 13))
                .foregroundColor(isEnabled ? .primary : .secondary)
        }
        .disabled(!isEnabled)
        .buttonStyle(.borderless)
    }

    private func textField(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        ZStack(alignment: .trailing) {
            let isSubmitDisabled = viewStore.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            queryInputField(viewStore: viewStore, isSubmitDisabled: isSubmitDisabled)

            let buttonBackground = Circle().fill(VoyagerDS.BrandSecondaryColor.c500)
            if viewStore.isLoadingSearch {
                Button {
                    viewStore.send(.cancelSearch)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.black)
                        .frame(width: 16, height: 16)
                        .background(buttonBackground)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            } else {
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
                .buttonStyle(.plain)
                .disabled(isSubmitDisabled)
                .padding(.trailing, 8)
            }
        }
        .frame(minHeight: 30)
    }

    private func queryInputField(
        viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>,
        isSubmitDisabled _: Bool,
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

    private func clearButton(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        Button {
            store.send(.composer(.clearAll))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.square")
                Text("Clear all")
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)),
            )
        }
        .buttonStyle(.plain)
        .disabled(viewStore.isLoadingSearch)
    }

    private func saveButton(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        let isEnabled = store.canSaveCollection && !viewStore.isLoadingSearch
        let isTemporaryCollection = store.openedCollectionURL == nil
        let isSaveAs = !isTemporaryCollection && isOptionKeyPressed
        return Button {
            store.send(.composer(isSaveAs ? .saveCollectionAs : .saveCollection))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSaveAs ? "square.and.arrow.down" : "tray.and.arrow.down")
                Text(isSaveAs ? "Save As" : "Save")
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)),
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
        let leadingPadding = store.sidebarVisible ? 0 : trafficLightAreaWidth
        let availableWidth = geometry.size.width - chipHorizontalPadding * 2 - leadingPadding
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
        let historyPaths: [String] = store.backHistory.compactMap { entry in
            if case let .folder(path) = entry.navigationState {
                path
            } else {
                nil
            }
        }

        return chipRowsView(
            rows: rows,
            composerStore: composerStore,
            pickerStore: pickerStore,
            historyPaths: historyPaths,
        )
        .allowsHitTesting(!viewStore.isLoadingSearch)
        .opacity(viewStore.isLoadingSearch ? 0.6 : 1)
        .onPreferenceChange(ChipSizePreferenceKey.self) { sizes in
            handleChipSizeChange(sizes: sizes, allChips: allChips, availableWidth: availableWidth)
        }
        .onAppear {
            updateCalculatedHeight(chips: allChips, availableWidth: availableWidth)
        }
        .padding(.horizontal, chipHorizontalPadding)
        .padding(.leading, leadingPadding)
        .padding(.vertical, chipVerticalPadding)
    }

    @ViewBuilder
    private func chipView(
        chip: ChipItemType,
        composerStore: StoreOf<ComposerFeature>,
        historyPaths: [String],
    ) -> some View {
        switch chip {
        case let .scope(paths):
            ScopeChipView(
                paths: paths,
                store: composerStore,
                favorites: store.favorites,
                backHistory: historyPaths,
            )
        case let .condition(condition):
            conditionChipView(condition: condition)
        }
    }

    private func chipRowsView(
        rows: [[ChipItemType]],
        composerStore: StoreOf<ComposerFeature>,
        pickerStore: StoreOf<ConditionPropertyPickerFeature>,
        historyPaths: [String],
    ) -> some View {
        VStack(alignment: .leading, spacing: chipSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowChips in
                let isLastRow = rowIndex == rows.count - 1

                HStack(spacing: chipSpacing) {
                    ForEach(Array(rowChips.enumerated()), id: \.element.id) { _, chip in
                        chipView(chip: chip, composerStore: composerStore, historyPaths: historyPaths)
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

    private func conditionChipView(condition: Condition) -> some View {
        ConditionChipView(
            propertyPickerStore: store.scope(state: \.composer.propertyPicker, action: \.composer.propertyPicker),
            condition: condition,
            isDark: isDark,
            hoverFillOpacity: hoverFillOpacity,
            operatorPickerStore: store.scope(state: \.composer.operatorPicker, action: \.composer.operatorPicker),
            valuePickerStore: store.scope(state: \.composer.valuePicker, action: \.composer.valuePicker),
            operatorOptions: operatorOptions(for: condition),
            defaultChipHeight: defaultChipHeight,
            onPropertyTap: {
                store.send(.composer(.propertyPicker(.startEditing(condition.propertyKey))))
            },
            onRemove: {
                store.send(.composer(.removeCondition(propertyKey: condition.propertyKey)))
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
                if store.composer.valuePicker.isPresented {
                    store.send(.composer(.valuePicker(.setPresented(false))))
                    return nil
                }
                store.send(.exitComposer)
                return nil
            }
            if event.keyCode == zKeyCode, event.modifierFlags.contains(.command) {
                if event.modifierFlags.contains(.shift) {
                    if store.composer.canRedo {
                        store.send(.composer(.redo))
                    }
                } else {
                    if store.composer.canUndo {
                        store.send(.composer(.undo))
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

    private func operatorOptions(for condition: Condition) -> [OperatorOption] {
        ConditionOperatorMapping.operatorOptions(for: condition.propertyKey).map { op in
            let valueArity: Int = {
                switch op.valueUI {
                case .rangeNumber, .rangeDate:
                    2
                case .none:
                    0
                default:
                    1
                }
            }()

            let valueType: ValueType = {
                switch op.valueUI {
                case .singleNumber, .rangeNumber, .listNumber:
                    .number
                case .singleDate, .rangeDate:
                    .date
                case .toggle:
                    .boolean
                case .listText, .singleText, .none:
                    .string
                }
            }()

            return OperatorOption(
                code: op.code,
                label: op.label,
                valueArity: valueArity,
                valueType: valueType,
                valueUIKind: op.valueUI,
            )
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
