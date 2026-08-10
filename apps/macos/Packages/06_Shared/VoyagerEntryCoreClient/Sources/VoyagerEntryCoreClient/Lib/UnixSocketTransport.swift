import Darwin
import Foundation

struct UnixSocketTransport {
    private static let responseLimit = 65536
    private static let requestTimeout = Duration.seconds(2)

    private let system: any UnixSocketSystem
    private let now: @Sendable () -> ContinuousClock.Instant

    init(
        system: any UnixSocketSystem = DarwinUnixSocketSystem(),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now },
    ) {
        self.system = system
        self.now = now
    }

    func request(_ request: Data, to endpoint: EntryCoreEndpoint) async throws -> Data {
        let deadline = now().advanced(by: Self.requestTimeout)
        let context = EntryCoreRequestContext(system: system)
        return try await context.execute { context in
            perform(request, to: endpoint, deadline: deadline, context: context)
        }
    }

    static func pollTimeoutMilliseconds(for remaining: Duration) -> Int32 {
        guard remaining > .zero else { return 0 }
        let components = remaining.components
        let wholeMilliseconds = components.seconds.multipliedReportingOverflow(by: 1000)
        if wholeMilliseconds.overflow || wholeMilliseconds.partialValue >= Int64(Int32.max) {
            return Int32.max
        }
        let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
        let roundedFraction = components.attoseconds + attosecondsPerMillisecond - 1
        let fractionalMilliseconds = roundedFraction / attosecondsPerMillisecond
        return max(1, Int32(wholeMilliseconds.partialValue + fractionalMilliseconds))
    }

    private func perform(
        _ request: Data,
        to endpoint: EntryCoreEndpoint,
        deadline: ContinuousClock.Instant,
        context: EntryCoreRequestContext,
    ) -> Result<Data, EntryCoreClientError> {
        let fd: Int32
        switch setup(context: context) {
        case let .success(socketFD):
            fd = socketFD
        case let .failure(error):
            return .failure(error)
        }
        guard let (address, addressLength) = socketAddress(for: endpoint) else {
            return .failure(.transport(.connect))
        }
        if let error = connect(
            fd,
            address: address,
            length: addressLength,
            deadline: deadline,
            context: context,
        ) {
            return .failure(error)
        }
        if let error = write(request, fd: fd, deadline: deadline, context: context) {
            return .failure(error)
        }
        if let error = terminalCheckpoint(.write, deadline: deadline, context: context) {
            return .failure(error)
        }
        guard case .success = system.shutdownWrite(fd) else {
            return .failure(context.isCancelled ? .cancelled : .transport(.write))
        }
        return read(fd: fd, deadline: deadline, context: context)
    }

    private func setup(context: EntryCoreRequestContext) -> Result<Int32, EntryCoreClientError> {
        switch system.makeWakePipe() {
        case let .success(read, write):
            context.registerWakePipe(read: read, write: write)
        case .failure:
            return .failure(context.isCancelled ? .cancelled : .transport(.connect))
        }
        guard !context.isCancelled else { return .failure(.cancelled) }
        let fd: Int32
        switch system.makeSocket() {
        case let .success(socketFD):
            fd = socketFD
            context.registerNetworkFD(socketFD)
        case .failure:
            return .failure(.transport(.connect))
        }
        guard case .success = system.setNoSigPipe(fd) else {
            return .failure(.transport(.connect))
        }
        return .success(fd)
    }

    private func socketAddress(for endpoint: EntryCoreEndpoint) -> (sockaddr_un, socklen_t)? {
        guard let pathOffset = MemoryLayout.offset(of: \sockaddr_un.sun_path) else { return nil }
        var address = sockaddr_un()
        let pathBytes = Array(endpoint.path.utf8)
        let addressLength = pathOffset + pathBytes.count + 1
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(addressLength)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }
        return (address, socklen_t(addressLength))
    }

    private func connect(
        _ fd: Int32,
        address: sockaddr_un,
        length: socklen_t,
        deadline: ContinuousClock.Instant,
        context: EntryCoreRequestContext,
    ) -> EntryCoreClientError? {
        if let error = terminalCheckpoint(.connect, deadline: deadline, context: context) { return error }
        switch connectDisposition(system.connect(fd, address: address, length: length)) {
        case .connected:
            return nil
        case let .failed(error):
            return error
        case .pending:
            break
        }
        if case let .failure(error) = wait(
            fd: fd,
            events: Int16(POLLOUT),
            phase: .connect,
            deadline: deadline,
            context: context,
        ) {
            return error
        }
        if let error = completedConnectError(system.socketError(fd)) {
            return error
        }
        return terminalCheckpoint(.connect, deadline: deadline, context: context)
    }

    private enum ConnectDisposition {
        case connected
        case pending
        case failed(EntryCoreClientError)
    }

    private func connectDisposition(_ result: UnixSocketCallResult) -> ConnectDisposition {
        switch result {
        case .success:
            .connected
        case let .failure(errorNumber) where errorNumber == ENOENT || errorNumber == ECONNREFUSED:
            .failed(.daemonUnavailable)
        case let .failure(errorNumber) where errorNumber == EINPROGRESS || errorNumber == EINTR:
            .pending
        case .failure:
            .failed(.transport(.connect))
        }
    }

    private func completedConnectError(_ result: UnixSocketCallResult) -> EntryCoreClientError? {
        switch result {
        case .success(0):
            nil
        case let .success(errorNumber) where errorNumber == ENOENT || errorNumber == ECONNREFUSED:
            .daemonUnavailable
        case .success, .failure:
            .transport(.connect)
        }
    }

    private func write(
        _ request: Data,
        fd: Int32,
        deadline: ContinuousClock.Instant,
        context: EntryCoreRequestContext,
    ) -> EntryCoreClientError? {
        var offset = 0
        while offset < request.count {
            if let error = terminalCheckpoint(.write, deadline: deadline, context: context) { return error }
            switch system.send(fd, bytes: Data(request.dropFirst(offset))) {
            case let .success(count):
                guard count > 0 else { return .transport(.write) }
                offset += Int(count)
            case let .failure(errorNumber):
                if errorNumber == EINTR { continue }
                if errorNumber == EAGAIN || errorNumber == EWOULDBLOCK {
                    if case let .failure(error) = wait(
                        fd: fd,
                        events: Int16(POLLOUT),
                        phase: .write,
                        deadline: deadline,
                        context: context,
                    ) {
                        return error
                    }
                    continue
                }
                return context.isCancelled ? .cancelled : .transport(.write)
            }
        }
        return nil
    }

    private func read(
        fd: Int32,
        deadline: ContinuousClock.Instant,
        context: EntryCoreRequestContext,
    ) -> Result<Data, EntryCoreClientError> {
        var response = Data()
        while true {
            if let error = terminalCheckpoint(.read, deadline: deadline, context: context) { return .failure(error) }
            let maximumBytes = response.count < Self.responseLimit ? Self.responseLimit - response.count : 1
            switch system.receive(fd, maximumBytes: maximumBytes) {
            case let .data(data):
                response.append(data)
                if response.count > Self.responseLimit { return .failure(.responseTooLarge) }
            case .eof:
                if let error = terminalCheckpoint(.read, deadline: deadline, context: context) {
                    return .failure(error)
                }
                return .success(response)
            case let .failure(errorNumber):
                if errorNumber == EINTR { continue }
                if errorNumber == EAGAIN || errorNumber == EWOULDBLOCK {
                    if case let .failure(error) = wait(
                        fd: fd,
                        events: Int16(POLLIN),
                        phase: .read,
                        deadline: deadline,
                        context: context,
                    ) {
                        return .failure(error)
                    }
                    continue
                }
                return .failure(context.isCancelled ? .cancelled : .transport(.read))
            }
        }
    }

    private enum WaitPollDisposition {
        case retry
        case ready(Int16)
        case failed(EntryCoreClientError)
    }

    private func wait(
        fd: Int32,
        events: Int16,
        phase: EntryCoreTransportPhase,
        deadline: ContinuousClock.Instant,
        context: EntryCoreRequestContext,
    ) -> Result<Int16, EntryCoreClientError> {
        while true {
            let timeout: Int32
            switch pollTimeout(phase: phase, deadline: deadline, context: context) {
            case let .success(milliseconds):
                timeout = milliseconds
            case let .failure(error):
                return .failure(error)
            }
            let result = system.poll(
                networkFD: fd,
                events: events,
                wakeFD: context.wakeReadDescriptor,
                timeoutMilliseconds: timeout,
            )
            switch waitDisposition(result, events: events, phase: phase, context: context) {
            case .retry:
                continue
            case let .ready(networkEvents):
                return .success(networkEvents)
            case let .failed(error):
                return .failure(error)
            }
        }
    }

    private func waitDisposition(
        _ result: UnixSocketPollResult,
        events: Int16,
        phase: EntryCoreTransportPhase,
        context: EntryCoreRequestContext,
    ) -> WaitPollDisposition {
        switch result {
        case let .ready(networkEvents, wakeEvents):
            if wakeEvents != 0 {
                system.drainWake(context.wakeReadDescriptor)
                if context.isCancelled { return .failed(.cancelled) }
            }
            if networkEvents & Int16(POLLNVAL) != 0 { return .failed(.transport(phase)) }
            if networkEvents & (events | Int16(POLLERR | POLLHUP)) != 0 { return .ready(networkEvents) }
            return .retry
        case .timedOut:
            return .failed(.timedOut(phase))
        case .failure(EINTR):
            return .retry
        case .failure:
            return .failed(context.isCancelled ? .cancelled : .transport(phase))
        }
    }

    private func pollTimeout(
        phase: EntryCoreTransportPhase,
        deadline: ContinuousClock.Instant,
        context: EntryCoreRequestContext,
    ) -> Result<Int32, EntryCoreClientError> {
        if context.isCancelled { return .failure(.cancelled) }
        let remaining = now().duration(to: deadline)
        guard remaining > .zero else { return .failure(.timedOut(phase)) }
        return .success(Self.pollTimeoutMilliseconds(for: remaining))
    }

    private func terminalCheckpoint(
        _ phase: EntryCoreTransportPhase,
        deadline: ContinuousClock.Instant,
        context: EntryCoreRequestContext,
    ) -> EntryCoreClientError? {
        if context.isCancelled { return .cancelled }
        if now() >= deadline { return .timedOut(phase) }
        return nil
    }
}
