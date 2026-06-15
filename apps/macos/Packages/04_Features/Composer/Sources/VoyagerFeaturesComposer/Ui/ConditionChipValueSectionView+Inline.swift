import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection

private struct ConditionChipValuePillView: View {
    let text: String
    let isDark: Bool
    let hoverFillOpacity: Double
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            Text(text.isEmpty ? "Value" : text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            isHovering
                                ? (isDark
                                    ? Color.white.opacity(hoverFillOpacity)
                                    : Color.black.opacity(hoverFillOpacity))
                                : Color.white.opacity(0.0001),
                        ),
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct ConditionChipInlineTextFieldView: View {
    let placeholderText: String
    let currentText: String
    let valueType: String
    let hasError: Bool
    let errorMessage: String?
    let selector: AnyView?
    let text: Binding<String>
    let isDark: Bool
    let onSubmit: () -> Void
    let focusedValueIndex: FocusState<Int?>.Binding
    let focusIndex: Int

    var body: some View {
        HStack(spacing: 4) {
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

            if let selector {
                selector
            }
        }
    }

    private var widthRange: (min: CGFloat, max: CGFloat) {
        if valueType == "number" {
            return (hasError ? 70 : 55, hasError ? 130 : 95)
        }
        return (hasError ? 80 : 60, hasError ? 150 : 110)
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(
                hasError ? Color.red.opacity(0.85) :
                    (isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)),
                lineWidth: 1,
            )
    }
}

private struct ConditionChipInlineInputContext {
    let valueArity: Int
    let valueType: String
    let valueUIKind: String
    let hasError: Bool
    let errorMessage: String?
}

extension ConditionChipValueSectionView {
    @ViewBuilder
    func rangeNumberSection(
        operatorCode: String,
        valueUIKind: String,
        valueArity: Int,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let isActive = valueStore.isPresented && valueStore.propertyKey == condition.propertyKey
        let isEditingThis = isActive && valueStore.editingIndex != nil
        let hasCommittedValues = (condition.values?.count ?? 0) >= 2
        let needsPrepare = valueStore.propertyKey != condition.propertyKey
            || valueStore.operatorCode != operatorCode
            || valueStore.valueArity != valueArity

        let prepare = {
            sendPrepare(
                operatorCode: operatorCode,
                valueUIKind: valueUIKind,
                valueArity: valueArity,
                editingIndex: nil,
                includeDisplayState: false,
            )
        }

        if isEditingThis && hasCommittedValues {
            rangeEditingView(
                operatorCode: operatorCode,
                valueUIKind: valueUIKind,
                editingIndex: valueStore.editingIndex ?? 0,
                valueStore: valueStore,
            )
            .onAppear { if needsPrepare { prepare() } }
            .onChange(of: needsPrepare) { newValue in
                if newValue { prepare() }
            }
        } else if isActive || !hasCommittedValues {
            inlineValueInputs(
                valueViewStore: valueStore,
                context: ConditionChipInlineInputContext(
                    valueArity: valueArity,
                    valueType: condition.valueType,
                    valueUIKind: valueUIKind,
                    hasError: valueStore.errorMessage != nil,
                    errorMessage: valueStore.errorMessage,
                ),
                editingIndex: nil,
            )
            .onAppear { if needsPrepare { prepare() } }
            .onChange(of: needsPrepare) { newValue in
                if newValue { prepare() }
            }
        } else if let values = displayState?.values ?? condition.values, values.count >= 2 {
            rangeDisplayView(
                operatorCode: operatorCode,
                valueUIKind: valueUIKind,
                values: values,
            )
        }
    }

