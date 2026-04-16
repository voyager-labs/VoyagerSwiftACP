import SwiftUI
import VoyagerShared

struct ComposerFeedbackToastView: View {
    let feedback: ComposerTransientFeedback

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VoyagerDS.BrandPrimaryColor.c500)

            Text(feedback.message)
                .font(VoyagerDS.Typography.caption)
                .foregroundStyle(VoyagerDS.SystemColor.label)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("composer.feedback.message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard, style: .continuous)
                .fill(VoyagerDS.Surface.popoverBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard, style: .continuous)
                        .stroke(VoyagerDS.Surface.popoverBorder, lineWidth: 1),
                ),
        )
        .shadow(
            color: VoyagerDS.Shadow.popoverColor(for: colorScheme),
            radius: VoyagerDS.Shadow.popoverRadius,
            x: 0,
            y: VoyagerDS.Shadow.popoverYOffset,
        )
        .accessibilityIdentifier("composer.feedback.toast")
        .fixedSize(horizontal: false, vertical: true)
    }
}
