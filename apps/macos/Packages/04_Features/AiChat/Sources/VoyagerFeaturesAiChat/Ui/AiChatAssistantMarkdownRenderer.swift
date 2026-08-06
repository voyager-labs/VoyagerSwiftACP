import AppKit
import SwiftUI
import VoyagerEntitiesAi
import VoyagerShared

struct AiChatAssistantMarkdownRenderedBlock: Equatable, Identifiable {
    let presentationID: AiChatMarkdownDocument.BlockID
    let block: AiChatMarkdownDocument.Block

    var id: AiChatMarkdownDocument.BlockID {
        presentationID
    }
}

struct AiChatAssistantMarkdownRenderedDocument: Equatable {
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let document: AiChatMarkdownDocument
    let blocks: [AiChatAssistantMarkdownRenderedBlock]
    let ownsChildVerticalScroll = false
}

struct AiChatAssistantMarkdownViewSnapshot: Equatable {
    let presentationID: AiChatMarkdownDocument.BlockID
    let transcriptRow: AiChatTranscriptRowDiscriminator?
    let selection: AiChatMarkdownDocument.PlainSelectionRange?
    let isFirstResponder: Bool
    let outerScrollOffset: CGFloat
    let currentSearchDescriptor: AiChatRenderedTextMatchDescriptor?

    init(
        presentationID: AiChatMarkdownDocument.BlockID,
        selection: AiChatMarkdownDocument.PlainSelectionRange?,
        isFirstResponder: Bool,
        outerScrollOffset: CGFloat,
        currentSearchDescriptor: AiChatRenderedTextMatchDescriptor?,
        transcriptRow: AiChatTranscriptRowDiscriminator? = nil,
    ) {
        self.presentationID = presentationID
        self.transcriptRow = transcriptRow
        self.selection = selection
        self.isFirstResponder = isFirstResponder
        self.outerScrollOffset = outerScrollOffset
        self.currentSearchDescriptor = currentSearchDescriptor
    }
}

@MainActor
final class AiChatAssistantMarkdownRenderSession: ObservableObject {
    private let highlightingClient: AiChatSyntaxHighlightingClient
    var renderedByRow: [AiChatTranscriptRowDiscriminator: AiChatAssistantMarkdownRenderedDocument] = [:]
    var preparedPresentationIDs: Set<AiChatMarkdownDocument.BlockID> = []
    var selectionProjections: [SelectionProjectionKey: SelectionProjection] = [:]
    var activeHighlightRequests: [AiChatAssistantMarkdownHighlightIdentity: HighlightRequest] = [:]
    var hasPreparedSession = false
    var preparedSessionID: AiChatSessionID?
    var preparedHasTranscriptContent = false
    var renderLifecycleRevision: UInt64 = 0
    private var nextHighlightRequestID: UInt64 = 0
    var capturedSnapshot: AiChatAssistantMarkdownViewSnapshot?
    private var capturedSelectionText: String?
    private var capturedSearchText: String?
    var diagnostics = AiChatAssistantMarkdownRenderDiagnostics()
    private(set) var handoffRevision: UInt64 = 0

    var hasCapturedViewState: Bool {
        capturedSnapshot != nil
    }

    var activeHighlightRequestCount: Int {
        activeHighlightRequests.count
    }

    var activeHighlightSourceBytes: Int {
        activeHighlightRequests.values.reduce(into: 0) { byteCount, request in
            byteCount += request.source.utf8.count
        }
    }

    init(highlightingClient: AiChatSyntaxHighlightingClient = .live()) {
        self.highlightingClient = highlightingClient
    }

