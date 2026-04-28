import ComposableArchitecture
import SwiftUI
import VoyagerShared

import VoyagerEntitiesEntry

struct ConditionChipView: View {
    let propertyPickerStore: StoreOf<ConditionPropertyPickerFeature>
    let condition: Condition
    let isDark: Bool
    let hoverFillOpacity: Double
    let operatorPickerStore: StoreOf<OperatorPickerFeature>
    let valuePickerStore: StoreOf<ValuePickerFeature>
    let operatorOptions: [String]
    let displayState: ConditionDisplayState?
    let defaultChipHeight: CGFloat
    let onPropertyTap: () -> Void
    let onRemove: () -> Void
    let onDisplayUnitChange: (_ propertyKey: String, _ unitCode: String) -> Void

    @State private var isChipHovering = false
    @State private var isRemoveHovering = false

    var body: some View {
        let isInactive = !condition.isActive

        return ZStack(alignment: .topTrailing) {
            HStack(spacing: 2) {
                ConditionChipPropertyOperatorView(
                    propertyPickerStore: propertyPickerStore,
                    operatorPickerStore: operatorPickerStore,
                    condition: condition,
                    operatorOptions: operatorOptions,
                    isDark: isDark,
                    hoverFillOpacity: hoverFillOpacity,
                    onPropertyTap: onPropertyTap,
                )

                ConditionChipValueSectionView(
                    condition: condition,
                    displayState: displayState,
                    isDark: isDark,
                    hoverFillOpacity: hoverFillOpacity,
                    valuePickerStore: valuePickerStore,
                    onDisplayUnitChange: onDisplayUnitChange,
                )
            }
            .allowsHitTesting(!isInactive)
            .opacity(isInactive ? 0.55 : 1)
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
}
