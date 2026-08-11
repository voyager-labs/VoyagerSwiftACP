import Darwin
import Dispatch
import Foundation
import os
@testable import VoyagerEntryCoreClient
import XCTest

final class UnixSocketTransportTests: XCTestCase {
    private let endpointPath = "/tmp/voyager-entry-core-test.sock"

    func testImmediateConnectWritesAllBytesShutsDownOnceAndReadsToEOF() async throws {
        let system = ScriptedUnixSocketSystem()
        system.configure {
            $0.sendResults = [.success(2), .failure(EINTR), .failure(EAGAIN), .success(3)]
            $0.pollActions = [.result(.ready(networkEvents: Int16(POLLOUT), wakeEvents: 0))]
            $0.receiveActions = [.result(.data(Data("ok".utf8))), .result(.eof)]
        }

        let response = try await makeTransport(system).request(Data("hello".utf8), to: endpoint())
        let snapshot = system.snapshot()

        XCTAssertEqual(response, Data("ok".utf8))
        XCTAssertEqual(snapshot.sent, Data("hello".utf8))
        XCTAssertEqual(snapshot.operations.count(where: { $0.hasPrefix("shutdown-write:") }), 1)
        XCTAssertEqual(snapshot.operations.count(where: { $0.hasPrefix("connect:") }), 1)
        assertEveryDescriptorClosedOnce(snapshot)
        assertEncodedAddress(snapshot)
    }

    func testPendingConnectPollsAndChecksSocketErrorWithoutRepeatingConnect() async throws {
        let system = ScriptedUnixSocketSystem()
        system.configure {
            $0.connectResults = [.failure(EINPROGRESS)]
            $0.pollActions = [.result(.ready(networkEvents: Int16(POLLOUT | POLLERR), wakeEvents: 0))]
            $0.socketErrorResults = [.success(0)]
        }

        _ = try await makeTransport(system).request(Data(), to: endpoint())
        let operations = system.snapshot().operations

        XCTAssertEqual(operations.count(where: { $0.hasPrefix("connect:") }), 1)
        XCTAssertEqual(operations.count(where: { $0.hasPrefix("socket-error:") }), 1)
    }

    func testConnectENOENTAndRefusedMapToDaemonUnavailable() async {
        for errorNumber in [ENOENT, ECONNREFUSED] {
            let system = ScriptedUnixSocketSystem()
            system.configure { $0.connectResults = [.failure(errorNumber)] }
            await assertError(.daemonUnavailable) {
                try await self.makeTransport(system).request(Data(), to: self.endpoint())
            }
            assertEveryDescriptorClosedOnce(system.snapshot())
        }
    }

    func testConnectSocketErrorMapsToConnectPhase() async {
        let system = ScriptedUnixSocketSystem()
        system.configure {
            $0.connectResults = [.failure(EINTR)]
            $0.pollActions = [.result(.ready(networkEvents: Int16(POLLHUP), wakeEvents: 0))]
            $0.socketErrorResults = [.success(EACCES)]
        }
        await assertError(.transport(.connect)) {
            try await self.makeTransport(system).request(Data(), to: self.endpoint())
        }
    }

    func testSetupAndPollFailuresMapToConnectPhaseAndCloseOwnedDescriptors() async {
        let wakeFailure = ScriptedUnixSocketSystem()
        wakeFailure.configure { $0.wakePipeResult = .failure(EMFILE) }
        await assertError(.transport(.connect)) {
            try await self.makeTransport(wakeFailure).request(Data(), to: self.endpoint())
        }
        XCTAssertTrue(wakeFailure.snapshot().closeCounts.isEmpty)

        let socketFailure = ScriptedUnixSocketSystem()
        socketFailure.configure { $0.socketResult = .failure(EMFILE) }
        await assertError(.transport(.connect)) {
            try await self.makeTransport(socketFailure).request(Data(), to: self.endpoint())
        }
        XCTAssertEqual(socketFailure.snapshot().closeCounts, [10: 1, 11: 1])

        let optionFailure = ScriptedUnixSocketSystem()
        optionFailure.configure { $0.noSigPipeResult = .failure(EINVAL) }
        await assertError(.transport(.connect)) {
            try await self.makeTransport(optionFailure).request(Data(), to: self.endpoint())
        }
        assertEveryDescriptorClosedOnce(optionFailure.snapshot())

        let pollFailure = ScriptedUnixSocketSystem()
        pollFailure.configure {
            $0.connectResults = [.failure(EINPROGRESS)]
            $0.pollActions = [.result(.failure(EINVAL))]
        }
        await assertError(.transport(.connect)) {
            try await self.makeTransport(pollFailure).request(Data(), to: self.endpoint())
        }
        assertEveryDescriptorClosedOnce(pollFailure.snapshot())
    }