    func render(
        content: String,
        transcriptRow: AiChatTranscriptRowDiscriminator,
    ) -> AiChatAssistantMarkdownRenderedDocument {
        let previous = compatiblePreviousDocument(content: content, transcriptRow: transcriptRow)
        let streamingFinalization = transcriptRow != .streamingAssistant
            && renderedByRow[.streamingAssistant]?.document.rawSource == content
        let document: AiChatMarkdownDocument
        if let current = renderedByRow[transcriptRow], current.document.rawSource == content {
            document = current.document
        } else if streamingFinalization, let streaming = renderedByRow[.streamingAssistant] {
            document = streaming.document
        } else {
            document = AiChatMarkdownParser.parse(content)
            diagnostics.documentParseCount += 1
        }

        let blocks = document.blocks.enumerated().map { index, block in
            let presentationID = presentationID(for: block, at: index, previous: previous)
            if preparedPresentationIDs.insert(presentationID).inserted {
                diagnostics.blockPreparationCount[presentationID, default: 0] += 1
            }
            return AiChatAssistantMarkdownRenderedBlock(presentationID: presentationID, block: block)
        }
        let rendered = AiChatAssistantMarkdownRenderedDocument(
            transcriptRow: transcriptRow,
            document: document,
            blocks: blocks,
        )
        if streamingFinalization {
            handoffRevision &+= 1
            handoffCapturedViewState(to: transcriptRow)
        }
        renderedByRow[transcriptRow] = rendered
        updateRetainedDocumentCount()
        for (index, block) in blocks.enumerated() {
            registerSelectionProjection(
                presentationID: block.presentationID,
                plainText: block.block.projections.plain,
                searchText: block.block.projections.search,
                transcriptRow: transcriptRow,
                blockIndex: index,
            )
        }
        expireCapturedViewStateIfIncompatible(with: rendered)
        return rendered
    }

    func capture(_ snapshot: AiChatAssistantMarkdownViewSnapshot) {
        capturedSnapshot = snapshot
        capturedSelectionText = selectedText(for: snapshot) ?? capturedSelectionText
        capturedSearchText = searchText(for: snapshot.currentSearchDescriptor) ?? capturedSearchText
    }

    func captureSelection(
        presentationID: AiChatMarkdownDocument.BlockID,
        transcriptRow: AiChatTranscriptRowDiscriminator,
        selection: AiChatMarkdownDocument.PlainSelectionRange?,
        isFirstResponder: Bool,
    ) {
        let hasSelection = selection?.utf16Length ?? 0 > 0
        if !isFirstResponder, !hasSelection {
            if capturedSnapshot?.presentationID == presentationID,
               capturedSnapshot?.transcriptRow == transcriptRow
            {
                clearViewState()
            }
            return
        }
        let snapshot = AiChatAssistantMarkdownViewSnapshot(
            presentationID: presentationID,
            selection: selection,
            isFirstResponder: isFirstResponder,
            outerScrollOffset: capturedSnapshot?.outerScrollOffset ?? 0,
            currentSearchDescriptor: capturedSnapshot?.currentSearchDescriptor,
            transcriptRow: transcriptRow,
        )
        capture(snapshot)
    }

    func clearViewState() {
        capturedSnapshot = nil
        capturedSelectionText = nil
        capturedSearchText = nil
    }

    func registerSelectionProjection(
        presentationID: AiChatMarkdownDocument.BlockID,
        plainText: String,
        searchText: String,
        transcriptRow: AiChatTranscriptRowDiscriminator,
        blockIndex: Int,
    ) {
        selectionProjections[.init(transcriptRow: transcriptRow, presentationID: presentationID)] = .init(
            plainText: plainText,
            searchText: searchText,
            transcriptRow: transcriptRow,
            blockIndex: blockIndex,
        )
    }

    func restoration(
        presentationID: AiChatMarkdownDocument.BlockID,
        transcriptRow: AiChatTranscriptRowDiscriminator,
    ) -> AiChatAssistantMarkdownViewSnapshot? {
        guard let capturedSnapshot,
              capturedSnapshot.presentationID == presentationID,
              capturedSnapshot.transcriptRow == transcriptRow,
              let projection = selectionProjections[.init(
                  transcriptRow: transcriptRow,
                  presentationID: presentationID,
              )]
        else { return nil }
        let selection = remappedRange(
            capturedSelectionText,
            fallback: capturedSnapshot.selection,
            in: projection.plainText,
        )
        let descriptor = remappedDescriptor(transcriptRow: transcriptRow)
        return .init(
            presentationID: presentationID,
            selection: selection,
            isFirstResponder: capturedSnapshot.isFirstResponder,
            outerScrollOffset: capturedSnapshot.outerScrollOffset,
            currentSearchDescriptor: descriptor,
            transcriptRow: transcriptRow,
        )
    }

    func captureContext(
        outerScrollOffset: CGFloat,
        currentSearchDescriptor: AiChatRenderedTextMatchDescriptor?,
    ) {
        guard let snapshot = capturedSnapshot else { return }
        let descriptor = currentSearchDescriptor ?? snapshot.currentSearchDescriptor
        capturedSnapshot = .init(
            presentationID: snapshot.presentationID,
            selection: snapshot.selection,
            isFirstResponder: snapshot.isFirstResponder,
            outerScrollOffset: outerScrollOffset,
            currentSearchDescriptor: descriptor,
            transcriptRow: snapshot.transcriptRow,
        )
        capturedSearchText = searchText(for: descriptor) ?? capturedSearchText
    }

