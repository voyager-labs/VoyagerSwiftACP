import Foundation

public struct SSEStreamReader: AsyncSequence {
    public typealias Element = ServerSentEvent

    private let bytes: URLSession.AsyncBytes

    public init(bytes: URLSession.AsyncBytes) {
        self.bytes = bytes
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(bytesIterator: bytes.makeAsyncIterator())
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var bytesIterator: URLSession.AsyncBytes.AsyncIterator
        var parser = ServerSentEventParser()
        var buffer: [ServerSentEvent] = []
        var finished = false

        public mutating func next() async throws -> ServerSentEvent? {
            while buffer.isEmpty, !finished {
                var lineBuffer = ""
                while true {
                    guard let byte = try await bytesIterator.next() else {
                        if !lineBuffer.isEmpty {
                            lineBuffer = ""
                            finished = true
                            buffer = parser.finish()
                        }
                        finished = true
                        buffer = parser.finish()
                        break
                    }
                    if byte == UInt8(ascii: "\n") {
                        break
                    }
                    if byte == UInt8(ascii: "\r") {
                        continue
                    }
                    lineBuffer.append(UnicodeScalar(byte))
                }
                if finished { break }
                buffer = parser.ingestLine(lineBuffer)
            }

            if buffer.isEmpty {
                return nil
            }
            return buffer.removeFirst()
        }
    }
}
