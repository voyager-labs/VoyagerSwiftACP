import Darwin
import Dispatch
import Foundation
import XCTest

final class EntryCoreDaemonReadinessTests: XCTestCase {
    func testBoundSocketIsNotReadyBeforeListen() throws {
        let tempRoot = try EntryCoreDaemonProcess.makeTemporaryRoot()
        defer { removeTemporaryRoot(tempRoot) }
        let socketURL = tempRoot.appendingPathComponent("d.sock")
        let listener = try BoundUnixSocket(path: socketURL.path)
        defer { listener.close() }

        XCTAssertFalse(EntryCoreDaemonProcess.socketIsReady(at: socketURL))
    }

    func testReadinessRetriesUntilListenWithoutFilesystemEvent() throws {
        let tempRoot = try EntryCoreDaemonProcess.makeTemporaryRoot()
        defer { removeTemporaryRoot(tempRoot) }
        let socketURL = tempRoot.appendingPathComponent("d.sock")
        let listener = try BoundUnixSocket(path: socketURL.path)
        defer { listener.close() }
        let eventSemaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(75)) {
            listener.listen()
        }
        let result = EntryCoreDaemonProcess.waitForSocketReadiness(
            at: socketURL,
            deadline: .now() + .seconds(1),
            eventSemaphore: eventSemaphore,
            processHasExited: { false },
        )

        XCTAssertEqual(result, .ready)
    }

    func testPendingConnectPollUsesRemainingDeadlineAndClosesOnce() {
        let clock = TestDispatchClock(uptimeNanoseconds: 1_000_000_000)
        let system = ScriptedEntryCoreDaemonSocketSystem(clock: clock)
        system.connectResult = .failure(EINPROGRESS)
        system.pollActions = [
            .init(advanceNanoseconds: 4_000_000, result: .failure(EINTR)),
            .init(advanceNanoseconds: 6_000_000, result: .timedOut),
        ]
        let deadline = DispatchTime(uptimeNanoseconds: clock.uptimeNanoseconds + 10_000_000)

        let result = EntryCoreDaemonProcess.waitForSocketReadiness(
            at: URL(fileURLWithPath: "/tmp/pending.sock"),
            deadline: deadline,
            eventSemaphore: DispatchSemaphore(value: 0),
            processHasExited: { false },
            system: system,
            now: clock.now,
        )

        XCTAssertEqual(result, .timedOut)
        XCTAssertEqual(system.pollTimeouts, [10, 6])
        XCTAssertEqual(system.socketErrorCallCount, 0)
        XCTAssertEqual(system.shutdownWriteCallCount, 0)
        XCTAssertEqual(system.closeCounts, [41: 1])
    }

    func testReadinessTimeoutTerminatesAndReapsProcess() throws {
        let tempRoot = try EntryCoreDaemonProcess.makeTemporaryRoot()
        defer { removeTemporaryRoot(tempRoot) }
        let socketURL = tempRoot.appendingPathComponent("d.sock")
        let executableURL = try makeExecutableScript(
            in: tempRoot,
            name: "never-ready",
            body: "trap 'exit 0' TERM\nwhile :; do :; done",
        )

        do {
            _ = try EntryCoreDaemonProcess.start(
                socketURL: socketURL,
                environment: ["VOYAGER_ENTRY_CORE_DAEMON_PATH": executableURL.path],
                timeout: 0.05,
            )
            XCTFail("A daemon that never listens must time out")
        } catch let error as EntryCoreDaemonProcessError {
            guard case let .readinessTimedOut(exit) = error else { throw error }
            XCTAssertTrue(exit.reaped)
            XCTAssertFalse(exit.usedSIGKILL)
            XCTAssertTrue(EntryCoreDaemonProcess.isProcessAbsent(exit.pid))
            XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
        }
    }

    private func makeExecutableScript(in root: URL, name: String, body: String) throws -> URL {
        let scriptURL = root.appendingPathComponent(name)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: scriptURL, options: .withoutOverwriting)
        guard chmod(scriptURL.path, 0o700) == 0 else { throw POSIXError(.EACCES) }
        return scriptURL
    }

    private func removeTemporaryRoot(
        _ root: URL,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            XCTFail("Remove readiness temporary root: \(error)", file: file, line: line)
        }
    }
}

private final class BoundUnixSocket: Sendable {
    private let descriptor: Int32

    init(path: String) throws {
        descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }

        var address = sockaddr_un()
        let pathBytes = Array(path.utf8)
        guard let pathOffset = MemoryLayout.offset(of: \sockaddr_un.sun_path) else {
            Darwin.close(descriptor)
            throw POSIXError(.EINVAL)
        }
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        let addressLength = pathOffset + pathBytes.count + 1
        guard
            !pathBytes.contains(0),
            pathBytes.count < pathCapacity,
            addressLength <= MemoryLayout<sockaddr_un>.size,
            addressLength <= Int(UInt8.max)
        else {
            Darwin.close(descriptor)
            throw POSIXError(.ENAMETOOLONG)
        }

        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(addressLength)
        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(addressLength))
            }
        }
        guard result == 0 else {
            let errorNumber = errno
            Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errorNumber) ?? .EIO)
        }
    }

    func listen() {
        _ = Darwin.listen(descriptor, 1)
    }

    func close() {
        Darwin.close(descriptor)
    }
}

private final class TestDispatchClock {
    private(set) var uptimeNanoseconds: UInt64

    init(uptimeNanoseconds: UInt64) {
        self.uptimeNanoseconds = uptimeNanoseconds
    }

    func now() -> DispatchTime {
        DispatchTime(uptimeNanoseconds: uptimeNanoseconds)
    }

    func advance(by nanoseconds: UInt64) {
        uptimeNanoseconds += nanoseconds
    }
}

private final class ScriptedEntryCoreDaemonSocketSystem: EntryCoreDaemonSocketSystem {
    struct PollAction {
        let advanceNanoseconds: UInt64
        let result: EntryCoreDaemonSocketPollResult
    }

    var connectResult = EntryCoreDaemonSocketCallResult.success(0)
    var pollActions: [PollAction] = []
    private(set) var pollTimeouts: [Int32] = []
    private(set) var socketErrorCallCount = 0
    private(set) var shutdownWriteCallCount = 0
    private(set) var closeCounts: [Int32: Int] = [:]

    private let clock: TestDispatchClock

    init(clock: TestDispatchClock) {
        self.clock = clock
    }

    func makeNonblockingSocket() -> EntryCoreDaemonSocketCallResult {
        .success(41)
    }

    func connect(
        _: Int32,
        address _: sockaddr_un,
        length _: socklen_t,
    ) -> EntryCoreDaemonSocketCallResult {
        connectResult
    }

    func poll(
        _: Int32,
        events _: Int16,
        timeoutMilliseconds: Int32,
    ) -> EntryCoreDaemonSocketPollResult {
        pollTimeouts.append(timeoutMilliseconds)
        guard !pollActions.isEmpty else { return .timedOut }
        let action = pollActions.removeFirst()
        clock.advance(by: action.advanceNanoseconds)
        return action.result
    }

    func socketError(_: Int32) -> EntryCoreDaemonSocketCallResult {
        socketErrorCallCount += 1
        return .success(0)
    }

    func shutdownWrite(_: Int32) {
        shutdownWriteCallCount += 1
    }

    func close(_ descriptor: Int32) {
        closeCounts[descriptor, default: 0] += 1
    }
}
