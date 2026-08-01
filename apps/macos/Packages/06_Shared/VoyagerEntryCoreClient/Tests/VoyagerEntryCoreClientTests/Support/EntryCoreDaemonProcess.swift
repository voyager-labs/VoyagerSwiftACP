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

final class EntryCoreDaemonProcess {
    private static let executableEnvironmentKey = "VOYAGER_ENTRY_CORE_DAEMON_PATH"
    private static let readinessTimeout: TimeInterval = 15
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
        while true {
            if socketIsReady() {
                stopDirectoryObservation()
                return
            }
            if exitObserved.withLock({ $0 }) || !process.isRunning {
                guard let exit = waitForExit(timeout: 0, usedSIGKILL: false) else {
                    throw EntryCoreDaemonProcessError.terminationTimedOut
                }
                throw EntryCoreDaemonProcessError.exitedBeforeReadiness(exit)
            }
            if eventSemaphore.wait(timeout: deadline) == .timedOut {
                let exit = try stopAfterReadinessTimeout()
                throw EntryCoreDaemonProcessError.readinessTimedOut(exit)
            }
        }
    }

    private func socketIsReady() -> Bool {
        var metadata = stat()
        guard lstat(socketURL.path, &metadata) == 0 else { return false }
        return metadata.st_mode & S_IFMT == S_IFSOCK
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
