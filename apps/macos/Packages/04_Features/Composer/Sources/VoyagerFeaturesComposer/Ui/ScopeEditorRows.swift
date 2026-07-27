import AppKit
import SwiftUI
import VoyagerShared

enum ScopeEditorCandidateRowActionKind: Equatable {
    case include
    case replace
    case exclude

    var symbolName: String {
        switch self {
        case .include, .replace:
            "checkmark"
        case .exclude:
            "minus"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .include:
            "Include scope"
        case .replace:
            "Replace current scope"
        case .exclude:
            "Exclude scope"
        }
    }

    var usesDestructiveStyling: Bool {
        self == .exclude
    }
}

struct IncludeSubfoldersRow: View {
    let includeSubfolders: Bool
    let onTap: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onTap(includeSubfolders)
            } label: {
                HStack(spacing: 10) {
                    Text("Include subfolders")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: includeSubfolders ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(includeSubfolders ? .accentColor : .secondary)
                        .accessibilityLabel(includeSubfolders ? "Included" : "Not included")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            VoyagerDS.SystemColor.separator
                .frame(height: 1)
        }
    }
}

struct CurrentScopeRow: View {
    let currentItem: ComposerScopeEditorCurrentItem
    let colorScheme: ColorScheme
    let displayName: String
    let removeAccessibilityIdentifier: String?
    let removeAccessibilityLabel: String
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.system(size: 13, weight: currentItem.isEditingTarget ? .semibold : .regular))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let exceptionSummary = currentItem.exceptionSummaryText {
                            statusBadge(text: exceptionSummary)
                        }

                        if currentItem.isEditingTarget {
                            statusBadge(text: "Editing", subtle: true)
                        }
                    }

                    Text(currentItem.base.path)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            removeButton()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .fill(VoyagerDS.Surface.chipItemBackground(for: colorScheme)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .stroke(VoyagerDS.Surface.chipItemBorder(for: colorScheme), lineWidth: 0.5),
        )
    }

    @ViewBuilder
    private func removeButton() -> some View {
        let button = Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(removeAccessibilityLabel)
        .help(removeAccessibilityLabel)

        if let removeAccessibilityIdentifier {
            button.accessibilityIdentifier(removeAccessibilityIdentifier)
        } else {
            button
        }
    }

    private func statusBadge(text: String, subtle: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(
                        subtle
                            ? VoyagerDS.Surface.chipItemBackground(for: colorScheme)
                            : VoyagerDS.Interaction.hoverFill(for: colorScheme),
                    ),
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct ExceptionRow: View {
    let exception: ComposerScopeEditorExceptionItem
    let colorScheme: ColorScheme
    let displayName: String
    let restoreAccessibilityIdentifier: String?
    let restoreAccessibilityLabel: String
    let onRestore: () -> Void

    private var text: String {
        displayName
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Excluded")
                    Text(text)
                        .font(VoyagerDS.Typography.caption)
                        .foregroundColor(.primary)
                    Text("Excluded")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text(exception.path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            restoreButton()
        }
        .padding(.leading, 22)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .fill(VoyagerDS.Surface.chipItemBackground(for: colorScheme).opacity(0.5)),
        )
    }

    @ViewBuilder
    private func restoreButton() -> some View {
        let button = Button(action: onRestore) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 9, weight: .medium))
                Text("Restore")
                    .font(VoyagerDS.Typography.chip)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(restoreAccessibilityLabel)
        .help(restoreAccessibilityLabel)

        if let restoreAccessibilityIdentifier {
            button.accessibilityIdentifier(restoreAccessibilityIdentifier)
        } else {
            button
        }
    }
}

struct AddableCandidateRow: View {
    let candidate: ComposerScopeEditorCandidateItem
    let isHovering: Bool
    let colorScheme: ColorScheme
    let applicationsIcon: NSImage?
    let actionKind: ScopeEditorCandidateRowActionKind
    let accessibilityIdentifier: String?

    var body: some View {
        HStack(spacing: 8) {
            if candidate.path == "/Applications", let applicationsIcon {
                Image(nsImage: applicationsIcon)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: candidate.iconName)
                    .font(VoyagerDS.Typography.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(VoyagerDS.Typography.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let secondary = candidate.secondaryText {
                    Text(secondary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            actionAffordance
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .fill(isHovering ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear),
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(actionKind.accessibilityLabel): \(candidate.name)")
        .help(actionKind.accessibilityLabel)
        .ifLetAccessibilityIdentifier(accessibilityIdentifier)
    }

    private var actionAffordance: some View {
        Image(systemName: actionKind.symbolName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(actionKind.usesDestructiveStyling ? .secondary : .accentColor)
            .frame(
                width: ComposerUIMetrics.compactControlHeight,
                height: ComposerUIMetrics.compactControlHeight,
            )
            .background(
                Circle()
                    .fill(actionKind.usesDestructiveStyling ? Color.secondary.opacity(0.12) : Color.accentColor
                        .opacity(0.14)),
            )
            .accessibilityHidden(true)
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

struct ScopeEditorSummaryRow: View {
    let summary: ComposerScopeSummary
    let ruleDescription: String
    let includeSubfolders: Bool?
    let onToggleIncludeSubfolders: ((Bool) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "scope")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18)

                HStack(spacing: 6) {
                    Text(summary.primaryText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    if let badge = summary.badgeText {
                        Text(badge)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let includeSubfolders {
                    includeSubfoldersButton(isOn: includeSubfolders)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summary.accessibilityText)
            .help(summary.accessibilityText)

            VoyagerDS.SystemColor.separator
                .frame(height: 1)
        }
    }

    private func includeSubfoldersButton(isOn: Bool) -> some View {
        Button {
            onToggleIncludeSubfolders?(isOn)
        } label: {
            HStack(spacing: 4) {
                Text(isOn ? "Subfolders On" : "Subfolders Off")
                    .font(VoyagerDS.Typography.smallButton)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isOn ? .accentColor : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isOn ? "Disable include subfolders" : "Enable include subfolders")
        .help(isOn ? "Include subfolders is on" : "Include subfolders is off")
    }
}

struct ScopeEditorParentContextRow: View {
    let displayName: String
    let path: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "folder")
                .font(VoyagerDS.Typography.chip)
                .foregroundColor(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("Browsing \(displayName)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .fill(Color.secondary.opacity(0.08)),
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Browsing \(displayName), \(path)")
        .help(path)
    }
}
