import Foundation
import SwiftUI
import VoyagerEntitiesAi

enum AiChatTranscriptRowDiscriminator: Equatable, Hashable {
    case message(index: Int)
    case streamingAssistant
}

struct AiChatRenderedTextMatchDescriptor: Equatable, Hashable {
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let blockIndex: Int
    let characterOffsets: Range<Int>
}

struct AiChatTranscriptBlockAnchor: Equatable, Hashable {
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let blockIndex: Int
}

struct AiChatTranscriptMatchAnchor: Equatable, Hashable {
    let descriptor: AiChatRenderedTextMatchDescriptor
}

struct AiChatTranscriptMatchScrollTarget: Equatable {
    let id: AiChatTranscriptMatchAnchor
    let scrollID: AiChatTranscriptBlockAnchor
    let relativeAnchor: UnitPoint
}

struct AiChatTranscriptBlockLookupResult: Equatable {
    let offsets: [Range<Int>]
    let inspectedDescriptorCount: Int
    let bucketLookupCount: Int
}

private struct AiChatTranscriptBlockMatchProjection: Equatable {
    let descriptors: [AiChatRenderedTextMatchDescriptor]
    let renderedCharacterCount: Int
}

struct AiChatTranscriptRenderedRow: Equatable {
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let renderedBlocks: [String]
}

enum AiChatRenderedTextMatcher {
    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

    static func matches(
        query: String,
        transcriptRow: AiChatTranscriptRowDiscriminator,
        renderedBlocks: [String],
    ) -> [AiChatRenderedTextMatchDescriptor] {
        renderedBlocks.enumerated().flatMap { blockIndex, text in
            matches(
                query: query,
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
                renderedText: text,
            )
        }
    }

    static func matches(
        query: String,
        transcriptRow: AiChatTranscriptRowDiscriminator,
        blockIndex: Int,
        renderedText: String,
    ) -> [AiChatRenderedTextMatchDescriptor] {
        guard !query.isEmpty else { return [] }
        return matches(query: query, in: renderedText).map { range in
            AiChatRenderedTextMatchDescriptor(
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
                characterOffsets: range,
            )
        }
    }

    private static func matches(query: String, in text: String) -> [Range<Int>] {
        var matches: [Range<Int>] = []
        var searchStart = text.startIndex
        var searchStartOffset = 0

        while searchStart < text.endIndex,
              let match = text.range(
                  of: query,
                  options: .caseInsensitive,
                  range: searchStart ..< text.endIndex,
                  locale: comparisonLocale,
              )
        {
            let lowerOffset = searchStartOffset + text.distance(from: searchStart, to: match.lowerBound)
            let upperOffset = lowerOffset + text.distance(from: match.lowerBound, to: match.upperBound)
            matches.append(lowerOffset ..< upperOffset)
            searchStart = match.upperBound
            searchStartOffset = upperOffset
        }

        return matches
    }
}

struct AiChatTranscriptSearchPresentation: Equatable {
    let query: String
    let matches: [AiChatRenderedTextMatchDescriptor]
    private let matchesByBlock: [AiChatTranscriptBlockAnchor: AiChatTranscriptBlockMatchProjection]

    @MainActor
    init(
        query: String,
        messages: [AiChatMessage],
        streamingAssistantContent: String?,
    ) {
        let renderer = AiChatAssistantMarkdownRenderSession()
        var renderedRows = messages.enumerated().map { index, message in
            let row = AiChatTranscriptRowDiscriminator.message(index: index)
            return AiChatTranscriptRenderedRow(
                transcriptRow: row,
                renderedBlocks: Self.renderedBlocks(
                    for: message,
                    transcriptRow: row,
                    renderer: renderer,
                ),
            )
        }
        if let streamingAssistantContent {
            renderedRows.append(AiChatTranscriptRenderedRow(
                transcriptRow: .streamingAssistant,
                renderedBlocks: renderer.render(
                    content: streamingAssistantContent,
                    transcriptRow: .streamingAssistant,
                ).document.searchBlocks,
            ))
        }
        self.init(query: query, renderedRows: renderedRows)
    }

