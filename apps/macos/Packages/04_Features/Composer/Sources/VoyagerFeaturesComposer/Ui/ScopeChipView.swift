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
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(VoyagerDS.Surface.chipContainerBackground(for: colorScheme))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityText)
        .help(summary.accessibilityText)
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

struct ScopeTokenChipView: View {
    let title: String
    let path: String?
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Text("\u{10088A}")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 12, height: 12)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove scope \(title)")
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, onRemove == nil ? 8 : 5)
        .frame(height: 22)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(VoyagerDS.SystemColor.separator.opacity(0.9)),
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(path.map { "Scope \(title), \($0)" } ?? title)
        .help(path ?? title)
    }
}

extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

enum ChipItemType: Identifiable, Hashable {
    case scopeRoot
    case scopeBase(path: String)
    case condition(Condition)
    case conditionAdd

    var id: String {
        switch self {
        case .scopeRoot:
            "scope-root"
        case let .scopeBase(path):
            "scope-base-\(path)"
        case let .condition(condition):
            "condition-\(condition.propertyKey)"
        case .conditionAdd:
            "condition-add"
        }
    }
}
