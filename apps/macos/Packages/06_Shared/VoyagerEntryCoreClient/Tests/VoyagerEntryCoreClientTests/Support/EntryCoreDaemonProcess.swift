import Darwin
import Dispatch
import Foundation
import os

struct EntryCoreDaemonProcessExit {
    let pid: Int32
    let status: Int32
    let reaped: Bool
    let usedSIGKILL: Bool
    let stdout: String
    let stderr: String
}

enum EntryCoreDaemonProcessError: Error {
    case missingExecutableEnvironment
    case invalidExecutable
    case invalidTemporaryRoot
    case launchFailed(Error)
    case exitedBeforeReadiness(EntryCoreDaemonProcessExit)
    case readinessTimedOut(EntryCoreDaemonProcessExit)
    case terminationTimedOut
    case forcedKill(EntryCoreDaemonProcessExit)
    case nonCleanExit(EntryCoreDaemonProcessExit)
    case processNotReaped(EntryCoreDaemonProcessExit)
    case socketRemained(EntryCoreDaemonProcessExit)
}

enum EntryCoreDaemonSocketCallResult: Equatable {
    case success(Int32)
    case failure(Int32)
}

enum EntryCoreDaemonSocketPollResult: Equatable {
    case ready(Int16)
    case timedOut
    case failure(Int32)
}

protocol EntryCoreDaemonSocketSystem {
    func makeNonblockingSocket() -> EntryCoreDaemonSocketCallResult
    func connect(_ descriptor: Int32, address: sockaddr_un, length: socklen_t) -> EntryCoreDaemonSocketCallResult
    func poll(_ descriptor: Int32, events: Int16, timeoutMilliseconds: Int32) -> EntryCoreDaemonSocketPollResult
    func socketError(_ descriptor: Int32) -> EntryCoreDaemonSocketCallResult
    func shutdownWrite(_ descriptor: Int32)
    func close(_ descriptor: Int32)
}

struct DarwinEntryCoreDaemonSocketSystem: EntryCoreDaemonSocketSystem {
    func makeNonblockingSocket() -> EntryCoreDaemonSocketCallResult {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .failure(errno) }
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            let errorNumber = errno
            Darwin.close(descriptor)
            return .failure(errorNumber)
        }
        return .success(descriptor)
    }

    func connect(
        _ descriptor: Int32,
        address: sockaddr_un,
        length: socklen_t,
    ) -> EntryCoreDaemonSocketCallResult {
        var mutableAddress = address
        let result = withUnsafePointer(to: &mutableAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, length)
            }
        }
        return result == 0 ? .success(0) : .failure(errno)
    }

    func poll(
        _ descriptor: Int32,
        events: Int16,
        timeoutMilliseconds: Int32,
    ) -> EntryCoreDaemonSocketPollResult {
        var pollDescriptor = pollfd(fd: descriptor, events: events, revents: 0)
        let result = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
        if result > 0 { return .ready(pollDescriptor.revents) }
        return result == 0 ? .timedOut : .failure(errno)
    }

    func socketError(_ descriptor: Int32) -> EntryCoreDaemonSocketCallResult {
        var value: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        let result = withUnsafeMutablePointer(to: &value) {
            getsockopt(descriptor, SOL_SOCKET, SO_ERROR, $0, &length)
        }
        return result == 0 ? .success(value) : .failure(errno)
    }

    func shutdownWrite(_ descriptor: Int32) {
        _ = Darwin.shutdown(descriptor, SHUT_WR)
    }

    func close(_ descriptor: Int32) {
        Darwin.close(descriptor)
    }
}

final class EntryCoreDaemonProcess {
    private static let executableEnvironmentKey = "VOYAGER_ENTRY_CORE_DAEMON_PATH"
    private static let readinessTimeout: TimeInterval = 15
    private static let readinessRetryTick = DispatchTimeInterval.milliseconds(25)
    private static let terminationTimeout: TimeInterval = 5
    private static let forcedTerminationTimeout: TimeInterval = 3

    let pid: Int32

    private let process: Process
    private let socketURL: URL
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let eventSemaphore = DispatchSemaphore(value: 0)
    private let exitObserved = OSAllocatedUnfairLock(initialState: false)
    private var directorySource: DispatchSourceFileSystemObject?
    private var processSource: DispatchSourceProcess?
    private var capturedExit: EntryCoreDaemonProcessExit?

