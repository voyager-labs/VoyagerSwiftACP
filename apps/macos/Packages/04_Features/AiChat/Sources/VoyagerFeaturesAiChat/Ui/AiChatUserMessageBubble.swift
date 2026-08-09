import AppKit
import SwiftUI
import VoyagerShared

struct AiChatUserMessageBubble: View {
    let blockID: AiChatMarkdownDocument.BlockID
    let attributedText: NSAttributedString
    let rawMessageContent: String
    let renderSession: AiChatAssistantMarkdownRenderSession
    let transcriptRow: AiChatTranscriptRowDiscriminator

    @Environment(\.colorScheme)
    private var colorScheme
    @StateObject private var copyInteraction = AiChatCopyInteractionModel()

    private var contextMenuActions: [AiChatOutputContextMenuAction] {
        [
            AiChatOutputContextMenuAction(
                title: "Copy Entire Message",
                isEnabled: !rawMessageContent.isEmpty,
                perform: {
                    copyInteraction.copyRow(
                        format: .plainText,
                        rawMarkdown: rawMessageContent,
                        plainText: rawMessageContent,
                    )
                },
            ),
        ]
    }

    private func measureNaturalTextWidth() -> CGFloat {
        guard !attributedText.string.isEmpty else { return 0 }
        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 1_000_000, height: CGFloat.greatestFiniteMagnitude),
        )
        textContainer.widthTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).width)
    }

    var body: some View {
        AiChatSelectableOutputText(
            blockID: blockID,
            attributedText: attributedText,
            renderSession: renderSession,
            transcriptRow: transcriptRow,
            sizingMode: .fitsContent,
            contextMenuActions: contextMenuActions,
        )
        .frame(maxWidth: max(measureNaturalTextWidth(), 0))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.userMessageBubble, style: .continuous)
                .fill(VoyagerDS.Surface.userMessageBubbleBackground(for: colorScheme)),
        )
        .overlay(alignment: .topTrailing) {
            if let feedback = copyInteraction.feedback {
                Text(feedback.visibleLabel)
                    .font(VoyagerDS.Typography.caption)
                    .foregroundStyle(
                        feedback == .copied
                            ? VoyagerDS.SystemColor.secondaryLabel
                            : Color.red,
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        VoyagerDS.SystemColor.controlBackground,
                        in: Capsule(style: .continuous),
                    )
                    .accessibilityLabel(feedback.accessibilityLabel)
            }
        }
    }
}
