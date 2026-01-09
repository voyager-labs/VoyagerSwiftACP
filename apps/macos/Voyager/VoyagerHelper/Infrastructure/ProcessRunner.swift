import Darwin
import Foundation
import Logging
import SwiftDotenv

struct BackendProcessConfig {
    let directory: String
    let executable: String
    let arguments: [String]?
    let environment: [String: String]
    let description: String
}

actor ProcessRunner {
    enum Error: Swift.Error, Equatable {
        case backendDirectoryError(Environment.BackendDirectoryError)
        case processNameNotConfigured
        case binaryNotFound(path: String)
    }

    private var process: Process?
    private var isStarting = false
    private var stopRequested = false
    private let logger = Logger(label: "VoyagerHelper")
    private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    func startIfNeeded() async {
        if let process, process.isRunning {
            return
        }
        if isStarting {
            return
        }

        stopRequested = false
        isStarting = true
        defer { isStarting = false }

        if stopRequested || Task.isCancelled {
            return
        }
        process = nil

        let config: BackendProcessConfig
        do {
            config = try await resolveProcessConfig()
        } catch {
            logger.error("Failed to create process config: \(error)")
            return
        }

        if stopRequested || Task.isCancelled {
            return
        }

        let proc = makeProcess(from: config)
        runProcess(proc, description: config.description)
    }

    func stop() async {
        stopRequested = true
        process?.terminate()
        process = nil
    }

    private func resolveProcessConfig() async throws -> BackendProcessConfig {
        try await MainActor.run {
            let directory: String
            do {
                directory = try environment.backendDirectory()
            } catch let error as Environment.BackendDirectoryError {
                throw Error.backendDirectoryError(error)
            }

            guard let backendMode = Dotenv.backendMode else {
                throw Error.backendDirectoryError(.backendModeNotSet)
            }

            let appEnv = Dotenv.appEnv
            let processName = Dotenv["PUBLIC_BACKEND_PROCESS_NAME"]?.stringValue
            let executable = try executablePath(
                in: directory,
                backendMode: backendMode,
                processName: processName,
            )
            let processEnv = resolveProcessEnvironment(backendMode: backendMode)

            let (arguments, description): ([String]?, String) = switch backendMode {
            case .source: (["uv", "run", appEnv?.rawValue ?? "dev"], "uv run \(appEnv?.rawValue ?? "dev")")
            case .bundled: (nil, "Bundled binary")
            }

            return BackendProcessConfig(
                directory: directory,
                executable: executable,
                arguments: arguments,
                environment: processEnv,
                description: description,
            )
        }
    }

    private nonisolated func executablePath(
        in directory: String,
        backendMode: Environment.BackendMode,
        processName: String?,
    ) throws -> String {
        switch backendMode {
        case .source:
            return "/usr/bin/env"
        case .bundled:
            guard let processName, !processName.isEmpty else {
                throw Error.processNameNotConfigured
            }
            let binaryPath = URL(fileURLWithPath: directory).appendingPathComponent(processName).path
            guard FileManager.default.fileExists(atPath: binaryPath) else {
                throw Error.binaryNotFound(path: binaryPath)
            }
            return binaryPath
        }
    }

    /// 백엔드 프로세스에 필요한 최소한의 환경 변수만 설정합니다.
    ///
    /// Python 백엔드의 `load_config()`가 `APP_ENV`를 기반으로 `.env.{app_env}` 파일을
    /// 자체적으로 로드하므로, 모든 dotenv 값을 주입할 필요가 없습니다.
    ///
    /// 주입되는 환경 변수:
    /// - `APP_ENV`: Python이 올바른 `.env` 파일을 로드하도록 설정
    /// - `BACKEND_MODE`: 백엔드 실행 모드 (source/bundled)
    /// - `PATH` (source 모드만): `uv` 실행을 위해 homebrew 경로 추가
    private nonisolated func resolveProcessEnvironment(
        backendMode: Environment.BackendMode,
    ) -> [String: String] {
        var env: [String: String] = ProcessInfo.processInfo.environment

        // source 모드에서만 PATH에 homebrew 경로 추가 (uv 실행용)
        if case .source = backendMode {
            let prefix = "/opt/homebrew/bin:/usr/local/bin"
            if let currentPath = env["PATH"], !currentPath.isEmpty {
                env["PATH"] = "\(prefix):\(currentPath)"
            } else {
                env["PATH"] = prefix
            }
        }

        return env
    }

    private func makeProcess(from config: BackendProcessConfig) -> Process {
        let proc = Process()
        proc.environment = config.environment
        proc.currentDirectoryURL = URL(fileURLWithPath: config.directory)
        proc.executableURL = URL(fileURLWithPath: config.executable)
        proc.arguments = config.arguments ?? []
        return proc
    }

    private func runProcess(_ proc: Process, description: String) {
        do {
            try proc.run()
            process = proc
            logger.info("Backend started: \(description) (pid: \(proc.processIdentifier))")
        } catch {
            logger.error("Failed to start backend: \(error)")
        }
    }
}
