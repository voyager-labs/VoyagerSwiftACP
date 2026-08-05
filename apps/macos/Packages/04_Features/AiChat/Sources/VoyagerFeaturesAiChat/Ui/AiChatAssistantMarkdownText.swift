import Foundation
import SwiftUI
import VoyagerShared

struct AiChatAssistantMarkdownText: View {
    @Environment(\.colorScheme)
    private var colorScheme
    let content: String
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { blockIndex, block in
                blockView(block, blockIndex: blockIndex)
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
    }

    private var blocks: [AssistantMarkdownBlock] {
        AssistantMarkdownBlock.parse(content)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantMarkdownBlock, blockIndex: Int) -> some View {
        switch block {
        case let .heading(level, text):
            Text(highlightedInlineMarkdown(text, blockIndex: blockIndex))
                .font(.system(size: headingSize(for: level), weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .paragraph(text):
            Text(highlightedInlineMarkdown(text, blockIndex: blockIndex))
                .font(VoyagerDS.Typography.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .font(.system(size: 13, weight: .semibold))
                Text(highlightedInlineMarkdown(text, blockIndex: blockIndex))
                    .font(VoyagerDS.Typography.body)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(number).")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(highlightedInlineMarkdown(text, blockIndex: blockIndex))
                    .font(VoyagerDS.Typography.body)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .code(text):
            Text(highlightedCode(text, blockIndex: blockIndex))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    VoyagerDS.Surface.inputBackground(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous),
                )
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: 17
        case 2: 15
        default: 14
        }
    }

    private func highlightedInlineMarkdown(_ text: String, blockIndex: Int) -> AttributedString {
        AiChatRenderedTextHighlighter.highlight(
            inlineMarkdown(text),
            matchOffsets: searchPresentation.matchOffsets(
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
            ),
            currentMatchOffsets: currentSearchMatchOffsets(blockIndex: blockIndex),
        )
    }

    private func highlightedCode(_ text: String, blockIndex: Int) -> AttributedString {
        AiChatRenderedTextHighlighter.highlight(
            AttributedString(text),
            matchOffsets: searchPresentation.matchOffsets(
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
            ),
            currentMatchOffsets: currentSearchMatchOffsets(blockIndex: blockIndex),
        )
    }

    private func currentSearchMatchOffsets(blockIndex: Int) -> Range<Int>? {
        guard currentSearchMatch?.transcriptRow == transcriptRow,
              currentSearchMatch?.blockIndex == blockIndex
        else { return nil }
        return currentSearchMatch?.characterOffsets
    }

    private func isCurrentSearchBlock(_ blockIndex: Int) -> Bool {
        currentSearchMatch?.transcriptRow == transcriptRow
            && currentSearchMatch?.blockIndex == blockIndex
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let markdown = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
            ),
        ) {
            return markdown
        }
        return AttributedString(text)
    }
}