    func restoration(
        for rendered: AiChatAssistantMarkdownRenderedDocument,
    ) -> AiChatAssistantMarkdownViewSnapshot? {
        guard let capturedSnapshot,
              capturedSnapshot.transcriptRow == rendered.transcriptRow,
              selectionPresentationIDs(in: rendered).contains(capturedSnapshot.presentationID)
        else { return nil }
        return restoration(
            presentationID: capturedSnapshot.presentationID,
            transcriptRow: rendered.transcriptRow,
        )
    }

    func highlight(
        _ renderedBlock: AiChatAssistantMarkdownRenderedBlock,
        transcriptRow: AiChatTranscriptRowDiscriminator,
        appearance: AiChatSyntaxHighlightingClient.Appearance,
        typographyVersion: Int,
        generation: UInt64,
    ) async -> AiChatSyntaxHighlightingClient.Result? {
        guard let code = renderedBlock.block.code else { return nil }
        let requestKey = AiChatAssistantMarkdownHighlightIdentity(
            transcriptRow: transcriptRow,
            presentationID: renderedBlock.presentationID,
            renderLifecycleRevision: renderLifecycleRevision,
        )
        let previousGeneration = diagnostics.highlightGeneration[requestKey] ?? 0
        let nextGeneration = max(previousGeneration &+ 1, generation)
        diagnostics.highlightGeneration[requestKey] = nextGeneration
        nextHighlightRequestID &+= 1
        let request = HighlightRequest(
            requestID: nextHighlightRequestID,
            generation: nextGeneration,
            source: code.payload,
        )
        activeHighlightRequests[requestKey] = request
        defer {
            if activeHighlightRequests[requestKey] == request {
                activeHighlightRequests[requestKey] = nil
            }
        }
        let result = await highlightingClient.highlight(.init(
            identity: requestKey.syntaxHighlightingIdentity,
            code: code.payload,
            languageLabel: code.originalLanguage,
            appearance: appearance,
            typographyVersion: typographyVersion,
            generation: nextGeneration,
        ))
        guard activeHighlightRequests[requestKey] == request,
              result.generation == nextGeneration,
              result.source == code.payload
        else { return nil }
        return result
    }

    private func handoffCapturedViewState(to transcriptRow: AiChatTranscriptRowDiscriminator) {
        guard let snapshot = capturedSnapshot,
              snapshot.transcriptRow == .streamingAssistant
        else { return }
        capturedSnapshot = .init(
            presentationID: snapshot.presentationID,
            selection: snapshot.selection,
            isFirstResponder: snapshot.isFirstResponder,
            outerScrollOffset: snapshot.outerScrollOffset,
            currentSearchDescriptor: snapshot.currentSearchDescriptor,
            transcriptRow: transcriptRow,
        )
    }

    private func expireCapturedViewStateIfIncompatible(
        with rendered: AiChatAssistantMarkdownRenderedDocument,
    ) {
        guard let snapshot = capturedSnapshot,
              snapshot.transcriptRow == rendered.transcriptRow,
              !selectionPresentationIDs(in: rendered).contains(snapshot.presentationID)
        else { return }
        clearViewState()
    }

    private func selectionPresentationIDs(
        in rendered: AiChatAssistantMarkdownRenderedDocument,
    ) -> Set<AiChatMarkdownDocument.BlockID> {
        var identifiers = Set(rendered.blocks.map(\.presentationID))
        for renderedBlock in rendered.blocks {
            guard let table = renderedBlock.block.table else { continue }
            for rowIndex in table.cells.indices {
                for columnIndex in table.cells[rowIndex].indices {
                    identifiers.insert(.init(
                        rawValue: "\(renderedBlock.presentationID.rawValue)-cell-\(rowIndex)-\(columnIndex)",
                    ))
                }
            }
        }
        return identifiers
    }

    private func compatiblePreviousDocument(
        content: String,
        transcriptRow: AiChatTranscriptRowDiscriminator,
    ) -> AiChatAssistantMarkdownRenderedDocument? {
        if let current = renderedByRow[transcriptRow] {
            return current
        }
        if transcriptRow != .streamingAssistant,
           let streaming = renderedByRow[.streamingAssistant],
           streaming.document.rawSource == content
        {
            return streaming
        }
        return nil
    }