    func testPollTimeoutUsesOneDecreasingAbsoluteBudget() async {
        let system = ScriptedUnixSocketSystem()
        system.configure {
            $0.connectResults = [.failure(EINPROGRESS)]
            $0.pollActions = [
                .sleep(milliseconds: 100, result: .failure(EINTR)),
                .result(.timedOut),
            ]
        }

        await assertError(.timedOut(.connect)) {
            try await self.makeTransport(system).request(Data(), to: self.endpoint())
        }
        let timeouts = system.snapshot().pollTimeouts
        XCTAssertEqual(timeouts.count, 2)
        XCTAssertTrue((1900 ... 2000).contains(timeouts[0]))
        XCTAssertLessThan(timeouts[1], timeouts[0])
    }

    func testPositiveSubMillisecondPollBudgetRoundsUpToOneMillisecond() {
        XCTAssertEqual(UnixSocketTransport.pollTimeoutMilliseconds(for: .nanoseconds(1)), 1)
        XCTAssertEqual(UnixSocketTransport.pollTimeoutMilliseconds(for: .microseconds(999)), 1)
        XCTAssertEqual(UnixSocketTransport.pollTimeoutMilliseconds(for: .milliseconds(1)), 1)
        XCTAssertEqual(UnixSocketTransport.pollTimeoutMilliseconds(for: .milliseconds(1) + .nanoseconds(1)), 2)
    }

    func testHUPDoesNotSkipBufferedReceive() async throws {
        let system = ScriptedUnixSocketSystem()
        system.configure {
            $0.receiveActions = [
                .result(.failure(EAGAIN)),
                .result(.data(Data("buffered".utf8))),
                .result(.eof),
            ]
            $0.pollActions = [.result(.ready(networkEvents: Int16(POLLIN | POLLHUP), wakeEvents: 0))]
        }

        let response = try await makeTransport(system).request(Data(), to: endpoint())

        XCTAssertEqual(response, Data("buffered".utf8))
        XCTAssertEqual(system.snapshot().operations.count(where: { $0.hasPrefix("receive:") }), 3)
    }

    func testResponseSizeAllows65536AndProbesOneExtraByte() async throws {
        let atLimit = Data(repeating: 65, count: 65536)
        let exactSystem = ScriptedUnixSocketSystem()
        exactSystem.configure { $0.receiveActions = [.result(.data(atLimit)), .result(.eof)] }
        let exact = try await makeTransport(exactSystem).request(Data(), to: endpoint())
        XCTAssertEqual(exact.count, 65536)
        XCTAssertTrue(exactSystem.snapshot().operations.contains("receive:20:1"))

        let overflowSystem = ScriptedUnixSocketSystem()
        overflowSystem.configure {
            $0.receiveActions = [.result(.data(atLimit)), .result(.data(Data([66])))]
        }
        await assertError(.responseTooLarge) {
            try await self.makeTransport(overflowSystem).request(Data(), to: self.endpoint())
        }
    }

    func testShutdownAndReceiveFailuresMapToWriteAndReadPhases() async {
        let shutdownSystem = ScriptedUnixSocketSystem()
        shutdownSystem.configure { $0.shutdownResult = .failure(EPIPE) }
        await assertError(.transport(.write)) {
            try await self.makeTransport(shutdownSystem).request(Data(), to: self.endpoint())
        }

        let receiveSystem = ScriptedUnixSocketSystem()
        receiveSystem.configure { $0.receiveActions = [.result(.failure(ECONNRESET))] }
        await assertError(.transport(.read)) {
            try await self.makeTransport(receiveSystem).request(Data(), to: self.endpoint())
        }
    }

    func testCancellationDuringPollWakesWorkerAndClosesFDsOnce() async {
        let system = ScriptedUnixSocketSystem()
        system.configure {
            $0.connectResults = [.failure(EINPROGRESS)]
            $0.pollActions = [.waitForWake]
        }
        let transport = makeTransport(system)
        let endpoint = endpoint()
        let task = Task { try await transport.request(Data(), to: endpoint) }
        await waitUntil { system.snapshot().operations.contains { $0.hasPrefix("poll:") } }

        task.cancel()

        await assertTaskError(task, equals: .cancelled)
        let snapshot = system.snapshot()
        XCTAssertEqual(snapshot.operations.count(where: { $0.hasPrefix("signal-wake:") }), 1)
        assertEveryDescriptorClosedOnce(snapshot)
    }

    func testCancellationBeforeWorkerSetupFinishesOnceWithoutClosingUnknownFD() async {
        let setupGate = DispatchSemaphore(value: 0)
        let system = ScriptedUnixSocketSystem()
        system.configure { $0.wakePipeGate = setupGate }
        let transport = makeTransport(system)
        let endpoint = endpoint()
        let task = Task { try await transport.request(Data(), to: endpoint) }
        await waitUntil { system.snapshot().operations.contains("wake-pipe") }

        task.cancel()
        setupGate.signal()

        await assertTaskError(task, equals: .cancelled)
        let snapshot = system.snapshot()
        XCTAssertEqual(snapshot.closeCounts, [10: 1, 11: 1])
        XCTAssertFalse(snapshot.operations.contains("socket"))
    }