    init(query: String, renderedRows: [AiChatTranscriptRenderedRow]) {
        self.query = query
        var matches: [AiChatRenderedTextMatchDescriptor] = []
        var matchesByBlock: [AiChatTranscriptBlockAnchor: AiChatTranscriptBlockMatchProjection] = [:]
        for row in renderedRows {
            Self.append(
                query: query,
                transcriptRow: row.transcriptRow,
                renderedBlocks: row.renderedBlocks,
                matches: &matches,
                matchesByBlock: &matchesByBlock,
            )
        }
        self.matches = matches
        self.matchesByBlock = matchesByBlock
    }

    private init(
        query: String,
        matches: [AiChatRenderedTextMatchDescriptor],
        matchesByBlock: [AiChatTranscriptBlockAnchor: AiChatTranscriptBlockMatchProjection],
    ) {
        self.query = query
        self.matches = matches
        self.matchesByBlock = matchesByBlock
    }

    static func empty(query: String) -> Self {
        Self(query: query, matches: [], matchesByBlock: [:])
    }

    func merging(_ other: Self) -> Self {
        guard query == other.query else { return other }
        var mergedIndex = matchesByBlock
        for (anchor, projection) in other.matchesByBlock {
            mergedIndex[anchor] = projection
        }
        return Self(
            query: query,
            matches: matches + other.matches,
            matchesByBlock: mergedIndex,
        )
    }

    var matchCountProjection: AiChatTranscriptSearchMatchCountProjection {
        .init(query: query, matchCount: matches.count)
    }

    func descriptor(atOrdinal ordinal: Int?) -> AiChatRenderedTextMatchDescriptor? {
        guard let ordinal, matches.indices.contains(ordinal - 1) else { return nil }
        return matches[ordinal - 1]
    }

    func anchor(for descriptor: AiChatRenderedTextMatchDescriptor) -> AiChatTranscriptBlockAnchor {
        AiChatTranscriptBlockAnchor(
            transcriptRow: descriptor.transcriptRow,
            blockIndex: descriptor.blockIndex,
        )
    }

    func matchOffsets(
        transcriptRow: AiChatTranscriptRowDiscriminator,
        blockIndex: Int,
    ) -> [Range<Int>] {
        matchLookup(transcriptRow: transcriptRow, blockIndex: blockIndex).offsets
    }

    func matchDescriptors(
        transcriptRow: AiChatTranscriptRowDiscriminator,
        blockIndex: Int,
    ) -> [AiChatRenderedTextMatchDescriptor] {
        matchesByBlock[AiChatTranscriptBlockAnchor(
            transcriptRow: transcriptRow,
            blockIndex: blockIndex,
        )]?.descriptors ?? []
    }

    func matchLookup(
        transcriptRow: AiChatTranscriptRowDiscriminator,
        blockIndex: Int,
    ) -> AiChatTranscriptBlockLookupResult {
        let descriptors = matchDescriptors(transcriptRow: transcriptRow, blockIndex: blockIndex)
        return AiChatTranscriptBlockLookupResult(
            offsets: descriptors.map(\.characterOffsets),
            inspectedDescriptorCount: descriptors.count,
            bucketLookupCount: 1,
        )
    }

    func scrollTarget(
        for descriptor: AiChatRenderedTextMatchDescriptor,
    ) -> AiChatTranscriptMatchScrollTarget? {
        let blockAnchor = anchor(for: descriptor)
        guard let projection = matchesByBlock[blockAnchor],
              projection.descriptors.contains(descriptor),
              projection.renderedCharacterCount > 0,
              descriptor.characterOffsets.lowerBound >= 0,
              descriptor.characterOffsets.upperBound <= projection.renderedCharacterCount
        else { return nil }

        let midpoint = CGFloat(
            descriptor.characterOffsets.lowerBound + descriptor.characterOffsets.count / 2,
        )
        let relativeY = min(max(midpoint / CGFloat(projection.renderedCharacterCount), 0), 1)
        return AiChatTranscriptMatchScrollTarget(
            id: AiChatTranscriptMatchAnchor(descriptor: descriptor),
            scrollID: blockAnchor,
            relativeAnchor: UnitPoint(x: 0.5, y: relativeY),
        )
    }

