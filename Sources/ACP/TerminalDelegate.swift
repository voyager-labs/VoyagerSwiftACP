#if os(macOS)
import ACPModel
import Foundation

/// Tracks state of a single terminal
private struct TerminalState: @unchecked Sendable {
    let process: Process
    var outputBuffer: String = ""
    var outputByteLimit: Int?
    var lastReadIndex: Int = 0
    var isReleased: Bool = false
    var wasTruncated: Bool = false
    var exitWaiters: [CheckedContinuation<(exitCode: Int?, signal: String?), Never>] = []
    /// Per-stream UTF-8 carry so characters split across read chunks survive.
    let stdoutAssembler: UTF8Assembler
    let stderrAssembler: UTF8Assembler
}

/// Accumulates raw pipe bytes and decodes only complete UTF-8 sequences, so a
/// multi-byte character split across two read chunks is not silently dropped.
final class UTF8Assembler: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    /// Appends a raw chunk and returns the decodable prefix, keeping any
    /// truncated trailing sequence for the next chunk. Bytes that are invalid
    /// UTF-8 outright decode as U+FFFD instead of being dropped.
    func decoded(byAppending data: Data) -> String? {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        let split = Self.validPrefixEnd(of: pending)
        guard split > 0 else { return nil }
        let chunk = Data(pending.prefix(split))
        pending = Data(pending.dropFirst(split))
        return String(data: chunk, encoding: .utf8) ?? String(decoding: chunk, as: UTF8.self)
    }

    /// Decodes whatever remains at EOF; invalid bytes become U+FFFD
    /// replacement characters instead of being discarded.
    func flushRemaining() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        let remainder = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return remainder
    }

    /// Byte length of the decodable prefix. A truncated multi-byte sequence
    /// can only sit at the tail, so scanning back three bytes suffices.
    static func validPrefixEnd(of data: Data) -> Int {
        let count = data.count
        guard count > 0 else { return 0 }
        var index = max(count - 3, 0)
        while index < count {
            let byte = data[data.startIndex + index]
            let sequenceLength = if byte & 0b1111_1000 == 0b1111_0000 {
                4
            } else if byte & 0b1111_0000 == 0b1110_0000 {
                3
            } else if byte & 0b1110_0000 == 0b1100_0000 {
                2
            } else {
                0
            }
            if sequenceLength > 0, index + sequenceLength > count {
                return index
            }
            index += 1
        }
        return count
    }
}

/// Cached output for released terminals
private struct ReleasedTerminalOutput {
    let output: String
    let exitCode: Int?
}

