import Foundation

/// Stderr is discarded until subscribed. Opt-in retention is bounded in bytes.
/// The lock guards subscription and the partial line across I/O and actor callers.
final class StderrDrain: @unchecked Sendable {
    private let lock = NSLock()
    private let byteBudget: Int
    private var output: BoundedStream<String>?
    private var buffer = Data()
    private var finished = false

    init(byteBudget: Int) {
        self.byteBudget = byteBudget
    }

    func subscribe() -> AsyncStream<String> {
        lock.withLock {
            if let output { return output.stream }
            let stream = BoundedStream<String>(byteBudget: byteBudget)
            output = stream
            if finished { stream.finish() }
            return stream.stream
        }
    }

    var bufferedByteCount: Int {
        lock.withLock { buffer.count + (output?.bufferedByteCount ?? 0) }
    }

    func receive(_ data: Data) {
        lock.withLock {
            guard !finished, let output else { return }
            guard data.count <= byteBudget - buffer.count - output.bufferedByteCount else {
                finishLocked()
                return
            }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                var line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.last == 0x0D { line.removeLast() }
                guard let text = String(data: line, encoding: .utf8) else { continue }
                guard output.yield(text, byteCount: max(1, text.utf8.count)) else {
                    finishLocked()
                    return
                }
            }
        }
    }

    func finish() {
        lock.withLock { finishLocked() }
    }

    private func finishLocked() {
        if !buffer.isEmpty, let output, let text = String(data: buffer, encoding: .utf8) {
            output.yield(text, byteCount: text.utf8.count)
        }
        buffer.removeAll()
        finished = true
        output?.finish()
    }
}
