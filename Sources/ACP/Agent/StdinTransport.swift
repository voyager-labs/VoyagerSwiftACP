import ACPModel
import Foundation

public actor StdinTransport: Transport {
    private let configuration: TransportConfiguration
    private let messageQueue: BoundedStream<Data>
    nonisolated public let messages: AsyncStream<Data>

    private let input: FileHandle
    private let output: FileHandle
    private var reader: FramedInput?
    private var running = false
    private var started = false
    private var closed = false
    private var terminationEvidence: TransportTermination?
    private let writeQueue = DispatchQueue(label: "com.acp.stdintransport.write", qos: .userInitiated)

    public var isConnected: Bool {
        running
    }

    nonisolated public var termination: TransportTermination? {
        get async { await terminationState() }
    }

    private func terminationState() -> TransportTermination? {
        terminationEvidence
    }

    public init() {
        self.init(configuration: .default)
    }

    public init(configuration: TransportConfiguration) {
        self.init(configuration: configuration, input: .standardInput, output: .standardOutput)
    }

    init(configuration: TransportConfiguration, input: FileHandle, output: FileHandle) {
        self.configuration = configuration
        self.input = input
        self.output = output
        let queue = BoundedStream<Data>(byteBudget: configuration.queuedByteBudget)
        messageQueue = queue
        messages = queue.stream
    }

    /// Start reading from stdin through an ordered, byte-bounded pipeline.
    public func start() async {
        guard !started, !closed else { return }
        started = true
        do {
            try configuration.validated()
        } catch {
            terminationEvidence = TransportTermination(
                reason: .failure(.startup("invalid transport limits")), cleanupComplete: false,
            )
            messageQueue.finish()
            return
        }
        running = true
        let queue = messageQueue
        let reader = FramedInput(
            handle: input,
            configuration: configuration,
            receive: { queue.yield($0, byteCount: $0.count) },
            ended: { [weak self] failure in
                Task { await self?.inputEnded(failure) }
            },
        )
        self.reader = reader
        reader.start()
    }

    public func send(_ data: Data) async throws {
        // Keep the writer available after a parse failure so Agent can send -32700.
        guard started, !closed else {
            throw ClientError.transportFailure(.write("agent transport is not running"))
        }
        var payload = data
        payload.append(0x0A)
        let line = payload
        let output = output
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writeQueue.async {
                do {
                    try output.write(contentsOf: line)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: ClientError.transportFailure(.write("stdout write failed")))
                }
            }
        }
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        running = false
        reader?.stop()
        reader = nil
        if terminationEvidence == nil {
            terminationEvidence = TransportTermination(reason: .explicitClose, cleanupComplete: false)
        }
        messageQueue.finish()
    }

    private func inputEnded(_ failure: TransportFailure?) {
        guard !closed else { return }
        running = false
        terminationEvidence = TransportTermination(
            reason: failure.map(TransportTermination.Reason.failure) ?? .stdoutEOF,
            cleanupComplete: false,
        )
        messageQueue.finish()
    }
}