/// Actor responsible for handling terminal operations for agent sessions
public actor TerminalDelegate {
    // MARK: - Errors

    public enum TerminalError: LocalizedError, Sendable {
        case terminalNotFound(String)
        case terminalReleased(String)
        case executableNotFound(String)
        case commandParsingFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .terminalNotFound(id):
                "Terminal with ID '\(id)' not found"
            case let .terminalReleased(id):
                "Terminal with ID '\(id)' has been released"
            case let .executableNotFound(path):
                "Executable not found: '\(path)'"
            case let .commandParsingFailed(command):
                "Failed to parse command string: '\(command)'"
            }
        }
    }

    // MARK: - Private Properties

    private var terminals: [String: TerminalState] = [:]
    private var releasedOutputs: [String: ReleasedTerminalOutput] = [:]
    private var releasedOutputOrder: [String] = []
    private let defaultOutputByteLimit = 1_000_000
    /// Peer-supplied limits are clamped so a terminal cannot grow without bound.
    private let maxOutputByteLimit = 64_000_000
    private let maxReleasedOutputEntries = 50
    private static let termGraceSeconds: TimeInterval = 2.0
    private static let killGraceSeconds: TimeInterval = 1.0
    private static let drainGraceSeconds: TimeInterval = 0.5
    private static let maxDrainOutputBytes = 1_000_000

    // MARK: - Private Cleanup

    /// Drains remaining pipe output on a worker with a hard deadline. A
    /// descendant that inherited the write end keeps the pipe open without
    /// EOF after the direct child exits, so this must never block the actor
    /// synchronously: whatever arrives within the window is kept, the rest is
    /// dropped when the pipes are closed.
    private func boundedDrain(_ pipe: Pipe, assembler: UTF8Assembler, terminalId: String) async {
        pipe.fileHandleForReading.readabilityHandler = nil
        let handle = pipe.fileHandleForReading
        let result = DrainResult()
        DispatchQueue.global(qos: .utility).async {
            var collected = 0
            while collected < Self.maxDrainOutputBytes {
                let chunk = (try? handle.read(upToCount: 65536)) ?? Data()
                guard !chunk.isEmpty else { break }
                collected += chunk.count
                if let output = assembler.decoded(byAppending: chunk) {
                    result.append(output)
                }
            }
            if let remainder = assembler.flushRemaining() {
                result.append(remainder)
            }
            result.finish()
        }

        let deadline = Date().addingTimeInterval(Self.drainGraceSeconds)
        while !result.isFinished, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let output = result.snapshot
        if !output.isEmpty {
            appendOutput(terminalId: terminalId, output: output)
        }
    }

    private func cancelPipeHandlers(_ process: Process) {
        if let outputPipe = process.standardOutput as? Pipe {
            outputPipe.fileHandleForReading.readabilityHandler = nil
        }
        if let errorPipe = process.standardError as? Pipe {
            errorPipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func closeProcessPipes(_ process: Process) {
        if let outputPipe = process.standardOutput as? Pipe {
            try? outputPipe.fileHandleForReading.close()
        }
        if let errorPipe = process.standardError as? Pipe {
            try? errorPipe.fileHandleForReading.close()
        }
    }

    /// Thread-safe drain outcome shared between the worker and the actor.
    private final class DrainResult: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = ""
        private var finished = false

        func append(_ text: String) {
            lock.withLock { storage += text }
        }

        func finish() {
            lock.withLock { finished = true }
        }

        var snapshot: String {
            lock.withLock { storage }
        }

        var isFinished: Bool {
            lock.withLock { finished }
        }
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Terminal Operations

    /// Create a new terminal process
    public func handleTerminalCreate(
        command: String,
        sessionId _: String,
        args: [String]?,
        cwd: String?,
        env: [EnvVariable]?,
        outputByteLimit: Int?,
    ) async throws -> CreateTerminalResponse {
        var executablePath: String
        var finalArgs: [String]

        let shellOperators = ["|", "&&", "||", ";", ">", ">>", "<", "$(", "`", "&"]
        let needsShell = shellOperators.contains { command.contains($0) }

        if needsShell {
            executablePath = "/bin/sh"
            if let args, !args.isEmpty {
                finalArgs = ["-c", ([command] + args).joined(separator: " ")]
            } else {
                finalArgs = ["-c", command]
            }
        } else if args == nil || args?.isEmpty == true {
            if command.contains(" ") || command.contains("\"") {
                let (parsedExecutable, parsedArgs) = try parseCommandString(command)
                executablePath = try resolveExecutablePath(parsedExecutable)
                finalArgs = parsedArgs
            } else {
                executablePath = try resolveExecutablePath(command)
                finalArgs = []
            }
        } else {
            executablePath = try resolveExecutablePath(command)
            finalArgs = args ?? []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = finalArgs

        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        var envDict = ShellEnvironment.loadUserShellEnvironment()
        if let envVars = env {
            for envVar in envVars {
                envDict[envVar.name] = envVar.value
            }
        }
        process.environment = envDict

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminalIdValue = UUID().uuidString
        let terminalId = TerminalId(terminalIdValue)

        let stdoutAssembler = UTF8Assembler()
        let stderrAssembler = UTF8Assembler()

        let state = TerminalState(
            process: process,
            outputByteLimit: Self.validatedOutputByteLimit(
                outputByteLimit,
                defaultLimit: defaultOutputByteLimit,
                maxLimit: maxOutputByteLimit,
            ),
            stdoutAssembler: stdoutAssembler,
            stderrAssembler: stderrAssembler,
        )
        terminals[terminalIdValue] = state

        outputPipe.fileHandleForReading.readabilityHandler = makeOutputHandler(
            assembler: stdoutAssembler,
            terminalId: terminalIdValue,
        )

        errorPipe.fileHandleForReading.readabilityHandler = makeOutputHandler(
            assembler: stderrAssembler,
            terminalId: terminalIdValue,
        )

        do {
            try process.run()
        } catch {
            // Roll the whole terminal back: a failed launch must not leak the
            // retained Process, pipe handles, or readability handlers.
            terminals.removeValue(forKey: terminalIdValue)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            throw error
        }

        return CreateTerminalResponse(terminalId: terminalId, _meta: nil)
    }

    /// One readability handler per pipe: decodes through the stream's UTF-8
    /// assembler so multi-byte characters split across read chunks are
    /// preserved, and flushes any remainder at EOF.
    private func makeOutputHandler(
        assembler: UTF8Assembler,
        terminalId: String,
    ) -> @Sendable (FileHandle) -> Void {
        { [weak self] handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    if let remainder = assembler.flushRemaining() {
                        Task {
                            await self?.appendOutput(terminalId: terminalId, output: remainder)
                        }
                    }
                    try? handle.close()
                    return
                }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    if let remainder = assembler.flushRemaining() {
                        Task {
                            await self?.appendOutput(terminalId: terminalId, output: remainder)
                        }
                    }
                    try? handle.close()
                    return
                }
                if let output = assembler.decoded(byAppending: data) {
                    Task {
                        await self?.appendOutput(terminalId: terminalId, output: output)
                    }
                }
            } catch {
                handle.readabilityHandler = nil
            }
        }
    }

    /// Get output from a terminal process
    public func handleTerminalOutput(
        terminalId: TerminalId,
        sessionId _: String,
    ) async throws -> TerminalOutputResponse {
        // The readability handlers are the only readers of the output pipes, so
        // this returns the actor-owned buffer snapshot instead of re-reading a
        // live pipe (a blocking read here would stall the whole actor).
        guard let state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        let exitStatus: TerminalExitStatus? = if state.process.isRunning {
            nil
        } else {
            TerminalExitStatus(
                exitCode: Int(state.process.terminationStatus),
                signal: nil,
                _meta: nil,
            )
        }

        return TerminalOutputResponse(
            output: state.outputBuffer,
            exitStatus: exitStatus,
            truncated: state.wasTruncated,
            _meta: nil,
        )
    }

    /// Wait for a terminal process to exit
    public func handleTerminalWaitForExit(
        terminalId: TerminalId,
        sessionId _: String,
    ) async throws -> WaitForExitResponse {
        guard let state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        if !state.process.isRunning {
            return WaitForExitResponse(
                exitCode: Int(state.process.terminationStatus),
                signal: nil,
                _meta: nil,
            )
        }

        let result = await withCheckedContinuation { continuation in
            var waiterState = state
            waiterState.exitWaiters.append(continuation)
            terminals[terminalId.value] = waiterState

            Task {
                await self.monitorProcessExit(terminalId: terminalId)
            }
        }

        return WaitForExitResponse(
            exitCode: result.exitCode,
            signal: result.signal,
            _meta: nil,
        )
    }

    /// Kill a terminal process
    public func handleTerminalKill(terminalId: TerminalId, sessionId _: String) async throws -> KillTerminalResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        _ = await boundedTeardown(state.process)

        let exitCode = terminalExitCode(state.process)
        for waiter in state.exitWaiters {
            waiter.resume(returning: (exitCode, nil))
        }
        state.exitWaiters.removeAll()
        terminals[terminalId.value] = state

        return KillTerminalResponse(_meta: nil)
    }

    /// Release a terminal process
    public func handleTerminalRelease(
        terminalId: TerminalId,
        sessionId _: String,
    ) async throws -> ReleaseTerminalResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        let didExit = await boundedTeardown(state.process)

        // Only drain remaining pipe bytes once the process has exited, and
        // even then through the bounded window: a descendant that inherited
        // the write end can keep the pipe open without EOF indefinitely.
        if didExit {
            if let outputPipe = state.process.standardOutput as? Pipe {
                await boundedDrain(outputPipe, assembler: state.stdoutAssembler, terminalId: terminalId.value)
            }
            if let errorPipe = state.process.standardError as? Pipe {
                await boundedDrain(errorPipe, assembler: state.stderrAssembler, terminalId: terminalId.value)
            }
        }
        cancelPipeHandlers(state.process)
        closeProcessPipes(state.process)
        state = terminals[terminalId.value] ?? state

        let exitCode = terminalExitCode(state.process)
        for waiter in state.exitWaiters {
            waiter.resume(returning: (exitCode, nil))
        }

        cacheReleasedOutput(
            terminalId: terminalId.value,
            output: state.outputBuffer,
            exitCode: exitCode,
        )

        state.isReleased = true
        state.exitWaiters.removeAll()
        terminals.removeValue(forKey: terminalId.value)

        return ReleaseTerminalResponse(_meta: nil)
    }

    /// Clean up all terminals
    public func cleanup() async {
        for (terminalId, state) in terminals {
            let didExit = await boundedTeardown(state.process)
            if didExit {
                if let outputPipe = state.process.standardOutput as? Pipe {
                    await boundedDrain(outputPipe, assembler: state.stdoutAssembler, terminalId: terminalId)
                }
                if let errorPipe = state.process.standardError as? Pipe {
                    await boundedDrain(errorPipe, assembler: state.stderrAssembler, terminalId: terminalId)
                }
            }
            cancelPipeHandlers(state.process)
            closeProcessPipes(state.process)
            let exitCode = terminalExitCode(state.process)
            for waiter in state.exitWaiters {
                waiter.resume(returning: (exitCode, nil))
            }
        }
        terminals.removeAll()
        releasedOutputs.removeAll()
        releasedOutputOrder.removeAll()
    }

    // MARK: - Public Helpers

    /// Get terminal output for display
    public func getOutput(terminalId: TerminalId) -> String? {
        if let state = terminals[terminalId.value] {
            return terminals[terminalId.value]?.outputBuffer ?? state.outputBuffer
        }
        return releasedOutputs[terminalId.value]?.output
    }

    /// Check if terminal is still running
    public func isRunning(terminalId: TerminalId) -> Bool {
        terminals[terminalId.value]?.process.isRunning ?? false
    }

    /// Test-visible size of the live terminal table (regression coverage for
    /// launch-failure rollback).
    var activeTerminalCount: Int {
        terminals.count
    }

    /// Peer-supplied limits are untrusted: negatives fall back to the default
    /// and oversized requests clamp to the package maximum.
    private static func validatedOutputByteLimit(_ requested: Int?, defaultLimit: Int, maxLimit: Int) -> Int {
        guard let requested else { return defaultLimit }
        guard requested >= 0 else { return defaultLimit }
        return min(requested, maxLimit)
    }

    /// TERM → bounded wait → KILL → bounded wait, mirroring
    /// `ACPProcessManager.shutdown()`. A process that ignores SIGTERM can never
    /// block this actor indefinitely.
    private func boundedTeardown(_ process: Process) async -> Bool {
        guard process.isRunning else { return true }

        process.terminate()
        if await waitForExit(process, timeout: Self.termGraceSeconds) {
            return true
        }
        if process.processIdentifier > 0 {
            kill(process.processIdentifier, SIGKILL)
        }
        return await waitForExit(process, timeout: Self.killGraceSeconds)
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return !process.isRunning
    }

    /// `terminationStatus` is undefined while the process runs; report a forced
    /// SIGKILL instead of reading stale state.
    private func terminalExitCode(_ process: Process) -> Int {
        process.isRunning ? Int(SIGKILL) : Int(process.terminationStatus)
    }

    // MARK: - Private Helpers

    private func appendOutput(terminalId: String, output: String) {
        guard var state = terminals[terminalId] else { return }

        state.outputBuffer += output

        if let limit = state.outputByteLimit {
            let byteCount = state.outputBuffer.utf8.count
            if byteCount > limit {
                state.outputBuffer = Self.truncatedKeepingTail(state.outputBuffer, byteCount: byteCount, limit: limit)
                state.wasTruncated = true
            }
        }

        terminals[terminalId] = state
    }

    /// Drops whole leading characters until the buffer fits the byte limit, so
    /// truncation never splits a multi-byte UTF-8 sequence.
    private static func truncatedKeepingTail(_ buffer: String, byteCount: Int, limit: Int) -> String {
        var droppedBytes = 0
        var index = buffer.startIndex
        while droppedBytes < byteCount - limit, index < buffer.endIndex {
            droppedBytes += buffer[index].utf8.count
            index = buffer.index(after: index)
        }
        return String(buffer[index...])
    }

    private func cacheReleasedOutput(terminalId: String, output: String, exitCode: Int) {
        releasedOutputs[terminalId] = ReleasedTerminalOutput(output: output, exitCode: exitCode)
        releasedOutputOrder.removeAll { $0 == terminalId }
        releasedOutputOrder.append(terminalId)

        while releasedOutputOrder.count > maxReleasedOutputEntries,
              let oldest = releasedOutputOrder.first
        {
            releasedOutputOrder.removeFirst()
            releasedOutputs.removeValue(forKey: oldest)
        }
    }

    private func monitorProcessExit(terminalId: TerminalId) async {
        guard let state = terminals[terminalId.value] else { return }
        let process = state.process

        while process.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard terminals[terminalId.value] != nil else { return }
        }

        guard var currentState = terminals[terminalId.value],
              !currentState.exitWaiters.isEmpty else { return }

        let exitCode = Int(process.terminationStatus)
        for waiter in currentState.exitWaiters {
            waiter.resume(returning: (exitCode, nil))
        }
        currentState.exitWaiters.removeAll()
        terminals[terminalId.value] = currentState
    }
}

