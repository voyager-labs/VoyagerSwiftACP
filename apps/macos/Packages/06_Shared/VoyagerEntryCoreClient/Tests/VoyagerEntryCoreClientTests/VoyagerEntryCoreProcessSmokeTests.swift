import Darwin
import Foundation
@testable import VoyagerEntryCoreClient
import XCTest

final class VoyagerEntryCoreProcessSmokeTests: XCTestCase {
    func testActualDaemonServesClientAndReconnectsAfterCleanRestart() async throws {
        let tempRoot = try EntryCoreDaemonProcess.makeTemporaryRoot()
        let socketURL = tempRoot.appendingPathComponent("d.sock")
        defer { removeTemporaryRoot(tempRoot) }

        let client = EntryCoreClient.live
        let daemon1 = try EntryCoreDaemonProcess.start(socketURL: socketURL)
        defer { assertCleanCleanup(daemon1) }

        let endpoint = try EntryCoreEndpoint(path: socketURL.path)
        let ping = try await client.ping(endpoint)
        let health = try await client.health(endpoint)
        let version = try await client.version(endpoint)
        XCTAssertEqual(ping, EntryCorePingResult())
        XCTAssertEqual(health, EntryCoreHealthResult())
        XCTAssertFalse(version.appVersion.isEmpty)
        XCTAssertEqual(version.protocolVersion, .v1)

        let firstPID = daemon1.pid
        let firstExit = try daemon1.terminate()
        XCTAssertEqual(firstExit.status, 0)
        XCTAssertTrue(firstExit.reaped)
        XCTAssertFalse(firstExit.usedSIGKILL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
        XCTAssertTrue(EntryCoreDaemonProcess.isProcessAbsent(firstPID))

        let daemon2 = try EntryCoreDaemonProcess.start(socketURL: socketURL)
        defer { assertCleanCleanup(daemon2) }

        XCTAssertNotEqual(daemon2.pid, firstPID)
        let restartedHealth = try await client.health(endpoint)
        XCTAssertEqual(restartedHealth, EntryCoreHealthResult())
        let secondExit = try daemon2.terminate()
        XCTAssertEqual(secondExit.status, 0)
        XCTAssertTrue(secondExit.reaped)
        XCTAssertFalse(secondExit.usedSIGKILL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
    }

    func testNonCleanStartupIsSurfacedReapedAndDoesNotDeleteDestination() throws {
        let tempRoot = try EntryCoreDaemonProcess.makeTemporaryRoot()
        let socketURL = tempRoot.appendingPathComponent("d.sock")
        let marker = Data("owned-by-test".utf8)
        try marker.write(to: socketURL, options: .withoutOverwriting)
        defer { removeTemporaryRoot(tempRoot) }

        do {
            let unexpectedDaemon = try EntryCoreDaemonProcess.start(socketURL: socketURL)
            defer { assertCleanCleanup(unexpectedDaemon) }
            XCTFail("Non-clean daemon startup must not be reported as restart success")
            return
        } catch let error as EntryCoreDaemonProcessError {
            guard case let .exitedBeforeReadiness(exit) = error else { throw error }
            XCTAssertNotEqual(exit.status, 0)
            XCTAssertTrue(exit.reaped)
            XCTAssertFalse(exit.usedSIGKILL)
            XCTAssertTrue(EntryCoreDaemonProcess.isProcessAbsent(exit.pid))
            XCTAssertEqual(try Data(contentsOf: socketURL), marker)

            if ProcessInfo.processInfo.environment["VOYAGER_ENTRY_CORE_PROCESS_FAILURE_PROBE"] == "1" {
                throw error
            }
        }

        XCTAssertEqual(try Data(contentsOf: socketURL), marker)
    }

    func testMissingDaemonEnvironmentFailsInsteadOfSkipping() {
        XCTAssertThrowsError(try EntryCoreDaemonProcess.requiredExecutableURL(environment: [:]))
    }

    private func assertCleanCleanup(
        _ daemon: EntryCoreDaemonProcess,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        do {
            try daemon.cleanup()
        } catch {
            XCTFail("Daemon cleanup failed: \(error)", file: file, line: line)
        }
    }

    private func removeTemporaryRoot(
        _ root: URL,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            XCTFail("Remove process-smoke temporary root: \(error)", file: file, line: line)
        }
    }
}
