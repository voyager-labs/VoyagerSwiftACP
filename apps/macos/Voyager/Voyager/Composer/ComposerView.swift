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
    @State private var localComposeText: String = ""
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
        VStack(spacing: 0) {
            firstRow
                .fixedSize(horizontal: false, vertical: true)
            horizontalSeparator
            secondRow
                .fixedSize(horizontal: false, vertical: true)
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

    private var firstRow: some View {
        HStack(spacing: 12) {
            undoButton
            redoButton
            textField
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

    private var textField: some View {
        TextField(
            "Enter your request...",
            text: Binding(
                get: { store.composer.text },
                set: { store.send(.composer(.setText($0))) },
            ),
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
        case condition(text: String)

        var id: String {
            switch self {
            case let .scope(paths):
                "scope-\(paths.joined(separator: "-"))"
            case let .condition(text):
                "condition-\(text)"
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

    private var secondRow: some View {
        GeometryReader { geometry in
            let leadingPadding = store.sidebarVisible ? 0 : trafficLightAreaWidth
            let availableWidth = geometry.size.width - chipHorizontalPadding * 2 - leadingPadding

            // TODO: voy-95에서 백엔드 데이터로 교체 (store.conditions)
            let allChips: [ChipItemType] =
                (store.composer.scopes.isEmpty ? [] : [.scope(paths: store.composer.scopes)]) + [
                    .condition(text: "name contains test"),
                    .condition(text: "size > 100KB"),
                    .condition(text: "modified < 7 days"),
                    .condition(text: "type is image"),
                    .condition(text: "created > 2024-01-01"),
                    .condition(text: "tagged with important"),
                    .condition(text: "size < 1MB"),
                    .condition(text: "extension is pdf"),
                ]

            let params = RowCalculationParams(
                availableWidth: availableWidth,
                spacing: chipSpacing,
                chipSizes: chipSizes,
                conditionButtonWidth: conditionButtonWidth,
                buttonSpacing: chipSpacing,
            )
            let rows = calculateRowsWithButtons(chips: allChips, params: params)

            VStack(alignment: .leading, spacing: chipSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowChips in
                    let isLastRow = rowIndex == rows.count - 1

                    let composerStore = store.scope(state: \.composer, action: \.composer)

                    HStack(spacing: chipSpacing) {
                        ForEach(Array(rowChips.enumerated()), id: \.element.id) { _, chip in
                            Group {
                                switch chip {
                                case let .scope(paths):
                                    ComposerScopeChipView(
                                        paths: paths,
                                        store: composerStore,
                                        isDark: isDark,
                                        favorites: store.favorites,
                                        backHistory: store.backHistory,
                                    )
                                case let .condition(text):
                                    conditionChipView(text: text)
                                }
                            }
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

                        if isLastRow, let lastChip = rowChips.last, case .condition = lastChip {
                            conditionAddButton
                        }
                    }
                }
            }
            .onPreferenceChange(ChipSizePreferenceKey.self) { sizes in
                for chip in allChips {
                    let anyId = AnyHashable(chip.id)
                    if let size = sizes[anyId] {
                        chipSizes[chip.id] = size
                    }
                }
                updateCalculatedHeight(
                    chips: allChips,
                    availableWidth: availableWidth,
                )
            }
            .onAppear {
                updateCalculatedHeight(
                    chips: allChips,
                    availableWidth: availableWidth,
                )
            }
            .padding(.horizontal, chipHorizontalPadding)
            .padding(.leading, leadingPadding)
            .padding(.vertical, chipVerticalPadding)
        }
        .frame(height: calculatedHeight)
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

    private func conditionChipView(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)),
            )
    }

    private var conditionAddButton: some View {
        addButton(action: {
            // TODO: addCondition (voy-95에서 구현)
        })
    }

    private func setupOnAppear() {
        isDark = isDarkMode()
        localComposeText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isComposeFieldFocused = true
        }
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == escapeKeyCode {
                store.send(.exitComposeMode)
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
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
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
