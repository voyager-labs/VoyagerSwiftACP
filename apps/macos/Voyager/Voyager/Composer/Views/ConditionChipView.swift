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
        let opLabel = condition.operatorLabel ?? "operator"
        let opColor: Color = condition.operatorLabel == nil ? .secondary.opacity(0.7) : .primary
        let selectedOperator = operatorOptions.first(where: { $0.code == condition.operatorCode })
        let valueArity = condition.operatorValueArity ?? selectedOperator?.valueArity ?? 0
        let isEditingValue = valueStore.isPresented && valueStore.propertyKey == condition.propertyKey

        return HStack(spacing: 2) {
            propertyLabelView()
            operatorButtonView(opStore: opStore, label: opLabel, color: opColor)
            valueSection(
                selectedOperator: selectedOperator,
                valueArity: valueArity,
                isEditingValue: isEditingValue,
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
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        if let op = selectedOperator, valueArity != 0 {
            if isEditingValue {
                inlineValueInputs(
                    valueViewStore: valueStore,
                    valueArity: valueArity,
                    valueType: condition.valueType,
                    errorMessage: valueStore.errorMessage,
                )
            } else {
                Button {
                    valuePickerStore.send(
                        .prepare(
                            propertyKey: condition.propertyKey,
                            operatorOption: op,
                            valueType: condition.valueType,
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
        } else {
            EmptyView()
        }
    }

    private func inlineValueInputs(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        valueArity: Int,
        valueType: ValueType,
        errorMessage: String?,
    ) -> some View {
        let hasError = errorMessage != nil
        let fieldCount = max(max(valueArity, valueViewStore.values.count), 1)

        return HStack(spacing: 6) {
            ForEach(0 ..< fieldCount, id: \.self) { index in
                let currentText = valueViewStore.values.indices.contains(index) ? valueViewStore.values[index] : ""
                let placeholderText = errorMessage ?? placeholder(
                    for: valueArity,
                    index: index,
                    valueType: valueType,
                )

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
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            hasError ? Color.red.opacity(0.85) :
                                (isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)),
                            lineWidth: 1,
                        ),
                )
                .onSubmit {
                    valuePickerStore.send(.commit)
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

    private func displayValueText() -> String {
        guard let values = condition.values, !values.isEmpty else { return "value" }
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
