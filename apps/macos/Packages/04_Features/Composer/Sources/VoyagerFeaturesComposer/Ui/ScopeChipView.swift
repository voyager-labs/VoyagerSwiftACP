import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesEntry
import VoyagerShared

struct ScopeChipView: View {
    let summary: ComposerScopeSummary
    let store: StoreOf<ComposerFeature>
    let favorites: [ScopeFavoriteItem]
    let backHistory: [String]
    @State private var dropdownHovering: Bool = false
    @Environment(\.colorScheme)
    private var colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.primaryText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let secondary = summary.secondaryText {
                    Text(secondary)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            if let badge = summary.badgeText {
                Text(badge)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(VoyagerDS.Interaction.hoverFill(for: colorScheme)),
                    )
                    .fixedSize(horizontal: true, vertical: false)
            }

            dropdownButton(compact: summary.primary == .rootOnly)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(VoyagerDS.Surface.chipContainerBackground(for: colorScheme))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityText)
    }

    private func dropdownButton(compact: Bool) -> some View {
        Button {
            store.send(.scopeEditorOpen(editingPath: nil, favorites: favorites, backHistory: backHistory))
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundColor(dropdownHovering ? .primary : .secondary)
                .padding(.horizontal, compact ? 3 : 6)
                .padding(.vertical, 2)
                .frame(height: 19)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(dropdownHovering ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear)
                )
        }
        .buttonStyle(.borderless)
        .onHover { hovering in
            dropdownHovering = hovering
        }
    }
}
