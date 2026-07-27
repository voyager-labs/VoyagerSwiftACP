import AppKit
import SwiftUI
import VoyagerShared

struct ScopeEditorSummaryRow: View {
    let summary: ComposerScopeSummary
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
