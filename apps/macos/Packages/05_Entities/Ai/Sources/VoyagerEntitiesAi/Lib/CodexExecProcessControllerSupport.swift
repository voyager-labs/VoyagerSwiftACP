import Foundation

final class CodexExecLifecycleIterator: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<CodexExecLifecycleEvent, Error>.Iterator

    init(_ stream: AsyncThrowingStream<CodexExecLifecycleEvent, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> CodexExecLifecycleEvent? {
        try await iterator.next()
    }
}

final class CodexExecInvocationCancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var entry: CodexExecProcessRegistry.Entry?
    private var cancelled = false
    private var noEntry = false
    private var nonOwningWaiter = false
    private var cancellationTask: Task<Void, Never>?
    private var entryWaiters: [CheckedContinuation<CodexExecProcessRegistry.Entry?, Never>] = []
    private var onCancelled: (@Sendable () async -> Void)?
    private var preEntryCancellationSink: (@Sendable () -> Void)?

    /// entry 설치 전에 취소가 요청되면 즉시 실행되는 회수 동작을 설치한다.
    /// stdin 쓰기처럼 entry 설치 전에 차단할 수 있는 launch 구간의 소유자가 사용한다.
    func installPreEntryCancellationSink(_ sink: @escaping @Sendable () -> Void) {
        lock.lock()
        preEntryCancellationSink = sink
        let shouldStart = cancelled
        lock.unlock()
        if shouldStart { startCancellationIfNeeded() }
    }

    func install(
        entry: CodexExecProcessRegistry.Entry,
        onCancelled: @escaping @Sendable () async -> Void = {},
    ) {
        lock.lock()
        self.entry = entry
        self.onCancelled = onCancelled
        let shouldCancel = cancelled
        let waiters = entryWaiters
        entryWaiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume(returning: entry) }
        if shouldCancel { startCancellationIfNeeded() }
    }

    func completeWithoutEntry() {
        lock.lock()
        guard entry == nil else {
            lock.unlock()
            return
        }
        noEntry = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume(returning: nil) }
    }

    func markNonOwningWaiter() {
        lock.lock()
        nonOwningWaiter = true
        lock.unlock()
    }

    func install(session: CodexExecRunSession) {
        lock.lock()
        let entry = entry
        lock.unlock()
        entry?.install(session: session)
    }

    func installCancellationSink(_ sink: @escaping @Sendable () -> Void) {
        lock.lock()
        let entry = entry
        lock.unlock()
        entry?.installCancellationSink(sink)
    }

    func cancelAndWait() async {
        let cancellationTask = makeCancellationTask()
        await cancellationTask?.value
    }

    private func makeCancellationTask() -> Task<Void, Never>? {
        lock.lock()
        cancelled = true
        let task = startCancellationIfNeededLocked()
        lock.unlock()
        return task
    }

    private func startCancellationIfNeeded() {
        lock.lock()
        let task = startCancellationIfNeededLocked()
        lock.unlock()
        _ = task
    }

    private func startCancellationIfNeededLocked() -> Task<Void, Never>? {
        guard cancellationTask == nil else { return cancellationTask }
        let sink = preEntryCancellationSink
        let task = Task { [self] in
            let nonOwningWaiter = isNonOwningWaiter()
            if nonOwningWaiter {
                let onCancelled = cancellationCompletion()
                await onCancelled?()
                return
            }
            // sink는 entry 설치 전 차단 구간의 회수 전용이다. entry가 있으면
            // entry 경로가 종료를 소유하므로 이중 terminate를 만들지 않는다.
            if !hasEntry() {
                sink?()
            }
            let entry = await waitForEntry()
            await entry?.cancelAndWait()
            let onCancelled = cancellationCompletion()
            await onCancelled?()
        }
        cancellationTask = task
        return task
    }

    private func hasEntry() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entry != nil
    }

    private func waitForEntry() async -> CodexExecProcessRegistry.Entry? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let entry {
                lock.unlock()
                continuation.resume(returning: entry)
            } else if noEntry {
                lock.unlock()
                continuation.resume(returning: nil)
            } else {
                entryWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    private func cancellationCompletion() -> (@Sendable () async -> Void)? {
        lock.lock()
        let completion = onCancelled
        lock.unlock()
        return completion
    }

    private func isNonOwningWaiter() -> Bool {
        lock.lock()
        let value = nonOwningWaiter
        lock.unlock()
        return value
    }
}