    @ViewBuilder
    func nonDateValueSection(
        operatorCode: String,
        valueUIKind: String,
        valueArity: Int,
        isEditingValue: Bool,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let isTokenPopover = ValuePickerTokenUtils.isTokenPopoverProperty(
            propertyType: condition.propertyType,
            valueUIKind: valueUIKind,
        )

        if isEditingValue, valueArity >= 2, let editingIndex = valueStore.editingIndex {
            rangeEditingView(
                operatorCode: operatorCode,
                valueUIKind: valueUIKind,
                editingIndex: editingIndex,
                valueStore: valueStore,
            )
        } else if isTokenPopover {
            tokenValueButton(
                operatorCode: operatorCode,
                valueUIKind: valueUIKind,
                valueArity: valueArity,
                valueViewStore: valueStore,
            )
        } else if isEditingValue {
            inlineValueInputs(
                valueViewStore: valueStore,
                context: ConditionChipInlineInputContext(
                    valueArity: valueArity,
                    valueType: condition.valueType,
                    valueUIKind: valueUIKind,
                    hasError: valueStore.errorMessage != nil,
                    errorMessage: valueStore.errorMessage,
                ),
                editingIndex: nil,
            )
        } else if valueArity >= 2, let values = displayState?.values ?? condition.values, values.count >= 2 {
            rangeDisplayView(
                operatorCode: operatorCode,
                valueUIKind: valueUIKind,
                values: values,
            )
        } else if condition.valueType == "boolean" {
            booleanValueButton(
                placeholderText: "",
                currentText: condition.values?.first ?? "",
                index: 0,
                valueViewStore: valueStore,
                prepareConfig: (operatorCode: operatorCode, valueUIKind: valueUIKind),
            )
        } else {
            singleValueButton(operatorCode: operatorCode, valueUIKind: valueUIKind, valueArity: valueArity)
        }
    }

    func rangeEditingView(
        operatorCode: String,
        valueUIKind: String,
        editingIndex: Int,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        HStack(spacing: 6) {
            if editingIndex == 1, let values = displayState?.values ?? condition.values, values.count >= 2 {
                rangeEditingPill(
                    text: values[0],
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    targetIndex: 0,
                    valueStore: valueStore,
                )
                Text(rangeSep)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            inlineValueInputs(
                valueViewStore: valueStore,
                context: ConditionChipInlineInputContext(
                    valueArity: 2,
                    valueType: condition.valueType,
                    valueUIKind: valueUIKind,
                    hasError: valueStore.errorMessage != nil,
                    errorMessage: valueStore.errorMessage,
                ),
                editingIndex: editingIndex,
            )

            if editingIndex == 0, let values = displayState?.values ?? condition.values, values.count >= 2 {
                Text(rangeSep)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                rangeEditingPill(
                    text: values[1],
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    targetIndex: 1,
                    valueStore: valueStore,
                )
            }
        }
    }

    func rangeEditingPill(
        text: String,
        operatorCode: String,
        valueUIKind: String,
        targetIndex: Int,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        ConditionChipValuePillView(
            text: text,
            isDark: isDark,
            hoverFillOpacity: hoverFillOpacity,
            onTap: {
                valuePickerStore.send(
                    .prepare(makePreparePayload(
                        operatorCode: operatorCode,
                        valueUIKind: valueUIKind,
                        valueArity: 2,
                        editingIndex: targetIndex,
                        valueStore: valueStore,
                    )),
                )
            },
        )
    }

    func rangeDisplayView(
        operatorCode: String,
        valueUIKind: String,
        values: [String],
    ) -> some View {
        HStack(spacing: 6) {
            ConditionChipValuePillView(
                text: values[0],
                isDark: isDark,
                hoverFillOpacity: hoverFillOpacity,
                onTap: {
                    valuePickerStore.send(
                        .prepare(makePreparePayload(
                            operatorCode: operatorCode,
                            valueUIKind: valueUIKind,
                            valueArity: 2,
                            editingIndex: 0,
                        )),
                    )
                },
            )
            Text(rangeSep)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            ConditionChipValuePillView(
                text: values[1],
                isDark: isDark,
                hoverFillOpacity: hoverFillOpacity,
                onTap: {
                    valuePickerStore.send(
                        .prepare(makePreparePayload(
                            operatorCode: operatorCode,
                            valueUIKind: valueUIKind,
                            valueArity: 2,
                            editingIndex: 1,
                        )),
                    )
                },
            )

            displayRangeUnitSelector()
        }
    }

    func singleValueButton(
        operatorCode: String,
        valueUIKind: String,
        valueArity: Int,
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                valuePickerStore.send(
                    .prepare(makePreparePayload(
                        operatorCode: operatorCode,
                        valueUIKind: valueUIKind,
                        valueArity: valueArity,
                        editingIndex: nil,
                    )),
                )
            } label: {
                Text(ConditionChipDisplayUtils.displayValueText(for: condition, displayValues: displayState?.values))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(condition.values == nil ? .secondary.opacity(0.7) : .primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                isValueHovering
                                    ?
                                    (isDark ? Color.white.opacity(hoverFillOpacity) : Color.black
                                        .opacity(hoverFillOpacity))
                                    : Color.white.opacity(0.0001),
                            ),
                    )
            }
            .contentShape(Rectangle())
            .frame(minWidth: 32, minHeight: 22, alignment: .center)
            .buttonStyle(.plain)
            .onHover { hovering in
                isValueHovering = hovering
            }

