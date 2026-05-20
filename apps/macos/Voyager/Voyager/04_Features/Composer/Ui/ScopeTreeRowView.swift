import AppKit
import SwiftUI

struct ScopeTreeRowView: View {
    let row: ComposerScopeTreeRow
    let colorScheme: ColorScheme
    let applicationsIcon: NSImage?
    let onBodyTap: () -> Void
    let onAction: (ComposerScopeTreeRowAvailableAction) -> Void
    let actionAccessibilityIdentifier: ((ComposerScopeTreeRowAvailableAction) -> String?)?

    private let indentationWidth: CGFloat = 16
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: CGFloat(max(row.depth, 0)) * indentationWidth)

            Button(action: onBodyTap) {
                HStack(spacing: 8) {
                    rowIcon
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(row.displayName)
                                .font(.system(size: 13, weight: titleWeight))
                                .foregroundColor(titleColor)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            statusBadge(text: stateBadgeText, tint: stateBadgeTint)
                            if let sourceBadgeText {
                                statusBadge(text: sourceBadgeText, tint: .secondary)
                            }
                        }

                        Text(row.secondaryText ?? row.path)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if let primaryAction = row.availableActions.first {
                actionButton(for: primaryAction)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundFill),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 0.5),
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var rowIcon: some View {
        Group {
            if row.path == "/Applications", let applicationsIcon {
                Image(nsImage: applicationsIcon)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(iconColor)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: row.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 16, height: 16)
            }
        }
    }

    private func actionButton(for action: ComposerScopeTreeRowAvailableAction) -> some View {
        Button(
            action: { onAction(action) },
            label: {
                HStack(spacing: 4) {
                    Image(systemName: actionSymbolName(for: action))
                        .font(.system(size: 9, weight: .semibold))
                    Text(actionLabel(for: action))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(actionUsesDestructiveStyling(action) ? .secondary : .accentColor)
            },
        )
        .buttonStyle(.borderless)
        .help(actionLabel(for: action))
        .accessibilityLabel(actionLabel(for: action))
        .ifLetAccessibilityIdentifier(actionAccessibilityIdentifier?(action))
    }

    private var backgroundFill: Color {
        switch row.visualState {
        case .included:
            if isHovering {
                VoyagerDS.Interaction.hoverFill(for: colorScheme)
            } else {
                VoyagerDS.Surface.chipItemBackground(for: colorScheme)
            }
        case .excluded:
            if isHovering {
                VoyagerDS.Interaction.hoverFill(for: colorScheme).opacity(0.7)
            } else {
                VoyagerDS.Surface.chipItemBackground(for: colorScheme).opacity(0.7)
            }
        case .none:
            if isHovering {
                VoyagerDS.Interaction.hoverFill(for: colorScheme)
            } else {
                VoyagerDS.Surface.chipItemBackground(for: colorScheme)
            }
        }
    }

    private var borderColor: Color {
        switch row.visualState {
        case .included:
            Color.accentColor.opacity(0.35)
        case .excluded:
            Color.secondary.opacity(0.2)
        case .none:
            VoyagerDS.Surface.chipItemBorder(for: colorScheme)
        }
    }

    private var titleColor: Color {
        switch row.visualState {
        case .excluded:
            .secondary
        case .included, .none:
            .primary
        }
    }

    private var titleWeight: Font.Weight {
        switch row.ruleSource {
        case .direct:
            .semibold
        case .inherited, .none:
            .regular
        }
    }

    private var iconColor: Color {
        switch row.visualState {
        case .included:
            .accentColor
        case .excluded, .none:
            .secondary
        }
    }

    private var stateBadgeText: String {
        switch row.visualState {
        case .included:
            "Included"
        case .excluded:
            "Excluded"
        case .none:
            "Available"
        }
    }

    private var stateBadgeTint: Color {
        switch row.visualState {
        case .included:
            .accentColor
        case .excluded, .none:
            .secondary
        }
    }

    private var sourceBadgeText: String? {
        switch row.ruleSource {
        case .direct:
            "Direct"
        case .inherited:
            "Inherited"
        case .none:
            nil
        }
    }

    private func actionSymbolName(for action: ComposerScopeTreeRowAvailableAction) -> String {
        switch action {
        case .include:
            "checkmark"
        case .exclude:
            "minus"
        case .clearDirectRule:
            switch row.kind {
            case .exception:
                "arrow.uturn.backward"
            case .base, .candidate, .root:
                "xmark"
            }
        }
    }

    private func actionLabel(for action: ComposerScopeTreeRowAvailableAction) -> String {
        switch action {
        case .include:
            "Include scope"
        case .exclude:
            "Exclude scope"
        case .clearDirectRule:
            switch row.kind {
            case .base:
                "Remove direct scope rule"
            case .exception:
                "Restore excluded scope"
            case .candidate, .root:
                "Remove direct scope rule"
            }
        }
    }

    private func actionUsesDestructiveStyling(_ action: ComposerScopeTreeRowAvailableAction) -> Bool {
        switch action {
        case .exclude, .clearDirectRule:
            true
        case .include:
            false
        }
    }

    private func statusBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(
                        tint == .accentColor
                            ? Color.accentColor.opacity(0.14)
                            : VoyagerDS.Surface.chipItemBackground(for: colorScheme),
                    ),
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

private extension View {
    @ViewBuilder
    func ifLetAccessibilityIdentifier(_ accessibilityIdentifier: String?) -> some View {
        if let accessibilityIdentifier {
            self.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            self
        }
    }
}
