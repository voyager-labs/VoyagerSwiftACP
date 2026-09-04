import Foundation
@testable import VoyagerEntitiesAi

private final class CodexExecRawStreamFinisher: @unchecked Sendable {
    var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    func finish(with error: Error) {
        continuation?.finish(throwing: error)
    }
}

final class CodexExecFakeProcess: @unchecked Sendable {
    let stdout: [Data]
    let stderr: [Data]
    let terminationStatus: Int32
    let appendNewline: Bool
    private(set) var writes: [Data] = []
    private(set) var closeCount = 0
    private(set) var terminationCount = 0
    private(set) var stderrChunks: [Data] = []
    private(set) var cleanupCount = 0
    var onTerminate: (() -> Void)?
    var onCleanup: (() -> Void)?

    init(stdout: [Data], stderr: [Data], terminationStatus: Int32, appendNewline: Bool = true) {
        self.stdout = stdout
        self.stderr = stderr
        self.terminationStatus = terminationStatus
        self.appendNewline = appendNewline
    }

    func write(_ data: Data) {
        writes.append(data)
    }

    func closeStdin() {
        closeCount += 1
    }

    func terminate() {
        terminationCount += 1
        onTerminate?()
    }

    func recordStderr(_ data: Data) {
        stderrChunks.append(data)
    }

    func cleanup() {
        cleanupCount += 1
        onCleanup?()
    }
}

final class CodexExecControlledRunner: @unchecked Sendable {
    let process: CodexExecFakeProcess
    private let ready = CodexExecRunnerGate()
    private var stdoutContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private let stdoutFinisher = CodexExecRawStreamFinisher()
    private let stderrFinisher = CodexExecRawStreamFinisher()
    private let calls = Counter()
    private var runCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    var initialLines: [String] = []
    private(set) var rawStreamsFinished = false

    init(process: CodexExecFakeProcess) {
        self.process = process
    }

    func waitUntilReady() async {
        await ready.waitUntilStarted()
    }

    func waitUntilReady(forRunCount count: Int) async {
        await ready.waitUntilStarted(count: count)
    }

    func send(_ line: String) {
        stdoutContinuation?.yield(Data((line + "\n").utf8))
    }

    func sendChunk(_ data: Data) {
        stdoutContinuation?.yield(data)
    }

    func finishStreams() {
        stdoutContinuation?.finish()
        stderrFinisher.continuation?.finish()
    }

    var runCount: Int {
        calls.value
    }

    func waitForRunCount(_ minimum: Int) async {
        guard runCount < minimum else { return }
        await withCheckedContinuation { runCountWaiters.append((minimum, $0)) }
    }

    func run(_: CodexExecCommand) async throws -> CodexExecProcess {
        calls.increment()
        let readyWaiters = runCountWaiters.filter { $0.0 <= calls.value }
        runCountWaiters.removeAll { $0.0 <= calls.value }
        readyWaiters.forEach { $0.1.resume() }
        return CodexExecProcess(
            stdout: AsyncThrowingStream { continuation in
                self.stdoutContinuation = continuation
                self.stdoutFinisher.continuation = continuation
                for line in self.initialLines {
                    continuation.yield(Data((line + "\n").utf8))
                }
                Task { await self.ready.signalStarted() }
            },
            stderr: AsyncThrowingStream { continuation in
                self.stderrFinisher.continuation = continuation
            },
            writeStdin: { data in self.process.write(data) },
            closeStdin: { self.process.closeStdin() },
            wait: { self.process.terminationStatus },
            terminate: { self.process.terminate() },
            cleanup: {
                self.rawStreamsFinished = true
                self.stdoutFinisher.finish(with: CancellationError())
                self.stderrFinisher.finish(with: CancellationError())
                self.process.cleanup()
            },
            finishRawStreams: { error in
                self.rawStreamsFinished = true
                self.stdoutFinisher.finish(with: error)
                self.stderrFinisher.finish(with: error)
            },
        )
    }
}

final class CodexExecFakeRunner: @unchecked Sendable {
    let process: CodexExecFakeProcess
    private let calls = Counter()

    init(process: CodexExecFakeProcess) {
        self.process = process
    }

    var runCount: Int {
        calls.value
    }

