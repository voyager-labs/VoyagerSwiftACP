import SwiftUI
import VoyagerShared

struct AiChatAssistantMarkdownBlockView: View {
    let renderedBlock: AiChatAssistantMarkdownRenderedBlock
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let blockIndex: Int
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
    let renderSession: AiChatAssistantMarkdownRenderSession
    @ObservedObject var copyInteraction: AiChatCopyInteractionModel
    let rawMarkdown: String
    let plainText: String

    var body: some View {
        switch renderedBlock.block.kind {
        case let .heading(level):
            selectableText
                .font(level == 1 ? VoyagerDS.Typography.title : VoyagerDS.Typography.body.bold())
        case .paragraph:
            selectableText
        case .bullet:
            listRow(marker: "•")
        case let .numbered(number):
            listRow(marker: "\(number).")
        case .blockquote:
            HStack(spacing: 8) {
                Rectangle()
                    .fill(VoyagerDS.SystemColor.separator)
                    .frame(width: 2)
                selectableText
            }
        case .table:
            tableView
        case .code:
            AiChatAssistantCodeBlockView(
                renderedBlock: renderedBlock,
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
                searchPresentation: searchPresentation,
                currentSearchMatch: currentSearchMatch,
                renderSession: renderSession,
                copyInteraction: copyInteraction,
                rawMarkdown: rawMarkdown,
                plainText: plainText,
            )
        }
    }

