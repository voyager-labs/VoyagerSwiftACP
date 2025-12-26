import ComposableArchitecture
import SwiftUI

struct ConditionChipView: View {
    let condition: Condition
    let isDark: Bool
    let hoverFillOpacity: Double
    let operatorPickerStore: StoreOf<OperatorPickerFeature>
    let operatorOptions: [OperatorOption]
    let defaultChipHeight: CGFloat
    let onPropertyTap: () -> Void
    let onRemove: () -> Void

    @State private var isPropertyHovering: Bool = false

    var body: some View {
        WithViewStore(operatorPickerStore, observe: { $0 }, content: { pickerViewStore in
            let operatorLabel = condition.operatorLabel ?? "operator"
            let operatorColor: Color = condition.operatorLabel == nil ? .secondary.opacity(0.7) : .primary

            HStack(spacing: 2) {
                Text(condition.propertyLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
                    .padding(.leading, 4)
                    .padding(.trailing, 2)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.clear),
                        alignment: .center,
                    )
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

                Button {
                    pickerViewStore.send(.prepare(propertyKey: condition.propertyKey, options: operatorOptions))
                } label: {
                    Text(operatorLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(operatorColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    pickerViewStore.propertyKey == condition.propertyKey && pickerViewStore.isPresented
                                        ?
                                        (isDark ? Color.white.opacity(hoverFillOpacity) : Color.black
                                            .opacity(hoverFillOpacity))
                                        : Color.white.opacity(0.0001),
                                ),
                            alignment: .center,
                        )
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 0)
                .padding(.vertical, 0)
                .frame(minWidth: 28, minHeight: 22, alignment: .center)
                .background(Color.white.opacity(0.0001))
                .buttonStyle(.plain)
                .popover(
                    isPresented: Binding(
                        get: { pickerViewStore.isPresented && pickerViewStore.propertyKey == condition.propertyKey },
                        set: { isPresented in
                            pickerViewStore.send(.setPresented(isPresented))
                        },
                    ),
                    arrowEdge: .bottom,
                ) {
                    OperatorPickerView(store: operatorPickerStore)
                }
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
        })
    }
}