    private static func append(
        query: String,
        transcriptRow: AiChatTranscriptRowDiscriminator,
        renderedBlocks: [String],
        matches: inout [AiChatRenderedTextMatchDescriptor],
        matchesByBlock: inout [AiChatTranscriptBlockAnchor: AiChatTranscriptBlockMatchProjection],
    ) {
        for (blockIndex, renderedText) in renderedBlocks.enumerated() {
            let descriptors = AiChatRenderedTextMatcher.matches(
                query: query,
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
                renderedText: renderedText,
            )
            let anchor = AiChatTranscriptBlockAnchor(
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
            )
            matches.append(contentsOf: descriptors)
            matchesByBlock[anchor] = AiChatTranscriptBlockMatchProjection(
                descriptors: descriptors,
                renderedCharacterCount: renderedText.count,
            )
        }
    }

    @MainActor
    private static func renderedBlocks(
        for message: AiChatMessage,
        transcriptRow: AiChatTranscriptRowDiscriminator,
        renderer: AiChatAssistantMarkdownRenderSession,
    ) -> [String] {
        switch message.role {
        case .assistant:
            renderer.render(content: message.content, transcriptRow: transcriptRow).document.searchBlocks
        case .user, .system, .tool:
            [message.content]
        }
    }
}

enum AiChatTranscriptStableRowRendering: Equatable {
    case plain
    case assistantMarkdown
}

struct AiChatTranscriptSearchProjectionRequest: Equatable {
    struct StableRow: Equatable {
        let index: Int
        let rendering: AiChatTranscriptStableRowRendering
        let content: String
        let renderedBlocks: [String]
    }

    let isPresented: Bool
    let query: String
    let sessionToken: UUID?
    let stableRows: [StableRow]
    let stableRowsRevision: UInt64
    let streamingAssistantContent: String?
    let streamingRenderedBlocks: [String]?
    let streamingRevision: UInt64

    var requiresWork: Bool {
        isPresented && !query.isEmpty
    }

    @MainActor
    static func make(
        isPresented: Bool,
        query: String,
        sessionToken: UUID?,
        messages: [AiChatMessage],
        streamingAssistantContent: String?,
        stableRowsRevision: UInt64 = 0,
        streamingRevision: UInt64 = 0,
    ) -> Self {
        guard isPresented, !query.isEmpty else {
            return Self(
                isPresented: isPresented,
                query: query,
                sessionToken: sessionToken,
                stableRows: [],
                stableRowsRevision: stableRowsRevision,
                streamingAssistantContent: nil,
                streamingRenderedBlocks: nil,
                streamingRevision: streamingRevision,
            )
        }
        let renderer = AiChatAssistantMarkdownRenderSession()
        return Self(
            isPresented: true,
            query: query,
            sessionToken: sessionToken,
            stableRows: messages.enumerated().map { index, message in
                let row = AiChatTranscriptRowDiscriminator.message(index: index)
                return StableRow(
                    index: index,
                    rendering: message.role == .assistant ? .assistantMarkdown : .plain,
                    content: message.content,
                    renderedBlocks: message.role == .assistant
                        ? renderer.render(content: message.content, transcriptRow: row).document.searchBlocks
                        : [message.content],
                )
            },
            stableRowsRevision: stableRowsRevision,
            streamingAssistantContent: streamingAssistantContent,
            streamingRenderedBlocks: streamingAssistantContent.map { content in
                renderer.render(content: content, transcriptRow: .streamingAssistant).document.searchBlocks
            },
            streamingRevision: streamingRevision,
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isPresented == rhs.isPresented
            && lhs.query == rhs.query
            && lhs.sessionToken == rhs.sessionToken
            && lhs.stableRowsRevision == rhs.stableRowsRevision
            && lhs.streamingRevision == rhs.streamingRevision
    }
}

struct AiChatTranscriptSearchRequestCacheDiagnostics: Equatable {
    var stableRowsBuildCount = 0
    var stableRowsReuseCount = 0
}

struct AiChatTranscriptSearchRequestSource {
    let sessionToken: UUID?
    let messages: [AiChatMessage]
    let streamingAssistantContent: String?
    let transcriptRevision: UInt64
    let streamingRevision: UInt64
}

@MainActor
struct AiChatTranscriptSearchRequestCache {
    private let fallbackRenderer = AiChatAssistantMarkdownRenderSession()
    private var cachedSessionToken: UUID?
    private var cachedMessageCount = 0
    private var cachedTranscriptRevision: UInt64 = 0
    private var cachedStableRows: [AiChatTranscriptSearchProjectionRequest.StableRow] = []
    private var stableRowsRevision: UInt64 = 0
    private(set) var diagnostics = AiChatTranscriptSearchRequestCacheDiagnostics()

