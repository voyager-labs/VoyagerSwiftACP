import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerShared

struct ConditionChipView: View {
    let store: StoreOf<ConditionEditorFeature>
    let isDark: Bool
    let hoverFillOpacity: Double
    let defaultChipHeight: CGFloat
    let onRemove: () -> Void

    @State private var isChipHovering = false
    @State private var isRemoveHovering = false

    var body: some View {
        WithViewStore(
            store,
            observe: { $0 },
            content: { viewStore in
                let isInactive = viewStore.condition.availability != .available

                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 2) {
                        ConditionChipPropertyOperatorView(
                            store: store,
                            condition: viewStore.condition,
                            isDark: isDark,
                            hoverFillOpacity: hoverFillOpacity,
                        )

                        ConditionChipValueSectionView(
                            store: store,
                            condition: viewStore.condition,
                            displayState: viewStore.displayState,
                            isDark: isDark,
                            hoverFillOpacity: hoverFillOpacity,
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
                            .accessibilityLabel("Remove condition \(viewStore.id.uuidString)")
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
                .accessibilityIdentifier("composer.condition.\(viewStore.id.uuidString)")
                .onHover { hovering in
                    isChipHovering = hovering
                }
            },
        )
    }
}