            if let selector = displayUnitSelector(
                unitValueState: currentUnitValueState(),
                onSelect: { unitCode in
                    onDisplayUnitChange(condition.propertyKey, unitCode)
                },
            ) {
                selector
            }
        }
    }

    private func inlineValueInputs(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        context: ConditionChipInlineInputContext,
        editingIndex: Int?,
    ) -> some View {
        let fieldCount = max(max(context.valueArity, valueViewStore.values.count), 1)
        let indices: [Int] = {
            if let editingIndex {
                return [editingIndex]
            }
            return Array(0 ..< fieldCount)
        }()
        let focusTarget = valueViewStore.editingIndex ?? indices.first
        let shouldFocus = valueViewStore.isPresented && valueViewStore.propertyKey == condition.propertyKey

        return HStack(spacing: 6) {
            inlineValueFields(indices: indices, valueViewStore: valueViewStore, context: context)
        }
        .padding(.leading, 4)
        .onAppear { updateInlineValueFocus(shouldFocus: shouldFocus, targetIndex: focusTarget) }
        .onChange(of: valueViewStore.isPresented) { _ in
            updateInlineValueFocus(shouldFocus: shouldFocus, targetIndex: focusTarget)
        }
        .onChange(of: valueViewStore.editingIndex) { _ in
            updateInlineValueFocus(shouldFocus: shouldFocus, targetIndex: focusTarget)
        }
        .onChange(of: valueViewStore.propertyKey) { _ in
            updateInlineValueFocus(shouldFocus: shouldFocus, targetIndex: focusTarget)
        }
    }

    private func inlineValueFields(
        indices: [Int],
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        context: ConditionChipInlineInputContext,
    ) -> some View {
        ForEach(indices, id: \.self) { index in
            let currentText = valueViewStore.values.indices.contains(index) ? valueViewStore.values[index] : ""
            let placeholderText = context.hasError ? "" : ConditionChipDisplayUtils.placeholder(
                for: context.valueArity,
                index: index,
                valueType: context.valueType,
            )

            if context.valueType == "date" || context.valueType == "datetime" {
                EmptyView()
            } else if context.valueType == "boolean" {
                booleanValueButton(
                    placeholderText: placeholderText,
                    currentText: currentText,
                    index: index,
                    valueViewStore: valueViewStore,
                    prepareConfig: (operatorCode: condition.operatorCode ?? "eq", valueUIKind: context.valueUIKind),
                )
            } else {
                inlineTextInputField(
                    valueViewStore: valueViewStore,
                    index: index,
                    placeholderText: placeholderText,
                    currentText: currentText,
                    context: context,
                )
            }

            if context.valueArity >= 2, index == 0 {
                Text(rangeSep)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
        }
    }

    private func inlineTextInputField(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        index: Int,
        placeholderText: String,
        currentText: String,
        context: ConditionChipInlineInputContext,
    ) -> some View {
        ConditionChipInlineTextFieldView(
            placeholderText: placeholderText,
            currentText: currentText,
            valueType: context.valueType,
            hasError: context.hasError,
            errorMessage: context.errorMessage,
            selector: editUnitSelector(valueViewStore: valueViewStore),
            text: valueViewStore.binding(
                get: { state in
                    state.values.indices.contains(index) ? state.values[index] : ""
                },
                send: { .setValue(index: index, text: $0) },
            ),
            isDark: isDark,
            onSubmit: { valuePickerStore.send(.commit) },
            focusedValueIndex: $focusedValueIndex,
            focusIndex: index,
        )
    }
}
