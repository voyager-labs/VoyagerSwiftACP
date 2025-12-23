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
            startWithBundledPython()
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
        proc.environment = mergedEnvironment(prependingPath: nil)
        proc.currentDirectoryURL = URL(fileURLWithPath: backendDirectory)
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["uv", "run", appEnv]

        do {
            try proc.run()
            process = proc
            fputs("[VoyagerHelper] Backend started: uv run \(appEnv) (pid: \(proc.processIdentifier))\n", stderr)
        } catch {
            fputs("[VoyagerHelper] ERROR: Failed to start backend: \(error)\n", stderr)
        }
    }

    private func startWithBundledPython() {
        guard let backendDirectory = environment.backendDirectory() else {
            fputs("[VoyagerHelper] ERROR: backendDirectory not found\n", stderr)
            return
        }

        let pythonPath = URL(fileURLWithPath: backendDirectory).appendingPathComponent("bin/python").path
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            fputs("[VoyagerHelper] ERROR: Python not found at \(pythonPath)\n", stderr)
            return
        }

        let host = environment.value(for: "VOYAGER_HOST") ?? "127.0.0.1"
        let port = environment.value(for: "VOYAGER_PORT") ?? "8000"

        let proc = Process()
        proc
            .environment = mergedEnvironment(prependingPath: URL(fileURLWithPath: pythonPath)
                .deletingLastPathComponent().path)
        proc.currentDirectoryURL = URL(fileURLWithPath: backendDirectory)
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-m", "uvicorn", "app.main:app", "--host", host, "--port", port]

        do {
            try proc.run()
            process = proc
            fputs("[VoyagerHelper] Backend started: bundled python (pid: \(proc.processIdentifier))\n", stderr)
        } catch {
            fputs("[VoyagerHelper] ERROR: Failed to start backend: \(error)\n", stderr)
        }
    }

    private func mergedEnvironment(prependingPath: String?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // PATH 구성
        env["PATH"] = buildPath(prependingPath: prependingPath)

        // PYTHONPATH 설정 (번들 모드에서 venv의 site-packages 포함)
        if let pythonPath = buildPythonPath(existingPath: env["PYTHONPATH"]) {
            env["PYTHONPATH"] = pythonPath
        }

        return env
    }

    private func buildPath(prependingPath: String?) -> String {
        var pathParts: [String] = []

        if let prepend = prependingPath, !prepend.isEmpty {
            pathParts.append(prepend)
        }

        if let custom = environment.value(for: "VOYAGER_PATH") {
            pathParts.append(custom)
        } else {
            pathParts.append("/opt/homebrew/bin:/usr/local/bin")
        }

        if let current = ProcessInfo.processInfo.environment["PATH"] {
            pathParts.append(current)
        }

        return pathParts.joined(separator: ":")
    }

    private func buildPythonPath(existingPath: String?) -> String? {
        guard let backendDir = environment.backendDirectory() else { return nil }

        let libDir = URL(fileURLWithPath: backendDir).appendingPathComponent("lib")
        let fm = FileManager.default

        guard let libContents = try? fm.contentsOfDirectory(at: libDir, includingPropertiesForKeys: nil) else {
            return nil
        }

        // Python 버전을 동적으로 찾기 (lib/python3.x/site-packages)
        for pythonVersionDir in libContents {
            let sitePackages = pythonVersionDir.appendingPathComponent("site-packages")
            if fm.fileExists(atPath: sitePackages.path) {
                var parts: [String] = [sitePackages.path]
                if let existing = existingPath, !existing.isEmpty {
                    parts.append(existing)
                }
                return parts.joined(separator: ":")
            }
        }

        return nil
    }
}
