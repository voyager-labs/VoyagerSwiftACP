import ACPModel
import Foundation
import os.log

// MARK: - Debug Message Types

public enum DebugMessageDirection: Sendable {
    case outgoing
    case incoming
}

/// Metadata-only wire diagnostic. Raw payload content is exposed only when the
/// caller installed a sanitizer via `enableDebugStream(sanitizer:)`; without one,
/// `rawPreview` is always nil and no wire bytes are retained.
public struct DebugMessage: Sendable {
    public let direction: DebugMessageDirection
    public let timestamp: Date
    public let byteCount: Int
    public let method: String?
    /// Sanitizer output (never raw wire bytes). Nil when no sanitizer is installed
    /// or the sanitizer declined the payload.
    public let rawPreview: String?

    /// Compatibility view containing sanitizer output only; empty without a sanitizer.
    public var rawData: Data {
        rawPreview.map { Data($0.utf8) } ?? Data()
    }

    /// Compatibility view of the sanitized preview, never unfiltered wire JSON.
    public var jsonString: String? {
        rawPreview
    }
}

public actor Client {
    // MARK: - Properties

    private let logger = Logger.forCategory("Client")

    private let transport: any Transport
    private let configuration: ClientConfiguration
    private let requestRouter: ACPRequestRouter

    /// True when this client owns a subprocess-backed transport.
    private var isProcessBacked: Bool {
        #if os(macOS)
        return transport is StdioTransport
        #else
        return false
        #endif
    }

    private var connectionState: ClientConnectionState = .idle
    private var negotiatedInitialization: InitializeResponse?
    private var initializationInFlight = false
    private var connectionOpened = false

    private var pendingRequests = PendingRequestTable<JSONRPCResponse>()
    private var nextRequestID = 1
    /// Runs before the pending continuation resumes, so session registration
    /// cannot race subsequent ingress frames.
    private var responseSinks: [RequestId: @Sendable (JSONRPCResponse) async throws -> Void] = [:]

    private var sessions: [SessionId: SessionSnapshot] = [:]
    private var promptRequestSessions: [RequestId: SessionId] = [:]
    private var startedWrites: Set<RequestId> = []
    private var cancellationWatchers: [SessionId: Task<Void, Never>] = [:]

    private struct InboundRequestContext {
        let sessionId: SessionId?
        let method: String
        var settled = false
        var task: Task<Void, Never>?
    }

    private var inboundRequests: [RequestId: InboundRequestContext] = [:]

    private var ingressTask: Task<Void, Never>?
    private var shutdownTask: Task<TransportTermination, Never>?
    private(set) var lastTermination: TransportTermination?

    private let notificationQueue: BoundedStream<JSONRPCNotification>
    private let notificationStream: AsyncStream<JSONRPCNotification>

    private var debugContinuation: AsyncStream<DebugMessage>.Continuation?
    private var debugStream: AsyncStream<DebugMessage>?
    private var debugSanitizer: (@Sendable (Data) -> String?)?

    let decoder: JSONDecoder
    let encoder: JSONEncoder

    public weak var delegate: ClientDelegate?

    // MARK: - Initialization

    /// Creates a client over a caller-owned transport. The caller connects the
    /// transport first, then calls `start()`.
    public init(transport: any Transport, configuration: ClientConfiguration = .default) {
        self.transport = transport
        self.configuration = configuration

        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        requestRouter = ACPRequestRouter()

        let queue = BoundedStream<JSONRPCNotification>(byteBudget: configuration.notificationByteBudget)
        notificationQueue = queue
        notificationStream = queue.stream
    }

    // Creates a process-backed client. Use `launch(agentPath:...)` to spawn the
    // agent subprocess.
    #if os(macOS)
    public init() {
        self.init(configuration: .default)
    }

    public init(configuration: ClientConfiguration) {
        self.init(
            transport: StdioTransport(configuration: configuration.transport),
            configuration: configuration,
        )
    }
    #endif

    // MARK: - Public API

    public var notifications: AsyncStream<JSONRPCNotification> {
        notificationStream
    }

    public var debugMessages: AsyncStream<DebugMessage>? {
        debugStream
    }

    /// Enables the metadata-only debug stream. Without a sanitizer no wire bytes
    /// are ever retained or exposed.
    public func enableDebugStream() {
        enableDebugStream(sanitizer: nil)
    }

    /// Enables the debug stream with a caller-provided sanitizer. Raw payload
    /// bytes are surfaced only through the sanitizer's return value.
    public func enableDebugStream(sanitizer: (@Sendable (Data) -> String?)?) {
        guard debugStream == nil else { return }
        debugSanitizer = sanitizer
        var continuation: AsyncStream<DebugMessage>.Continuation!
        debugStream = AsyncStream { cont in
            continuation = cont
        }
        debugContinuation = continuation
    }

    public func disableDebugStream() {
        debugContinuation?.finish()
        debugContinuation = nil
        debugStream = nil
        debugSanitizer = nil
    }

    /// Current connection lifecycle state.
    public var state: ClientConnectionState {
        connectionState
    }

    /// The negotiated initialize response once the connection is `ready`.
    public var initialization: InitializeResponse? {
        negotiatedInitialization
    }

    /// Opaque snapshot of a tracked session.
    public func sessionSnapshot(for sessionId: SessionId) -> SessionSnapshot? {
        sessions[sessionId]
    }

    /// Installs the ingress pipeline for an injected transport. Returns after the
    /// ingress task is installed; it does not wait for the stream to end.
    public func start() async throws {
        guard !connectionOpened else {
            throw ClientError.transportError("Client already owns a connection")
        }
        connectionOpened = true
        connectionState = .connected
        installIngress()
    }

    /// Installs the ingress pipeline and spawns the agent subprocess.
    public func launch(
        agentPath: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
    ) async throws {
        guard !connectionOpened else {
            throw ClientError.transportError("Client already owns a connection")
        }
        #if os(macOS)
        guard let stdio = transport as? StdioTransport else {
            throw ClientError.transportFailure(.startup("launch requires a process-backed client"))
        }
        connectionOpened = true
        connectionState = .starting
        do {
            try await stdio.launch(
                executablePath: agentPath,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment,
            )
        } catch {
            connectionState = .failed
            throw error
        }
        connectionState = .connected
        installIngress()
        #else
        throw ClientError.transportFailure(.startup("subprocess launch is unsupported on this platform"))
        #endif
    }

    /// The running agent process identifier, when this client launched one.
    public func processIdentifier() async -> Int32? {
        #if os(macOS)
        guard let stdio = transport as? StdioTransport else { return nil }
        return await stdio.processIdentifier()
        #else
        return nil
        #endif
    }

    /// The running agent process group identifier, when process grouping succeeded.
    public func processGroupIdentifier() async -> Int32? {
        #if os(macOS)
        guard let stdio = transport as? StdioTransport else { return nil }
        return await stdio.processGroupIdentifier()
        #else
        return nil
        #endif
    }

    /// Complete stderr lines emitted by the running agent.
    public func stderrLines() async -> AsyncStream<String>? {
        #if os(macOS)
        guard let stdio = transport as? StdioTransport else { return nil }
        return await stdio.stderrLines()
        #else
        return nil
        #endif
    }

    /// Installs the delegate synchronously with respect to the connection so that
    /// callbacks arriving before or during initialization are never missed.
    public func setDelegate(_ delegate: ClientDelegate?) {
        self.delegate = delegate
        requestRouter.setDelegate(delegate)
    }

    // MARK: - Initialization

    public func initialize(
        protocolVersion: Int = 1,
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo? = nil,
        timeout: TimeInterval? = nil,
    ) async throws -> InitializeResponse {
        switch connectionState {
        case .initializing:
            throw ClientError.initializationInProgress
        case .ready:
            throw ClientError.alreadyInitialized
        case .failed:
            // A process exit surfaces as processFailed; other failures keep the
            // terminal-initialization contract.
            if let termination = lastTermination, case .processExit = termination.reason {
                throw Self.mappedTerminalError(termination)
            }
            throw ClientError.initializationFailed(terminalFailureDescription())
        case .closing, .closed:
            throw ClientError.initializationFailed("connection is closed")
        case .idle, .starting:
            throw isProcessBacked ? ClientError.processNotRunning : ClientError.notConnected
        case .connected:
            break
        }

        connectionState = .initializing
        initializationInFlight = true

        let info = clientInfo ?? ClientInfo(
            name: "ACP",
            title: "ACP Client",
            version: "1.0.0",
        )
        let request = InitializeRequest(
            protocolVersion: protocolVersion,
            clientCapabilities: capabilities,
            clientInfo: info,
        )

        do {
            let response = try await sendRequest(
                method: "initialize",
                params: request,
                timeout: timeout ?? configuration.requestTimeout,
            )
            let decoded = try decodeResult(InitializeResponse.self, from: response)

            guard decoded.protocolVersion == Self.supportedProtocolVersion else {
                let selected = decoded.protocolVersion
                await failConnection(ClientError.unsupportedProtocolVersion(selected))
                throw ClientError.unsupportedProtocolVersion(selected)
            }

            negotiatedInitialization = decoded
            initializationInFlight = false
            connectionState = .ready
            return decoded
        } catch {
            initializationInFlight = false
            let mapped = Self.mapInitializationError(error)
            await failConnection(mapped)
            throw mapped
        }
    }

    private static let supportedProtocolVersion = 1

    private static func mapInitializationError(_ error: Error) -> ClientError {
        if let clientError = error as? ClientError {
            return clientError
        }
        return ClientError.protocolViolation("initialize response could not be decoded")
    }
}

