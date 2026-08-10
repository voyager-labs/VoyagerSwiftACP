import AppKit
import SwiftUI
import VoyagerEntitiesAi
import VoyagerShared

struct AiChatTimestampTooltipGeometry: Equatable {
    enum VerticalPlacement: Equatable { case above, below }
    let frame: CGRect
    let verticalPlacement: VerticalPlacement

    static func resolve(
        viewportBounds: CGRect,
        messageBounds: CGRect,
        clockBounds: CGRect,
        preferredSize: CGSize,
    ) -> Self {
        let edgeInset: CGFloat = 4
        let spacing: CGFloat = 4
        let availableSize = CGSize(
            width: max(0, viewportBounds.width - edgeInset * 2),
            height: max(0, viewportBounds.height - edgeInset * 2),
        )
        let size = CGSize(
            width: min(preferredSize.width, availableSize.width),
            height: min(preferredSize.height, availableSize.height),
        )
        let minimumX = viewportBounds.minX + edgeInset
        let maximumX = max(minimumX, viewportBounds.maxX - edgeInset - size.width)
        let originX = min(max(clockBounds.midX - size.width / 2, minimumX), maximumX)
        let minimumY = viewportBounds.minY + edgeInset
        let maximumY = max(minimumY, viewportBounds.maxY - edgeInset - size.height)
        let aboveY = messageBounds.minY - spacing - size.height
        let belowY = messageBounds.maxY + spacing
        let aboveFits = aboveY >= minimumY
        let belowFits = belowY <= maximumY
        let availableAbove = max(0, messageBounds.minY - spacing - minimumY)
        let availableBelow = max(0, viewportBounds.maxY - edgeInset - messageBounds.maxY - spacing)
        let verticalPlacement: VerticalPlacement = if aboveFits {
            .above
        } else if belowFits {
            .below
        } else {
            availableAbove >= availableBelow ? .above : .below
        }
        let preferredY = verticalPlacement == .above ? aboveY : belowY
        let originY = min(max(preferredY, minimumY), maximumY)
        return Self(
            frame: CGRect(origin: CGPoint(x: originX, y: originY), size: size),
            verticalPlacement: verticalPlacement,
        )
    }
}

struct AiChatAssistantMetadataPanelGeometry: Equatable {
    enum VerticalPlacement: Equatable { case above, below }
    let frame: CGRect
    let visibleBodyBounds: CGRect
    let verticalPlacement: VerticalPlacement

    static func resolve(
        viewportBounds: CGRect,
        bodyBounds: CGRect,
        preferredSize: CGSize,
    ) -> Self? {
        let edgeInset: CGFloat = 4
        let spacing: CGFloat = 4
        let visibleBodyBounds = bodyBounds.intersection(viewportBounds)
        let finiteGeometry = [
            visibleBodyBounds.minX, visibleBodyBounds.minY,
            visibleBodyBounds.width, visibleBodyBounds.height,
            preferredSize.width, preferredSize.height,
        ].allSatisfy(\.isFinite)
        guard finiteGeometry, !visibleBodyBounds.isNull, !visibleBodyBounds.isEmpty else { return nil }
        let availableWidth = viewportBounds.width - edgeInset * 2
        let availableHeight = viewportBounds.height - edgeInset * 2
        guard availableWidth > 0, availableHeight > 0 else { return nil }
        let size = CGSize(
            width: min(preferredSize.width, availableWidth),
            height: min(preferredSize.height, availableHeight),
        )
        let minimumX = viewportBounds.minX + edgeInset
        let maximumX = viewportBounds.maxX - edgeInset - size.width
        let originX = min(max(visibleBodyBounds.minX, minimumX), max(minimumX, maximumX))
        let minimumY = viewportBounds.minY + edgeInset
        let maximumY = viewportBounds.maxY - edgeInset - size.height
        let aboveY = visibleBodyBounds.minY - spacing - size.height
        let belowY = visibleBodyBounds.maxY + spacing
        let aboveFits = aboveY >= minimumY
        let belowFits = belowY <= maximumY
        let availableAbove = max(0, visibleBodyBounds.minY - spacing - minimumY)
        let availableBelow = max(0, viewportBounds.maxY - edgeInset - visibleBodyBounds.maxY - spacing)
        let verticalPlacement: VerticalPlacement = if aboveFits {
            .above
        } else if belowFits {
            .below
        } else {
            availableAbove >= availableBelow ? .above : .below
        }
        let preferredY = verticalPlacement == .above ? aboveY : belowY
        let originY = min(max(preferredY, minimumY), max(minimumY, maximumY))
        return Self(
            frame: CGRect(origin: CGPoint(x: originX, y: originY), size: size),
            visibleBodyBounds: visibleBodyBounds,
            verticalPlacement: verticalPlacement,
        )
    }
}

enum AiChatTimestampTooltipTrigger: Int {
    case focus
    case hover