    private func presentationID(
        for block: AiChatMarkdownDocument.Block,
        at index: Int,
        previous: AiChatAssistantMarkdownRenderedDocument?,
    ) -> AiChatMarkdownDocument.BlockID {
        guard let previous else { return block.id }
        if let stable = previous.blocks.first(where: { $0.block.id == block.id }) {
            return stable.presentationID
        }
        guard previous.blocks.indices.contains(index) else { return block.id }
        let previousBlock = previous.blocks[index]
        let sameSourceStart = previousBlock.block.sourceRange.utf8Offsets.lowerBound
            == block.sourceRange.utf8Offsets.lowerBound
        let previousPlain = previousBlock.block.projections.plain
        let currentPlain = block.projections.plain
        let hasProjectionContinuity = previousPlain.hasPrefix(currentPlain)
            || currentPlain.hasPrefix(previousPlain)
            || isIncompleteFenceCompletion(from: previousBlock.block, to: block)
        return sameSourceStart && hasProjectionContinuity
            ? previousBlock.presentationID
            : block.id
    }

    private func isIncompleteFenceCompletion(
        from previous: AiChatMarkdownDocument.Block,
        to current: AiChatMarkdownDocument.Block,
    ) -> Bool {
        guard previous.kind == .paragraph,
              current.kind == .code,
              let code = current.code,
              let openingLineEnd = previous.rawSlice.firstIndex(of: "\n")
        else { return false }
        let openingLine = previous.rawSlice[..<openingLineEnd].trimmingCharacters(in: .newlines)
        let expectedOpening = code.openingIndentation + code.fenceDelimiter
        guard openingLine.hasPrefix(expectedOpening) else { return false }
        let payloadStart = previous.rawSlice.index(after: openingLineEnd)
        return previous.rawSlice[payloadStart...] == code.payload
    }

    private func selectedText(for snapshot: AiChatAssistantMarkdownViewSnapshot) -> String? {
        guard let transcriptRow = snapshot.transcriptRow,
              let selection = snapshot.selection,
              let projection = selectionProjections[.init(
                  transcriptRow: transcriptRow,
                  presentationID: snapshot.presentationID,
              )],
              let range = selection.searchRange(
                  in: projection.plainText,
                  invalidRangePolicy: .discard,
              )
        else { return nil }
        return range.substring(in: projection.plainText)
    }

    private func searchText(for descriptor: AiChatRenderedTextMatchDescriptor?) -> String? {
        guard let descriptor,
              let rendered = renderedByRow[descriptor.transcriptRow],
              rendered.blocks.indices.contains(descriptor.blockIndex)
        else { return nil }
        let projection = rendered.blocks[descriptor.blockIndex].block.projections.search
        return AiChatMarkdownDocument.SearchRange(characterOffsets: descriptor.characterOffsets)
            .substring(in: projection)
    }

    private func remappedDescriptor(
        transcriptRow: AiChatTranscriptRowDiscriminator,
    ) -> AiChatRenderedTextMatchDescriptor? {
        guard let rendered = renderedByRow[transcriptRow],
              let capturedDescriptor = capturedSnapshot?.currentSearchDescriptor,
              rendered.blocks.indices.contains(capturedDescriptor.blockIndex)
        else { return nil }
        let projection = rendered.blocks[capturedDescriptor.blockIndex].block.projections.search
        guard let offsets = remappedSearchOffsets(
            capturedSearchText,
            fallback: capturedDescriptor.characterOffsets,
            in: projection,
        )
        else { return nil }
        return .init(
            transcriptRow: transcriptRow,
            blockIndex: capturedDescriptor.blockIndex,
            characterOffsets: offsets,
        )
    }

    struct SelectionProjectionKey: Hashable {
        let transcriptRow: AiChatTranscriptRowDiscriminator
        let presentationID: AiChatMarkdownDocument.BlockID
    }

    struct SelectionProjection {
        let plainText: String
        let searchText: String
        let transcriptRow: AiChatTranscriptRowDiscriminator
        let blockIndex: Int
    }

    struct HighlightRequest: Equatable {
        let requestID: UInt64
        let generation: UInt64
        let source: String
    }

    private func remappedRange(
        _ text: String?,
        fallback: AiChatMarkdownDocument.PlainSelectionRange?,
        in projection: String,
    ) -> AiChatMarkdownDocument.PlainSelectionRange? {
        guard let text, let range = projection.range(of: text) else {
            guard let fallback,
                  let range = fallback.searchRange(in: projection, invalidRangePolicy: .clamp)
            else { return nil }
            return range.plainSelectionRange(in: projection)
        }
        return AiChatMarkdownDocument.SearchRange(range, in: projection)
            .plainSelectionRange(in: projection)
    }

