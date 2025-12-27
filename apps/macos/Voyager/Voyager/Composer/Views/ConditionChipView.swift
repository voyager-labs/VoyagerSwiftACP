// swiftlint:disable type_body_length function_body_length file_length
import ComposableArchitecture
import SwiftUI

struct ConditionChipView: View {
    let condition: Condition
    let isDark: Bool
    let hoverFillOpacity: Double
    let operatorPickerStore: StoreOf<OperatorPickerFeature>
    let valuePickerStore: StoreOf<ValuePickerFeature>
    let operatorOptions: [OperatorOption]
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

    var body: some View {
        WithViewStore(operatorPickerStore, observe: { $0 }, content: { opStore in
            WithViewStore(valuePickerStore, observe: { $0 }, content: { valueStore in
                chipContent(opStore: opStore, valueStore: valueStore)
            })
        })
    }

    private func chipContent(
        opStore: ViewStore<OperatorPickerFeature.State, OperatorPickerFeature.Action>,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let opLabel = condition.operatorLabel ?? "Operator"
        let opColor: Color = condition.operatorLabel == nil ? .secondary.opacity(0.7) : .primary
        let selectedOperator = operatorOptions.first(where: { $0.code == condition.operatorCode })
        let valueArity = condition.operatorValueArity ?? selectedOperator?.valueArity ?? 0
        let isDateType = condition.valueType == .date
        let isEditingValue = !isDateType && valueStore.isPresented && valueStore.propertyKey == condition.propertyKey

        return HStack(spacing: 2) {
            propertyLabelView()
            operatorButtonView(opStore: opStore, label: opLabel, color: opColor)
            valueSection(
                selectedOperator: selectedOperator,
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
            }
            .buttonStyle(.borderless)
            .padding(2)
            .offset(x: 6, y: -6)
            .opacity(isChipHovering ? 1 : 0)
            .allowsHitTesting(isChipHovering)
        }
        .onHover { hovering in
            isChipHovering = hovering
        }
    }

