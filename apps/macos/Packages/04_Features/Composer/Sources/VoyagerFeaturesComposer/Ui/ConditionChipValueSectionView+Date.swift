import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection

private struct ConditionChipDateValueButtonConfig {
    let placeholderText: String
    let currentText: String
    let hasError: Bool
    let index: Int
    let operatorCode: String
    let valueUIKind: String
    let valueArity: Int
}

private struct ConditionChipDateButtonContext {
    let displayedValues: [String]?
    let operatorCode: String
    let valueUIKind: String
    let valueArity: Int
    let hasError: Bool
}

private struct ConditionChipDateButtonLabelView: View {
    let config: ConditionChipDateValueButtonConfig
    let isHovering: Bool
    let isDark: Bool
    let hoverFillOpacity: Double

    var body: some View {
        Text(labelText)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(config.currentText.isEmpty ? .secondary : .primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: 50, maxWidth: 80, alignment: .center)
            .fixedSize(horizontal: true, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isHovering
                            ? (isDark ? Color.white.opacity(hoverFillOpacity) : Color.black.opacity(hoverFillOpacity))
                            : Color.white.opacity(0.0001),
                    ),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        config.hasError ? Color.red.opacity(0.85) : Color.clear,
                        lineWidth: config.hasError ? 1 : 0,
                    ),
            )
    }

    private var labelText: String {
        if config.currentText.isEmpty {
            return config.placeholderText.isEmpty ? "Value" : config.placeholderText.capitalized
        }
        return ValueNormalizerUtils.formatDateOnlyString(config.currentText) ?? config.currentText
    }
}

extension ConditionChipValueSectionView {
    @ViewBuilder
    func dateValueSection(
        operatorCode: String,
        valueUIKind: String,
        valueArity: Int,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let hasError = valueViewStore.errorMessage != nil
        let displayedValues = ConditionChipDisplayUtils.displayedValuesForDate(
            conditionValues: condition.values,
            conditionPropertyKey: condition.propertyKey,
            pickerPropertyKey: valueViewStore.propertyKey,
            pickerPresented: valueViewStore.isPresented,
            pickerValues: valueViewStore.values,
        )
        let context = ConditionChipDateButtonContext(
            displayedValues: displayedValues,
            operatorCode: operatorCode,
            valueUIKind: valueUIKind,
            valueArity: valueArity,
            hasError: hasError,
        )
        let fromConfig = makeDateButtonConfig(
            placeholderText: "From",
            index: 0,
            context: context,
        )
        let toConfig = makeDateButtonConfig(
            placeholderText: "To",
            index: 1,
            context: context,
        )
        let singleConfig = makeDateButtonConfig(
            placeholderText: "Value",
            index: 0,
            context: context,
        )

        if valueArity >= 2 {
            HStack(spacing: 6) {
                dateValueButton(config: fromConfig, valueViewStore: valueViewStore)
                Text(rangeSep)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                dateValueButton(config: toConfig, valueViewStore: valueViewStore)
            }
        } else {
            dateValueButton(config: singleConfig, valueViewStore: valueViewStore)
        }
    }

    private func makeDateButtonConfig(
        placeholderText: String,
        index: Int,
        context: ConditionChipDateButtonContext,
    ) -> ConditionChipDateValueButtonConfig {
        let currentText = index == 0
            ? (context.displayedValues?.first ?? "")
            : ((context.displayedValues?.count ?? 0) > 1 ? (context.displayedValues?[1] ?? "") : "")

        return .init(
            placeholderText: placeholderText,
            currentText: currentText,
            hasError: context.hasError,
            index: index,
            operatorCode: context.operatorCode,
            valueUIKind: context.valueUIKind,
            valueArity: context.valueArity,
        )
    }

    private func dateValueButton(
        config: ConditionChipDateValueButtonConfig,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { datePopoverIndex == config.index },
            set: { show in
                if !show { datePopoverIndex = nil }
            },
        )
        let currentValues: [String]? = {
            if valueViewStore.propertyKey == condition.propertyKey {
                return valueViewStore.values
            }
            return condition.values
        }()
        let isHovering = dateHoverIndex == config.index

        return Button {
            sendPrepare(
                operatorCode: config.operatorCode,
                valueUIKind: config.valueUIKind,
                valueArity: config.valueArity,
                editingIndex: config.index,
                valueStore: valueViewStore,
                existingValues: currentValues,
                includeDisplayState: false,
            )
            tempDate = ValueNormalizerUtils.parseDate(config.currentText) ?? Date()
            datePopoverIndex = config.index
        } label: {
            ConditionChipDateButtonLabelView(
                config: config,
                isHovering: isHovering,
                isDark: isDark,
                hoverFillOpacity: hoverFillOpacity,
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hover in
            if hover {
                dateHoverIndex = config.index
            } else if dateHoverIndex == config.index {
                dateHoverIndex = nil
            }
        }
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            datePopoverContent(config: config, valueViewStore: valueViewStore)
        }
    }

    private func datePopoverContent(
        config: ConditionChipDateValueButtonConfig,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let applySelection = {
                let formatted = ValueNormalizerUtils.formatDateOnly(tempDate)
                valueViewStore.send(.setValue(index: config.index, text: formatted))
                valuePickerStore.send(.commit)
                DispatchQueue.main.async {
                    if valueViewStore.errorMessage == nil {
                        datePopoverIndex = nil
                    }
                }
            }

            CalendarDatePicker(selection: $tempDate, onCommit: applySelection)

            HStack {
                Spacer()
                Button("Apply") {
                    applySelection()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(12)
    }
}

private struct CalendarDatePicker: NSViewRepresentable {
    @Binding var selection: Date
    let onCommit: () -> Void

    final class Coordinator: NSObject {
        @Binding var selection: Date
        let onCommit: () -> Void

        init(selection: Binding<Date>, onCommit: @escaping () -> Void) {
            _selection = selection
            self.onCommit = onCommit
        }

        @objc
        func dateChanged(_ sender: NSDatePicker) {
            selection = sender.dateValue
            if NSApp.currentEvent?.clickCount == 2 {
                onCommit()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = [.yearMonthDay]
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        picker.dateValue = selection
        return picker
    }

    func updateNSView(_ nsView: NSDatePicker, context _: Context) {
        if nsView.dateValue != selection {
            nsView.dateValue = selection
        }
    }
}
