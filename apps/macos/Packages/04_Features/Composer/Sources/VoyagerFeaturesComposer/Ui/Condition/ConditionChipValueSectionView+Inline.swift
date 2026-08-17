import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerShared

private struct ConditionChipInlineTextFieldView: View {
    let placeholderText: String
    let currentText: String
    let input: Condition.ValueInputKind
    let hasError: Bool
    let errorMessage: String?
    let text: Binding<String>
    let isDark: Bool
    let onSubmit: () -> Void
    let focusedValueIndex: FocusState<Int?>.Binding
    let focusIndex: Int

    var body: some View {
        TextField(placeholderText, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: widthRange.min, maxWidth: widthRange.max, alignment: .leading)
            .background(fieldBorder)
            .overlay(alignment: .leading) {
                if hasError, currentText.isEmpty, let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                }
            }
            .focused(focusedValueIndex, equals: focusIndex)
            .onSubmit(onSubmit)
    }

    private var widthRange: (min: CGFloat, max: CGFloat) {
        switch input {
        case .singleNumber, .listNumber, .rangeNumber:
            (hasError ? 70 : 55, hasError ? 130 : 95)
        case .none, .singleText, .listText, .singleDate, .rangeDate, .toggle:
            (hasError ? 80 : 60, hasError ? 150 : 110)
        }
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipItem)
            .stroke(
                hasError ? Color.red.opacity(0.85) :
                    (isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)),
                lineWidth: 1,
            )
    }
}

extension ConditionChipValueSectionView {
    func rangeNumberSection(
        contract: Condition.ValueContract,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        inlineValueContent(valueStore: valueStore, contract: contract)
    }

    func ordinaryValueSection(
        contract: Condition.ValueContract,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        inlineValueContent(valueStore: valueStore, contract: contract)
    }

    @ViewBuilder
    private func inlineValueContent(
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        contract: Condition.ValueContract,
    ) -> some View {
        if valueStore.isPresented {
            inlineValueInputs(contract: contract, valueStore: valueStore)
        } else {
            valueLabel(contract: contract, valueStore: valueStore)
        }
    }

    private func valueLabel(
        contract _: Condition.ValueContract,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        HStack(spacing: 4) {
            Button {
                prepare(editingIndex: nil, valueStore: valueStore)
            } label: {
                Text(ConditionChipDisplay.displayValueText(for: condition, displayValues: displayState?.values))
                    .font(VoyagerDS.Typography.chip)
                    .foregroundColor(condition.values == nil ? .secondary.opacity(0.7) : .primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipItem)
                            .fill(isValueHovering
                                ?
                                (isDark ? Color.white.opacity(hoverFillOpacity) : Color.black
                                    .opacity(hoverFillOpacity))
                                : Color.white.opacity(0.0001)),
                    )
            }
            .contentShape(Rectangle())
            .frame(
                minWidth: ComposerUIMetrics.valueControlMinimumWidth,
                minHeight: ComposerUIMetrics.compactControlHeight,
                alignment: .center,
            )
            .buttonStyle(.plain)
            .onHover { isValueHovering = $0 }

            if let selector = displayUnitSelector(unitValueState: currentUnitValueState()) { selector }
        }
    }

    private func inlineValueInputs(
        contract: Condition.ValueContract,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let count = inputCount(contract: contract, values: valueStore.values)
        let indices = Array(0 ..< count)
        let shouldFocus = valueStore.isPresented
        let selector = editUnitSelector(valueStore: valueStore)

        return HStack(spacing: 6) {
            ForEach(indices, id: \.self) { index in
                let currentText = valueStore.values.indices.contains(index) ? valueStore.values[index] : ""
                ConditionChipInlineTextFieldView(
                    placeholderText: placeholder(contract: contract, index: index),
                    currentText: currentText,
                    input: contract.input,
                    hasError: valueStore.errorMessage != nil,
                    errorMessage: valueStore.errorMessage,
                    text: valueStore.binding(
                        get: { $0.values.indices.contains(index) ? $0.values[index] : "" },
                        send: { .setValue(index: index, text: $0) },
                    ),
                    isDark: isDark,
                    onSubmit: { valuePickerStore.send(.commit) },
                    focusedValueIndex: $focusedValueIndex,
                    focusIndex: index,
                )

                if count >= 2, index == 0 {
                    Text(rangeSep)
                        .font(VoyagerDS.Typography.chip)
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
            }

            if let selector { selector }
        }
        .padding(.leading, 4)
        .onAppear { updateInlineValueFocus(shouldFocus: shouldFocus, targetIndex: indices.first) }
        .onChange(of: valueStore.isPresented) { _ in
            updateInlineValueFocus(shouldFocus: valueStore.isPresented, targetIndex: indices.first)
        }
    }

    private func inputCount(contract: Condition.ValueContract, values: [String]) -> Int {
        switch contract.count {
        case let .fixed(count): max(count, 1)
        case .multiple: max(values.count, 1)
        }
    }

    private func placeholder(contract: Condition.ValueContract, index: Int) -> String {
        switch contract.count {
        case let .fixed(count) where count >= 2:
            index == 0 ? "From" : "To"
        case .fixed, .multiple:
            switch contract.input {
            case .singleNumber, .listNumber, .rangeNumber: "Number Value"
            case .none, .singleText, .listText, .singleDate, .rangeDate, .toggle: "Value"
            }
        }
    }

    func editUnitSelector(
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> AnyView? {
        guard let state = valueStore.unitValueState else { return nil }
        return AnyView(unitSelector(state: state) {
            valuePickerStore.send(.selectUnit($0))
        })
    }

    func displayUnitSelector(unitValueState: UnitValueState?) -> AnyView? {
        guard let state = unitValueState else { return nil }
        return AnyView(unitSelector(state: state) {
            store.send(.view(.setDisplayUnit($0)))
        })
    }

    private func unitSelector(
        state: UnitValueState,
        onSelect: @escaping (String) -> Void,
    ) -> UnitSelectorView {
        UnitSelectorView(
            availableUnitCodes: state.availableUnitCodes,
            selectedUnitCode: state.selectedUnitCode,
            selectedUnitLabel: state.label(for: state.selectedUnitCode),
            labelForUnit: { state.label(for: $0) },
            onSelect: onSelect,
        )
    }

    func updateInlineValueFocus(shouldFocus: Bool, targetIndex: Int?) {
        let nextFocus = shouldFocus ? targetIndex : nil
        guard focusedValueIndex != nextFocus else { return }
        DispatchQueue.main.async { focusedValueIndex = nextFocus }
    }
}