public extension Client {
    // MARK: - Session Operations

    func newSession(
        workingDirectory: String,
        additionalDirectories: [String]? = nil,
        mcpServers: [MCPServerConfig] = [],
        timeout: TimeInterval? = nil,
    ) async throws -> NewSessionResponse {
        try ensureReadyForSessionOperation()
        guard workingDirectory.hasPrefix("/") else {
            throw ClientError.invalidParams("cwd must be an absolute path")
        }
        let request = NewSessionRequest(
            cwd: workingDirectory,
            additionalDirectories: additionalDirectories,
            mcpServers: mcpServers,
        )

        let response = try await sendRequest(
            method: "session/new",
            params: request,
            timeout: timeout ?? configuration.requestTimeout,
            sink: { response in try await self.registerNewSessionResponse(response) },
        )
        return try decodeResult(NewSessionResponse.self, from: response)
    }

    /// Runs before the session/new continuation resumes so ingress never observes
    /// an untracked session id.
    private func registerNewSessionResponse(_ response: JSONRPCResponse) async throws {
        guard response.error == nil else { return }
        let decoded = try decodeResult(NewSessionResponse.self, from: response)
        if sessions[decoded.sessionId] != nil {
            throw ClientError.protocolViolation("agent reused session id")
        }
        sessions[decoded.sessionId] = SessionSnapshot(sessionId: decoded.sessionId, state: .idle, lastStopReason: nil)
    }