    func run(_: CodexExecCommand) async throws -> CodexExecProcess {
        calls.increment()
        let process = process
        let stdoutFinisher = CodexExecRawStreamFinisher()
        let stderrFinisher = CodexExecRawStreamFinisher()
        return CodexExecProcess(
            stdout: AsyncThrowingStream { continuation in
                stdoutFinisher.continuation = continuation
                for chunk in process.stdout {
                    continuation.yield(process.appendNewline ? chunk + Data("\n".utf8) : chunk)
                }
                continuation.finish()
            },
            stderr: AsyncThrowingStream { continuation in
                stderrFinisher.continuation = continuation
                for chunk in process.stderr {
                    process.recordStderr(chunk)
                    continuation.yield(chunk)
                }
                continuation.finish()
            },
            writeStdin: { data in process.write(data) },
            closeStdin: { process.closeStdin() },
            wait: { process.terminationStatus },
            terminate: { process.terminate() },
            cleanup: { process.cleanup() },
            finishRawStreams: { error in
                stdoutFinisher.finish(with: error)
                stderrFinisher.finish(with: error)
            },
        )
    }
}

actor CodexExecCommandRecorder {
    private(set) var commands: [CodexExecCommand] = []

    func record(_ command: CodexExecCommand) {
        commands.append(command)
    }
}

actor CodexExecRunnerGate {
    private var startedCount = 0
    private var released = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var startedCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func signalStarted() {
        startedCount += 1
        let continuations = startedWaiters
        startedWaiters.removeAll()
        continuations.forEach { $0.resume() }
        let countContinuations = startedCountWaiters.filter { $0.0 <= startedCount }
        startedCountWaiters.removeAll { $0.0 <= startedCount }
        countContinuations.forEach { $0.1.resume() }
    }

    func waitUntilStarted() async {
        guard startedCount == 0 else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func waitUntilStarted(count: Int) async {
        guard startedCount < count else { return }
        await withCheckedContinuation { startedCountWaiters.append((count, $0)) }
    }

    func release() {
        released = true
        let continuations = releaseWaiters
        releaseWaiters.removeAll()
        continuations.forEach { $0.resume() }
    }

    func waitUntilReleased() async {
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }
}

final class CodexExecRaceRunner: @unchecked Sendable {
    let freshProcess: CodexExecFakeProcess
    let resumeProcess: CodexExecFakeProcess
    let freshGate: CodexExecRunnerGate
    private let calls = Counter()

    init(
        freshProcess: CodexExecFakeProcess,
        resumeProcess: CodexExecFakeProcess,
        freshGate: CodexExecRunnerGate,
    ) {
        self.freshProcess = freshProcess
        self.resumeProcess = resumeProcess
        self.freshGate = freshGate
    }

    var runCount: Int {
        calls.value
    }

    func run(command: CodexExecCommand) async throws -> CodexExecProcess {
        calls.increment()
        let process = command.arguments.contains("resume") ? resumeProcess : freshProcess
        if !command.arguments.contains("resume") {
            await freshGate.signalStarted()
            await freshGate.waitUntilReleased()
        }
        return CodexExecProcess(
            stdout: AsyncThrowingStream { continuation in
                for chunk in process.stdout {
                    continuation.yield(process.appendNewline ? chunk + Data("\n".utf8) : chunk)
                }
                continuation.finish()
            },
            stderr: AsyncThrowingStream { continuation in
                for chunk in process.stderr {
                    process.recordStderr(chunk)
                    continuation.yield(chunk)
                }
                continuation.finish()
            },
            writeStdin: { data in process.write(data) },
            closeStdin: { process.closeStdin() },
            wait: { process.terminationStatus },
            terminate: { process.terminate() },
            cleanup: { process.cleanup() },
        )
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class CodexExecInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class CodexExecAppServerEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CodexAppServerEvent] = []

    func append(_ event: CodexAppServerEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    var events: [CodexAppServerEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

actor CodexExecLifecycleCollector {
    private var events: [CodexExecLifecycleEvent] = []

    func append(_ event: CodexExecLifecycleEvent) {
        events.append(event)
    }

    func values() -> [CodexExecLifecycleEvent] {
        events
    }
}