    func testCancellationBeforeSuccessfulFinishWinsAndClosesFDsOnce() async {
        let release = DispatchSemaphore(value: 0)
        let system = ScriptedUnixSocketSystem()
        system.configure { $0.receiveActions = [.wait(release, .eof)] }
        let transport = makeTransport(system)
        let endpoint = endpoint()
        let task = Task { try await transport.request(Data(), to: endpoint) }
        await waitUntil { system.snapshot().operations.contains("receive:20:65536") }

        task.cancel()
        release.signal()

        await assertTaskError(task, equals: .cancelled)
        assertEveryDescriptorClosedOnce(system.snapshot())
    }

    func testRealDarwinUnixSocketRoundTrip() async throws {
        let directory = "/tmp/ec-\(UUID().uuidString.prefix(8))"
        let path = directory + "/socket"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let server = try TemporaryUnixServer(path: path, response: Data("response".utf8))
        defer { server.close() }

        let response = try await UnixSocketTransport().request(
            Data("request".utf8),
            to: EntryCoreEndpoint(path: path),
        )

        XCTAssertEqual(response, Data("response".utf8))
        XCTAssertEqual(try server.waitForRequest(), Data("request".utf8))
    }

    private func makeTransport(_ system: ScriptedUnixSocketSystem) -> UnixSocketTransport {
        UnixSocketTransport(system: system)
    }

    private func endpoint() -> EntryCoreEndpoint {
        do {
            return try EntryCoreEndpoint(path: endpointPath)
        } catch {
            preconditionFailure("test endpoint must be valid")
        }
    }

    private func assertEncodedAddress(
        _ snapshot: ScriptedUnixSocketSystem.State,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        guard var address = snapshot.connectedAddress, let length = snapshot.connectedLength else {
            return XCTFail("missing connected address", file: file, line: line)
        }
        XCTAssertEqual(address.sun_family, sa_family_t(AF_UNIX), file: file, line: line)
        XCTAssertEqual(address.sun_len, UInt8(length), file: file, line: line)
        let bytes = withUnsafeBytes(of: &address.sun_path) { Array($0) }
        let expected = Array(endpointPath.utf8) + [0]
        XCTAssertEqual(Array(bytes.prefix(expected.count)), expected, file: file, line: line)
        XCTAssertTrue(bytes.dropFirst(expected.count).allSatisfy { $0 == 0 }, file: file, line: line)
        guard let pathOffset = MemoryLayout.offset(of: \sockaddr_un.sun_path) else {
            return XCTFail("missing sun_path offset", file: file, line: line)
        }
        XCTAssertEqual(Int(length), pathOffset + expected.count, file: file, line: line)
    }

    private func assertEveryDescriptorClosedOnce(
        _ snapshot: ScriptedUnixSocketSystem.State,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(snapshot.closeCounts, [20: 1, 10: 1, 11: 1], file: file, line: line)
    }

    private func assertError(
        _ expected: EntryCoreClientError,
        operation: () async throws -> Data,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) async {
        do {
            _ = try await operation()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, expected, file: file, line: line)
        }
    }

    private func assertTaskError(
        _ task: Task<Data, Error>,
        equals expected: EntryCoreClientError,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) async {
        do {
            _ = try await task.value
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, expected, file: file, line: line)
        }
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0 ..< 1000 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("condition was not reached")
    }
}

private final class TemporaryUnixServer: Sendable {
    private let queue = DispatchQueue(label: "TemporaryUnixServer")
    private let completion = DispatchSemaphore(value: 0)
    private struct State {
        var request = Data()
        var failure: Error?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let listener: Int32

    init(path: String, response: Data) throws {
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard let pathOffset = MemoryLayout.offset(of: \sockaddr_un.sun_path) else {
            Darwin.close(listener)
            throw POSIXError(.EINVAL)
        }
        let length = pathOffset + bytes.count + 1
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(length)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
        }
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(length))
            }
        }
        guard bindResult == 0, Darwin.listen(listener, 1) == 0 else {
            Darwin.close(listener)
            throw POSIXError(.EIO)
        }
        queue.async { [self] in
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { return finish(error: POSIXError(.EIO)) }
            defer { Darwin.close(client) }
            var received = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = Darwin.recv(client, &buffer, buffer.count, 0)
                if count == 0 { break }
                guard count > 0 else { return finish(error: POSIXError(.EIO)) }
                received.append(buffer, count: count)
            }
            let sendResult = response.withUnsafeBytes { Darwin.send(client, $0.baseAddress, $0.count, 0) }
            guard sendResult == response.count else { return finish(error: POSIXError(.EIO)) }
            finish(request: received)
        }
    }

    func waitForRequest() throws -> Data {
        guard completion.wait(timeout: .now() + 2) == .success else { throw POSIXError(.ETIMEDOUT) }
        return try state.withLock { state in
            if let failure = state.failure { throw failure }
            return state.request
        }
    }

    func close() {
        Darwin.close(listener)
    }

    private func finish(request: Data = Data(), error: Error? = nil) {
        state.withLock { state in
            state.request = request
            state.failure = error
        }
        completion.signal()
    }
}
