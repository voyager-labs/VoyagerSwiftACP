import SwiftUI

struct ConditionChipView: View {
    let condition: Condition
    let isDark: Bool
    let hoverFillOpacity: Double
    let operatorOptions: [(code: String, label: String)]
    let defaultChipHeight: CGFloat
    let onPropertyTap: () -> Void
    let onOperatorSelect: (String, String) -> Void
    let onRemove: () -> Void

    @State private var isPropertyHovering: Bool = false
    @State private var isOperatorHovering: Bool = false
    @State private var isPopoverPresented: Bool = false

    var body: some View {
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
                isPopoverPresented = true
            } label: {
                Text(operatorLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(operatorColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                isOperatorHovering || isPopoverPresented
                                    ?
                                    (isDark ? Color.white.opacity(hoverFillOpacity) : Color.black
                                        .opacity(hoverFillOpacity))
                                    : Color.white.opacity(0.0001),
                            ),
                        alignment: .center,
                    )
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isOperatorHovering = hovering
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 0)
            .frame(minWidth: 28, minHeight: 22, alignment: .center)
            .background(Color.white.opacity(0.0001))
            .buttonStyle(.plain)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                operatorList()
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
    }

    @ViewBuilder
    private func operatorList() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(operatorOptions, id: \.code) { option in
                Button {
                    onOperatorSelect(option.code, option.label)
                    isPopoverPresented = false
                } label: {
                    HStack {
                        Text(option.label)
                            .foregroundColor(.primary)
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color(red: 0.16, green: 0.16, blue: 0.16) : Color.white),
        )
    }
}
