// swiftlint:disable type_body_length function_body_length file_length
import AppKit
import ComposableArchitecture
import SwiftUI

struct ConditionChipView: View {
    let propertyPickerStore: StoreOf<ConditionPropertyPickerFeature>
    let condition: Condition
    let isDark: Bool
    let hoverFillOpacity: Double
    let operatorPickerStore: StoreOf<OperatorPickerFeature>
    let valuePickerStore: StoreOf<ValuePickerFeature>
    let operatorOptions: [String]
    let defaultChipHeight: CGFloat
    let onPropertyTap: () -> Void
    let onRemove: () -> Void

    @State private var isPropertyHovering: Bool = false
    @State private var isOperatorHovering: Bool = false
    @State private var isValueHovering: Bool = false
    @State private var datePopoverIndex: Int?
    @State private var tempDate: Date = .init()
    @State private var dateHoverIndex: Int?
    @State private var isChipHovering: Bool = false
    @State private var isRemoveHovering: Bool = false
    @State private var boolPopoverIndex: Int?
    @State private var boolHoverIndex: Int?
    @State private var boolOptionHoverValue: String?
    @FocusState private var focusedValueIndex: Int?

    var body: some View {
        WithViewStore(
            operatorPickerStore,
            observe: { $0 },
            content: { opStore in
                WithViewStore(
                    valuePickerStore,
                    observe: { $0 },
                    content: { valueStore in
                        chipContent(opStore: opStore, valueStore: valueStore)
                    },
                )
            },
        )
    }