// MARK: - Command Resolution

extension TerminalDelegate {
    private func parseCommandString(_ command: String) throws -> (String, [String]) {
        var executable: String?
        var args: [String] = []
        var currentArg = ""
        var inQuotes = false
        var escapeNext = false

        for char in command {
            if escapeNext {
                currentArg.append(char)
                escapeNext = false
                continue
            }

            if char == "\\" {
                escapeNext = true
                continue
            }

            if char == "\"" {
                inQuotes.toggle()
                continue
            }

            if char == " ", !inQuotes {
                if !currentArg.isEmpty {
                    if executable == nil {
                        executable = currentArg
                    } else {
                        args.append(currentArg)
                    }
                    currentArg = ""
                }
                continue
            }

            currentArg.append(char)
        }

        if !currentArg.isEmpty {
            if executable == nil {
                executable = currentArg
            } else {
                args.append(currentArg)
            }
        }

        guard let exec = executable, !exec.isEmpty else {
            throw TerminalError.commandParsingFailed(command)
        }

        return (exec, args)
    }

    private func resolveExecutablePath(_ command: String) throws -> String {
        let fileManager = FileManager.default

        if command.hasPrefix("/") {
            if fileManager.fileExists(atPath: command) {
                return command
            }
            throw TerminalError.executableNotFound(command)
        }

        let commonPaths = [
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/opt/local/bin/\(command)",
        ]

        for path in commonPaths where fileManager.fileExists(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe

        defer {
            try? pipe.fileHandleForReading.close()
        }

        do {
            try process.run()
            process.waitUntilExit()
            if let data = try? pipe.fileHandleForReading.read(upToCount: 4096),
               let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            {
                if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
        } catch {
            // Fallback if 'which' fails
        }

        throw TerminalError.executableNotFound(command)
    }
}

// MARK: - Typealiases for backward compatibility

@available(*, deprecated, renamed: "TerminalDelegate")
public typealias ACPTerminalDelegate = TerminalDelegate
#endif