    @MainActor
    mutating func request(
        isPresented: Bool,
        query: String,
        source: AiChatTranscriptSearchRequestSource,
        assistantRenderer: AiChatAssistantMarkdownRenderSession? = nil,
    ) -> AiChatTranscriptSearchProjectionRequest {
        let sessionToken = source.sessionToken
        let messages = source.messages
        let streamingAssistantContent = source.streamingAssistantContent
        let transcriptRevision = source.transcriptRevision
        let streamingRevision = source.streamingRevision
        guard isPresented, !query.isEmpty else {
            return AiChatTranscriptSearchProjectionRequest.make(
                isPresented: isPresented,
                query: query,
                sessionToken: sessionToken,
                messages: [],
                streamingAssistantContent: nil,
                stableRowsRevision: stableRowsRevision,
                streamingRevision: streamingRevision,
            )
        }

        let sameStableIdentity = cachedSessionToken == sessionToken
            && cachedMessageCount == messages.count
            && cachedTranscriptRevision == transcriptRevision
        if sameStableIdentity {
            diagnostics.stableRowsReuseCount += 1
        } else {
            cachedSessionToken = sessionToken
            cachedMessageCount = messages.count
            cachedTranscriptRevision = transcriptRevision
            cachedStableRows = stableRows(
                from: messages,
                assistantRenderer: assistantRenderer,
            )
            stableRowsRevision &+= 1
            diagnostics.stableRowsBuildCount += 1
        }
        return AiChatTranscriptSearchProjectionRequest(
            isPresented: true,
            query: query,
            sessionToken: sessionToken,
            stableRows: cachedStableRows,
            stableRowsRevision: stableRowsRevision,
            streamingAssistantContent: streamingAssistantContent,
            streamingRenderedBlocks: streamingAssistantContent.map { content in
                (assistantRenderer ?? fallbackRenderer)
                    .render(content: content, transcriptRow: .streamingAssistant)
                    .document.searchBlocks
            },
            streamingRevision: streamingRevision,
        )
    }

    private func stableRows(
        from messages: [AiChatMessage],
        assistantRenderer: AiChatAssistantMarkdownRenderSession?,
    ) -> [AiChatTranscriptSearchProjectionRequest.StableRow] {
        let renderer = assistantRenderer ?? fallbackRenderer
        return messages.enumerated().map { index, message in
            AiChatTranscriptSearchProjectionRequest.StableRow(
                index: index,
                rendering: message.role == .assistant ? .assistantMarkdown : .plain,
                content: message.content,
                renderedBlocks: message.role == .assistant
                    ? renderer.render(
                        content: message.content,
                        transcriptRow: .message(index: index),
                    ).document.searchBlocks
                    : [message.content],
            )
        }
    }
}

struct AiChatTranscriptSearchProjectionDiagnostics: Equatable {
    var noWorkCount = 0
    var stableProjectionBuildCount = 0
    var stableProjectionReuseCount = 0
    var streamingProjectionBuildCount = 0
    var debounceCount = 0
    var cancellationCount = 0
}

struct AiChatTranscriptSearchProjectionResult: Equatable {
    let request: AiChatTranscriptSearchProjectionRequest
    let generation: UInt64
    let presentation: AiChatTranscriptSearchPresentation

