import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection

struct ConditionChipPropertyOperatorView: View {
    let propertyPickerStore: StoreOf<ConditionPropertyPickerFeature>
    let operatorPickerStore: StoreOf<OperatorPickerFeature>
    let condition: Condition
    let operatorOptions: [String]
    let isDark: Bool
    let hoverFillOpacity: Double
    let onPropertyTap: () -> Void

    @State private var isPropertyHovering = false
    @State private var isOperatorHovering = false

    var body: some View {
        WithViewStore(propertyPickerStore, observe: { $0 }, content: { propertyStore in
            WithViewStore(operatorPickerStore, observe: { $0 }, content: { opStore in
                HStack(spacing: 2) {
                    propertyLabelView(propertyStore: propertyStore)
                    operatorButtonView(opStore: opStore)
                }
            })
        })
    }

    private func propertyLabelView(
        propertyStore: ViewStore<ConditionPropertyPickerFeature.State, ConditionPropertyPickerFeature.Action>,
    ) -> some View {
        HStack(spacing: 6) {
            let category = propertyStore.propertyCategories[condition.propertyKey]
            let type = propertyStore.propertyTypes[condition.propertyKey]
            Image(
                systemName: ConditionPropertyIconUtils.iconName(
                    forKey: condition.propertyKey,
                    category: category,
                    type: type,
                ),
            )
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
    }

    private func operatorButtonView(
        opStore: ViewStore<OperatorPickerFeature.State, OperatorPickerFeature.Action>,
    ) -> some View {
        let label = condition.operatorLabel ?? "Operator"
        let color: Color = condition.operatorLabel == nil ? .secondary.opacity(0.7) : .primary

        return Button {
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
                set: { isPresented in opStore.send(.setPresented(isPresented)) },
            ),
            arrowEdge: .bottom,
            content: {
                OperatorPickerView(store: operatorPickerStore)
            },
        )
    }
}
