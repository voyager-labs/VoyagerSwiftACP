import Foundation

struct SSEByteFrameAccumulator {
    private var buffer = Data()

    mutating func consume(_ byte: UInt8) throws -> [String] {
        buffer.append(byte)
        return try consumeCompletedFrames()
    }

    mutating func finish() throws -> [String] {
        guard !buffer.isEmpty else { return [] }
        let frame = buffer
        buffer.removeAll(keepingCapacity: false)
        return try payloads(from: frame)
    }

    private mutating func consumeCompletedFrames() throws -> [String] {
        var payloads: [String] = []
        while let range = nextSeparatorRange() {
            let frame = buffer[..<range.lowerBound]
            buffer.removeSubrange(..<range.upperBound)
            try payloads.append(contentsOf: self.payloads(from: Data(frame)))
        }
        return payloads
    }

    private func nextSeparatorRange() -> Range<Data.Index>? {
        let lineFeed = Data([0x0A, 0x0A])
        let carriageReturnLineFeed = Data([0x0D, 0x0A, 0x0D, 0x0A])
        let lineFeedRange = buffer.range(of: lineFeed)
        let carriageReturnLineFeedRange = buffer.range(of: carriageReturnLineFeed)

        switch (lineFeedRange, carriageReturnLineFeedRange) {
        case let (.some(lineFeedRange), .some(carriageReturnLineFeedRange)):
            return lineFeedRange.lowerBound < carriageReturnLineFeedRange.lowerBound
                ? lineFeedRange
                : carriageReturnLineFeedRange
        case let (.some(range), .none), let (.none, .some(range)):
            return range
        case (.none, .none):
            return nil
        }
    }

    private func payloads(from frame: Data) throws -> [String] {
        guard !frame.isEmpty else { return [] }
        guard let text = String(data: frame, encoding: .utf8) else {
            throw AnthropicStreamParsingError.invalidPayload
        }
        return AiChatProviderExecutionClient.ssePayloads(from: text + "\n\n")
    }
}