    func sendPrompt(
        sessionId: SessionId,
        content: [ContentBlock],
    ) async throws -> SessionPromptResponse {
        try await sendPrompt(sessionId: sessionId, content: content, timeout: nil)
    }

    func sendPrompt(
        sessionId: SessionId,
        content: [ContentBlock],
        timeout: TimeInterval?,
    ) async throws -> SessionPromptResponse {
        try ensureReadyForSessionOperation()
        guard let session = sessions[sessionId] else {
            throw ClientError.unknownSession(sessionId)
        }
        switch session.state {
        case .prompting, .cancelling:
            throw ClientError.sessionBusy(sessionId)
        case .closed:
            throw ClientError.sessionClosed(sessionId)
        case .idle:
            break
        }
        try Self.validateContentBlocks(content, against: negotiatedInitialization?.agentCapabilities)

        sessions[sessionId] = SessionSnapshot(
            sessionId: sessionId,
            state: .prompting,
            lastStopReason: session.lastStopReason,
        )

        let request = SessionPromptRequest(sessionId: sessionId, prompt: content)
        do {
            let response = try await sendRequest(
                method: "session/prompt",
                params: request,
                timeout: timeout ?? configuration.promptTimeout,
            )
            return try decodeResult(SessionPromptResponse.self, from: response)
        } catch {
            if isConnectionLive, !promptRequestSessions.values.contains(sessionId) {
                sessions[sessionId] = SessionSnapshot(
                    sessionId: sessionId,
                    state: .idle,
                    lastStopReason: sessions[sessionId]?.lastStopReason,
                )
            }
            throw error
        }
    }

    func sendCancelNotification(sessionId: SessionId) async throws {
        try await cancelSession(sessionId: sessionId)
    }

    func cancelSession(sessionId: SessionId) async throws {
        try ensureReadyForSessionOperation()
        guard let session = sessions[sessionId] else {
            throw ClientError.unknownSession(sessionId)
        }
        switch session.state {
        case .idle, .closed, .cancelling:
            // Repeated cancel, idle cancel, and closed cancel are no-ops.
            return
        case .prompting:
            break
        }

        let graceNanoseconds = try Self.deadlineNanoseconds(configuration.cancellationGrace)
        sessions[sessionId] = SessionSnapshot(
            sessionId: sessionId,
            state: .cancelling,
            lastStopReason: session.lastStopReason,
        )
        try await writeNotification(
            method: "session/cancel",
            params: CancelSessionRequest(sessionId: sessionId),
        )
        await resolvePendingPermissions(sessionId: sessionId)
        startCancellationWatcher(sessionId, nanoseconds: graceNanoseconds)
    }

    func closeSession(sessionId: SessionId) async throws -> CloseSessionResponse {
        try ensureReadyForSessionOperation()
        guard negotiatedInitialization?.agentCapabilities.sessionCapabilities?.close != nil else {
            throw ClientError.unsupportedCapability("session/close")
        }
        let request = CloseSessionRequest(sessionId: sessionId)
        let response = try await sendRequest(method: "session/close", params: request)
        let decoded = try decodeEmptyTolerantResponse(
            CloseSessionResponse.self,
            from: response,
            emptyValue: CloseSessionResponse(),
        )
        if var snapshot = sessions[sessionId] {
            snapshot = SessionSnapshot(sessionId: sessionId, state: .closed, lastStopReason: snapshot.lastStopReason)
            sessions[sessionId] = snapshot
        }
        return decoded
    }

    func loadSession(
        sessionId: SessionId,
        cwd: String,
        additionalDirectories: [String]? = nil,
        mcpServers: [MCPServerConfig] = [],
    ) async throws -> LoadSessionResponse {
        try ensureReadyForSessionOperation()
        let request = LoadSessionRequest(
            sessionId: sessionId,
            cwd: cwd,
            additionalDirectories: additionalDirectories,
            mcpServers: mcpServers,
        )

        let response = try await sendRequest(method: "session/load", params: request, sink: { response in
            await self.adoptSession(from: response, fallback: sessionId)
        })

        if let error = response.error {
            if isSessionAlreadyActive(error) {
                try registerSessionOnLoad(sessionId)
                return LoadSessionResponse(sessionId: sessionId, modes: nil, models: nil, configOptions: nil)
            }
            throw ClientError.agentError(error)
        }

        let extractedSessionId = extractSessionId(from: response.result) ?? sessionId
        let effectiveSessionId = extractedSessionId

        guard let result = response.result else {
            try registerSessionOnLoad(effectiveSessionId)
            return LoadSessionResponse(
                sessionId: effectiveSessionId,
                modes: nil,
                models: nil,
                configOptions: nil,
            )
        }

        let data = try encoder.encode(result)
        if let payload = try? decoder.decode(LoadSessionResponsePayload.self, from: data) {
            // The session table tracks the load (requested or echoed id), but the
            // returned response preserves exactly what the wire carried.
            try registerSessionOnLoad(payload.sessionId ?? effectiveSessionId)
            return LoadSessionResponse(
                sessionId: payload.sessionId,
                modes: payload.modes,
                models: payload.models,
                configOptions: payload.configOptions,
            )
        }

        if let decoded = try? decoder.decode(LoadSessionResponse.self, from: data) {
            try registerSessionOnLoad(decoded.sessionId ?? effectiveSessionId)
            return decoded
        }

        try registerSessionOnLoad(effectiveSessionId)
        return LoadSessionResponse(
            sessionId: effectiveSessionId,
            modes: nil,
            models: nil,
            configOptions: nil,
        )
    }

