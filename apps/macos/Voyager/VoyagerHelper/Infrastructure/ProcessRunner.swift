import Foundation

final class ProcessRunner {
    private let environment: Environment
    private var process: Process?

    init(environment: Environment) {
        self.environment = environment

        // 초기화 시 로깅
        let backendDir: String
        if let dir = environment.backendDirectory() {
            backendDir = dir
        } else {
            backendDir = "<nil>"
        }

        let appEnv = environment.value(for: "APP_ENV") ?? "dev"
        fputs("[VoyagerHelper] backendDir=\(backendDir) appEnv=\(appEnv)\n", stderr)
    }

    func startIfNeeded() {
        if let running = process, running.isRunning { return }

        let appEnv = environment.value(for: "APP_ENV") ?? "dev"

        if appEnv == "prod" {
            debugLog("[VoyagerHelper] start backend mode=prod (bundled)")
            startWithBundledPython()
        } else {
            debugLog("[VoyagerHelper] start backend mode=dev (uv)")
            startWithUv()
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func startWithUv() {
        guard let backendDirectory = environment.backendDirectory() else {
            debugLog("[VoyagerHelper] backend uv skipped: backendDirectory is nil")
            return
        }
        let appEnv = environment.value(for: "APP_ENV") ?? "dev"
        let env = mergedEnvironment(prependingPath: nil)

        let proc = Process()
        proc.environment = env
        proc.currentDirectoryURL = URL(fileURLWithPath: backendDirectory)
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["uv", "run", appEnv]

        do {
            try proc.run()
            process = proc
        } catch {
            debugLog("[VoyagerHelper] backend 시작 실패(uv): \(error)")
        }
    }

    private func startWithBundledPython() {
        guard let backendDirectory = environment.backendDirectory() else {
            debugLog("[VoyagerHelper] backend bundled skipped: backendDirectory is nil")
            return
        }

        // backendDirectory가 backend-venv인 경우, Python 경로는 venv/bin/python
        let pythonPath = URL(fileURLWithPath: backendDirectory).appendingPathComponent("bin/python").path
        let fm = FileManager.default
        guard fm.fileExists(atPath: pythonPath) else {
            debugLog("[VoyagerHelper] backend bundled skipped: Python not found at \(pythonPath)")
            return
        }

        let host = environment.value(for: "VOYAGER_HOST") ?? "127.0.0.1"
        let port = environment.value(for: "VOYAGER_PORT") ?? "8000"
        let env = mergedEnvironment(prependingPath: URL(fileURLWithPath: pythonPath).deletingLastPathComponent().path)

        let proc = Process()
        proc.environment = env
        proc.currentDirectoryURL = URL(fileURLWithPath: backendDirectory)
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-m", "uvicorn", "app.main:app", "--host", host, "--port", port]

        do {
            try proc.run()
            process = proc
        } catch {
            debugLog("[VoyagerHelper] backend 시작 실패(bundled): \(error)")
        }
    }

    private func mergedEnvironment(prependingPath: String?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment.envVars {
            env[key] = value
        }

        // PATH 구성
        var pathParts: [String] = []
        if let prepend = prependingPath, !prepend.isEmpty {
            pathParts.append(prepend)
        }
        if let custom = environment.value(for: "VOYAGER_PATH") {
            pathParts.append(custom)
        } else {
            // 홈브류 기본 경로를 넣어 uv 같은 바이너리를 찾기 쉽게 한다
            pathParts.append("/opt/homebrew/bin:/usr/local/bin")
        }
        if let current = ProcessInfo.processInfo.environment["PATH"] {
            pathParts.append(current)
        }
        if !pathParts.isEmpty {
            env["PATH"] = pathParts.joined(separator: ":")
        }

        return env
    }

    private func debugLog(_ message: String) {
        fputs(message + "\n", stderr)
    }
}
