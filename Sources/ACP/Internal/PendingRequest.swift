import ACPModel
import Foundation

struct PendingRequestTable<Response: Sendable> {
    struct Entry {
        let continuation: CheckedContinuation<Response, Error>
        var deadlineTask: Task<Void, Never>?
        var writeTask: Task<Void, Never>?
    }

    private(set) var entries: [RequestId: Entry] = [:]

    var count: Int {
        entries.count
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    func contains(_ id: RequestId) -> Bool {
        entries[id] != nil
    }

    func pendingIDs() -> [RequestId] {
        Array(entries.keys)
    }

    mutating func register(
        id: RequestId,
        continuation: CheckedContinuation<Response, Error>,
        deadlineTask: Task<Void, Never>? = nil,
    ) {
        entries[id] = Entry(continuation: continuation, deadlineTask: deadlineTask, writeTask: nil)
    }

    mutating func attachWriteTask(id: RequestId, task: Task<Void, Never>) {
        entries[id]?.writeTask = task
    }

    /// Settles the entry exactly once. Returns false when the id is unknown,
    /// already settled, or was never registered.
    @discardableResult
    mutating func complete(id: RequestId, _ outcome: Result<Response, Error>, cancelWrite: Bool = true) -> Bool {
        guard let entry = entries.removeValue(forKey: id) else { return false }
        entry.deadlineTask?.cancel()
        if cancelWrite { entry.writeTask?.cancel() }
        switch outcome {
        case let .success(value):
            entry.continuation.resume(returning: value)
        case let .failure(error):
            entry.continuation.resume(throwing: error)
        }
        return true
    }

    /// Fails every pending entry once (used on connection shutdown/exit).
    mutating func failAll(_ error: Error) {
        let settled = entries
        entries.removeAll()
        for entry in settled.values {
            entry.deadlineTask?.cancel()
            entry.writeTask?.cancel()
            entry.continuation.resume(throwing: error)
        }
    }

    /// Cancels deadline timers without settling the entries.
    mutating func cancelDeadlineTasks() {
        for id in entries.keys {
            entries[id]?.deadlineTask?.cancel()
        }
    }

    /// Cancels queued write tasks without settling the entries (shutdown path).
    mutating func cancelWriteTasks() {
        for id in entries.keys {
            entries[id]?.writeTask?.cancel()
        }
    }
}
