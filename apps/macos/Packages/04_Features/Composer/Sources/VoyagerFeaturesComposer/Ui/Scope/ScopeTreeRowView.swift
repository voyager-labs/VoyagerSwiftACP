import AppKit
import SwiftUI
import VoyagerShared

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
                                .layoutPriority(1)
                                .helpIfPresent(sourceBadgeHelp)

                            statusBadge(
                                text: stateBadgeText,
                                tint: stateBadgeTint,
                                background: stateBadgeBackground,
                            )
                        }

                        Text(row.path)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .helpIfPresent(sourceBadgeHelp)

            Spacer(minLength: 8)

            if let primaryAction = row.availableActions.first {
                actionButton(for: primaryAction)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .fill(backgroundFill),
        )
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .stroke(borderColor, lineWidth: 0.5),
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .helpIfPresent(sourceBadgeHelp)
    }

    private var rowIcon: some View {
        Group {
            if row.path == "/Applications", let applicationsIcon {
                Image(nsImage: applicationsIcon)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(iconColor)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: row.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
        }
    }

    private func actionButton(for action: ComposerScopeTreeRowAvailableAction) -> some View {
        Button(
            action: { onAction(action) },
            label: {
                HStack(spacing: isHovering ? 4 : 0) {
                    Image(systemName: actionSymbolName(for: action))
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                    if isHovering {
                        Text(actionLabel(for: action))
                            .font(VoyagerDS.Typography.smallButton)
                    }
                }
                .foregroundColor(actionForegroundColor(for: action))
                .padding(.horizontal, isHovering ? 8 : 6)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(VoyagerDS.Surface.chipItemBackground(for: colorScheme).opacity(isHovering ? 0.95 : 0.7)),
                )
                .overlay(
                    Capsule()
                        .stroke(
                            VoyagerDS.Surface.chipItemBorder(for: colorScheme).opacity(isHovering ? 1 : 0.65),
                            lineWidth: 0.5,
                        ),
                )
            },
        )
        .buttonStyle(.borderless)
        .help(actionHelp(for: action))
        .accessibilityLabel(actionLabel(for: action))
        .accessibilityHint(actionHelp(for: action))
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
        case .inherited:
            .medium
        case .none:
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
        case .excluded:
            .red
        case .none:
            .secondary
        }
    }

    private var stateBadgeBackground: Color {
        switch row.visualState {
        case .included:
            Color.accentColor.opacity(0.14)
        case .excluded:
            Color.red.opacity(0.12)
        case .none:
            VoyagerDS.Surface.chipItemBackground(for: colorScheme)
        }
    }

    private var sourceBadgeHelp: String? {
        switch row.ruleSource {
        case .direct:
            nil
        case let .inherited(sourcePath):
            "Inherited from \(sourcePath)"
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
                "Remove direct rule"
            case .exception:
                "Restore scope"
            case .candidate, .root:
                "Remove direct rule"
            }
        }
    }

    private func actionHelp(for action: ComposerScopeTreeRowAvailableAction) -> String {
        switch action {
        case .include:
            "Include this folder in the scope"
        case .exclude:
            "Exclude this folder from the scope"
        case .clearDirectRule:
            switch row.kind {
            case .base:
                "Remove the direct include rule for this folder"
            case .exception:
                "Restore the previously excluded scope"
            case .candidate, .root:
                "Remove the direct rule for this folder"
            }
        }
    }

    private func actionForegroundColor(for action: ComposerScopeTreeRowAvailableAction) -> Color {
        switch action {
        case .include:
            .accentColor
        case .exclude:
            .red
        case .clearDirectRule:
            switch row.kind {
            case .exception:
                .accentColor
            case .base, .candidate, .root:
                .red
            }
        }
    }

    private func statusBadge(
        text: String,
        tint: Color,
        background: Color,
        helpText: String? = nil,
    ) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(background),
            )
            .helpIfPresent(helpText)
            .accessibilityLabel(helpText ?? text)
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

    @ViewBuilder
    func helpIfPresent(_ helpText: String?) -> some View {
        if let helpText {
            help(helpText)
        } else {
            self
        }
    }
}
