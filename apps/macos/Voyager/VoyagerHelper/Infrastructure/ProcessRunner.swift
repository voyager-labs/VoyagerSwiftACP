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

struct BackendTerminationEvent: Sendable {
    let reason: Process.TerminationReason?
    let status: Int32?
    let uptime: TimeInterval
    let wasReady: Bool
    let didStart: Bool
}

actor ProcessRunner {
    enum Error: Swift.Error, Equatable {
        case backendHostNotConfigured
        case backendModeNotConfigured
        case appEnvNotConfigured
        case processNameNotConfigured
        case backendDirectoryNotFound
        case binaryNotFound(path: String)
        // 시작 단계 에러
        case alreadyStarting
        case cancelled
        case portReservationFailed
        case processConfigFailed
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

    func startAndMonitor() async -> BackendTerminationEvent {
        if let process, process.isRunning {
            let startDate = Date()
            let (reason, status) = await waitForTermination(process)
            return BackendTerminationEvent(
                reason: reason,
                status: status,
                uptime: Date().timeIntervalSince(startDate),
                wasReady: true,
                didStart: true,
            )
        }

        do {
            guard !isStarting else { throw Error.alreadyStarting }

            stopRequested = false
            isStarting = true
            defer { isStarting = false }

            guard !stopRequested, !Task.isCancelled else { throw Error.cancelled }
            process = nil

            let context = try await resolveLaunchContext()

            guard let reservedPort = try? portReservation.reserve() else {
                throw Error.portReservationFailed
            }

            let config = try makeProcessConfig(
                reservedPort: reservedPort,
                backendMode: context.backendMode,
                appEnv: context.appEnv,
                processName: context.processName,
                directory: context.directory,
            )

            let startDate = Date()
            let result = await runProcess(
                config: config,
                host: context.host,
                port: reservedPort,
            )
            if !result.wasReady {
                logger.error("Backend start flow failed")
            }

            return BackendTerminationEvent(
                reason: result.reason,
                status: result.status,
                uptime: Date().timeIntervalSince(startDate),
                wasReady: result.wasReady,
                didStart: result.didStart,
            )
        } catch {
            logger.error("Backend startup failed: \(error)")
            return BackendTerminationEvent(
                reason: nil,
                status: nil,
                uptime: 0,
                wasReady: false,
                didStart: false,
            )
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

    private func runProcess(
        config: BackendProcessConfig,
        host: String,
        port: Int,
    ) async -> BackendTerminationEvent {
        let proc = Process()
        proc.environment = config.environment
        proc.currentDirectoryURL = URL(fileURLWithPath: config.directory)
        proc.executableURL = URL(fileURLWithPath: config.executable)
        proc.arguments = config.arguments ?? []

        do {
            try proc.run()
        } catch {
            logger.error("Failed to start backend: \(error)")
            return BackendTerminationEvent(
                reason: nil,
                status: nil,
                uptime: 0,
                wasReady: false,
                didStart: false,
            )
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
                return BackendTerminationEvent(
                    reason: nil,
                    status: nil,
                    uptime: 0,
                    wasReady: false,
                    didStart: false,
                )
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

            let (reason, status) = await waitForTermination(proc)
            process = nil
            return BackendTerminationEvent(
                reason: reason,
                status: status,
                uptime: 0,
                wasReady: true,
                didStart: true,
            )
        }

        logger.error("Backend port verification failed")
        proc.terminate()
        process = nil
        return BackendTerminationEvent(
            reason: nil,
            status: nil,
            uptime: 0,
            wasReady: false,
            didStart: true,
        )
    }

    private func waitForTermination(_ proc: Process) async -> (Process.TerminationReason?, Int32?) {
        if !proc.isRunning {
            return (proc.terminationReason, proc.terminationStatus)
        }
        return await withCheckedContinuation { continuation in
            proc.terminationHandler = { process in
                continuation.resume(returning: (process.terminationReason, process.terminationStatus))
            }
        }
    }
}