    func outranks(_ current: Self?) -> Bool {
        current.map { rawValue > $0.rawValue } ?? true
    }
}

struct AiChatTimestampTooltipSizing: Equatable {
    static func resolve(label: String, availableWidth: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let horizontalPadding = AiChatTimestampAffordancePresentation.tooltipHorizontalPadding * 2
        let verticalPadding = AiChatTimestampAffordancePresentation.tooltipVerticalPadding * 2
        let availablePanelWidth = max(1, availableWidth - 8)
        let maximumWidth = min(
            AiChatTimestampAffordancePresentation.tooltipMaximumWidth,
            availablePanelWidth,
        )
        let intrinsicTextWidth = ceil((label as NSString).size(withAttributes: attributes).width)
        let width = min(intrinsicTextWidth + horizontalPadding, maximumWidth)
        let contentWidth = max(1, width - horizontalPadding)
        let textBounds = (label as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
        )
        return CGSize(
            width: width,
            height: max(
                AiChatTimestampAffordancePresentation.controlSize,
                ceil(textBounds.height) + verticalPadding,
            ),
        )
    }
}

struct AiChatTimestampTooltipAnchor {
    let label: String
    let trigger: AiChatTimestampTooltipTrigger
    let clockBounds: Anchor<CGRect>
    var messageBounds: Anchor<CGRect>?
}

struct AiChatTimestampTooltipAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: AiChatTimestampTooltipAnchor? = nil
    static func reduce(value: inout AiChatTimestampTooltipAnchor?, nextValue: () -> AiChatTimestampTooltipAnchor?) {
        guard let candidate = nextValue() else { return }
        if candidate.trigger.outranks(value?.trigger) {
            value = candidate
        }
    }
}

struct AiChatAssistantMetadataAnchor {
    let requestID: AiChatRequestID
    let label: String
    let bodyBounds: Anchor<CGRect>
}

struct AiChatAssistantMetadataAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [AiChatRequestID: AiChatAssistantMetadataAnchor] = [:]

    static func reduce(
        value: inout [AiChatRequestID: AiChatAssistantMetadataAnchor],
        nextValue: () -> [AiChatRequestID: AiChatAssistantMetadataAnchor],
    ) {
        value.merge(nextValue()) { _, candidate in candidate }
    }
}

struct AiChatAssistantMetadataPanelSizing: Equatable {
    static func resolve(label: String, availableWidth: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let horizontalPadding = AiChatTimestampAffordancePresentation.tooltipHorizontalPadding * 2
        let verticalPadding = AiChatTimestampAffordancePresentation.tooltipVerticalPadding * 2
        let maximumWidth = min(
            AiChatTimestampAffordancePresentation.tooltipMaximumWidth,
            max(1, availableWidth - 8),
        )
        let textWidth = ceil((label as NSString).size(withAttributes: attributes).width)
        let width = min(textWidth + horizontalPadding, maximumWidth)
        let contentWidth = max(1, width - horizontalPadding)
        let textBounds = (label as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
        )
        return CGSize(width: width, height: ceil(textBounds.height) + verticalPadding)
    }
}

struct AiChatTimestampTooltip: View {
    @Environment(\.colorScheme)
    private var colorScheme
    let label: String
    let size: CGSize

    var body: some View {
        Text(label)
            .font(.system(size: NSFont.smallSystemFontSize))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, AiChatTimestampAffordancePresentation.tooltipHorizontalPadding)
            .padding(.vertical, AiChatTimestampAffordancePresentation.tooltipVerticalPadding)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .background(
                VoyagerDS.Surface.popoverBackground(for: colorScheme),
                in: RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous),
            )
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                    .strokeBorder(VoyagerDS.Surface.popoverBorder, lineWidth: 1),
            )
            .shadow(
                color: VoyagerDS.Shadow.popoverColor(for: colorScheme),
                radius: VoyagerDS.Shadow.popoverRadius,
                y: VoyagerDS.Shadow.popoverYOffset,
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct AiChatAssistantMetadataPanel: View {
    @Environment(\.colorScheme)
    private var colorScheme
    let label: String
    let size: CGSize

    var body: some View {
        Text(label)
            .font(.system(size: NSFont.smallSystemFontSize))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, AiChatTimestampAffordancePresentation.tooltipHorizontalPadding)
            .padding(.vertical, AiChatTimestampAffordancePresentation.tooltipVerticalPadding)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .background(
                VoyagerDS.Surface.popoverBackground(for: colorScheme),
                in: RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous),
            )
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                    .strokeBorder(VoyagerDS.Surface.popoverBorder, lineWidth: 1),
            )
            .shadow(
                color: VoyagerDS.Shadow.popoverColor(for: colorScheme),
                radius: VoyagerDS.Shadow.popoverRadius,
                y: VoyagerDS.Shadow.popoverYOffset,
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
