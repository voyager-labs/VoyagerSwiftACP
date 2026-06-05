import Foundation
import VoyagerEntitiesAi

extension AiChatFeature {
    func truncateHistory(
        _ messages: [AiChatMessage],
        currentUserMessage: String,
        budget: Int = kAiChatHistoryCharacterBudget,
    ) -> (messages: [AiChatMessage], metadata: AiChatHistoryTruncationMetadata) {
        guard !messages.isEmpty else {
            return emptyHistoryTruncationResult(budget: budget)
        }

        let currentUserIndex = currentUserIndex(in: messages, currentUserMessage: currentUserMessage)
        let protectedMessages = Array(messages[currentUserIndex...])
        let previousChunks = historyChunks(before: currentUserIndex, in: messages)
        let includedMessages = includeChunks(
            previousChunks,
            protectedMessages: protectedMessages,
            budget: budget,
        )
        let excludedMessageCount = messages.count - includedMessages.count

        return (
            includedMessages,
            AiChatHistoryTruncationMetadata(
                includedMessageCount: includedMessages.count,
                excludedMessageCount: excludedMessageCount,
                budget: budget,
                truncationReason: excludedMessageCount > 0 ? .characterBudgetExceeded : nil,
            ),
        )
    }

    private func emptyHistoryTruncationResult(
        budget: Int,
    ) -> (messages: [AiChatMessage], metadata: AiChatHistoryTruncationMetadata) {
        (
            [],
            AiChatHistoryTruncationMetadata(
                includedMessageCount: 0,
                excludedMessageCount: 0,
                budget: budget,
                truncationReason: nil,
            ),
        )
    }

    private func currentUserIndex(
        in messages: [AiChatMessage],
        currentUserMessage: String,
    ) -> Array<AiChatMessage>.Index {
        messages.lastIndex { $0.role == .user && $0.content == currentUserMessage }
            ?? messages.lastIndex(where: { $0.role == .user })
            ?? messages.index(before: messages.endIndex)
    }

    private func historyChunks(
        before currentUserIndex: Array<AiChatMessage>.Index,
        in messages: [AiChatMessage],
    ) -> [[AiChatMessage]] {
        var chunks: [[AiChatMessage]] = []
        var index = messages.startIndex
        while index < currentUserIndex {
            let result = nextHistoryChunk(from: index, before: currentUserIndex, in: messages)
            chunks.append(result.chunk)
            index = result.nextIndex
        }
        return chunks
    }

    private func nextHistoryChunk(
        from index: Array<AiChatMessage>.Index,
        before currentUserIndex: Array<AiChatMessage>.Index,
        in messages: [AiChatMessage],
    ) -> (chunk: [AiChatMessage], nextIndex: Array<AiChatMessage>.Index) {
        let message = messages[index]
        let nextIndex = messages.index(after: index)
        guard message.role == .user,
              nextIndex < currentUserIndex,
              messages[nextIndex].role == .assistant
        else {
            return ([message], nextIndex)
        }
        return ([message, messages[nextIndex]], messages.index(after: nextIndex))
    }

    private func includeChunks(
        _ chunks: [[AiChatMessage]],
        protectedMessages: [AiChatMessage],
        budget: Int,
    ) -> [AiChatMessage] {
        var includedMessages = protectedMessages
        var usedCharacters = protectedMessages.reduce(0) { $0 + $1.content.count }

        for chunk in chunks.reversed() {
            let chunkCharacters = chunk.reduce(0) { $0 + $1.content.count }
            guard usedCharacters + chunkCharacters <= budget else { break }
            includedMessages.insert(contentsOf: chunk, at: 0)
            usedCharacters += chunkCharacters
        }
        return includedMessages
    }
}
