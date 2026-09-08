import Foundation

struct JSONLineFramer {
    struct Limits {
        let maxFrameSize: Int
        let maxBufferedBytes: Int
    }

    enum FramingFailure: Error, Equatable {
        case frameTooLarge(bytes: Int)
        case bufferOverflow(bytes: Int)
        case invalidUTF8
        case emptyFrame
        case malformedFrame(reason: String)
        case incompleteFrameAtEOF(bytes: Int)
    }

    private var buffer = Data()
    private let limits: Limits

    init(limits: Limits) {
        self.limits = limits
    }

    var bufferedByteCount: Int {
        buffer.count
    }

    /// Feeds raw bytes and returns every complete frame they completed, in order.
    mutating func feed(_ data: Data) throws -> [Data] {
        var frames: [Data] = []
        try feed(data) { frames.append($0) }
        return frames
    }

    mutating func feed(_ data: Data, receive: (Data) throws -> Void) throws {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var line = buffer.subdata(in: buffer.startIndex ..< newlineIndex)
            let consumed = buffer.distance(from: buffer.startIndex, to: newlineIndex) + 1
            buffer.removeFirst(consumed)
            if line.last == 0x0D {
                line.removeLast()
            }
            let frame = try Self.validateFrame(line, limits: limits)
            try receive(frame)
        }

        guard buffer.count <= limits.maxBufferedBytes else {
            let bytes = buffer.count
            buffer.removeAll(keepingCapacity: false)
            throw FramingFailure.bufferOverflow(bytes: bytes)
        }
    }

    /// Called when the input stream reached EOF. Throws when an incomplete frame remains.
    mutating func finish() throws -> [Data] {
        guard buffer.isEmpty else {
            let bytes = buffer.count
            buffer.removeAll(keepingCapacity: false)
            throw FramingFailure.incompleteFrameAtEOF(bytes: bytes)
        }
        return []
    }

    static func validateFrame(_ line: Data, limits: Limits) throws -> Data {
        let trimmedLine = line.trimmingWhitespace()
        if trimmedLine.isEmpty {
            throw FramingFailure.emptyFrame
        }
        guard trimmedLine.count <= limits.maxFrameSize else {
            throw FramingFailure.frameTooLarge(bytes: trimmedLine.count)
        }
        guard String(data: trimmedLine, encoding: .utf8) != nil else {
            throw FramingFailure.invalidUTF8
        }
        guard let object = try? JSONSerialization.jsonObject(with: trimmedLine) else {
            throw FramingFailure.malformedFrame(reason: "frame is not valid JSON")
        }
        guard object is [String: Any] else {
            throw FramingFailure.malformedFrame(reason: "frame is not a JSON object")
        }
        return trimmedLine
    }
}

private extension Data {
    func trimmingWhitespace() -> Data {
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0D]
        var start = startIndex
        var end = endIndex
        while start < end, whitespace.contains(self[start]) {
            start = index(after: start)
        }
        while start < end, whitespace.contains(self[index(before: end)]) {
            end = index(before: end)
        }
        guard start < end else { return Data() }
        return subdata(in: start ..< end)
    }
}