    func resumeSession(
        sessionId: SessionId,
        cwd: String,
        additionalDirectories: [String]? = nil,
        mcpServers: [MCPServerConfig] = [],
    ) async throws -> ResumeSessionResponse {
        try ensureReadyForSessionOperation()
        let request = ResumeSessionRequest(
            sessionId: sessionId,
            cwd: cwd,
            additionalDirectories: additionalDirectories,
            mcpServers: mcpServers,
        )

        let response = try await sendRequest(method: "session/resume", params: request, sink: { response in
            await self.adoptSession(from: response, fallback: sessionId)
        })
        let decoded = try decodeEmptyTolerantResponse(
            ResumeSessionResponse.self,
            from: response,
            emptyValue: ResumeSessionResponse(),
        )
        try registerSessionOnLoad(sessionId)
        return decoded
    }

    func forkSession(
        sessionId: SessionId,
        cwd: String,
        additionalDirectories: [String]? = nil,
        mcpServers: [MCPServerConfig] = [],
    ) async throws -> ForkSessionResponse {
        try ensureReadyForSessionOperation()
        let request = ForkSessionRequest(
            sessionId: sessionId,
            cwd: cwd,
            additionalDirectories: additionalDirectories,
            mcpServers: mcpServers,
        )

        let response = try await sendRequest(method: "session/fork", params: request, sink: { response in
            await self.adoptSession(from: response, fallback: sessionId)
        })
        let decoded = try decodeResult(ForkSessionResponse.self, from: response)
        try registerSessionOnLoad(decoded.sessionId)
        return decoded
    }

    /// Adopting sink for load/resume/fork: registers the echoed (or requested)
    /// session id before the pending continuation resumes.
    private func adoptSession(from response: JSONRPCResponse, fallback: SessionId) async {
        guard response.error == nil else { return }
        let echoed = extractSessionId(from: response.result) ?? fallback
        try? registerSessionOnLoad(echoed)
    }

    /// Marks a session registered without failing when the agent re-announced the
    /// same id for a load/resume/fork of an already tracked session.
    private func registerSessionOnLoad(_ sessionId: SessionId) throws {
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot(sessionId: sessionId, state: .idle, lastStopReason: nil)
        }
    }
}

extension Client {
    // MARK: - Request Core

    public func sendRequest(
        method: String,
        params: some Encodable,
        timeout: TimeInterval? = nil,
    ) async throws -> JSONRPCResponse {
        try await sendRequest(method: method, params: params, timeout: timeout, sink: nil)
    }

    private func sendRequest(
        method: String,
        params: some Encodable,
        timeout: TimeInterval? = nil,
        sink: (@Sendable (JSONRPCResponse) async throws -> Void)?,
    ) async throws -> JSONRPCResponse {
        try ensureRequestAllowed()
        try Task.checkCancellation()

        let requestID: Int
        do {
            requestID = try allocateRequestID()
        } catch {
            throw error
        }
        let requestIdentifier = RequestId.number(requestID)

        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)

        let request = JSONRPCRequest(
            id: requestIdentifier,
            method: method,
            params: paramsValue,
        )