final class CodexExecStderrCollector: @unchecked Sendable {
    private static let maximumRetainedBytes = CodexExecDiagnosticsBuilder.maximumStderrBytes * 2
    private let lock = NSLock()
    private var prefix = Data()
    private var suffix = Data()
    private var isTruncated = false

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        guard isTruncated else {
            return CodexExecDiagnosticsBuilder.redactAndBoundStderr(Self.decodePrefix(prefix))
        }
        let marker = "\n[TRUNCATED]\n"
        let head = CodexExecDiagnosticsBuilder.redactAndBoundStderr(
            Self.completePrefixLines(Self.decodePrefix(prefix)),
        )
        let tail = CodexExecDiagnosticsBuilder.redactAndBoundStderr(
            Self.completeSuffixLines(Self.decodeSuffix(suffix)),
        )
        let tailBudget = CodexExecDiagnosticsBuilder.maximumStderrBytes - marker.utf8.count
        let boundedTail = Self.prefixUTF8(tail, maximumBytes: tailBudget)
        let headBudget = tailBudget - boundedTail.utf8.count
        return Self.prefixUTF8(head, maximumBytes: headBudget) + marker + boundedTail
    }

    func append(_ data: Data) {
        lock.lock()
        if !isTruncated {
            let available = max(0, Self.maximumRetainedBytes - prefix.count)
            prefix.append(data.prefix(available))
            let overflow = data.dropFirst(available)
            if !overflow.isEmpty {
                isTruncated = true
                appendToSuffix(overflow)
            }
        } else {
            appendToSuffix(data)
        }
        lock.unlock()
    }

    private func appendToSuffix(_ bytes: some Collection<UInt8>) {
        let retained = bytes.suffix(Self.maximumRetainedBytes)
        let overflow = max(0, suffix.count + retained.count - Self.maximumRetainedBytes)
        suffix.removeFirst(overflow)
        suffix.append(contentsOf: retained)
    }

    private static func decodePrefix(_ data: Data) -> String {
        var bytes = data
        while !bytes.isEmpty {
            if let value = String(data: bytes, encoding: .utf8) { return value }
            bytes.removeLast()
        }
        return ""
    }

    private static func decodeSuffix(_ data: Data) -> String {
        var bytes = data
        while !bytes.isEmpty {
            if let value = String(data: bytes, encoding: .utf8) { return value }
            bytes.removeFirst()
        }
        return ""
    }

    private static func completePrefixLines(_ value: String) -> String {
        guard let newline = value.lastIndex(of: "\n") else { return "" }
        return String(value[...newline])
    }

    private static func completeSuffixLines(_ value: String) -> String {
        guard let newline = value.firstIndex(of: "\n") else { return "" }
        return String(value[value.index(after: newline)...])
    }

    private static func prefixUTF8(_ value: String, maximumBytes: Int) -> String {
        var bytes = Data(value.utf8.prefix(max(0, maximumBytes)))
        while !bytes.isEmpty {
            if let value = String(data: bytes, encoding: .utf8) { return value }
            bytes.removeLast()
        }
        return ""
    }
}

final class CodexExecTerminationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var terminated = false

    func run(_ action: () -> Void) {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return
        }
        terminated = true
        lock.unlock()
        action()
    }
}

final class CodexExecHandshakeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var pendingError: Error?

    func install(_ continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        if let pendingError {
            lock.unlock()
            continuation.resume(throwing: pendingError)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(returning value: String) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = continuation
        if continuation == nil {
            pendingError = error
        } else {
            self.continuation = nil
        }
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

final class CodexExecStreamFinishGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func run(_ action: () -> Void) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        action()
    }
}

struct CodexExecConsumeContext: @unchecked Sendable {
    let process: CodexExecProcess
    let events: AsyncThrowingStream<CodexExecDecodedEvent, Error>.Continuation
    let lifecycle: AsyncThrowingStream<CodexExecLifecycleEvent, Error>.Continuation
    let result: AsyncThrowingStream<CodexExecTerminalResult, Error>.Continuation
    let runID: String
    let handshake: CodexExecHandshakeGate
    let onEventStreamFinished: @Sendable () async -> Void
    let recordPreEventStreamEvent: @Sendable (Int) async throws -> Void
    let rawEventsEnabled: Bool
    let terminate: @Sendable () -> Void
    let onProducerFinished: @Sendable () async -> Void
    let cancelSession: @Sendable () async -> Void
    let onRawFailure: @Sendable (Error) -> Void
}

extension CodexExecProcessController {
    static func configure(
        _ process: Process,
        command: CodexExecCommand,
        input: Pipe,
        output: Pipe,
        error: Pipe,
    ) {
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
    }
}
