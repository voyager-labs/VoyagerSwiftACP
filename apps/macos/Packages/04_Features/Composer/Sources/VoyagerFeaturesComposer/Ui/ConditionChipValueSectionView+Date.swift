import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerShared

private struct ConditionChipDateValueButtonConfig {
    let placeholderText: String
    let currentText: String
    let hasError: Bool
    let index: Int
    let contract: Condition.ValueContract
}

private struct ConditionChipDateButtonContext {
    let displayedValues: [String]?
    let contract: Condition.ValueContract
    let hasError: Bool
}

private enum DateModeTab: String, Hashable {
    case absolute
    case relative
}

private let kDatePopoverContentWidth: CGFloat = 139
private let kDatePopoverHorizontalPadding: CGFloat = 12
private let kRelativeUnitPickerWidth: CGFloat = 82
private let kRelativeInputSpacing: CGFloat = 4
private let kRelativeAmountFieldWidth = kDatePopoverContentWidth - kRelativeUnitPickerWidth - kRelativeInputSpacing

private struct DatePopoverBindings {
    let dateModeTab: Binding<DateModeTab>
    let dateSelection: Binding<Date>
    let relativePreset: Binding<DateValueState.RelativePreset>
    let relativeAmountText: Binding<String>
    let relativeUnit: Binding<RelativeDateConditionLiteral.Unit>
    let rawDateSelection: Binding<Date>
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
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: 50, alignment: .center)
            .fixedSize(horizontal: true, vertical: false)
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
        return config.currentText
    }
}

