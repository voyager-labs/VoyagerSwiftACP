#if os(macOS)
import ACPModel
import Darwin
import Foundation
import os.log

actor ACPProcessManager {
    // MARK: - State

    private enum LifecycleState: Equatable {
        case idle
        case running
        case closing
        case closed
        case failed
    }

    /// Events emitted by the output pipeline. `finished` is delivered exactly
    /// once when the frame stream ends for any reason.
    enum PipelineEvent {
        case frame(Data)
        case finished
    }

    private var process: Process?
    private var processGroupId: pid_t?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var state: LifecycleState = .idle
    private var terminationEvidence: TransportTermination?

    private(set) var eventSink: (@Sendable (PipelineEvent) -> Bool)?
    private var frameFinished = false
    private var stdoutReader: FramedInput?
    private let stderrDrain: StderrDrain

    private let configuration: TransportConfiguration
    private let logger: Logger

    /// Ignores SIGPIPE process-wide so writes to a dead child's stdin surface as
    /// typed write errors instead of terminating the host.
    private static let sigpipeGuard: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    // MARK: - Initialization

    init(configuration: TransportConfiguration) {
        self.configuration = configuration
        stderrDrain = StderrDrain(byteBudget: configuration.queuedByteBudget)
        logger = Logger.forCategory("ACPProcessManager")
    }

    func setEventSink(_ sink: (@Sendable (PipelineEvent) -> Bool)?) {
        eventSink = sink
    }

    // MARK: - Lifecycle

    var isRunning: Bool {
        state == .running
    }

    var processIdentifier: Int32? {
        guard state == .running, let pid = process?.processIdentifier, pid > 0 else {
            return nil
        }
        return pid
    }

    var processGroupIdentifier: Int32? {
        guard state == .running else { return nil }
        return processGroupId
    }

    var stderrLines: AsyncStream<String>? {
        guard state == .running else { return nil }
        return stderrDrain.subscribe()
    }

    /// Terminal evidence. The reason is sticky; exit status and cleanup flags are
    /// refined as they become known.
    var termination: TransportTermination? {
        terminationEvidence
    }

    func launch(
        executablePath: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment customEnvironment: [String: String]? = nil,
    ) throws {
        guard state == .idle else {
            throw ClientError.transportFailure(.startup("process manager already owns a child"))
        }
        try configuration.validated()
        _ = Self.sigpipeGuard

        let proc = Process()

        Self.configureExecutable(proc, executablePath: executablePath, arguments: arguments)
        Self.configureEnvironment(
            proc,
            executablePath: executablePath,
            workingDirectory: workingDirectory,
            customEnvironment: customEnvironment,
        )

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdinHandle = stdin.fileHandleForWriting
        stdoutHandle = stdout.fileHandleForReading
        stderrHandle = stderr.fileHandleForReading

        do {
            try proc.run()
        } catch {
            // Startup failure: reclaim every pipe and handler that was created.
            stopReadHandlers()
            closeAllHandles()
            state = .failed
            terminationEvidence = TransportTermination(
                reason: .failure(.startup("failed to launch executable")),
                cleanupComplete: true,
            )
            throw ClientError.transportFailure(.startup("failed to launch executable"))
        }

        process = proc
        processGroupId = nil
        if proc.processIdentifier > 0 {
            let pid = proc.processIdentifier
            if setpgid(pid, pid) == 0 {
                processGroupId = pid
            } else {
                logger.warning("Failed to set process group for pid=\(pid)")
            }
        }

        proc.terminationHandler = { [weak self] terminated in
            let exitCode = terminated.terminationStatus
            Task { await self?.handleNaturalExit(exitCode: exitCode) }
        }

        state = .running
        startReadHandlers()
    }

    // MARK: - I/O

    /// Writes one raw JSON frame (the newline is appended here).
    func write(_ data: Data) async throws {
        guard state == .running, let stdin = stdinHandle else {
            throw ClientError.transportFailure(.write("process is not running"))
        }
        var lineData = data
        lineData.append(0x0A)

        // Dup the descriptor so an in-flight write stays valid even if a
        // concurrent shutdown closes the owned handle.
        let fd = Darwin.dup(stdin.fileDescriptor)
        guard fd >= 0 else {
            throw ClientError.transportFailure(.write("could not duplicate stdin descriptor"))
        }
        let payload = lineData
        defer {
            close(fd)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Blocking pipe writes run on a dedicated serial queue, never on a
            // cooperative executor or this actor.
            Self.writeQueue.async {
                switch Self.writeToFileDescriptor(fd: fd, data: payload) {
                case .success:
                    continuation.resume()
                case let .failure(failure):
                    continuation.resume(throwing: failure)
                }
            }
        }
    }

    private static let writeQueue = DispatchQueue(label: "com.acp.processmanager.write", qos: .userInitiated)

    private enum WriteOutcome {
        case success
        case failure(Error)
    }

    nonisolated private static func writeToFileDescriptor(fd: Int32, data: Data) -> WriteOutcome {
        // SIGPIPE is ignored process-wide, so a dead child's stdin surfaces as a
        // thrown error here instead of a signal.
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        do {
            try handle.write(contentsOf: data)
            return .success
        } catch {
            return .failure(ClientError.transportFailure(.write("write to child stdin failed")))
        }
    }

    // MARK: - Shutdown

    /// Bounded teardown: block new writes, close stdin, SIGTERM, wait up to 2s,
    /// SIGKILL, wait up to 1s. Returns immutable terminal evidence where
    /// `cleanupComplete` reflects whether the direct child exit was confirmed.
    func shutdown() async -> TransportTermination {
        switch state {
        case .closed:
            return terminationEvidence ?? .genericClosure()
        case .failed where process?.isRunning != true:
            return terminationEvidence ?? .genericClosure()
        case .failed, .idle:
            state = .closed
            let evidence = TransportTermination(reason: .explicitClose, cleanupComplete: true)
            terminationEvidence = evidence
            return evidence
        case .closing, .running:
            break
        }

        state = .closing
        let proc = process
        let pgid = processGroupId

        stopReadHandlers()
        stopPipelines()

        if let stdin = stdinHandle {
            try? stdin.close()
            stdinHandle = nil
        }

        if let proc, proc.isRunning {
            if let pgid {
                _ = killpg(pgid, SIGTERM)
            } else {
                proc.terminate()
            }
        }

        var exited = await waitForExit(proc, timeout: 2.0)
        if !exited, let proc, proc.processIdentifier > 0 {
            if let pgid {
                _ = killpg(pgid, SIGKILL)
            } else {
                _ = kill(proc.processIdentifier, SIGKILL)
            }
            exited = await waitForExit(proc, timeout: 1.0)
        }

        closeAllHandles()
        process = nil
        processGroupId = nil

        let evidence = shutdownEvidence(proc, exited: exited)

        settleTermination(evidence)
        emitFinished()
        finishStderrStream()
        state = exited ? .closed : .failed
        return terminationEvidence ?? evidence
    }

    private func shutdownEvidence(_ proc: Process?, exited: Bool) -> TransportTermination {
        if exited, let proc {
            let signalNumber: Int32? = proc.terminationReason == .uncaughtSignal ? proc.terminationStatus : nil
            return TransportTermination(
                reason: naturalReason ?? .explicitClose,
                exitStatus: proc.terminationStatus,
                terminationSignal: signalNumber,
                cleanupComplete: true,
            )
        } else if naturalReason == nil {
            return TransportTermination(
                reason: .failure(.shutdownTimeout),
                exitStatus: nil,
                terminationSignal: nil,
                cleanupComplete: false,
            )
        } else {
            return TransportTermination(
                reason: naturalReason ?? .explicitClose,
                exitStatus: nil,
                terminationSignal: nil,
                cleanupComplete: false,
            )
        }
    }

    private var naturalReason: TransportTermination.Reason?
    /// Exit code observed by Foundation's termination handler before the relay
    /// finished draining; the relay settles the evidence once frames are out.
    private var pendingExitCode: Int32?

    private func waitForExit(_ proc: Process?, timeout: TimeInterval) async -> Bool {
        guard let proc else { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return !proc.isRunning
    }

    // MARK: - Pipelines

    private func startReadHandlers() {
        guard let stdoutHandle else { return }
        let sink = eventSink
        let reader = FramedInput(
            handle: stdoutHandle,
            configuration: configuration,
            receive: { sink?(.frame($0)) ?? false },
            ended: { [weak self] failure in
                Task { await self?.stdoutEnded(failure) }
            },
        )
        stdoutReader = reader
        reader.start()

        let drain = stderrDrain
        stderrHandle?.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                drain.finish()
            } else {
                drain.receive(data)
            }
        }
    }

    private func stopReadHandlers() {
        stdoutReader?.stop()
        stdoutReader = nil
        stderrHandle?.readabilityHandler = nil
    }

    private func stopPipelines() {
        stderrDrain.finish()
    }

    private func stdoutEnded(_ failure: TransportFailure?) async {
        if let failure {
            settleTermination(TransportTermination(reason: .failure(failure), cleanupComplete: false))
            emitFinished()
            _ = await shutdown()
        } else {
            await stdoutPipelineEnded()
        }
    }

    /// The relay finished draining stdout. Complete frames were already yielded;
    /// now the terminal evidence is recorded and the frame stream finishes.
    private func stdoutPipelineEnded() async {
        if let exitCode = pendingExitCode {
            // Natural exit: complete frames are out, so report the exit.
            settleTermination(TransportTermination(
                reason: .processExit(exitCode),
                exitStatus: exitCode,
                terminationSignal: nil,
                cleanupComplete: true,
            ))
            emitFinished()
            finishStderrStream()
            closeAllHandles()
            state = .closed
            return
        }

        guard state == .running else {
            emitFinished()
            return
        }
        let childAlive = process?.isRunning == true
        settleTermination(TransportTermination(
            reason: childAlive ? .stdoutEOF : (process?.terminationStatus)
                .map(TransportTermination.Reason.processExit) ?? .stdoutEOF,
            exitStatus: childAlive ? nil : process?.terminationStatus,
            terminationSignal: nil,
            cleanupComplete: !childAlive,
        ))
        emitFinished()
        finishStderrStream()

        if childAlive {
            // EOF while the child is alive bounds the child teardown through the
            // regular shutdown path (state stays .running so shutdown proceeds).
            _ = await shutdown()
        } else {
            closeAllHandles()
            state = .closed
        }
    }

    /// Record process exit without cutting off unread stdout. The reader owns EOF.
    private func handleNaturalExit(exitCode: Int32) async {
        try? stdinHandle?.close()
        stdinHandle = nil

        if frameFinished {
            // The relay already ended the frame stream (EOF path); refine the
            // recorded evidence with the observed exit.
            settleTermination(TransportTermination(
                reason: naturalReason ?? .processExit(exitCode),
                exitStatus: exitCode,
                terminationSignal: nil,
                cleanupComplete: true,
            ))
            closeAllHandles()
            state = .closed
            return
        }

        pendingExitCode = exitCode
    }

    private func settleTermination(_ evidence: TransportTermination) {
        if let existing = terminationEvidence {
            // The reason is sticky; status fields are refined as they become known
            // (e.g. stdoutEOF evidence gains the exit status after the bounded kill).
            terminationEvidence = TransportTermination(
                reason: existing.reason,
                exitStatus: evidence.exitStatus ?? existing.exitStatus,
                terminationSignal: evidence.terminationSignal ?? existing.terminationSignal,
                cleanupComplete: existing.cleanupComplete || evidence.cleanupComplete,
            )
            return
        }
        terminationEvidence = evidence
        naturalReason = evidence.reason
    }

    private func emitFinished() {
        guard !frameFinished else { return }
        frameFinished = true
        _ = eventSink?(.finished)
        eventSink = nil
    }

    private func finishStderrStream() {
        stderrDrain.finish()
    }

    private func closeAllHandles() {
        stopReadHandlers()
        try? stdinHandle?.close()
        stdinHandle = nil
        if let stdout = stdoutHandle {
            try? stdout.close()
        }
        if let stderr = stderrHandle {
            try? stderr.close()
        }
        stdoutHandle = nil
        stderrHandle = nil
    }
}

