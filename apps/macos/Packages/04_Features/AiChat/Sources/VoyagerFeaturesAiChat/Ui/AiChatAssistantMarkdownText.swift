import Foundation
import SwiftUI
import VoyagerShared

struct AiChatAssistantMarkdownText: View {
    let content: String
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
    let renderSession: AiChatAssistantMarkdownRenderSession

    @StateObject private var copyInteraction = AiChatCopyInteractionModel()

    var body: some View {
        let rendered = renderSession.render(content: content, transcriptRow: transcriptRow)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rendered.blocks.enumerated()), id: \.element.presentationID) { blockIndex, block in
                AiChatAssistantMarkdownBlockView(
                    renderedBlock: block,
                    transcriptRow: transcriptRow,
                    blockIndex: blockIndex,
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                    renderSession: renderSession,
                    copyInteraction: copyInteraction,
                    rawMarkdown: content,
                    plainText: rendered.document.plainText,
                )
                .overlay {
                    AiChatTranscriptMatchAnchors(
                        descriptors: searchPresentation.matchDescriptors(
                            transcriptRow: transcriptRow,
                            blockIndex: blockIndex,
                        ),
                    )
                }
                .accessibilityValue(
                    isCurrentSearchBlock(blockIndex) ? "Current search result" : "",
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
        .background {
            if copyInteraction.isRowSelected {
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                    .fill(VoyagerDS.SystemColor.controlBackground.opacity(0.7))
            }
        }
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

    private func isCurrentSearchBlock(_ blockIndex: Int) -> Bool {
        currentSearchMatch?.transcriptRow == transcriptRow
            && currentSearchMatch?.blockIndex == blockIndex
    }
}
