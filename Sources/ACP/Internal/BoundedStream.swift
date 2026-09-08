import Foundation

/// A single-consumer stream whose queued elements are limited by bytes.
/// The lock protects the queue, waiter, and terminal state across synchronous I/O callbacks.
final class BoundedStream<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let byteBudget: Int
    private var queue: [(Element, Int)?] = []
    private var head = 0
    private var bytes = 0
    private var finished = false
    private var waiter: CheckedContinuation<Element?, Never>?

    init(byteBudget: Int) {
        self.byteBudget = byteBudget
    }

    var stream: AsyncStream<Element> {
        AsyncStream(unfolding: { await self.next() }, onCancel: { self.finish(discard: true) })
    }

    var bufferedByteCount: Int {
        lock.withLock { bytes }
    }

    @discardableResult
    func yield(_ element: Element, byteCount: Int) -> Bool {
        lock.lock()
        guard !finished, byteCount >= 0, byteCount <= byteBudget - bytes else {
            lock.unlock()
            return false
        }
        if let pending = waiter {
            waiter = nil
            lock.unlock()
            pending.resume(returning: element)
        } else {
            queue.append((element, byteCount))
            bytes += byteCount
            lock.unlock()
        }
        return true
    }

    func finish(discard: Bool = false) {
        lock.lock()
        finished = true
        if discard {
            queue.removeAll()
            head = 0
            bytes = 0
        }
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume(returning: nil)
    }

    private func next() async -> Element? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if head < queue.count, let (element, count) = queue[head] {
                queue[head] = nil
                head += 1
                bytes -= count
                // Release consumed payloads without shifting the array on every read.
                if head >= 64 || head == queue.count {
                    queue.removeFirst(head)
                    head = 0
                }
                lock.unlock()
                continuation.resume(returning: element)
            } else if finished {
                lock.unlock()
                continuation.resume(returning: nil)
            } else {
                precondition(waiter == nil, "BoundedStream supports one consumer")
                waiter = continuation
                lock.unlock()
            }
        }
    }
}
