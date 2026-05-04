import SwiftUI

struct ScopeChangeFeedbackBannerView: View {
    let display: ComposerScopeChangeFeedbackDisplay
    let colorScheme: ColorScheme
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: display.isFailure ? "exclamationmark.triangle.fill" : display
                .isDelayed ? "clock.arrow.circlepath" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(display.isFailure ? VoyagerDS.BrandPrimaryColor.c500 : .secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(display.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VoyagerDS.SystemColor.label)
                    .fixedSize(horizontal: false, vertical: true)

                Text(display.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(display.phaseLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if display.showsUndo {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if display.showsRedo {
                    Button("Redo", action: onRedo)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(VoyagerDS.Surface.popoverBackground(for: colorScheme)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(VoyagerDS.Surface.popoverBorder, lineWidth: 1),
        )
    }
}