        let effectiveTimeout = timeout ?? defaultTimeout(for: method)
        let deadlineNanoseconds = try effectiveTimeout.map(Self.deadlineNanoseconds)

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONRPCResponse, Error>) in
                // Actor-isolated body: registration completes before the first
                // suspension, so no response can race the registration.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if method == "session/prompt", let sessionId = Self.extractSessionID(from: paramsValue) {
                    promptRequestSessions[requestIdentifier] = sessionId
                }
                if let sink {
                    responseSinks[requestIdentifier] = sink
                }
                let deadlineTask = makeDeadlineTask(id: requestIdentifier, nanoseconds: deadlineNanoseconds)
                pendingRequests.register(id: requestIdentifier, continuation: continuation, deadlineTask: deadlineTask)
                let writeTask = Task { [weak self] () in
                    guard let self else { return }
                    await performWrite(id: requestIdentifier, request: request, method: method)
                }
                pendingRequests.attachWriteTask(id: requestIdentifier, task: writeTask)
            }
        }, onCancel: { [weak self] in
            Task { await self?.callerCancelled(requestID: requestID) }
        })
    }

    private func allocateRequestID() throws -> Int {
        let id = nextRequestID
        guard id > 0, id < Int.max else {
            throw ClientError.requestIDExhausted
        }
        nextRequestID += 1
        return id
    }

    /// Internal test hook: injects the request ID counter near exhaustion to
    /// prove the counter fails with a typed error instead of wrapping.
    func _test_setRequestIDCounter(_ value: Int) {
        nextRequestID = value
    }

    private func defaultTimeout(for method: String) -> TimeInterval? {
        method == "session/prompt" ? configuration.promptTimeout : configuration.requestTimeout
    }

    private static func deadlineNanoseconds(_ seconds: TimeInterval) throws -> UInt64 {
        let nanoseconds = seconds * 1_000_000_000
        guard nanoseconds.isFinite, nanoseconds >= 0, nanoseconds < Double(UInt64.max) else {
            throw ClientError.invalidParams("deadline must be a finite nonnegative duration within range")
        }
        return UInt64(nanoseconds)
    }

    private func makeDeadlineTask(id: RequestId, nanoseconds: UInt64?) -> Task<Void, Never>? {
        guard let nanoseconds else { return nil }
        return Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.deadlineFired(id: id)
        }
    }

    private func deadlineFired(id: RequestId) async {
        await abandonRequest(id: id, error: ClientError.requestTimeout)
    }

    private func callerCancelled(requestID: Int) async {
        await abandonRequest(id: .number(requestID), error: CancellationError())
    }

    private func abandonRequest(id: RequestId, error: Error) async {
        guard pendingRequests.contains(id) else { return }
        let sessionId = promptRequestSessions[id]
        let retainTurn = sessionId != nil && startedWrites.contains(id)
        pendingRequests.complete(id: id, .failure(error), cancelWrite: !retainTurn)
        responseSinks.removeValue(forKey: id)
        if retainTurn, let sessionId {
            do {
                try await cancelSession(sessionId: sessionId)
            } catch {
                await failConnection(.transportFailure(.write("session cancellation failed")))
            }
        } else {
            promptRequestSessions.removeValue(forKey: id)
            startedWrites.remove(id)
        }
    }

    private func performWrite(id: RequestId, request: JSONRPCRequest, method: String) async {
        guard !Task.isCancelled, pendingRequests.contains(id) else { return }
        startedWrites.insert(id)
        do {
            let frame = try encodeFrame(request)
            try await transport.send(frame)
            emitDebug(direction: .outgoing, data: frame, method: method)
        } catch {
            if pendingRequests.contains(id) {
                pendingRequests.complete(id: id, .failure(ClientError.transportFailure(.write("request write failed"))))
            }
            await failConnection(ClientError.transportFailure(.write("request write failed")))
        }
    }

    private func encodeFrame(_ message: some Encodable) throws -> Data {
        var data = try encoder.encode(message)
        data.append(0x0A)
        return data
    }
}

extension Client {
    // MARK: - Shutdown

    /// Shuts down the connection: fails pending requests, cancels inbound handlers,
    /// terminates the transport, and returns terminal evidence. Idempotent; every
    /// caller receives the same terminal result.
    public func shutdown() async -> TransportTermination {
        if let shutdownTask {
            return await shutdownTask.value
        }
        let task = Task { [weak self] in
            await self?.performShutdown() ?? TransportTermination.genericClosure()
        }
        shutdownTask = task
        defer { shutdownTask = nil }
        return await task.value
    }

    /// Compatibility API: shuts down and discards the termination evidence.
    public func terminate() async {
        _ = await shutdown()
    }

    private func performShutdown() async -> TransportTermination {
        let priorState = connectionState
        let alreadyTerminal = priorState == .closed || priorState == .failed
        if !alreadyTerminal {
            connectionState = .closing
        }

        pendingRequests.failAll(ClientError.connectionClosed)
        responseSinks.removeAll()
        promptRequestSessions.removeAll()
        startedWrites.removeAll()
        cancelInboundHandlers()
        for sessionId in sessions.keys {
            closeSessionState(sessionId)
        }
        for watcher in cancellationWatchers.values {
            watcher.cancel()
        }
        cancellationWatchers.removeAll()

        await transport.close()
        let evidence = await transport.termination ?? TransportTermination.genericClosure()
        settleTermination(evidence)

        notificationQueue.finish()
        debugContinuation?.finish()
        debugContinuation = nil
        debugStream = nil

        for sessionId in sessions.keys {
            closeSessionState(sessionId)
        }

        if !alreadyTerminal {
            connectionState = .closed
        }
        return lastTermination ?? evidence
    }

    private func closeSessionState(_ sessionId: SessionId) {
        guard let snapshot = sessions[sessionId], snapshot.state != .closed else { return }
        sessions[sessionId] = SessionSnapshot(
            sessionId: sessionId,
            state: .closed,
            lastStopReason: snapshot.lastStopReason,
        )
    }

    // MARK: - Ingress

    private func installIngress() {
        guard ingressTask == nil else { return }
        let transport = transport
        ingressTask = Task { [weak self] in
            for await frame in transport.messages {
                guard let self else { break }
                await ingest(frame)
            }
            guard let self else { return }
            await ingressDidEnd()
        }
    }

    private func ingest(_ frame: Data) async {
        guard isConnectionLive else { return }
        emitDebug(direction: .incoming, data: frame, method: Self.extractMethod(from: frame))

        let message: Message
        do {
            message = try decoder.decode(Message.self, from: frame)
        } catch {
            // A well-framed but invalid envelope from the agent is a typed
            // protocol failure followed by connection shutdown.
            await failConnection(ClientError.protocolViolation("agent sent an invalid envelope"))
            return
        }

        switch message {
        case let .response(response):
            await handleResponse(response)

        case let .notification(notification):
            await handleInboundNotification(notification)

        case let .request(request):
            dispatchInbound(request)
        }
    }

