import SwiftUI

struct ScopeChangeFeedbackBannerView: View {
    let display: ComposerScopeChangeFeedbackDisplay
    let colorScheme: ColorScheme
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: display.isFailure ? "exclamationmark.triangle.fill" : display
                .isDelayed ? "clock.arrow.circlepath" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(display.isFailure ? VoyagerDS.BrandPrimaryColor.c500 : .secondary)

            HStack(spacing: 6) {
                Text(display.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VoyagerDS.SystemColor.label)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(display.phaseLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if display.showsUndo {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityLabel("Undo latest scope change")
                }

                if display.showsRedo {
                    Button("Redo", action: onRedo)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityLabel("Redo latest scope change")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(VoyagerDS.Surface.popoverBackground(for: colorScheme)),
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(VoyagerDS.Surface.popoverBorder, lineWidth: 1),
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(display.accessibilityLabel ?? "Scope change feedback")
        .help(display.accessibilityLabel ?? "\(display.title). \(display.message)")
    }
}