    private func chipContent(
        opStore: ViewStore<OperatorPickerFeature.State, OperatorPickerFeature.Action>,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let opLabel = condition.operatorLabel ?? "Operator"
        let opColor: Color = condition.operatorLabel == nil ? .secondary.opacity(0.7) : .primary
        let valueUIKind = condition.operatorValueUIKind ?? "singleText"
        let valueArity = condition.operatorValueArity ?? ValueNormalizerUtils.expectedArity(for: valueUIKind)
        let isDateType = condition.valueType == "date" || condition.valueType == "datetime"
        let isBooleanType = condition.valueType == "boolean"
        let isEditingValue = !isDateType && !isBooleanType && valueStore.isPresented &&
            valueStore.propertyKey == condition.propertyKey

        return HStack(spacing: 2) {
            propertyLabelView()
            operatorButtonView(opStore: opStore, label: opLabel, color: opColor)
            valueSection(
                valueUIKind: valueUIKind,
                valueArity: valueArity,
                isEditingValue: isEditingValue,
                isDateType: isDateType,
                valueStore: valueStore,
            )
        }
        .padding(.horizontal, 8)
        .frame(height: defaultChipHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)),
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .background(
                        Circle()
                            .fill(isRemoveHovering
                                ? VoyagerDS.Interaction.controlHoverFill(for: isDark ? .dark : .light)
                                : .clear)
                            .frame(width: 14, height: 14),
                    )
            }
            .buttonStyle(.borderless)
            .padding(2)
            .offset(x: 6, y: -6)
            .opacity(isChipHovering ? 1 : 0)
            .allowsHitTesting(isChipHovering)
            .onHover { hovering in
                isRemoveHovering = hovering
            }
        }
        .onHover { hovering in
            isChipHovering = hovering
        }
    }

    private func propertyLabelView() -> some View {
        WithViewStore(propertyPickerStore, observe: { $0 }, content: { propertyStore in
            HStack(spacing: 6) {
                Image(systemName: ConditionPropertyIconUtils.iconName(forKey: condition.propertyKey))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 12, height: 12)
                Text(condition.propertyLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
            }
            .padding(.leading, 4)
            .padding(.trailing, 2)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onHover { hovering in
                isPropertyHovering = hovering
            }
            .background(
                isPropertyHovering
                    ? (isDark ? Color.white.opacity(hoverFillOpacity) : Color.black.opacity(hoverFillOpacity))
                    : Color.clear,
            )
            .onTapGesture {
                onPropertyTap()
                propertyStore.send(.startEditing(condition.propertyKey))
                propertyStore.send(.setPresented(true))
            }
            .popover(
                isPresented: propertyStore.binding(
                    get: { $0.isPresented && $0.editingConditionKey == condition.propertyKey },
                    send: ConditionPropertyPickerFeature.Action.setPresented,
                ),
                arrowEdge: .bottom,
                content: {
                    ConditionPropertyPickerView(store: propertyPickerStore)
                },
            )
        })
    }

    private func operatorButtonView(
        opStore: ViewStore<OperatorPickerFeature.State, OperatorPickerFeature.Action>,
        label: String,
        color: Color,
    ) -> some View {
        Button {
            opStore.send(.prepare(
                propertyKey: condition.propertyKey,
                options: operatorOptions,
                optionLabels: [:],
            ))
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            (opStore.propertyKey == condition.propertyKey && opStore.isPresented) || isOperatorHovering
                                ?
                                (isDark ? Color.white.opacity(hoverFillOpacity) : Color.black
                                    .opacity(hoverFillOpacity))
                                : Color.white.opacity(0.0001),
                        ),
                )
        }
        .contentShape(Rectangle())
        .frame(minWidth: 28, minHeight: 22, alignment: .center)
        .buttonStyle(.plain)
        .onHover { hovering in
            isOperatorHovering = hovering
        }
        .popover(
            isPresented: Binding(
                get: { opStore.isPresented && opStore.propertyKey == condition.propertyKey },
                set: { isPresented in
                    opStore.send(.setPresented(isPresented))
                },
            ),
            arrowEdge: .bottom,
            content: {
                OperatorPickerView(store: operatorPickerStore)
            },
        )
    }

    // swiftlint:disable cyclomatic_complexity
    @ViewBuilder
    private func valueSection(
        valueUIKind: String,
        valueArity: Int,
        isEditingValue: Bool,
        isDateType: Bool,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        if let operatorCode = condition.operatorCode, valueArity != 0 {
            if valueUIKind == "rangeNumber" {
                let isActive = valueStore.isPresented && valueStore.propertyKey == condition.propertyKey
                let isEditingThis = isActive && valueStore.editingIndex != nil
                let hasCommittedValues = (condition.values?.count ?? 0) >= 2
                let needsPrepare = valueStore.propertyKey != condition.propertyKey ||
                    valueStore.operatorCode != operatorCode ||
                    valueStore.valueArity != valueArity
                let sendPrepare: () -> Void = {
                    _ = valuePickerStore.send(
                        .prepare(
                            .init(
                                propertyKey: condition.propertyKey,
                                operatorCode: operatorCode,
                                valueType: condition.valueType,
                                valueUIKind: valueUIKind,
                                valueArity: valueArity,
                                existingValues: condition.values,
                                editingIndex: nil,
                            ),
                        ),
                    )
                }

                if isEditingThis && hasCommittedValues {
                    rangeEditingView(
                        operatorCode: operatorCode,
                        valueUIKind: valueUIKind,
                        editingIndex: valueStore.editingIndex ?? 0,
                        valueStore: valueStore,
                    )
                    .onAppear {
                        if needsPrepare {
                            sendPrepare()
                        }
                    }
                    .onChange(of: needsPrepare, perform: { newValue in
                        if newValue { sendPrepare() }
                    })
                } else if isActive || !hasCommittedValues {
                    inlineValueInputs(
                        valueViewStore: valueStore,
                        valueArity: valueArity,
                        valueType: condition.valueType,
                        valueUIKind: valueUIKind,
                        errorMessage: valueStore.errorMessage,
                        editingIndex: nil,
                    )
                    .onAppear {
                        if needsPrepare {
                            sendPrepare()
                        }
                    }
                    .onChange(of: needsPrepare, perform: { newValue in
                        if newValue { sendPrepare() }
                    })
                } else if let values = condition.values, values.count >= 2 {
                    rangeDisplayView(
                        operatorCode: operatorCode,
                        valueUIKind: valueUIKind,
                        values: values,
                    )
                }
            } else
            if isDateType {
                dateValueSection(
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    valueArity: valueArity,
                    valueViewStore: valueStore,
                )
            } else
            if isEditingValue, valueArity >= 2, let editingIndex = valueStore.editingIndex {
                rangeEditingView(
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    editingIndex: editingIndex,
                    valueStore: valueStore,
                )
            } else if isEditingValue {
                inlineValueInputs(
                    valueViewStore: valueStore,
                    valueArity: valueArity,
                    valueType: condition.valueType,
                    valueUIKind: valueUIKind,
                    errorMessage: valueStore.errorMessage,
                    editingIndex: nil,
                )
            } else if valueArity >= 2, let values = condition.values, values.count >= 2 {
                rangeDisplayView(
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    values: values,
                )
            } else {
                if condition.valueType == "boolean" {
                    let currentText = condition.values?.first ?? ""
                    booleanValueButton(
                        placeholderText: "",
                        currentText: currentText,
                        index: 0,
                        valueViewStore: ViewStore(valuePickerStore, observe: { $0 }),
                        operatorCode: operatorCode,
                        valueUIKind: valueUIKind,
                    )
                } else {
                    singleValueButton(operatorCode: operatorCode, valueUIKind: valueUIKind, valueArity: valueArity)
                }
            }
        } else {
            EmptyView()
        }
    }

    // swiftlint:enable cyclomatic_complexity

    private func rangeEditingView(
        operatorCode: String,
        valueUIKind: String,
        editingIndex: Int,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        HStack(spacing: 6) {
            if editingIndex == 1, let values = condition.values, values.count >= 2 {
                ValuePillView(
                    text: values[0],
                    isDark: isDark,
                    hoverFillOpacity: hoverFillOpacity,
                    onTap: {
                        valuePickerStore.send(
                            .prepare(
                                .init(
                                    propertyKey: condition.propertyKey,
                                    operatorCode: operatorCode,
                                    valueType: condition.valueType,
                                    valueUIKind: valueUIKind,
                                    valueArity: 2,
                                    existingValues: condition.values,
                                    editingIndex: 0,
                                ),
                            ),
                        )
                    },
                )
                Text("and")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            inlineValueInputs(
                valueViewStore: valueStore,
                valueArity: 2,
                valueType: condition.valueType,
                valueUIKind: valueUIKind,
                errorMessage: valueStore.errorMessage,
                editingIndex: editingIndex,
            )

            if editingIndex == 0, let values = condition.values, values.count >= 2 {
                Text("and")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                ValuePillView(
                    text: values[1],
                    isDark: isDark,
                    hoverFillOpacity: hoverFillOpacity,
                    onTap: {
                        valuePickerStore.send(
                            .prepare(
                                .init(
                                    propertyKey: condition.propertyKey,
                                    operatorCode: operatorCode,
                                    valueType: condition.valueType,
                                    valueUIKind: valueUIKind,
                                    valueArity: 2,
                                    existingValues: condition.values,
                                    editingIndex: 1,
                                ),
                            ),
                        )
                    },
                )
            }
        }
    }

    private func rangeDisplayView(
        operatorCode: String,
        valueUIKind: String,
        values: [String],
    ) -> some View {
        HStack(spacing: 6) {
            ValuePillView(
                text: values[0],
                isDark: isDark,
                hoverFillOpacity: hoverFillOpacity,
                onTap: {
                    valuePickerStore.send(
                        .prepare(
                            .init(
                                propertyKey: condition.propertyKey,
                                operatorCode: operatorCode,
                                valueType: condition.valueType,
                                valueUIKind: valueUIKind,
                                valueArity: 2,
                                existingValues: condition.values,
                                editingIndex: 0,
                            ),
                        ),
                    )
                },
            )
            Text("and")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            ValuePillView(
                text: values[1],
                isDark: isDark,
                hoverFillOpacity: hoverFillOpacity,
                onTap: {
                    valuePickerStore.send(
                        .prepare(
                            .init(
                                propertyKey: condition.propertyKey,
                                operatorCode: operatorCode,
                                valueType: condition.valueType,
                                valueUIKind: valueUIKind,
                                valueArity: 2,
                                existingValues: condition.values,
                                editingIndex: 1,
                            ),
                        ),
                    )
                },
            )
        }
    }

    @ViewBuilder
    private func dateValueSection(
        operatorCode: String,
        valueUIKind: String,
        valueArity: Int,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let hasError = valueViewStore.errorMessage != nil
        if valueArity >= 2 {
            HStack(spacing: 6) {
                dateValueButton(
                    placeholderText: "From",
                    currentText: condition.values?.first ?? "",
                    hasError: hasError,
                    index: 0,
                    valueViewStore: valueViewStore,
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    valueArity: valueArity,
                )
                Text("and")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                dateValueButton(
                    placeholderText: "To",
                    currentText: (condition.values?.count ?? 0) > 1 ? (condition.values?[1] ?? "") : "",
                    hasError: hasError,
                    index: 1,
                    valueViewStore: valueViewStore,
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    valueArity: valueArity,
                )
            }
        } else {
            dateValueButton(
                placeholderText: "Value",
                currentText: condition.values?.first ?? "",
                hasError: hasError,
                index: 0,
                valueViewStore: valueViewStore,
                operatorCode: operatorCode,
                valueUIKind: valueUIKind,
                valueArity: valueArity,
            )
        }
    }

    private func singleValueButton(
        operatorCode: String,
        valueUIKind: String,
        valueArity: Int,
    ) -> some View {
        Button {
            valuePickerStore.send(
                .prepare(
                    .init(
                        propertyKey: condition.propertyKey,
                        operatorCode: operatorCode,
                        valueType: condition.valueType,
                        valueUIKind: valueUIKind,
                        valueArity: valueArity,
                        existingValues: condition.values,
                        editingIndex: nil,
                    ),
                ),
            )
        } label: {
            Text(displayValueText())
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(condition.values == nil ? .secondary.opacity(0.7) : .primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            isValueHovering
                                ? (isDark ? Color.white.opacity(hoverFillOpacity) :
                                    Color.black.opacity(hoverFillOpacity))
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
    }

    private struct ValuePillView: View {
        let text: String
        let isDark: Bool
        let hoverFillOpacity: Double
        let onTap: () -> Void

        @State private var isHovering: Bool = false

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
                                    ? (isDark ? Color.white.opacity(hoverFillOpacity) :
                                        Color.black.opacity(hoverFillOpacity))
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

    private func inlineValueInputs(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        valueArity: Int,
        valueType: String,
        valueUIKind: String,
        errorMessage: String?,
        editingIndex: Int?,
    ) -> some View {
        let hasError = errorMessage != nil
        let fieldCount = max(max(valueArity, valueViewStore.values.count), 1)
        let indices: [Int] = {
            if let editingIndex {
                return [editingIndex]
            }
            return Array(0 ..< fieldCount)
        }()
        let shouldFocus = valueViewStore.isPresented &&
            valueViewStore.propertyKey == condition.propertyKey

        return HStack(spacing: 6) {
            ForEach(indices, id: \.self) { index in
                let currentText = valueViewStore.values.indices.contains(index) ? valueViewStore.values[index] : ""
                let placeholderText = hasError ? "" : placeholder(
                    for: valueArity,
                    index: index,
                    valueType: valueType,
                )

                if valueType == "date" || valueType == "datetime" {
                    EmptyView()
                } else if valueType == "boolean" {
                    booleanValueButton(
                        placeholderText: placeholderText,
                        currentText: currentText,
                        index: index,
                        valueViewStore: valueViewStore,
                        operatorCode: condition.operatorCode ?? "eq",
                        valueUIKind: valueUIKind,
                    )
                } else {
                    HStack(spacing: 4) {
                        TextField(
                            placeholderText,
                            text: valueViewStore.binding(
                                get: { state in
                                    state.values.indices.contains(index) ? state.values[index] : ""
                                },
                                send: { .setValue(index: index, text: $0) },
                            ),
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Color.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(
                            minWidth: {
                                if valueType == "number" {
                                    return hasError ? 70 : 55
                                }
                                return hasError ? 80 : 60
                            }(),
                            maxWidth: {
                                if valueType == "number" {
                                    return hasError ? 130 : 95
                                }
                                return hasError ? 150 : 110
                            }(),
                            alignment: .leading,
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    hasError ? Color.red.opacity(0.85) :
                                        (isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)),
                                    lineWidth: 1,
                                ),
                        )
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
                        .focused($focusedValueIndex, equals: index)
                        .onSubmit {
                            valuePickerStore.send(.commit)
                        }

                        if valueType == "number", condition.propertyKey == "size" {
                            Text("bytes")
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                                .fixedSize()
                        }
                    }
                }

                if valueArity >= 2, index == 0 {
                    Text("and")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
            }
        }
        .padding(.leading, 4)
        .onAppear {
            updateInlineValueFocus(
                shouldFocus: shouldFocus,
                targetIndex: valueViewStore.editingIndex ?? indices.first,
            )
        }
        .onChange(of: valueViewStore.isPresented) { _ in
            updateInlineValueFocus(
                shouldFocus: shouldFocus,
                targetIndex: valueViewStore.editingIndex ?? indices.first,
            )
        }
        .onChange(of: valueViewStore.editingIndex) { _ in
            updateInlineValueFocus(
                shouldFocus: shouldFocus,
                targetIndex: valueViewStore.editingIndex ?? indices.first,
            )
        }
        .onChange(of: valueViewStore.propertyKey) { _ in
            updateInlineValueFocus(
                shouldFocus: shouldFocus,
                targetIndex: valueViewStore.editingIndex ?? indices.first,
            )
        }
    }

    private func updateInlineValueFocus(shouldFocus: Bool, targetIndex: Int?) {
        let nextFocus = shouldFocus ? targetIndex : nil
        guard focusedValueIndex != nextFocus else { return }
        DispatchQueue.main.async {
            focusedValueIndex = nextFocus
        }
    }

    private func dateValueButton(
        placeholderText: String,
        currentText: String,
        hasError: Bool,
        index: Int,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        operatorCode: String,
        valueUIKind: String,
        valueArity: Int,
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { datePopoverIndex == index },
            set: { show in
                if !show { datePopoverIndex = nil }
            },
        )

        return Button {
            let currentValues: [String]? = {
                if valueViewStore.propertyKey == condition.propertyKey {
                    return valueViewStore.values
                }
                return condition.values
            }()
            valuePickerStore.send(
                .prepare(
                    .init(
                        propertyKey: condition.propertyKey,
                        operatorCode: operatorCode,
                        valueType: condition.valueType,
                        valueUIKind: valueUIKind,
                        valueArity: valueArity,
                        existingValues: currentValues,
                        editingIndex: index,
                    ),
                ),
            )
            tempDate = ValueNormalizerUtils.parseDate(currentText) ?? Date()
            datePopoverIndex = index
        } label: {
            let isHovering = dateHoverIndex == index
            let labelText = currentText.isEmpty
                ? (placeholderText.isEmpty ? "Value" : placeholderText.capitalized)
                : (ValueNormalizerUtils.formatDateOnlyString(currentText) ?? currentText)
            Text(labelText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(currentText.isEmpty ? .secondary : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(minWidth: 50, maxWidth: 80, alignment: .center)
                .fixedSize(horizontal: true, vertical: true)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            isHovering
                                ? (isDark ? Color.white.opacity(hoverFillOpacity) :
                                    Color.black.opacity(hoverFillOpacity))
                                : Color.white.opacity(0.0001),
                        ),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            hasError ? Color.red.opacity(0.85) :
                                Color.clear,
                            lineWidth: hasError ? 1 : 0,
                        ),
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hover in
            if hover {
                dateHoverIndex = index
            } else if dateHoverIndex == index {
                dateHoverIndex = nil
            }
        }
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                let applySelection = {
                    let formatted = ValueNormalizerUtils.formatDateOnly(tempDate)
                    valueViewStore.send(.setValue(index: index, text: formatted))
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

    private func booleanValueButton(
        placeholderText: String,
        currentText: String,
        index: Int,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        operatorCode: String,
        valueUIKind: String,
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { boolPopoverIndex == index },
            set: { show in
                if !show { boolPopoverIndex = nil }
            },
        )

        return Button {
            valuePickerStore.send(
                .prepare(
                    .init(
                        propertyKey: condition.propertyKey,
                        operatorCode: operatorCode,
                        valueType: "boolean",
                        valueUIKind: valueUIKind,
                        valueArity: 1,
                        existingValues: condition.values,
                        editingIndex: index,
                    ),
                ),
            )
            boolPopoverIndex = index
        } label: {
            let isHovering = boolHoverIndex == index
            let labelText = currentText
                .isEmpty ? (placeholderText.isEmpty ? "Value" : placeholderText.capitalized) : currentText.capitalized
            Text(labelText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(currentText.isEmpty ? .secondary : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(minWidth: 50, maxWidth: 70, alignment: .center)
                .fixedSize(horizontal: true, vertical: true)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            isHovering
                                ? (isDark ? Color.white.opacity(hoverFillOpacity) :
                                    Color.black.opacity(hoverFillOpacity))
                                : Color.white.opacity(0.0001),
                        ),
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hover in
            if hover {
                boolHoverIndex = index
            } else if boolHoverIndex == index {
                boolHoverIndex = nil
            }
        }
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                let trueHovering = boolOptionHoverValue == "True"
                Button {
                    valueViewStore.send(.setValue(index: 0, text: "True"))
                    valuePickerStore.send(.commit)
                    boolPopoverIndex = nil
                } label: {
                    HStack {
                        Text("True")
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                trueHovering
                                    ? (isDark ? Color.white.opacity(hoverFillOpacity) :
                                        Color.black.opacity(hoverFillOpacity))
                                    : Color.clear,
                            ),
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { hovering in
                    boolOptionHoverValue = hovering ? "True" :
                        (boolOptionHoverValue == "True" ? nil : boolOptionHoverValue)
                }

                let falseHovering = boolOptionHoverValue == "False"
                Button {
                    valueViewStore.send(.setValue(index: 0, text: "False"))
                    valuePickerStore.send(.commit)
                    boolPopoverIndex = nil
                } label: {
                    HStack {
                        Text("False")
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                falseHovering
                                    ? (isDark ? Color.white.opacity(hoverFillOpacity) :
                                        Color.black.opacity(hoverFillOpacity))
                                    : Color.clear,
                            ),
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { hovering in
                    boolOptionHoverValue = hovering ? "False" :
                        (boolOptionHoverValue == "False" ? nil : boolOptionHoverValue)
                }
            }
            .padding(10)
            .frame(width: 150)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(VoyagerDS.Surface.popoverBackground(for: isDark ? .dark : .light)),
            )
        }
    }

    private func displayValueText() -> String {
        guard let values = condition.values, !values.isEmpty else { return "Value" }
        let suffix = if condition.propertyKey == "size", condition.valueType == "number" {
            " bytes"
        } else {
            ""
        }
        if condition.valueType == "date" || condition.valueType == "datetime" {
            let first = ValueNormalizerUtils.formatDateOnlyString(values[0]) ?? values[0]
            if values.count >= 2 {
                let second = ValueNormalizerUtils.formatDateOnlyString(values[1]) ?? values[1]
                if first == second {
                    return first + suffix
                }
                return first + " ~ " + second + suffix
            }
            return first + suffix
        }
        if values.count >= 2 {
            return values[0] + " and " + values[1] + suffix
        }
        return values[0] + suffix
    }

    private func placeholder(for arity: Int, index: Int, valueType: String) -> String {
        if arity >= 2 {
            return index == 0 ? "From" : "To"
        }

        switch valueType {
        case "number":
            return "Number Value"
        default:
            return "Value"
        }
    }
}

private struct CalendarDatePicker: NSViewRepresentable {
    @Binding var selection: Date
    let onCommit: () -> Void

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
}

// swiftlint:enable type_body_length function_body_length
