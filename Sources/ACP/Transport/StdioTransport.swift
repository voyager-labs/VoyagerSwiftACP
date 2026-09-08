#if os(macOS)
import ACPModel
import Foundation
import os.log

public actor StdioTransport: Transport {
    // MARK: - Properties

    private let manager: ACPProcessManager
    private let configuration: TransportConfiguration

    private let messageQueue: BoundedStream<Data>
    nonisolated public let messages: AsyncStream<Data>

    // MARK: - Transport Protocol

    public var isConnected: Bool {
        get async {
            await manager.isRunning
        }
    }

    nonisolated public var termination: TransportTermination? {
        get async {
            await manager.termination
        }
    }

    // MARK: - Initialization

    public init(configuration: TransportConfiguration = .default) {
        self.configuration = configuration
        manager = ACPProcessManager(configuration: configuration)

        let queue = BoundedStream<Data>(byteBudget: configuration.queuedByteBudget)
        messages = queue.stream
        messageQueue = queue
    }

    // MARK: - Lifecycle

    /// Launch a subprocess with the given executable path and arguments.
    public func launch(
        executablePath: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
    ) async throws {
        try configuration.validated()
        try Task.checkCancellation()

        let queue = messageQueue
        await manager.setEventSink { event in
            switch event {
            case let .frame(frame):
                return queue.yield(frame, byteCount: frame.count)
            case .finished:
                queue.finish()
                return true
            }
        }
        try await manager.launch(
            executablePath: executablePath,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
        )
    }

    public func send(_ data: Data) async throws {
        try await manager.write(data)
    }

    public func close() async {
        _ = await manager.shutdown()
    }

    /// Bounded teardown returning the same immutable evidence as `termination`.
    public func shutdown() async -> TransportTermination {
        await manager.shutdown()
    }

    // MARK: - Process Introspection

    public func processIdentifier() async -> Int32? {
        await manager.processIdentifier
    }

    public func processGroupIdentifier() async -> Int32? {
        await manager.processGroupIdentifier
    }

    public func stderrLines() async -> AsyncStream<String>? {
        await manager.stderrLines
    }
}
#endif
