import SwiftUI
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

struct FileManagerHistorySwipeProgressHUD: View {
    static let circleDiameter: CGFloat = 44
    static let armedScale: CGFloat = 1.18
    static let armedAnimationDuration = 0.12
    static let terminalAnimationDuration = 0.14

    let progress: EntryHistorySwipeProgress
    let reduceMotion: Bool

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            if progress.direction == .back {
                historySwipeVisual.offset(x: horizontalOffset)
                Spacer()
            } else {
                Spacer()
                historySwipeVisual.offset(x: horizontalOffset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var historySwipeVisual: some View {
        ZStack {
            Circle()
                .fill(VoyagerDS.Surface.overlayBackground(for: colorScheme))
                .overlay {
                    Circle()
                        .strokeBorder(VoyagerDS.Surface.overlayBorder, lineWidth: 1)
                }
                .shadow(
                    color: VoyagerDS.Shadow.overlayColor(for: colorScheme),
                    radius: VoyagerDS.Shadow.overlayRadius(for: colorScheme),
                    y: VoyagerDS.Shadow.overlayYOffset(for: colorScheme),
                )

            Image(systemName: progress.direction == .back ? "chevron.left" : "chevron.right")
                .font(VoyagerDS.Typography.title)
                .foregroundStyle(
                    progress.isArmed ? Color.accentColor : VoyagerDS.SystemColor.secondaryLabel,
                )
                .accessibilityHidden(true)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeOut(duration: Self.armedAnimationDuration),
                    value: progress.isArmed,
                )
        }
        .frame(width: Self.circleDiameter, height: Self.circleDiameter)
        .opacity(progress.progress == 0 ? 0 : 1)
        .scaleEffect(reduceMotion ? 1 : progress.isArmed ? Self.armedScale : 1)
        .animation(
            reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.78),
            value: progress.isArmed,
        )
    }

    private var horizontalOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        let distance = (1 - progress.progress) * Self.circleDiameter
        return progress.direction == .back ? -distance : distance
    }
}
