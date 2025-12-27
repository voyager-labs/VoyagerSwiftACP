import Darwin
import Foundation

final class ProcessRunner {
    private let environment: Environment
    private var process: Process?
    private var stderrPipe: Pipe?
    private var assignedPort: Int?
    var onPortAssigned: ((Int) -> Void)?

    init(environment: Environment) {
        self.environment = environment
    }

    func startIfNeeded() {
        guard process == nil || process?.isRunning == false else { return }
        process = nil

        // backend mode에 따라 실행 방식 결정
        switch environment.backendMode {
        case .bundled:
            startWithBundledBinary()
        case .source:
            startWithUv()
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe = nil
        assignedPort = nil
    }

    private func startWithUv() {
        guard let backendDirectory = environment.backendDirectory() else {
            fputs("[VoyagerHelper] ERROR: backendDirectory not found\n", stderr)
            return
        }

        let appEnv = environment.environmentType.rawValue
        let proc = makeProcess(
            directory: backendDirectory,
            executable: "/usr/bin/env",
            arguments: ["uv", "run", appEnv],
        )

        runProcess(proc, description: "uv run \(appEnv)")
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

        let proc = makeProcess(directory: serverDirectory, executable: binaryPath)

        runProcess(proc, description: "Bundled binary")
    }

    private func makeProcess(
        directory: String,
        executable: String,
        arguments: [String]? = nil,
    ) -> Process {
        let proc = Process()
        proc.environment = ProcessInfo.processInfo.environment
        proc.currentDirectoryURL = URL(fileURLWithPath: directory)
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments ?? []
        return proc
    }

    private func runProcess(_ proc: Process, description: String) {
        let pipe = Pipe()
        proc.standardError = pipe
        stderrPipe = pipe

        setupStderrParsing(pipe: pipe)

        do {
            try proc.run()
            process = proc
            fputs("[VoyagerHelper] Backend started: \(description) (pid: \(proc.processIdentifier))\n", stderr)
        } catch {
            fputs("[VoyagerHelper] ERROR: Failed to start backend: \(error)\n", stderr)
        }
    }

    private func setupStderrParsing(pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            FileHandle.standardError.write(data)

            guard let output = String(data: data, encoding: .utf8) else { return }

            for line in output.components(separatedBy: .newlines) {
                guard let port = Self.parsePort(from: line) else { continue }

                DispatchQueue.main.sync { [weak self] in
                    self?.assignedPort = port
                    self?.onPortAssigned?(port)
                    fputs("[VoyagerHelper] Backend port assigned: \(port)\n", stderr)
                }
                return
            }
        }
    }

    private nonisolated static func parsePort(from line: String) -> Int? {
        // "Uvicorn running on http://{host}:{port}" 형식 파싱
        guard line.contains("Uvicorn running on"),
              let match = line.range(of: #"http://[^:]+:(\d+)"#, options: .regularExpression),
              let portMatch = line.range(of: #":(\d+)"#, options: .regularExpression, range: match)
        else { return nil }

        let portString = line[portMatch].dropFirst() // ":" 제거
        return Int(portString)
    }
}
