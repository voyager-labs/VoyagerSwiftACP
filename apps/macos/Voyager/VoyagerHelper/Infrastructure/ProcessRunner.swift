import Darwin
import Foundation

final class ProcessRunner {
    private let environment: Environment
    private var process: Process?

    init(environment: Environment) {
        self.environment = environment
    }

    func startIfNeeded() {
        if let running = process, running.isRunning {
            return
        }

        if process != nil {
            process = nil
        }

        // backend mode에 따라 실행 방식 결정
        switch environment.backendMode {
        case .bundled:
            startWithBundledBinary()
        case .source:
            startWithUv()
        }
    }

    func stop() {
        if let proc = process {
            proc.terminate()
            process = nil
        }
    }

    private func startWithUv() {
        guard let backendDirectory = environment.backendDirectory() else {
            fputs("[VoyagerHelper] ERROR: backendDirectory not found\n", stderr)
            return
        }

        let appEnv = environment.environmentType.rawValue
        let proc = Process()
        proc.environment = ProcessInfo.processInfo.environment
        proc.currentDirectoryURL = URL(fileURLWithPath: backendDirectory)
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["uv", "run", appEnv]

        do {
            try proc.run()
            process = proc
            fputs(
                "[VoyagerHelper] Backend started: uv run \(appEnv) (pid: \(proc.processIdentifier))\n",
                stderr,
            )
        } catch {
            fputs("[VoyagerHelper] ERROR: Failed to start backend: \(error)\n", stderr)
        }
    }

    private func startWithBundledBinary() {
        guard let serverDirectory = environment.backendDirectory() else {
            fputs("[VoyagerHelper] ERROR: server directory not found\n", stderr)
            return
        }

        // Nuitka 바이너리 경로: server/server.bin
        let binaryPath = URL(fileURLWithPath: serverDirectory).appendingPathComponent("server.bin").path
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            fputs("[VoyagerHelper] ERROR: server.bin not found at \(binaryPath)\n", stderr)
            return
        }

        let proc = Process()
        proc.environment = ProcessInfo.processInfo.environment
        proc.currentDirectoryURL = URL(fileURLWithPath: serverDirectory)
        proc.executableURL = URL(fileURLWithPath: binaryPath)

        do {
            try proc.run()
            process = proc
            fputs(
                "[VoyagerHelper] Backend started: Nuitka binary (pid: \(proc.processIdentifier))\n",
                stderr,
            )
        } catch {
            fputs("[VoyagerHelper] ERROR: Failed to start backend: \(error)\n", stderr)
        }
    }
}