private extension ACPProcessManager {
    static func configureExecutable(_ proc: Process, executablePath: String, arguments: [String]) {
        let resolvedPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: executablePath)) ??
            executablePath
        let actualPath = resolvedPath
            .hasPrefix("/") ? resolvedPath : ((executablePath as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent(resolvedPath)

        let isNodeScript: Bool = {
            guard let handle = FileHandle(forReadingAtPath: actualPath) else { return false }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 64),
                  let firstLine = String(data: data, encoding: .utf8) else { return false }
            return firstLine.hasPrefix("#!/usr/bin/env node")
        }()

        if isNodeScript {
            let searchPaths = [
                (executablePath as NSString).deletingLastPathComponent,
                (actualPath as NSString).deletingLastPathComponent,
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
            ]

            var foundNode: String?
            for searchPath in searchPaths {
                let nodePath = (searchPath as NSString).appendingPathComponent("node")
                if FileManager.default.fileExists(atPath: nodePath) {
                    foundNode = nodePath
                    break
                }
            }

            if let nodePath = foundNode {
                proc.executableURL = URL(fileURLWithPath: nodePath)
                proc.arguments = [actualPath] + arguments
            } else {
                proc.executableURL = URL(fileURLWithPath: executablePath)
                proc.arguments = arguments
            }
        } else {
            proc.executableURL = URL(fileURLWithPath: executablePath)
            proc.arguments = arguments
        }
    }

    static func configureEnvironment(
        _ proc: Process, executablePath: String, workingDirectory: String?, customEnvironment: [String: String]?,
    ) {
        var environment = ShellEnvironment.loadUserShellEnvironment()

        if let customEnvironment {
            for (key, value) in customEnvironment {
                environment[key] = value
            }
        }

        if let workingDirectory, !workingDirectory.isEmpty {
            environment["PWD"] = workingDirectory
            environment["OLDPWD"] = workingDirectory
            proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let agentDir = (executablePath as NSString).deletingLastPathComponent

        if let existingPath = environment["PATH"] {
            environment["PATH"] = "\(agentDir):\(existingPath)"
        } else {
            environment["PATH"] = agentDir
        }

        proc.environment = environment
    }
}

#endif
