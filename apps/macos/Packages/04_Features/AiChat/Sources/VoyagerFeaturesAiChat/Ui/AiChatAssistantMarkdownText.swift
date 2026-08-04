import Foundation
import SwiftUI
import VoyagerShared

struct AiChatAssistantMarkdownText: View {
    @Environment(\.colorScheme)
    private var colorScheme
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [AssistantMarkdownBlock] {
        AssistantMarkdownBlock.parse(content)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inlineMarkdown(text))
                .font(.system(size: headingSize(for: level), weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(VoyagerDS.Typography.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .font(.system(size: 13, weight: .semibold))
                Text(inlineMarkdown(text))
                    .font(VoyagerDS.Typography.body)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(number).")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(inlineMarkdown(text))
                    .font(VoyagerDS.Typography.body)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .code(text):
            Text(text)
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
