import Darwin
import Foundation
import Logging

struct BackendProcessConfig {
    let directory: String
    let executable: String
    let arguments: [String]?
    let environment: [String: String]
    let description: String
}

final class ProcessRunner {
    enum Error: Swift.Error, Equatable {
        case backendDirectoryError(Environment.BackendDirectoryError)
        case processNameNotConfigured
        case binaryNotFound(path: String)
    }

    private var process: Process?
    private let logger = Logger(label: "VoyagerHelper")
    private let environment: Environment

    init(environment: Environment = Environment()) {
        self.environment = environment
    }

    func startIfNeeded() {
        guard process == nil || process?.isRunning == false else { return }
        process = nil

        let config: BackendProcessConfig
        do {
            config = try makeProcessConfig()
        } catch {
            logger.error("Failed to create process config: \(error)")
            return
        }

        let proc = makeProcess(from: config)
        runProcess(proc, description: config.description)
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func makeProcessConfig() throws -> BackendProcessConfig {
        let directory: String
        do {
            directory = try environment.backendDirectory()
        } catch let error as Environment.BackendDirectoryError {
            throw Error.backendDirectoryError(error)
        }

        let executable = try executablePath(in: directory)
        let processEnv = resolveProcessEnvironment()

        let (arguments, description): ([String]?, String) = switch environment.backendMode {
        case .source: (["uv", "run", environment.appEnv.rawValue], "uv run \(environment.appEnv.rawValue)")
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

    private func executablePath(in directory: String) throws -> String {
        switch environment.backendMode {
        case .source:
            return "/usr/bin/env"
        case .bundled:
            guard let processName = environment.value(for: "PUBLIC_BACKEND_PROCESS_NAME") else {
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
    private func resolveProcessEnvironment() -> [String: String] {
        var env: [String: String] = ProcessInfo.processInfo.environment

        env["APP_ENV"] = environment.appEnv.rawValue
        env["BACKEND_MODE"] = environment.backendMode.rawValue

        // source 모드에서만 PATH에 homebrew 경로 추가 (uv 실행용)
        if case .source = environment.backendMode {
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
