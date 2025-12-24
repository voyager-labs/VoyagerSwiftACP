import AppKit
import ComposableArchitecture
import SwiftUI

private struct ChipSizePreferenceKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGSize] = [:]

    static func reduce(value: inout [AnyHashable: CGSize], nextValue: () -> [AnyHashable: CGSize]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// swiftlint:disable type_body_length
struct ComposerView: View {
    let store: StoreOf<FileManagerFeature>
    @State private var isDark: Bool = isDarkMode()
    @FocusState private var isComposeFieldFocused: Bool
    @Environment(\.colorScheme)
    private var colorScheme: ColorScheme
    @State private var escKeyMonitor: Any?

    private let trafficLightAreaWidth: CGFloat = 80
    private let escapeKeyCode: UInt16 = 53

    var body: some View {
        mainContent
            .onAppear {
                setupOnAppear()
            }
            .onDisappear {
                cleanupEscKeyMonitor()
            }
            .onChange(of: colorScheme) { newScheme in
                isDark = newScheme == .dark
            }
            .onChange(of: store.composer.isPresented) { isPresented in
                if !isPresented {
                    cleanupEscKeyMonitor()
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
            RoundedRectangle(cornerRadius: 12)
                .fill(overlayBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(overlayBorderColor, lineWidth: 1),
                )
                .shadow(color: overlayShadowColor, radius: overlayShadowRadius, y: overlayShadowY),
        )
    }

    private func firstRow(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        HStack(spacing: 12) {
            undoButton
            redoButton
            textField(viewStore: viewStore)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.leading, store.sidebarVisible ? 0 : trafficLightAreaWidth)
        .padding(.vertical, 10)
        .frame(height: 48)
    }

    private var undoButton: some View {
        Button {
            // TODO: Undo 기능 추후 구현
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
    }

    private var redoButton: some View {
        Button {
            // TODO: Redo 기능 추후 구현
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
    }

    private func textField(viewStore: ViewStore<ComposerFeature.State, ComposerFeature.Action>) -> some View {
        TextField(
            "Enter your request...",
            text: viewStore.binding(get: \.text, send: ComposerFeature.Action.setText),
        )
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.12), lineWidth: 1),
        )
        .focused($isComposeFieldFocused)
        .onSubmit {
            // TODO: Enter 시 동작 추후 구현
        }
    }

    private var horizontalSeparator: some View {
        Rectangle()
            .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
            .frame(height: 1)
    }

    private enum ChipItemType: Identifiable, Hashable {
        case scope(paths: [String])
        case condition(propertyLabel: String)

        var id: String {
            switch self {
            case let .scope(paths):
                "scope-\(paths.joined(separator: "-"))"
            case let .condition(propertyLabel):
                "condition-\(propertyLabel)"
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

        let scopeChips: [ChipItemType] = viewStore.scopes.isEmpty
            ? []
            : [.scope(paths: viewStore.scopes)]
        let conditionChips: [ChipItemType] = viewStore.conditions.map { condition in
            // TODO(voy-95): operator, value 추가 후 포맷팅 로직 구현
            .condition(propertyLabel: condition.propertyLabel)
        }
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
            ComposerScopeChipView(
                paths: paths,
                store: composerStore,
                isDark: isDark,
                favorites: store.favorites,
                backHistory: historyPaths,
            )
        case let .condition(propertyLabel):
            conditionChipView(propertyLabel: propertyLabel)
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

    private func conditionChipView(propertyLabel: String) -> some View {
        HStack(spacing: 4) {
            Text(propertyLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))
            Text("select operator...")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .frame(height: defaultChipHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)),
        )
    }

    private func conditionAddButton(pickerStore: StoreOf<ConditionPropertyPickerFeature>) -> some View {
        WithViewStore(pickerStore, observe: { $0 }, content: { viewStore in
            addButton {
                viewStore.send(.setPresented(true))
            }
            .popover(
                isPresented: viewStore.binding(
                    get: \.isPresented,
                    send: ConditionPropertyPickerFeature.Action.setPresented,
                ),
                arrowEdge: .bottom,
                content: {
                    ConditionPropertyPickerView(store: pickerStore)
                },
            )
        })
    }

    private func setupOnAppear() {
        isDark = isDarkMode()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isComposeFieldFocused = true
        }
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == escapeKeyCode {
                store.send(.exitComposer)
                return nil
            }
            return event
        }
    }

    private var overlayBackground: Color {
        if isDark {
            Color(red: 0.19, green: 0.19, blue: 0.19)
        } else {
            Color.white
        }
    }

    private var overlayBorderColor: Color {
        if isDark {
            Color.white.opacity(0.1)
        } else {
            Color.black.opacity(0.12)
        }
    }

    private var overlayShadowColor: Color {
        if isDark {
            Color.black.opacity(0.4)
        } else {
            Color.black.opacity(0.15)
        }
    }

    private var overlayShadowRadius: CGFloat {
        if isDark {
            24
        } else {
            16
        }
    }

    private var overlayShadowY: CGFloat {
        if isDark {
            12
        } else {
            8
        }
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
            .frame(width: 1)
            .frame(height: 20)
    }

    private func addButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: defaultChipHeight, height: defaultChipHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)),
                )
        }
        .buttonStyle(.borderless)
    }

    private func cleanupEscKeyMonitor() {
        if let monitor = escKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escKeyMonitor = nil
        }
    }
}

// swiftlint:enable type_body_length