extension ConditionChipValueSectionView {
    @ViewBuilder
    func dateValueSection(
        contract: Condition.ValueContract,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let hasError = valueViewStore.errorMessage != nil
        let displayedValues = ConditionChipDisplay.displayedValuesForDate(
            conditionValues: condition.values,
            pickerState: .init(
                presented: valueViewStore.isPresented,
                values: valueViewStore.values,
                dateValueState: valueViewStore.dateValueState,
            ),
        )
        let context = ConditionChipDateButtonContext(
            displayedValues: displayedValues,
            contract: contract,
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

        if valueCount(contract) >= 2 {
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
            contract: context.contract,
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
        let currentValues = valueViewStore.isPresented ? valueViewStore.values : condition.values
        let isHovering = dateHoverIndex == config.index

        return Group {
            if ComposerPickerHostPolicy.host(for: .date) == .anchoredDropdown {
                ComposerAnchoredDropdown(
                    isPresented: isPresented,
                    dropdownAccessibilityIdentifier: "composer.date.dropdown",
                ) {
                    dateValueButtonTrigger(
                        config: config,
                        currentValues: currentValues,
                        isHovering: isHovering,
                        valueViewStore: valueViewStore,
                    )
                } content: {
                    datePopoverContent(config: config, valueViewStore: valueViewStore)
                }
            }
        }
    }

    private func dateValueButtonTrigger(
        config: ConditionChipDateValueButtonConfig,
        currentValues: [String]?,
        isHovering: Bool,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        Button {
            prepare(
                editingIndex: config.index,
                valueStore: valueViewStore,
                existingValues: currentValues,
                includeDisplayState: false,
            )
            tempDate = ConditionValueNormalizer.parseDate(config.currentText) ?? Date()
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
    }

    private func datePopoverContent(
        config: ConditionChipDateValueButtonConfig,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let bindings = makeDatePopoverBindings(config: config, valueViewStore: valueViewStore)

        return VStack(alignment: .center, spacing: 12) {
            let applySelection = makeDateApplySelection(valueViewStore: valueViewStore)

            if valueCount(config.contract) == 1, valueViewStore.dateValueState != nil {
                let isRelativePreview = bindings.dateModeTab.wrappedValue == .relative

                semanticDatePopoverFields(
                    valueViewStore: valueViewStore,
                    dateModeTabBinding: bindings.dateModeTab,
                    relativePresetBinding: bindings.relativePreset,
                    relativeAmountTextBinding: bindings.relativeAmountText,
                    relativeUnitBinding: bindings.relativeUnit,
                )

                calendarPicker(
                    selection: bindings.dateSelection,
                    onCommit: applySelection,
                    isPreviewOnly: isRelativePreview,
                )
            } else {
                calendarPicker(selection: bindings.rawDateSelection, onCommit: applySelection)
            }

            if let error = valueViewStore.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .accessibilityIdentifier("composer.date.error")
            }

            dateApplyButton(action: applySelection)
        }
        .padding(.horizontal, kDatePopoverHorizontalPadding)
        .padding(.vertical, 14)
        .frame(width: kDatePopoverContentWidth + kDatePopoverHorizontalPadding * 2)
    }

    private func makeDatePopoverBindings(
        config: ConditionChipDateValueButtonConfig,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> DatePopoverBindings {
        DatePopoverBindings(
            dateModeTab: makeDateModeTabBinding(valueViewStore: valueViewStore),
            dateSelection: Binding(
                get: { valueViewStore.dateValueState?.selectedDate ?? Date() },
                set: { valueViewStore.send(.setDateSelection($0)) },
            ),
            relativePreset: Binding(
                get: { valueViewStore.dateValueState?.relativePreset ?? .custom },
                set: { valueViewStore.send(.setRelativeDatePreset($0)) },
            ),
            relativeAmountText: makeRelativeAmountTextBinding(valueViewStore: valueViewStore),
            relativeUnit: Binding(
                get: { valueViewStore.dateValueState?.relativeUnit ?? .day },
                set: { valueViewStore.send(.setRelativeDateUnit($0)) },
            ),
            rawDateSelection: Binding(
                get: { tempDate },
                set: { date in
                    tempDate = date
                    valueViewStore.send(.setValue(
                        index: config.index,
                        text: ConditionValueNormalizer.formatDateOnly(date),
                    ))
                },
            ),
        )
    }

    private func makeDateModeTabBinding(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> Binding<DateModeTab> {
        Binding(
            get: {
                switch valueViewStore.dateValueState?.mode ?? .absolute {
                case .absolute:
                    .absolute
                case .relative, .today:
                    .relative
                }
            },
            set: { tab in
                switch tab {
                case .absolute:
                    valueViewStore.send(.setDateMode(.absolute))
                case .relative:
                    valueViewStore.send(.setDateMode(.relative))
                }
            },
        )
    }

    private func makeRelativeAmountTextBinding(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> Binding<String> {
        Binding(
            get: { String(valueViewStore.dateValueState?.relativeAmount ?? 1) },
            set: { text in
                let digits = text.filter(\.isNumber)
                guard let amount = Int(digits), amount > 0 else { return }
                valueViewStore.send(.setRelativeDateAmount(amount))
            },
        )
    }

    private func makeDateApplySelection(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> () -> Void {
        {
            valuePickerStore.send(.commit)
            DispatchQueue.main.async {
                if valueViewStore.errorMessage == nil {
                    datePopoverIndex = nil
                }
            }
        }
    }

    @ViewBuilder
    private func semanticDatePopoverFields(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        dateModeTabBinding: Binding<DateModeTab>,
        relativePresetBinding: Binding<DateValueState.RelativePreset>,
        relativeAmountTextBinding: Binding<String>,
        relativeUnitBinding: Binding<RelativeDateConditionLiteral.Unit>,
    ) -> some View {
        dateTypePicker(selection: dateModeTabBinding)

        if dateModeTabBinding.wrappedValue == .relative {
            relativeDateFields(
                valueViewStore: valueViewStore,
                relativePresetBinding: relativePresetBinding,
                relativeAmountTextBinding: relativeAmountTextBinding,
                relativeUnitBinding: relativeUnitBinding,
            )
        }
    }

    private func dateTypePicker(selection: Binding<DateModeTab>) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Text("Date Type")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Picker("Date Type", selection: selection) {
                Text("On date").tag(DateModeTab.absolute)
                Text("Relative").tag(DateModeTab.relative)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: kDatePopoverContentWidth)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func relativeDateFields(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        relativePresetBinding: Binding<DateValueState.RelativePreset>,
        relativeAmountTextBinding: Binding<String>,
        relativeUnitBinding: Binding<RelativeDateConditionLiteral.Unit>,
    ) -> some View {
        VStack(alignment: .center, spacing: 8) {
            relativePresetPicker(selection: relativePresetBinding)

            if relativePresetBinding.wrappedValue == .custom {
                relativeCustomInputRow(
                    amountText: relativeAmountTextBinding,
                    unit: relativeUnitBinding,
                )
            }

            Text(valueViewStore.dateValueState?.displayText() ?? "Value")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func relativePresetPicker(selection: Binding<DateValueState.RelativePreset>) -> some View {
        RelativePresetMenuPicker(selection: selection, width: kDatePopoverContentWidth)
            .fixedSize()
            .frame(width: kDatePopoverContentWidth, alignment: .center)
    }

    private func relativeCustomInputRow(
        amountText: Binding<String>,
        unit: Binding<RelativeDateConditionLiteral.Unit>,
    ) -> some View {
        HStack(spacing: kRelativeInputSpacing) {
            TextField("1", text: amountText)
                .textFieldStyle(.roundedBorder)
                .frame(width: kRelativeAmountFieldWidth)

            Picker("", selection: unit) {
                Text("Day").tag(RelativeDateConditionLiteral.Unit.day)
                Text("Week").tag(RelativeDateConditionLiteral.Unit.week)
                Text("Month").tag(RelativeDateConditionLiteral.Unit.month)
                Text("Year").tag(RelativeDateConditionLiteral.Unit.year)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: kRelativeUnitPickerWidth)
        }
        .frame(width: kDatePopoverContentWidth)
    }

    private func calendarPicker(
        selection: Binding<Date>,
        onCommit: @escaping () -> Void,
        isPreviewOnly: Bool = false,
    ) -> some View {
        VStack(alignment: .center, spacing: 4) {
            CalendarDatePicker(selection: selection, onCommit: onCommit)
                .fixedSize()
                .allowsHitTesting(!isPreviewOnly)
                .opacity(isPreviewOnly ? 0.72 : 1)
                .frame(width: kDatePopoverContentWidth, alignment: .center)

            if isPreviewOnly {
                Text("Preview based on today")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func dateApplyButton(action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("Apply") {
                action()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("composer.date.apply")
        }
        .frame(width: kDatePopoverContentWidth)
        .padding(.top, 4)
    }

    private func valueCount(_ contract: Condition.ValueContract) -> Int {
        switch contract.count {
        case let .fixed(count): count
        case .multiple: 1
        }
    }
}
