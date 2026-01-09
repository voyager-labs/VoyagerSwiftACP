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

private struct BackendLaunchContext: Sendable {
    let host: String
    let backendMode: Environment.BackendMode
    let appEnv: Environment.AppEnv
    let processName: String
    let directory: String
}

actor ProcessRunner {
    enum Error: Swift.Error, Equatable {
        case backendHostNotConfigured
        case backendModeNotConfigured
        case appEnvNotConfigured
        case processNameNotConfigured
        case backendDirectoryNotFound
        case binaryNotFound(path: String)
    }

    private var process: Process?
    private var isStarting = false
    private var stopRequested = false
    private let logger = Logger(label: "VoyagerHelper")
    private let environment: Environment
    private let portReservation: PortReservationService

    init(
        environment: Environment,
        portReservation: PortReservationService = PortReservationService(),
    ) {
        self.environment = environment
        self.portReservation = portReservation
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

        let context: BackendLaunchContext
        do {
            context = try await resolveLaunchContext()
        } catch {
            logger.error("Failed to resolve launch context: \(error)")
            return
        }
        guard let reservedPort = try? portReservation.reserve() else {
            logger.error("Failed to reserve backend port")
            return
        }

        guard let config = try? makeProcessConfig(
            reservedPort: reservedPort,
            backendMode: context.backendMode,
            appEnv: context.appEnv,
            processName: context.processName,
            directory: context.directory,
        ) else {
            logger.error("Failed to create process config")
            return
        }

        let didStart = await runProcess(
            config: config,
            host: context.host,
            port: reservedPort,
        )
        if !didStart {
            logger.error("Backend start flow failed")
        }
    }

    func stop() async {
        stopRequested = true
        process?.terminate()
        process = nil
    }

    private func makeProcessConfig(
        reservedPort: Int,
        backendMode: Environment.BackendMode,
        appEnv: Environment.AppEnv,
        processName: String,
        directory: String,
    ) throws -> BackendProcessConfig {
        let executable = try executablePath(
            in: directory,
            backendMode: backendMode,
            processName: processName,
        )
        let processEnv = resolveProcessEnvironment(
            reservedPort: reservedPort,
            backendMode: backendMode,
        )

        let (arguments, description): ([String]?, String) = switch backendMode {
        case .source: (["uv", "run", appEnv.rawValue], "uv run \(appEnv.rawValue)")
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

    private nonisolated func executablePath(
        in directory: String,
        backendMode: Environment.BackendMode,
        processName: String,
    ) throws -> String {
        switch backendMode {
        case .source:
            return "/usr/bin/env"
        case .bundled:
            guard !processName.isEmpty else {
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
        reservedPort: Int,
        backendMode: Environment.BackendMode,
    ) -> [String: String] {
        var env: [String: String] = ProcessInfo.processInfo.environment
        env["PUBLIC_BACKEND_PORT"] = String(reservedPort)

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

    private func resolveLaunchContext() async throws -> BackendLaunchContext {
        let logger = logger

        return try await MainActor.run {
            guard let backendMode = Dotenv.backendMode else {
                logger.error("Missing BACKEND_MODE in .env")
                throw Error.backendModeNotConfigured
            }

            guard let appEnv = Dotenv.appEnv else {
                logger.error("Missing APP_ENV in .env")
                throw Error.appEnvNotConfigured
            }

            guard let host = Dotenv["PUBLIC_BACKEND_HOST"]?.stringValue, !host.isEmpty else {
                logger.error("Missing PUBLIC_BACKEND_HOST in .env")
                throw Error.backendHostNotConfigured
            }

            guard let processName = Dotenv["PUBLIC_BACKEND_PROCESS_NAME"]?.stringValue else {
                logger.error("Missing PUBLIC_BACKEND_PROCESS_NAME in .env")
                throw Error.processNameNotConfigured
            }

            guard let directory = try? environment.backendDirectory() else {
                logger.error("Failed to resolve backend directory")
                throw Error.backendDirectoryNotFound
            }

            return BackendLaunchContext(
                host: host,
                backendMode: backendMode,
                appEnv: appEnv,
                processName: processName,
                directory: directory,
            )
        }
    }

    private func makeProcess(from config: BackendProcessConfig) -> Process {
        let proc = Process()
        proc.environment = config.environment
        proc.currentDirectoryURL = URL(fileURLWithPath: config.directory)
        proc.executableURL = URL(fileURLWithPath: config.executable)
        proc.arguments = config.arguments ?? []
        return proc
    }

    private func runProcess(
        config: BackendProcessConfig,
        host: String,
        port: Int,
    ) async -> Bool {
        let proc = makeProcess(from: config)
        do {
            try proc.run()
        } catch {
            logger.error("Failed to start backend: \(error)")
            return false
        }

        let isReady = await portReservation.verifyListening(
            host: host,
            port: port,
            isRunning: { proc.isRunning },
            shouldStop: { [stopRequested] in stopRequested },
        )

        if isReady {
            if stopRequested || Task.isCancelled {
                proc.terminate()
                process = nil
                return false
            }
            process = proc
            logger.info("Backend started: \(config.description) (pid: \(proc.processIdentifier))")

            let urlString = "http://\(host):\(port)"
            Task { @MainActor in
                DistributedNotificationCenter.default().post(
                    name: .backendEndpointDidUpdate,
                    object: nil,
                    userInfo: ["host": host, "port": port, "url": urlString],
                )
            }

            return true
        }

        logger.error("Backend port verification failed")
        proc.terminate()
        process = nil
        return false
    }
}