    func isCurrent(
        request: AiChatTranscriptSearchProjectionRequest,
        generation: UInt64,
    ) -> Bool {
        self.request == request && self.generation == generation
    }
}

private struct AiChatTranscriptStableProjectionKey: Equatable {
    let sessionToken: UUID?
    let query: String
    let stableRowsRevision: UInt64
}

actor AiChatTranscriptSearchProjector {
    private let streamingDebounce: Duration
    private var latestGeneration: UInt64 = 0
    private var stableProjectionKey: AiChatTranscriptStableProjectionKey?
    private var stablePresentation: AiChatTranscriptSearchPresentation?
    private var projectionDiagnostics = AiChatTranscriptSearchProjectionDiagnostics()

    init(streamingDebounce: Duration = .zero) {
        self.streamingDebounce = streamingDebounce
    }

    func invalidate(generation: UInt64) {
        latestGeneration = max(latestGeneration, generation)
    }

    func diagnostics() -> AiChatTranscriptSearchProjectionDiagnostics {
        projectionDiagnostics
    }

    func project(
        _ request: AiChatTranscriptSearchProjectionRequest,
        generation: UInt64,
    ) async throws -> AiChatTranscriptSearchProjectionResult {
        latestGeneration = max(latestGeneration, generation)
        guard generation == latestGeneration else {
            try cancelProjection()
        }
        guard request.requiresWork else {
            projectionDiagnostics.noWorkCount += 1
            return projectionResult(
                request: request,
                generation: generation,
                presentation: .empty(query: request.query),
            )
        }

        try await debounceStreamingProjection(request)
        try checkCancellation(generation: generation)
        let stable = try stablePresentation(for: request, generation: generation)
        let presentation = try mergedStreamingPresentation(
            stable: stable,
            request: request,
            generation: generation,
        )
        try checkCancellation(generation: generation)
        return projectionResult(
            request: request,
            generation: generation,
            presentation: presentation,
        )
    }

    private func debounceStreamingProjection(
        _ request: AiChatTranscriptSearchProjectionRequest,
    ) async throws {
        guard request.streamingAssistantContent != nil, streamingDebounce > .zero else { return }
        projectionDiagnostics.debounceCount += 1
        do {
            try await Task.sleep(for: streamingDebounce)
        } catch is CancellationError {
            try cancelProjection()
        }
    }

    private func stablePresentation(
        for request: AiChatTranscriptSearchProjectionRequest,
        generation: UInt64,
    ) throws -> AiChatTranscriptSearchPresentation {
        let stableKey = AiChatTranscriptStableProjectionKey(
            sessionToken: request.sessionToken,
            query: request.query,
            stableRowsRevision: request.stableRowsRevision,
        )
        if stableKey == stableProjectionKey, let stablePresentation {
            projectionDiagnostics.stableProjectionReuseCount += 1
            return stablePresentation
        }

        let presentation = try makeStablePresentation(for: request)
        try checkCancellation(generation: generation)
        stableProjectionKey = stableKey
        stablePresentation = presentation
        projectionDiagnostics.stableProjectionBuildCount += 1
        return presentation
    }

    private func mergedStreamingPresentation(
        stable: AiChatTranscriptSearchPresentation,
        request: AiChatTranscriptSearchProjectionRequest,
        generation: UInt64,
    ) throws -> AiChatTranscriptSearchPresentation {
        guard request.streamingAssistantContent != nil,
              let streamingRenderedBlocks = request.streamingRenderedBlocks
        else { return stable }
        try checkCancellation(generation: generation)
        let renderedRows = [
            AiChatTranscriptRenderedRow(
                transcriptRow: .streamingAssistant,
                renderedBlocks: streamingRenderedBlocks,
            ),
        ]
        let streaming = AiChatTranscriptSearchPresentation(
            query: request.query,
            renderedRows: renderedRows,
        )
        projectionDiagnostics.streamingProjectionBuildCount += 1
        return stable.merging(streaming)
    }

    private func makeStablePresentation(
        for request: AiChatTranscriptSearchProjectionRequest,
    ) throws -> AiChatTranscriptSearchPresentation {
        var renderedRows: [AiChatTranscriptRenderedRow] = []
        renderedRows.reserveCapacity(request.stableRows.count)
        for row in request.stableRows {
            try Task.checkCancellation()
            let blocks = row.renderedBlocks
            renderedRows.append(AiChatTranscriptRenderedRow(
                transcriptRow: .message(index: row.index),
                renderedBlocks: blocks,
            ))
        }
        return AiChatTranscriptSearchPresentation(query: request.query, renderedRows: renderedRows)
    }

    private func projectionResult(
        request: AiChatTranscriptSearchProjectionRequest,
        generation: UInt64,
        presentation: AiChatTranscriptSearchPresentation,
    ) -> AiChatTranscriptSearchProjectionResult {
        AiChatTranscriptSearchProjectionResult(
            request: request,
            generation: generation,
            presentation: presentation,
        )
    }

    private func checkCancellation(generation: UInt64) throws {
        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            try cancelProjection()
        }
        guard generation == latestGeneration else {
            try cancelProjection()
        }
    }