    private init(executableURL: URL, socketURL: URL) throws {
        process = Process()
        self.socketURL = socketURL
        stdoutPipe = Pipe()
        stderrPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["--socket", socketURL.path]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw EntryCoreDaemonProcessError.launchFailed(error)
        }
        pid = process.processIdentifier
        installEventSources()
    }

    deinit {
        directorySource?.cancel()
        processSource?.cancel()
    }

    static func requiredExecutableURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) throws -> URL {
        guard
            let path = environment[executableEnvironmentKey],
            !path.isEmpty,
            path.first == "/"
        else {
            throw EntryCoreDaemonProcessError.missingExecutableEnvironment
        }

        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            !isDirectory.boolValue,
            FileManager.default.isExecutableFile(atPath: path)
        else {
            throw EntryCoreDaemonProcessError.invalidExecutable
        }
        return URL(fileURLWithPath: path)
    }

    static func makeTemporaryRoot() throws -> URL {
        var template = Array("/tmp/ec-XXXXXX".utf8CString)
        guard let createdPath = mkdtemp(&template) else {
            throw EntryCoreDaemonProcessError.invalidTemporaryRoot
        }
        let path = String(cString: createdPath)
        guard chmod(path, 0o700) == 0 else {
            _ = rmdir(path)
            throw EntryCoreDaemonProcessError.invalidTemporaryRoot
        }

        var metadata = stat()
        guard
            lstat(path, &metadata) == 0,
            metadata.st_uid == geteuid(),
            metadata.st_mode & S_IFMT == S_IFDIR,
            metadata.st_mode & 0o777 == 0o700
        else {
            _ = rmdir(path)
            throw EntryCoreDaemonProcessError.invalidTemporaryRoot
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func start(
        socketURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = readinessTimeout,
    ) throws -> EntryCoreDaemonProcess {
        let executableURL = try requiredExecutableURL(environment: environment)
        let daemon = try EntryCoreDaemonProcess(executableURL: executableURL, socketURL: socketURL)
        do {
            try daemon.waitUntilReady(timeout: timeout)
            return daemon
        } catch {
            daemon.stopDirectoryObservation()
            throw error
        }
    }

    static func isProcessAbsent(_ pid: Int32) -> Bool {
        errno = 0
        return kill(pid, 0) == -1 && errno == ESRCH
    }

    func terminate(timeout: TimeInterval = terminationTimeout) throws -> EntryCoreDaemonProcessExit {
        if let capturedExit {
            return try validateCleanExit(capturedExit)
        }

        process.terminate()
        if let exit = waitForExit(timeout: timeout, usedSIGKILL: false) {
            return try validateCleanExit(exit)
        }

        let exit = try forceTerminationAfterTimeout()
        if exit.usedSIGKILL {
            throw EntryCoreDaemonProcessError.forcedKill(exit)
        }
        return try validateCleanExit(exit)
    }

    func cleanup(timeout: TimeInterval = terminationTimeout) throws {
        _ = try terminate(timeout: timeout)
    }

    private func installEventSources() {
        let queue = DispatchQueue(label: "voyager.entry-core.process.\(pid)")
        let directoryDescriptor = open(socketURL.deletingLastPathComponent().path, O_EVTONLY)
        if directoryDescriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: directoryDescriptor,
                eventMask: [.write, .delete, .rename],
                queue: queue,
            )
            source.setEventHandler { [eventSemaphore] in
                eventSemaphore.signal()
            }
            source.setCancelHandler {
                Darwin.close(directoryDescriptor)
            }
            directorySource = source
            source.resume()
        }

        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: queue,
        )
        source.setEventHandler { [eventSemaphore, exitObserved] in
            exitObserved.withLock { $0 = true }
            eventSemaphore.signal()
        }
        processSource = source
        source.resume()
    }

    private func waitUntilReady(timeout: TimeInterval) throws {
        let deadline = dispatchDeadline(after: timeout)
        switch Self.waitForSocketReadiness(
            at: socketURL,
            deadline: deadline,
            eventSemaphore: eventSemaphore,
            processHasExited: { [exitObserved, process] in
                exitObserved.withLock { $0 } || !process.isRunning
            },
        ) {
        case .ready:
            stopDirectoryObservation()
        case .processExited:
            guard let exit = waitForExit(timeout: 0, usedSIGKILL: false) else {
                throw EntryCoreDaemonProcessError.terminationTimedOut
            }
            throw EntryCoreDaemonProcessError.exitedBeforeReadiness(exit)
        case .timedOut:
            let exit = try stopAfterReadinessTimeout()
            throw EntryCoreDaemonProcessError.readinessTimedOut(exit)
        }
    }

    enum SocketReadinessWaitResult: Equatable {
        case ready
        case processExited
        case timedOut
    }

    static func waitForSocketReadiness(
        at socketURL: URL,
        deadline: DispatchTime,
        eventSemaphore: DispatchSemaphore,
        processHasExited: () -> Bool,
        system: any EntryCoreDaemonSocketSystem = DarwinEntryCoreDaemonSocketSystem(),
        now: () -> DispatchTime = { .now() },
    ) -> SocketReadinessWaitResult {
        while true {
            if processHasExited() { return .processExited }
            let current = now()
            guard current.uptimeNanoseconds < deadline.uptimeNanoseconds else { return .timedOut }
            if socketIsReady(at: socketURL, deadline: deadline, system: system, now: now) {
                return .ready
            }
            if processHasExited() { return .processExited }

            let afterProbe = now()
            guard afterProbe.uptimeNanoseconds < deadline.uptimeNanoseconds else { return .timedOut }
            let tick = afterProbe + readinessRetryTick
            let wakeup = DispatchTime(
                uptimeNanoseconds: min(tick.uptimeNanoseconds, deadline.uptimeNanoseconds),
            )
            _ = eventSemaphore.wait(timeout: wakeup)
        }
    }

    static func socketIsReady(
        at socketURL: URL,
        deadline: DispatchTime = .distantFuture,
        system: any EntryCoreDaemonSocketSystem = DarwinEntryCoreDaemonSocketSystem(),
        now: () -> DispatchTime = { .now() },
    ) -> Bool {
        guard let (address, addressLength) = socketAddress(at: socketURL) else { return false }
        let descriptor: Int32
        switch system.makeNonblockingSocket() {
        case let .success(socketDescriptor):
            descriptor = socketDescriptor
        case .failure:
            return false
        }
        defer { system.close(descriptor) }

        switch system.connect(descriptor, address: address, length: addressLength) {
        case .success:
            return finishConnectedSocket(descriptor, deadline: deadline, system: system, now: now)
        case let .failure(errorNumber) where errorNumber == EINPROGRESS || errorNumber == EINTR:
            return waitForPendingConnection(descriptor, deadline: deadline, system: system, now: now)
        case .failure:
            return false
        }
    }

    private static func waitForPendingConnection(
        _ descriptor: Int32,
        deadline: DispatchTime,
        system: any EntryCoreDaemonSocketSystem,
        now: () -> DispatchTime,
    ) -> Bool {
        while true {
            guard let timeout = pollTimeoutMilliseconds(deadline: deadline, now: now()) else { return false }
            switch system.poll(descriptor, events: Int16(POLLOUT), timeoutMilliseconds: timeout) {
            case .failure(EINTR):
                continue
            case .timedOut, .failure:
                return false
            case let .ready(events):
                if events & Int16(POLLNVAL) != 0 { return false }
                guard events & Int16(POLLOUT | POLLERR | POLLHUP) != 0 else { continue }
            }

            guard case .success(0) = system.socketError(descriptor) else { return false }
            return finishConnectedSocket(descriptor, deadline: deadline, system: system, now: now)
        }
    }

    private static func socketAddress(at socketURL: URL) -> (sockaddr_un, socklen_t)? {
        let pathBytes = Array(socketURL.path.utf8)
        guard
            !pathBytes.contains(0),
            let pathOffset = MemoryLayout.offset(of: \sockaddr_un.sun_path)
        else { return nil }

        var address = sockaddr_un()
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        let addressLength = pathOffset + pathBytes.count + 1
        guard
            pathBytes.count < pathCapacity,
            addressLength <= MemoryLayout<sockaddr_un>.size,
            addressLength <= Int(UInt8.max)
        else { return nil }

        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(addressLength)
        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
        }
        return (address, socklen_t(addressLength))
    }

    private static func pollTimeoutMilliseconds(
        deadline: DispatchTime,
        now: DispatchTime,
    ) -> Int32? {
        guard now.uptimeNanoseconds < deadline.uptimeNanoseconds else { return nil }
        let tick = now + readinessRetryTick
        let pollDeadline = min(tick.uptimeNanoseconds, deadline.uptimeNanoseconds)
        let remaining = pollDeadline - now.uptimeNanoseconds
        let roundedMilliseconds = (remaining + 999_999) / 1_000_000
        return Int32(min(roundedMilliseconds, UInt64(Int32.max)))
    }

    private static func finishConnectedSocket(
        _ descriptor: Int32,
        deadline: DispatchTime,
        system: any EntryCoreDaemonSocketSystem,
        now: () -> DispatchTime,
    ) -> Bool {
        guard now().uptimeNanoseconds < deadline.uptimeNanoseconds else { return false }
        system.shutdownWrite(descriptor)
        return true
    }

    private func stopAfterReadinessTimeout() throws -> EntryCoreDaemonProcessExit {
        process.terminate()
        if let exit = waitForExit(timeout: Self.terminationTimeout, usedSIGKILL: false) {
            return exit
        }
        let exit = try forceTerminationAfterTimeout()
        if exit.usedSIGKILL {
            throw EntryCoreDaemonProcessError.forcedKill(exit)
        }
        return exit
    }

    private func forceTerminationAfterTimeout() throws -> EntryCoreDaemonProcessExit {
        errno = 0
        let signalResult = kill(pid, SIGKILL)
        let signalWasSent: Bool
        if signalResult == 0 {
            signalWasSent = true
        } else if errno == ESRCH {
            signalWasSent = false
        } else {
            throw EntryCoreDaemonProcessError.terminationTimedOut
        }

        guard let exit = waitForExit(
            timeout: Self.forcedTerminationTimeout,
            usedSIGKILL: signalWasSent,
        ) else {
            throw EntryCoreDaemonProcessError.terminationTimedOut
        }
        return exit
    }

    private func waitForExit(
        timeout: TimeInterval,
        usedSIGKILL: Bool,
    ) -> EntryCoreDaemonProcessExit? {
        if let capturedExit { return capturedExit }

        let deadline = dispatchDeadline(after: timeout)
        while process.isRunning, !exitObserved.withLock({ $0 }) {
            if eventSemaphore.wait(timeout: deadline) == .timedOut,
               process.isRunning,
               !exitObserved.withLock({ $0 })
            {
                return nil
            }
        }

        process.waitUntilExit()
        stopDirectoryObservation()
        processSource?.cancel()
        processSource = nil

        var childStatus: Int32 = 0
        errno = 0
        let waitResult = waitpid(pid, &childStatus, WNOHANG)
        let reaped = waitResult == -1 && errno == ECHILD && Self.isProcessAbsent(pid)
        let exit = EntryCoreDaemonProcessExit(
            pid: pid,
            status: process.terminationStatus,
            reaped: reaped,
            usedSIGKILL: usedSIGKILL,
            stdout: String(bytes: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(bytes: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
        )
        capturedExit = exit
        return exit
    }

    private func validateCleanExit(_ exit: EntryCoreDaemonProcessExit) throws -> EntryCoreDaemonProcessExit {
        guard !exit.usedSIGKILL else {
            throw EntryCoreDaemonProcessError.forcedKill(exit)
        }
        guard exit.reaped else {
            throw EntryCoreDaemonProcessError.processNotReaped(exit)
        }
        guard exit.status == 0 else {
            throw EntryCoreDaemonProcessError.nonCleanExit(exit)
        }
        guard !FileManager.default.fileExists(atPath: socketURL.path) else {
            throw EntryCoreDaemonProcessError.socketRemained(exit)
        }
        return exit
    }

    private func stopDirectoryObservation() {
        directorySource?.cancel()
        directorySource = nil
    }

    private func dispatchDeadline(after timeout: TimeInterval) -> DispatchTime {
        .now() + .milliseconds(max(0, Int(timeout * 1000)))
    }
}