    private func remappedSearchOffsets(
        _ text: String?,
        fallback: Range<Int>?,
        in projection: String,
    ) -> Range<Int>? {
        if let text, let range = projection.range(of: text) {
            return AiChatMarkdownDocument.SearchRange(range, in: projection).characterOffsets
        }
        guard let fallback,
              fallback.lowerBound >= 0,
              fallback.upperBound <= projection.count
        else { return nil }
        return fallback
    }
}

enum AiChatAssistantMarkdownAttributedText {
    // SwiftUI 속성이 AppKit 변환에서 소실되므로 최종 문자열을 AppKit 속성으로 구성한다.
    private static let bodyPointSize: CGFloat = 13
    private static let headingLevel1PointSize: CGFloat = 15
    private static let codePointSize: CGFloat = 12

    static func make(
        block: AiChatMarkdownDocument.Block,
        syntaxRuns: [AiChatSyntaxHighlightingClient.Run],
        matchOffsets: [Range<Int>],
        currentMatchOffsets: Range<Int>?,
    ) -> NSAttributedString {
        let text = block.projections.rendered
        let attributed = makeBase(text: text, font: appKitFont(for: block.kind))
        applyInlineIntents(block.inlineIntents, to: attributed, baseText: text)
        applySyntaxRuns(syntaxRuns, to: attributed, baseText: text)
        applySearchDecorations(
            matchOffsets: matchOffsets,
            currentMatchOffsets: currentMatchOffsets,
            to: attributed,
            baseText: text,
        )
        return attributed
    }

    static func make(
        text: String,
        inlineIntents: [AiChatMarkdownDocument.InlineIntent],
        matchOffsets: [Range<Int>],
        currentMatchOffsets: Range<Int>?,
        appliesHangulWordPriorityLineBreak: Bool = false,
    ) -> NSAttributedString {
        let attributed = makeBase(text: text, font: appKitFont(for: .paragraph))
        applyInlineIntents(inlineIntents, to: attributed, baseText: text)
        applySearchDecorations(
            matchOffsets: matchOffsets,
            currentMatchOffsets: currentMatchOffsets,
            to: attributed,
            baseText: text,
        )
        if appliesHangulWordPriorityLineBreak {
            applyHangulWordPriorityLineBreak(to: attributed)
        }
        return attributed
    }