    private func cancelProjection() throws -> Never {
        projectionDiagnostics.cancellationCount += 1
        throw CancellationError()
    }
}

enum AiChatRenderedTextHighlightKind: Equatable {
    case match
    case current
}

struct AiChatRenderedTextHighlightDecoration: Equatable {
    let offsets: Range<Int>
    let kind: AiChatRenderedTextHighlightKind
}

struct AiChatRenderedTextHighlightResult: Equatable {
    let attributedText: AttributedString
    let resolvedDecorationCount: Int
    let characterAdvanceCount: Int
}

enum AiChatRenderedTextHighlighter {
    static func decorations(
        matchOffsets: [Range<Int>],
        currentMatchOffsets: Range<Int>?,
    ) -> [AiChatRenderedTextHighlightDecoration] {
        matchOffsets.map { offsets in
            AiChatRenderedTextHighlightDecoration(
                offsets: offsets,
                kind: offsets == currentMatchOffsets ? .current : .match,
            )
        }
    }

    static func highlight(
        _ attributedText: AttributedString,
        matchOffsets: [Range<Int>],
        currentMatchOffsets: Range<Int>?,
    ) -> AttributedString {
        highlighting(
            attributedText,
            matchOffsets: matchOffsets,
            currentMatchOffsets: currentMatchOffsets,
        ).attributedText
    }

    static func highlighting(
        _ attributedText: AttributedString,
        matchOffsets: [Range<Int>],
        currentMatchOffsets: Range<Int>?,
    ) -> AiChatRenderedTextHighlightResult {
        var highlightedText = attributedText
        let characterCount = highlightedText.characters.count
        let sortedDecorations = decorations(
            matchOffsets: matchOffsets,
            currentMatchOffsets: currentMatchOffsets,
        ).sorted { lhs, rhs in
            if lhs.offsets.lowerBound == rhs.offsets.lowerBound {
                lhs.offsets.upperBound < rhs.offsets.upperBound
            } else {
                lhs.offsets.lowerBound < rhs.offsets.lowerBound
            }
        }
        var cursorIndex = highlightedText.startIndex
        var cursorOffset = 0
        var resolvedDecorationCount = 0
        var characterAdvanceCount = 0

        for decoration in sortedDecorations {
            let offsets = decoration.offsets
            guard offsets.lowerBound >= cursorOffset,
                  offsets.upperBound >= offsets.lowerBound,
                  offsets.upperBound <= characterCount,
                  let lowerBound = highlightedText.characters.index(
                      cursorIndex,
                      offsetBy: offsets.lowerBound - cursorOffset,
                      limitedBy: highlightedText.endIndex,
                  ),
                  let upperBound = highlightedText.characters.index(
                      lowerBound,
                      offsetBy: offsets.count,
                      limitedBy: highlightedText.endIndex,
                  )
            else { continue }

            let range = lowerBound ..< upperBound
            switch decoration.kind {
            case .match:
                highlightedText[range].backgroundColor = Color.yellow.opacity(0.28)
            case .current:
                highlightedText[range].backgroundColor = Color.accentColor.opacity(0.28)
                highlightedText[range].underlineStyle = Text.LineStyle(pattern: .solid)
            }
            characterAdvanceCount += offsets.upperBound - cursorOffset
            resolvedDecorationCount += 1
            cursorIndex = upperBound
            cursorOffset = offsets.upperBound
        }

        return AiChatRenderedTextHighlightResult(
            attributedText: highlightedText,
            resolvedDecorationCount: resolvedDecorationCount,
            characterAdvanceCount: characterAdvanceCount,
        )
    }
}