    private func handleResponse(_ response: JSONRPCResponse) async {
        guard pendingRequests.contains(response.id) || promptRequestSessions[response.id] != nil else {
            // Unknown, duplicate, or late response id: ignore without touching
            // pending state; diagnostics carry no payload.
            logger.debug("Ignoring response for unknown request id")
            return
        }
        if let sink = responseSinks.removeValue(forKey: response.id) {
            do {
                try await sink(response)
            } catch {
                pendingRequests.complete(id: response.id, .failure(error))
                if let clientError = error as? ClientError {
                    await failConnection(clientError)
                }
                return
            }
        }
        if let sessionId = promptRequestSessions.removeValue(forKey: response.id) {
            settlePromptTurn(sessionId: sessionId, response: response)
        }
        startedWrites.remove(response.id)
        pendingRequests.complete(id: response.id, .success(response))
    }

    private func handleInboundNotification(_ notification: JSONRPCNotification) async {
        if notification.method == "session/update" {
            do {
                try await validateSessionUpdate(notification)
            } catch let clientError as ClientError {
                await failConnection(clientError)
                return
            } catch {
                await failConnection(ClientError.protocolViolation("invalid session/update"))
                return
            }
        }

        let byteCount = (try? encoder.encode(notification).count) ?? 0
        guard notificationQueue.yield(notification, byteCount: byteCount) else {
            await failConnection(.protocolViolation("notification byte budget exceeded"))
            return
        }

        do {
            try await requestRouter.routeNotification(notification)
        } catch {
            // Invalid params on a known notification is a typed protocol failure.
            await failConnection(ClientError.protocolViolation("invalid notification params"))
        }
    }

    private func validateSessionUpdate(_ notification: JSONRPCNotification) async throws {
        guard let params = notification.params?.value as? [String: Any] else {
            throw ClientError.protocolViolation("session/update params must be an object")
        }
        guard let rawSessionId = params["sessionId"] as? String else {
            throw ClientError.protocolViolation("session/update is missing sessionId")
        }
        let sessionId = SessionId(rawSessionId)

        guard let updateObject = params["update"] as? [String: Any] else {
            throw ClientError.protocolViolation("session/update is missing the update object")
        }

        guard sessions[sessionId] != nil else {
            throw ClientError.protocolViolation("session/update for unknown session")
        }
        guard let variant = updateObject["sessionUpdate"] as? String else {
            throw ClientError.protocolViolation("session/update is missing discriminator")
        }
        let knownVariants: Set = [
            "user_message_chunk", "agent_message_chunk", "agent_thought_chunk",
            "tool_call", "tool_call_update", "plan", "plan_update", "plan_removed",
            "available_commands_update", "current_mode_update", "config_option_update",
            "session_info_update", "usage_update",
        ]
        guard knownVariants.contains(variant) else { return }
        let updateData = try JSONSerialization.data(withJSONObject: updateObject)
        _ = try decoder.decode(SessionUpdate.self, from: updateData)
    }

    private func dispatchInbound(_ request: JSONRPCRequest) {
        var context = InboundRequestContext(
            sessionId: Self.extractSessionID(from: request.params),
            method: request.method,
        )
        let task = Task { [weak self] () in
            guard let self else { return }
            await runInboundRequest(request)
        }
        context.task = task
        inboundRequests[request.id] = context
    }

    private func runInboundRequest(_ request: JSONRPCRequest) async {
        let outcome: Result<AnyCodable, InboundRouteError>
        do {
            let result = try await requestRouter.routeRequest(request)
            outcome = .success(result)
        } catch {
            outcome = .failure(Self.inboundRouteError(from: error))
        }
        await settleInbound(request.id, outcome)
    }

    struct InboundRouteError: Error {
        let code: Int
        let message: String
        let data: AnyCodable?
    }

    private static func inboundRouteError(from error: Error) -> InboundRouteError {
        if let jsonError = error as? JSONRPCError {
            return InboundRouteError(code: jsonError.code, message: jsonError.message, data: jsonError.data)
        }
        if let clientError = error as? ClientError {
            switch clientError {
            case .unknownMethod:
                return InboundRouteError(code: -32601, message: "Method not found", data: nil)
            case .invalidParams:
                return InboundRouteError(code: -32602, message: "Invalid params", data: nil)
            case .invalidResponse:
                return InboundRouteError(code: -32601, message: "Method not found", data: nil)
            default:
                break
            }
        }
        if error is DecodingError {
            return InboundRouteError(code: -32602, message: "Invalid params", data: nil)
        }
        // Fixed, payload-free internal error message.
        return InboundRouteError(code: -32603, message: "Internal error", data: nil)
    }

    private func settleInbound(_ id: RequestId, _ outcome: Result<AnyCodable, InboundRouteError>) async {
        guard let context = inboundRequests[id], !context.settled else {
            return
        }
        inboundRequests.removeValue(forKey: id)

        switch outcome {
        case let .success(result):
            let response = JSONRPCResponse(id: id, result: result, error: nil)
            try? await writeFrame(response)
        case let .failure(error):
            let rpcError = JSONRPCError(code: error.code, message: error.message, data: error.data)
            let response = JSONRPCResponse(id: id, result: nil, error: rpcError)
            try? await writeFrame(response)
        }
    }

    private func resolvePendingPermissions(sessionId: SessionId) async {
        let matching = inboundRequests.filter { _, context in
            !context.settled && context.sessionId == sessionId && context.method == "session/request_permission"
        }
        guard !matching.isEmpty else { return }

        for (requestId, context) in matching {
            inboundRequests.removeValue(forKey: requestId)
            context.task?.cancel()

            let outcome = RequestPermissionResponse(outcome: PermissionOutcome(cancelled: true))
            guard let outcomeData = try? encoder.encode(outcome),
                  let outcomeValue = try? decoder.decode(AnyCodable.self, from: outcomeData)
            else {
                continue
            }
            let response = JSONRPCResponse(id: requestId, result: outcomeValue, error: nil)
            try? await writeFrame(response)
        }
    }

