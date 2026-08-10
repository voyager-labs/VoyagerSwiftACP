import Foundation
import VoyagerEntitiesAi

struct AiChatAssistantMarkdownHighlightIdentity: Hashable {
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let presentationID: AiChatMarkdownDocument.BlockID
    let renderLifecycleRevision: UInt64

    init(
        transcriptRow: AiChatTranscriptRowDiscriminator,
        presentationID: AiChatMarkdownDocument.BlockID,
        renderLifecycleRevision: UInt64 = 0,
    ) {
        self.transcriptRow = transcriptRow
        self.presentationID = presentationID
        self.renderLifecycleRevision = renderLifecycleRevision
    }

    var syntaxHighlightingIdentity: AiChatSyntaxHighlightingClient.RequestIdentity {
        let rowIdentity = switch transcriptRow {
        case let .message(index): "message:\(index)"
        case .streamingAssistant: "streaming-assistant"
        }
        return .init(rawValue: "\(renderLifecycleRevision):\(rowIdentity):\(presentationID.rawValue)")
    }
}

struct AiChatAssistantMarkdownRenderDiagnostics: Equatable {
    var documentParseCount = 0
    var retainedDocumentCount = 0
    var blockPreparationCount: [AiChatMarkdownDocument.BlockID: Int] = [:]
    var highlightGeneration: [AiChatAssistantMarkdownHighlightIdentity: UInt64] = [:]
    let streamingCoalescingLifecycleCount = 1
}

extension AiChatAssistantMarkdownRenderSession {
    func prepareForTranscript(in state: AiChatState) {
        let stableMessages = Dictionary(uniqueKeysWithValues: state.transcriptHistory.enumerated()
            .map { index, message in
                (AiChatTranscriptRowDiscriminator.message(index: index), message)
            })
        let stableAssistantSources = stableMessages.compactMapValues { message in
            message.role == .assistant ? message.content : nil
        }
        prepareForSession(
            state.sessionID,
            hasTranscriptContent: !state.transcriptHistory.isEmpty || state.streamingAssistantDraft != nil,
            stableTranscriptSources: stableAssistantSources,
            stableTranscriptMessages: stableMessages,
            streamingTranscriptSource: state.streamingAssistantDraft,
        )
    }
}

extension AiChatAssistantMarkdownRenderSession {
    var retainedSelectionProjectionCount: Int {
        selectionProjections.count
    }

    var retainedSelectionProjectionBytes: Int {
        selectionProjections.values.reduce(into: 0) { byteCount, projection in
            byteCount += projection.plainText.utf8.count
            byteCount += projection.searchText.utf8.count
        }
    }

    func prepareForSession(
        _ sessionID: AiChatSessionID?,
        hasTranscriptContent: Bool = true,
        stableTranscriptSources: [AiChatTranscriptRowDiscriminator: String]? = nil,
        stableTranscriptMessages: [AiChatTranscriptRowDiscriminator: AiChatMessage]? = nil,
        streamingTranscriptSource: String? = nil,
    ) {
        let didChangeSession = !hasPreparedSession || preparedSessionID != sessionID
        let didBecomeEmpty = hasPreparedSession
            && !didChangeSession
            && preparedHasTranscriptContent
            && !hasTranscriptContent
        hasPreparedSession = true
        preparedSessionID = sessionID
        preparedHasTranscriptContent = hasTranscriptContent
        if didChangeSession || didBecomeEmpty {
            resetRetainedTranscriptState()
        } else if stableTranscriptSources != nil || stableTranscriptMessages != nil {
            pruneRetainedTranscriptState(
                to: stableTranscriptSources,
                stableTranscriptMessages: stableTranscriptMessages,
                streamingTranscriptSource: streamingTranscriptSource,
            )
        }
        if let stableTranscriptMessages {
            preparedTranscriptMessages = stableTranscriptMessages
        }
    }

    private func pruneRetainedTranscriptState(
        to stableTranscriptSources: [AiChatTranscriptRowDiscriminator: String]?,
        stableTranscriptMessages: [AiChatTranscriptRowDiscriminator: AiChatMessage]?,
        streamingTranscriptSource: String?,
    ) {
        var staleRows = Set<AiChatTranscriptRowDiscriminator>()
        if let stableTranscriptSources {
            staleRows.formUnion(renderedByRow.compactMap { row, rendered in
                switch row {
                case .message:
                    stableTranscriptSources[row] != rendered.document.rawSource ? row : nil
                case .streamingAssistant:
                    streamingTranscriptSource == nil
                        && !stableTranscriptSources.values.contains(rendered.document.rawSource)
                        ? row
                        : nil
                }
            })
        }
        if let stableTranscriptMessages {
            staleRows.formUnion(preparedTranscriptMessages.compactMap { row, message in
                stableTranscriptMessages[row] != message ? row : nil
            })
        }
        guard !staleRows.isEmpty else { return }
        renderLifecycleRevision &+= 1
        renderedByRow = renderedByRow.filter { !staleRows.contains($0.key) }
        selectionProjections = selectionProjections.filter { !staleRows.contains($0.key.transcriptRow) }
        activeHighlightRequests = activeHighlightRequests.filter { !staleRows.contains($0.key.transcriptRow) }
        diagnostics.highlightGeneration.removeAll(keepingCapacity: false)
        if let capturedRow = capturedSnapshot?.transcriptRow, staleRows.contains(capturedRow) {
            clearViewState()
        }
        preparedPresentationIDs = Set(renderedByRow.values.flatMap { $0.blocks.map(\.presentationID) })
        diagnostics.blockPreparationCount = diagnostics.blockPreparationCount.filter {
            preparedPresentationIDs.contains($0.key)
        }
        updateRetainedDocumentCount()
    }

    func updateRetainedDocumentCount() {
        diagnostics.retainedDocumentCount = Set(renderedByRow.values.map(\.document.rawSource)).count
    }

    private func resetRetainedTranscriptState() {
        renderLifecycleRevision &+= 1
        renderedByRow.removeAll(keepingCapacity: false)
        preparedPresentationIDs.removeAll(keepingCapacity: false)
        selectionProjections.removeAll(keepingCapacity: false)
        activeHighlightRequests.removeAll(keepingCapacity: false)
        preparedTranscriptMessages.removeAll(keepingCapacity: false)
        clearViewState()
        diagnostics.retainedDocumentCount = 0
        diagnostics.blockPreparationCount.removeAll(keepingCapacity: false)
        diagnostics.highlightGeneration.removeAll(keepingCapacity: false)
    }
}