    private static func makeBase(text: String, font: NSFont) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ],
        )
    }

    private static func appKitFont(
        for kind: AiChatMarkdownDocument.BlockKind,
    ) -> NSFont {
        switch kind {
        case .code:
            NSFont.monospacedSystemFont(ofSize: codePointSize, weight: .regular)
        case let .heading(level):
            if level == 1 {
                NSFont.systemFont(ofSize: headingLevel1PointSize, weight: .semibold)
            } else {
                NSFont.boldSystemFont(ofSize: bodyPointSize)
            }
        case .paragraph, .bullet, .numbered, .blockquote, .table:
            NSFont.systemFont(ofSize: bodyPointSize)
        }
    }

    private static func applyInlineIntents(
        _ intents: [AiChatMarkdownDocument.InlineIntent],
        to attributed: NSMutableAttributedString,
        baseText: String,
    ) {
        for intent in intents {
            apply(intent, to: attributed, baseText: baseText)
        }
    }

    private static func apply(
        _ intent: AiChatMarkdownDocument.InlineIntent,
        to attributed: NSMutableAttributedString,
        baseText: String,
    ) {
        let searchRange: AiChatMarkdownDocument.SearchRange = switch intent {
        case let .emphasis(range), let .strong(range), let .code(range):
            range
        case let .link(range, _):
            range
        }
        guard let nsRange = nsRange(
            characterOffsets: searchRange.characterOffsets,
            in: baseText,
        ) else { return }
        switch intent {
        case .emphasis:
            applySymbolicTraits(.italic, in: nsRange, of: attributed)
        case .strong:
            applySymbolicTraits(.bold, in: nsRange, of: attributed)
        case let .link(_, destination):
            if let url = URL(string: destination) {
                attributed.addAttribute(.link, value: url, range: nsRange)
            }
        case .code:
            let codeFont = appKitFont(for: .code)
            attributed.setAttributes(
                [
                    .font: codeFont,
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.controlBackgroundColor,
                ],
                range: nsRange,
            )
        }
    }

    private static func applySyntaxRuns(
        _ runs: [AiChatSyntaxHighlightingClient.Run],
        to attributed: NSMutableAttributedString,
        baseText: String,
    ) {
        for run in runs {
            guard let nsRange = nsRange(
                utf16Offsets: run.sourceRange.utf16Offsets,
                in: baseText,
            ) else { continue }
            let attributes = run.attributes
            let codeFont = appKitFont(for: .code)
            attributed.addAttribute(.font, value: codeFont, range: nsRange)
            if let foreground = attributes.foreground {
                attributed.addAttribute(
                    .foregroundColor,
                    value: nsColor(from: foreground),
                    range: nsRange,
                )
            }
            if let background = attributes.background {
                attributed.addAttribute(
                    .backgroundColor,
                    value: nsColor(from: background),
                    range: nsRange,
                )
            }
            if attributes.isBold || attributes.isItalic {
                var traits = codeFont.fontDescriptor.symbolicTraits
                if attributes.isBold { traits.insert(.bold) }
                if attributes.isItalic { traits.insert(.italic) }
                let descriptor = codeFont.fontDescriptor.withSymbolicTraits(traits)
                attributed.addAttribute(
                    .font,
                    value: NSFont(descriptor: descriptor, size: 0) ?? codeFont,
                    range: nsRange,
                )
            }
        }
    }

    private static func applySearchDecorations(
        matchOffsets: [Range<Int>],
        currentMatchOffsets: Range<Int>?,
        to attributed: NSMutableAttributedString,
        baseText: String,
    ) {
        let decorations = AiChatRenderedTextHighlighter.decorations(
            matchOffsets: matchOffsets,
            currentMatchOffsets: currentMatchOffsets,
        )
        for decoration in decorations {
            guard let nsRange = nsRange(
                characterOffsets: decoration.offsets,
                in: baseText,
            ) else { continue }
            switch decoration.kind {
            case .match:
                attributed.addAttribute(
                    .backgroundColor,
                    value: NSColor.systemYellow.withAlphaComponent(0.28),
                    range: nsRange,
                )
            case .current:
                attributed.addAttribute(
                    .backgroundColor,
                    value: NSColor.controlAccentColor.withAlphaComponent(0.28),
                    range: nsRange,
                )
                attributed.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: nsRange,
                )
            }
        }
    }

    /// 제한된 폭에서 한글 단어의 마지막 음절이 분리되지 않게 한다.
    private static func applyHangulWordPriorityLineBreak(to attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else { return }
        let paragraphStyle: NSMutableParagraphStyle = if let existing = attributed.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil,
        ) as? NSParagraphStyle {
            (existing.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        } else {
            NSMutableParagraphStyle()
        }
        paragraphStyle.lineBreakStrategy = .hangulWordPriority
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
    }

    private static func applySymbolicTraits(
        _ traits: NSFontDescriptor.SymbolicTraits,
        in nsRange: NSRange,
        of attributed: NSMutableAttributedString,
    ) {
        attributed.enumerateAttribute(
            .font,
            in: nsRange,
            options: [],
        ) { value, subrange, stop in
            guard let font = value as? NSFont else { stop.pointee = true
                return
            }
            let merged = font.fontDescriptor.symbolicTraits.union(traits)
            let descriptor = font.fontDescriptor.withSymbolicTraits(merged)
            attributed.addAttribute(
                .font,
                value: NSFont(descriptor: descriptor, size: 0) ?? font,
                range: subrange,
            )
        }
    }

    private static func nsColor(
        from components: AiChatSyntaxHighlightingClient.ColorComponents,
    ) -> NSColor {
        NSColor(
            red: CGFloat(components.red),
            green: CGFloat(components.green),
            blue: CGFloat(components.blue),
            alpha: CGFloat(components.alpha),
        )
    }

    private static func nsRange(
        characterOffsets: Range<Int>,
        in text: String,
    ) -> NSRange? {
        AiChatMarkdownDocument.SearchRange(characterOffsets: characterOffsets)
            .plainSelectionRange(in: text)?
            .nsRange
    }

    private static func nsRange(
        utf16Offsets: Range<Int>,
        in text: String,
    ) -> NSRange? {
        AiChatMarkdownDocument.PlainSelectionRange(
            utf16Location: utf16Offsets.lowerBound,
            utf16Length: utf16Offsets.count,
        )
        .searchRange(in: text, invalidRangePolicy: .discard)?
        .plainSelectionRange(in: text)?
        .nsRange
    }
}