    private var selectableText: some View {
        AiChatSelectableOutputText(
            blockID: renderedBlock.presentationID,
            attributedText: attributedText,
            renderSession: renderSession,
            transcriptRow: transcriptRow,
            contextMenuActions: rowContextMenuActions,
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedText: NSAttributedString {
        AiChatAssistantMarkdownAttributedText.make(
            block: renderedBlock.block,
            syntaxRuns: [],
            matchOffsets: matchOffsets,
            currentMatchOffsets: currentMatchOffsets,
        )
    }

    private func listRow(marker: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(marker)
                .font(VoyagerDS.Typography.body.bold())
                .foregroundStyle(VoyagerDS.SystemColor.secondaryLabel)
            selectableText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var tableView: some View {
        if let table = renderedBlock.block.table {
            ViewThatFits(in: .horizontal) {
                tableGrid(table)
                ScrollView(.horizontal) {
                    tableGrid(table)
                }
                .scrollIndicators(.visible)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("표")
            .accessibilityValue(
                AiChatMarkdownAccessibility.tableValue(
                    rowCount: table.cells.count,
                    columnCount: table.alignments.count,
                ),
            )
        }
    }

    private func tableGrid(_ table: AiChatMarkdownDocument.TableMetadata) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(table.cells.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, cell in
                        tableCell(
                            cell,
                            rowIndex: rowIndex,
                            columnIndex: columnIndex,
                            alignment: table.alignments[columnIndex],
                        )
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .overlay {
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                .stroke(VoyagerDS.SystemColor.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous))
    }

    private func tableCell(
        _ cell: AiChatMarkdownDocument.TableCell,
        rowIndex: Int,
        columnIndex: Int,
        alignment: AiChatMarkdownDocument.TableAlignment,
    ) -> some View {
        let cellOffsets = tableCellOffsets(rowIndex: rowIndex, columnIndex: columnIndex)
        let attributed = AiChatAssistantMarkdownAttributedText.make(
            text: cell.text,
            inlineIntents: cell.inlineIntents,
            matchOffsets: localized(matchOffsets, to: cellOffsets),
            currentMatchOffsets: localized(currentMatchOffsets, to: cellOffsets),
        )
        let cellID = AiChatMarkdownDocument.BlockID(
            rawValue: "\(renderedBlock.presentationID.rawValue)-cell-\(rowIndex)-\(columnIndex)",
        )
        renderSession.registerSelectionProjection(
            presentationID: cellID,
            plainText: cell.text,
            searchText: cell.text,
            transcriptRow: transcriptRow,
            blockIndex: blockIndex,
        )
        return AiChatSelectableOutputText(
            blockID: cellID,
            attributedText: attributed,
            renderSession: renderSession,
            transcriptRow: transcriptRow,
            contextMenuActions: rowContextMenuActions,
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minWidth: 72, alignment: alignment.swiftUIAlignment)
        .background(rowIndex == 0 ? VoyagerDS.SystemColor.controlBackground : .clear)
        .overlay(alignment: .trailing) {
            if columnIndex + 1 < renderedBlock.block.table?.alignments.count ?? 0 {
                Rectangle()
                    .fill(VoyagerDS.SystemColor.separator)
                    .frame(width: 1)
            }
        }
    }

    private var rowContextMenuActions: [AiChatOutputContextMenuAction] {
        makeRowContextMenuActions(
            interaction: copyInteraction,
            rawMarkdown: rawMarkdown,
            plainText: plainText,
        )
    }

    private var matchOffsets: [Range<Int>] {
        searchPresentation.matchOffsets(transcriptRow: transcriptRow, blockIndex: blockIndex)
    }

    private var currentMatchOffsets: Range<Int>? {
        guard currentSearchMatch?.transcriptRow == transcriptRow,
              currentSearchMatch?.blockIndex == blockIndex
        else { return nil }
        return currentSearchMatch?.characterOffsets
    }

    private func tableCellOffsets(rowIndex: Int, columnIndex: Int) -> Range<Int> {
        guard let table = renderedBlock.block.table else { return 0 ..< 0 }
        var cursor = 0
        for currentRow in table.cells.indices {
            for currentColumn in table.cells[currentRow].indices {
                let cell = table.cells[currentRow][currentColumn]
                let range = cursor ..< cursor + cell.text.count
                if currentRow == rowIndex, currentColumn == columnIndex { return range }
                cursor = range.upperBound + 1
            }
        }
        return 0 ..< 0
    }

    private func localized(_ offsets: [Range<Int>], to cell: Range<Int>) -> [Range<Int>] {
        offsets.compactMap { localized($0, to: cell) }
    }

    private func localized(_ offsets: Range<Int>?, to cell: Range<Int>) -> Range<Int>? {
        guard let offsets else { return nil }
        let lower = max(offsets.lowerBound, cell.lowerBound)
        let upper = min(offsets.upperBound, cell.upperBound)
        guard lower < upper else { return nil }
        return lower - cell.lowerBound ..< upper - cell.lowerBound
    }
}

private struct AiChatAssistantCodeBlockView: View {
    let renderedBlock: AiChatAssistantMarkdownRenderedBlock
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let blockIndex: Int
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
    let renderSession: AiChatAssistantMarkdownRenderSession
    @ObservedObject var copyInteraction: AiChatCopyInteractionModel
    let rawMarkdown: String
    let plainText: String

    @Environment(\.colorScheme)
    private var colorScheme
    @State private var syntaxRuns: [AiChatSyntaxHighlightingClient.Run] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(renderedBlock.block.code?.originalLanguage ?? "Code")
                    .font(VoyagerDS.Typography.caption)
                    .foregroundStyle(VoyagerDS.SystemColor.secondaryLabel)
                    .accessibilityHidden(true)
            }
            AiChatSelectableOutputText(
                blockID: renderedBlock.presentationID,
                attributedText: attributedText,
                renderSession: renderSession,
                transcriptRow: transcriptRow,
                allowsHorizontalOverflow: true,
                sizingMode: .fitsContent,
                accessibilityLabel: AiChatMarkdownAccessibility.codeValue(
                    originalLanguage: renderedBlock.block.code?.originalLanguage,
                ),
                accessibilityValue: renderedBlock.block.code?.payload,
                contextMenuActions: codeContextMenuActions,
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(
            VoyagerDS.Surface.inputBackground(for: colorScheme),
            in: RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous),
        )
        .overlay {
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                .strokeBorder(VoyagerDS.Surface.inputBorder(for: colorScheme), lineWidth: 1)
        }
        .task(id: highlightTaskID) {
            syntaxRuns = []
            let expectedSource = renderedBlock.block.code?.payload
            guard let result = await renderSession.highlight(
                renderedBlock,
                transcriptRow: transcriptRow,
                appearance: colorScheme == .dark ? .dark : .light,
                typographyVersion: 1,
                generation: UInt64(renderedBlock.block.projections.rendered.utf8.count),
            ), result.isEligibleForDisplay, result.source == expectedSource
            else { return }
            syntaxRuns = result.runs
        }
    }

    private var attributedText: NSAttributedString {
        AiChatAssistantMarkdownAttributedText.make(
            block: renderedBlock.block,
            syntaxRuns: syntaxRuns,
            matchOffsets: searchPresentation.matchOffsets(
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
            ),
            currentMatchOffsets: currentMatchOffsets,
        )
    }

    private var codeContextMenuActions: [AiChatOutputContextMenuAction] {
        let rowActions = makeRowContextMenuActions(
            interaction: copyInteraction,
            rawMarkdown: rawMarkdown,
            plainText: plainText,
        )
        guard let payload = renderedBlock.block.code?.payload else { return rowActions }
        return [
            AiChatOutputContextMenuAction(
                title: "Copy Code",
                isEnabled: true,
                perform: { copyInteraction.copyCode(payload) },
            ),
        ] + rowActions
    }

    private var currentMatchOffsets: Range<Int>? {
        guard currentSearchMatch?.transcriptRow == transcriptRow,
              currentSearchMatch?.blockIndex == blockIndex
        else { return nil }
        return currentSearchMatch?.characterOffsets
    }

    private var highlightTaskID: String {
        "\(renderedBlock.presentationID.rawValue)-\(colorScheme)-\(renderedBlock.block.projections.rendered)"
    }
}

@MainActor
private func makeRowContextMenuActions(
    interaction: AiChatCopyInteractionModel,
    rawMarkdown: String,
    plainText: String,
) -> [AiChatOutputContextMenuAction] {
    [
        AiChatOutputContextMenuAction(
            title: "Copy Entire Message as Markdown",
            isEnabled: !rawMarkdown.isEmpty,
            perform: {
                interaction.copyRow(
                    format: .markdown,
                    rawMarkdown: rawMarkdown,
                    plainText: plainText,
                )
            },
        ),
        AiChatOutputContextMenuAction(
            title: "Copy Entire Message as Plain Text",
            isEnabled: !plainText.isEmpty,
            perform: {
                interaction.copyRow(
                    format: .plainText,
                    rawMarkdown: rawMarkdown,
                    plainText: plainText,
                )
            },
        ),
    ]
}

private extension AiChatMarkdownDocument.TableAlignment {
    var swiftUIAlignment: Alignment {
        switch self {
        case .right: .trailing
        case .center: .center
        case .none, .left: .leading
        }
    }
}