    private func cancelInboundHandlers() {
        for (_, context) in inboundRequests {
            context.task?.cancel()
        }
        inboundRequests.removeAll()
    }

    // MARK: - Cancellation Grace

    private func startCancellationWatcher(_ sessionId: SessionId, nanoseconds: UInt64) {
        guard sessions[sessionId]?.state == .cancelling else { return }
        cancellationWatchers[sessionId]?.cancel()
        let watcher = Task { [weak self] () in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await cancellationGraceExpired(sessionId: sessionId)
        }
        cancellationWatchers[sessionId] = watcher
    }

    private func cancellationGraceExpired(sessionId: SessionId) async {
        guard sessions[sessionId]?.state == .cancelling else { return }
        // No terminal prompt response arrived within the grace period: the
        // connection is torn down and every pending request fails.
        await failConnection(ClientError.protocolViolation("cancellation grace expired"))
    }

    private func settlePromptTurn(sessionId: SessionId, response: JSONRPCResponse) {
        guard sessions[sessionId]?.state != .closed else { return }
        var stopReason: StopReason?
        if let result = response.result,
           !(result.value is NSNull),
           let data = try? encoder.encode(result),
           let decoded = try? decoder.decode(SessionPromptResponse.self, from: data)
        {
            stopReason = decoded.stopReason
        }
        sessions[sessionId] = SessionSnapshot(
            sessionId: sessionId,
            state: .idle,
            lastStopReason: stopReason ?? sessions[sessionId]?.lastStopReason,
        )
        cancellationWatchers[sessionId]?.cancel()
        cancellationWatchers.removeValue(forKey: sessionId)
    }

    // MARK: - Ingress End / Failure

    private func ingressDidEnd() async {
        // Only transport-provided evidence is authoritative; a missing evidence
        // value is a generic closure and must not win the sticky settle race
        // against the real evidence that shutdown() will produce.
        let evidence = await transport.termination
        if let evidence {
            settleTermination(evidence)
        }

        pendingRequests.failAll(mappedPendingError(for: evidence ?? TransportTermination.genericClosure()))
        responseSinks.removeAll()
        promptRequestSessions.removeAll()
        startedWrites.removeAll()
        cancelInboundHandlers()
        for sessionId in sessions.keys {
            closeSessionState(sessionId)
        }
        for watcher in cancellationWatchers.values {
            watcher.cancel()
        }
        cancellationWatchers.removeAll()

        notificationQueue.finish()

        switch connectionState {
        case .closing, .closed, .failed:
            break
        default:
            connectionState = (evidence?.isFailureLike ?? false) ? .failed : .closed
        }

        // EOF or failure while the direct child may still be alive: bound the
        // child teardown instead of leaving it running.
        if evidence?.isFailureLike == true, connectionState != .closing, connectionState != .closed {
            await transport.close()
            connectionState = .failed
        }
    }

    private func mappedPendingError(for evidence: TransportTermination) -> Error {
        Self.mappedTerminalError(evidence)
    }

    private static func mappedTerminalError(_ evidence: TransportTermination) -> Error {
        switch evidence.reason {
        case let .processExit(code):
            return ClientError.processFailed(code)
        case let .failure(failure):
            return ClientError.transportFailure(failure)
        case .stdoutEOF, .explicitClose:
            // When the direct child's exit became known later, prefer it.
            if let status = evidence.exitStatus {
                return ClientError.processFailed(status)
            }
            return ClientError.connectionClosed
        }
    }

    private func failConnection(_ error: ClientError) async {
        pendingRequests.failAll(error)
        connectionState = .closing
        responseSinks.removeAll()
        promptRequestSessions.removeAll()
        startedWrites.removeAll()
        cancelInboundHandlers()
        for sessionId in sessions.keys {
            closeSessionState(sessionId)
        }
        for watcher in cancellationWatchers.values {
            watcher.cancel()
        }
        cancellationWatchers.removeAll()
        await transport.close()
        // Only the transport's own evidence is authoritative here; a synthesized
        // placeholder must never win the sticky settle against it.
        if let evidence = await transport.termination {
            settleTermination(evidence)
        }
        notificationQueue.finish()
        connectionState = .failed
    }

    private func settleTermination(_ evidence: TransportTermination) {
        guard let existing = lastTermination else {
            lastTermination = evidence
            return
        }
        // Preserve the first terminal cause while recording subsequently
        // confirmed child exit and cleanup, as ProcessManager does.
        lastTermination = TransportTermination(
            reason: existing.reason,
            exitStatus: evidence.exitStatus ?? existing.exitStatus,
            terminationSignal: evidence.terminationSignal ?? existing.terminationSignal,
            cleanupComplete: existing.cleanupComplete || evidence.cleanupComplete,
        )
    }

    private var isConnectionLive: Bool {
        switch connectionState {
        case .connected, .initializing, .ready:
            true
        default:
            false
        }
    }

    private func terminalFailureDescription() -> String {
        if case let .processExit(code) = lastTermination?.reason {
            return "process exited with code \(code)"
        }
        return "connection failed"
    }
}

extension Client {
    // MARK: - Guards

