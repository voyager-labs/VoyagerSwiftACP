import ACPModel
import Foundation

/// Serializes bytes and EOF at the file-handle callback, before any actor hop.
/// The lock protects framing state and synchronizes stop with in-flight reads.
final class FramedInput: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private let chunkSize: Int
    private var framer: JSONLineFramer
    private var stopped = false
    private let receive: @Sendable (Data) -> Bool
    private let ended: @Sendable (TransportFailure?) -> Void

    init(
        handle: FileHandle,
        configuration: TransportConfiguration,
        receive: @escaping @Sendable (Data) -> Bool,
        ended: @escaping @Sendable (TransportFailure?) -> Void,
    ) {
        self.handle = handle
        chunkSize = min(configuration.bufferSize, configuration.queuedByteBudget)
        framer = JSONLineFramer(limits: .init(
            maxFrameSize: configuration.maxMessageSize,
            maxBufferedBytes: configuration.queuedByteBudget,
        ))
        self.receive = receive
        self.ended = ended
    }

    func start() {
        handle.readabilityHandler = { [weak self] _ in self?.readAvailable() }
    }

    func stop() {
        lock.withLock {
            stopped = true
            handle.readabilityHandler = nil
        }
    }

    private func readAvailable() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        do {
            let data = handle.availableData
            if !data.isEmpty {
                var offset = data.startIndex
                while offset < data.endIndex {
                    let end = data.index(
                        offset,
                        offsetBy: min(chunkSize, data.distance(from: offset, to: data.endIndex)),
                    )
                    try framer.feed(data.subdata(in: offset ..< end)) { frame in
                        guard receive(frame) else {
                            throw TransportFailure.bufferOverflow(frame.count)
                        }
                    }
                    offset = end
                }
                lock.unlock()
                return
            }
            _ = try framer.finish()
            stopReading(failure: nil)
        } catch {
            stopReading(failure: (error as? TransportFailure) ?? Self.failure(error))
        }
    }

    private func stopReading(failure: TransportFailure?) {
        stopped = true
        handle.readabilityHandler = nil
        lock.unlock()
        ended(failure)
    }

    static func failure(_ error: Error) -> TransportFailure {
        switch error as? JSONLineFramer.FramingFailure {
        case let .frameTooLarge(bytes): .frameLimit(bytes)
        case let .bufferOverflow(bytes): .bufferOverflow(bytes)
        case .invalidUTF8: .malformedFrame("frame is not valid UTF-8")
        case .emptyFrame: .malformedFrame("frame is empty")
        case let .malformedFrame(reason): .malformedFrame(reason)
        case .incompleteFrameAtEOF: .malformedFrame("incomplete frame at EOF")
        case nil: .read("input pipeline failed")
        }
    }
}