    private func propertyLabelView() -> some View {
        Text(condition.propertyLabel)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary.opacity(0.8))
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
            }
    }

    private func operatorButtonView(
        opStore: ViewStore<OperatorPickerFeature.State, OperatorPickerFeature.Action>,
        label: String,
        color: Color,
    ) -> some View {
        Button {
            opStore.send(.prepare(propertyKey: condition.propertyKey, options: operatorOptions))
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
        ) {
            OperatorPickerView(store: operatorPickerStore)
        }
    }

    @ViewBuilder
    private func valueSection(
        selectedOperator: OperatorOption?,
        valueArity: Int,
        isEditingValue: Bool,
        isDateType: Bool,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        if let op = selectedOperator, valueArity != 0 {
            if isDateType {
                dateValueSection(operatorOption: op, valueArity: valueArity)
            } else
            if isEditingValue, valueArity >= 2, let editingIndex = valueStore.editingIndex {
                rangeEditingView(
                    operatorOption: op,
                    editingIndex: editingIndex,
                    valueStore: valueStore,
                )
            } else if isEditingValue {
                inlineValueInputs(
                    valueViewStore: valueStore,
                    valueArity: valueArity,
                    valueType: condition.valueType,
                    errorMessage: valueStore.errorMessage,
                    editingIndex: nil,
                )
            } else if valueArity >= 2, let values = condition.values, values.count >= 2 {
                rangeDisplayView(operatorOption: op, values: values)
            } else {
                singleValueButton(operatorOption: op)
            }
        } else {
            EmptyView()
        }
    }

    private func rangeEditingView(
        operatorOption: OperatorOption,
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
                                    operatorOption: operatorOption,
                                    valueType: condition.valueType,
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
                valueArity: operatorOption.valueArity,
                valueType: condition.valueType,
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
                                    operatorOption: operatorOption,
                                    valueType: condition.valueType,
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

    private func rangeDisplayView(operatorOption: OperatorOption, values: [String]) -> some View {
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
                                operatorOption: operatorOption,
                                valueType: condition.valueType,
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
                                operatorOption: operatorOption,
                                valueType: condition.valueType,
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
    private func dateValueSection(operatorOption: OperatorOption, valueArity: Int) -> some View {
        if valueArity >= 2 {
            HStack(spacing: 6) {
                dateValueButton(
                    placeholderText: "From",
                    currentText: condition.values?.first ?? "",
                    hasError: false,
                    index: 0,
                    valueViewStore: ViewStore(valuePickerStore, observe: { $0 }),
                    operatorOption: operatorOption,
                )
                Text("and")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                dateValueButton(
                    placeholderText: "To",
                    currentText: (condition.values?.count ?? 0) > 1 ? (condition.values?[1] ?? "") : "",
                    hasError: false,
                    index: 1,
                    valueViewStore: ViewStore(valuePickerStore, observe: { $0 }),
                    operatorOption: operatorOption,
                )
            }
        } else {
            dateValueButton(
                placeholderText: "Value",
                currentText: condition.values?.first ?? "",
                hasError: false,
                index: 0,
                valueViewStore: ViewStore(valuePickerStore, observe: { $0 }),
                operatorOption: operatorOption,
            )
        }
    }

    private func singleValueButton(operatorOption: OperatorOption) -> some View {
        Button {
            valuePickerStore.send(
                .prepare(
                    .init(
                        propertyKey: condition.propertyKey,
                        operatorOption: operatorOption,
                        valueType: condition.valueType,
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
        valueType: ValueType,
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

        return HStack(spacing: 6) {
            ForEach(indices, id: \.self) { index in
                let currentText = valueViewStore.values.indices.contains(index) ? valueViewStore.values[index] : ""
                let placeholderText = hasError ? "" : placeholder(
                    for: valueArity,
                    index: index,
                    valueType: valueType,
                )

                if valueType == .date {
                    EmptyView()
                } else {
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
                            if valueType == .number {
                                return hasError ? 70 : 55
                            }
                            return hasError ? 80 : 60
                        }(),
                        maxWidth: {
                            if valueType == .number {
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
                    .onSubmit {
                        valuePickerStore.send(.commit)
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
    }

    private func dateValueButton(
        placeholderText: String,
        currentText: String,
        hasError: Bool,
        index: Int,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        operatorOption: OperatorOption,
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { datePopoverIndex == index },
            set: { show in
                if !show { datePopoverIndex = nil }
            },
        )

        return Button {
            valuePickerStore.send(
                .prepare(
                    .init(
                        propertyKey: condition.propertyKey,
                        operatorOption: operatorOption,
                        valueType: condition.valueType,
                        existingValues: condition.values,
                        editingIndex: index,
                    ),
                ),
            )
            tempDate = ValuePickerFeature.parseDate(currentText) ?? Date()
            datePopoverIndex = index
        } label: {
            let isHovering = dateHoverIndex == index
            let labelText = currentText
                .isEmpty ? (placeholderText.isEmpty ? "Value" : placeholderText.capitalized) : currentText
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
                DatePicker(
                    "",
                    selection: $tempDate,
                    displayedComponents: [.date],
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                HStack {
                    Spacer()
                    Button("Apply") {
                        let formatted = ValuePickerFeature.formatDate(tempDate)
                        valueViewStore.send(.setValue(index: index, text: formatted))
                        valuePickerStore.send(.commit)
                        datePopoverIndex = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(12)
        }
    }

    private func displayValueText() -> String {
        guard let values = condition.values, !values.isEmpty else { return "Value" }
        if values.count >= 2 {
            return values[0] + " and " + values[1]
        }
        return values[0]
    }

    private func placeholder(for arity: Int, index: Int, valueType: ValueType) -> String {
        if arity >= 2 {
            return index == 0 ? "From" : "To"
        }

        switch valueType {
        case .number:
            return "Number Value"
        default:
            return "Value"
        }
    }
}

// swiftlint:enable type_body_length function_body_length