    func ensureRequestAllowed() throws {
        switch connectionState {
        case .connected, .initializing, .ready:
            return
        case .idle, .starting:
            throw isProcessBacked ? ClientError.processNotRunning : ClientError.notConnected
        case .closing:
            throw ClientError.connectionClosed
        case .closed:
            throw ClientError.connectionClosed
        case .failed:
            if let termination = lastTermination {
                throw Self.mappedTerminalError(termination)
            }
            throw ClientError.connectionClosed
        }
    }

    private func ensureReadyForSessionOperation() throws {
        switch connectionState {
        case .ready:
            return
        case .initializing:
            throw ClientError.initializationInProgress
        case .idle, .starting, .connected:
            throw ClientError.notInitialized
        case .closing, .closed:
            throw ClientError.connectionClosed
        case .failed:
            if let termination = lastTermination {
                throw Self.mappedTerminalError(termination)
            }
            throw ClientError.connectionClosed
        }
    }

    private static func validateContentBlocks(
        _ content: [ContentBlock],
        against capabilities: AgentCapabilities?,
    ) throws {
        let promptCapabilities = capabilities?.promptCapabilities
        for block in content {
            switch block {
            case .image:
                guard promptCapabilities?.image == true else {
                    throw ClientError.unsupportedCapability("image content")
                }
            case .audio:
                guard promptCapabilities?.audio == true else {
                    throw ClientError.unsupportedCapability("audio content")
                }
            case .text, .resourceLink, .resource:
                continue
            }
        }
    }

    // MARK: - Response Decoding Helpers

    private struct LoadSessionResponsePayload: Decodable {
        let sessionId: SessionId?
        let modes: ModesInfo?
        let models: ModelsInfo?
        let configOptions: [SessionConfigOption]?
    }

    private func extractSessionId(from result: AnyCodable?) -> SessionId? {
        guard let value = result?.value else { return nil }

        if let dict = value as? [String: Any] {
            if let id = dict["sessionId"] as? String ?? dict["session_id"] as? String {
                return SessionId(id)
            }
        }

        if let dict = value as? [String: AnyCodable] {
            if let id = dict["sessionId"]?.value as? String ?? dict["session_id"]?.value as? String {
                return SessionId(id)
            }
        }

        return nil
    }

    private func decodeResult<T: Decodable>(_ type: T.Type, from response: JSONRPCResponse) throws -> T {
        if let error = response.error {
            throw ClientError.agentError(error)
        }
        guard let result = response.result, !(result.value is NSNull) else {
            throw ClientError.invalidResponse
        }
        let data = try encoder.encode(result)
        return try decoder.decode(type, from: data)
    }

    func decodeEmptyTolerantResponse<T: Decodable>(
        _ type: T.Type,
        from response: JSONRPCResponse,
        emptyValue: @autoclosure () -> T,
    ) throws -> T {
        if response.result == nil || (response.result?.value is NSNull) {
            return emptyValue()
        }

        if let dict = response.result?.value as? [String: Any], dict.isEmpty {
            return emptyValue()
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(type, from: data)
    }

    private func isSessionAlreadyActive(_ error: JSONRPCError) -> Bool {
        let message = error.message.lowercased()
        if message.contains("already active") || message.contains("already started") || message
            .contains("already exists")
        {
            return true
        }

        if let dataString = error.data?.value as? String {
            let lower = dataString.lowercased()
            if lower.contains("already active") || lower.contains("already started") || lower
                .contains("already exists")
            {
                return true
            }
        }

        if let data = error.data?.value as? [String: Any],
           let details = data["details"] as? String
        {
            let lower = details.lowercased()
            if lower.contains("already active") || lower.contains("already started") || lower
                .contains("already exists")
            {
                return true
            }
        }

        return false
    }

    // MARK: - Wire Writes

    func writeNotification(method: String, params: some Encodable) async throws {
        try ensureRequestAllowed()
        try await writeNotificationUnchecked(method: method, params: params)
    }

    private func writeNotificationUnchecked(method: String, params: some Encodable) async throws {
        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)

        let notification = JSONRPCNotification(method: method, params: paramsValue)
        try await writeFrame(notification, method: method)
    }

    private func writeFrame(_ message: some Encodable, method: String? = nil) async throws {
        let frame = try encodeFrame(message)
        try await transport.send(frame)
        emitDebug(direction: .outgoing, data: frame, method: method)
    }

    // MARK: - Diagnostics

    private func emitDebug(direction: DebugMessageDirection, data: Data, method: String?) {
        guard let debugContinuation else { return }
        let preview = debugSanitizer?(data)
        debugContinuation.yield(DebugMessage(
            direction: direction,
            timestamp: Date(),
            byteCount: data.count,
            method: method,
            rawPreview: preview,
        ))
    }

    private static func extractMethod(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["method"] as? String
    }

    private static func extractSessionID(from params: AnyCodable?) -> SessionId? {
        guard let dict = params?.value as? [String: Any],
              let raw = dict["sessionId"] as? String
        else {
            return nil
        }
        return SessionId(raw)
    }
}

extension TransportTermination {
    /// True when the termination evidence represents an ending that leaves the
    /// connection failed from the caller's perspective (typed failure, peer EOF,
    /// or direct-child exit).
    var isFailureLike: Bool {
        switch reason {
        case .failure, .stdoutEOF, .processExit:
            true
        case .explicitClose:
            false
        }
    }
}

// MARK: - Typealiases for backward compatibility

@available(*, deprecated, renamed: "Client")
public typealias ACPClient = Client
