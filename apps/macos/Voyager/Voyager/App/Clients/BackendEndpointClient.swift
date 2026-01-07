import AppKit
import ComposableArchitecture
import Foundation
import Logging
import SwiftDotenv

public struct BackendEndpointClient: Sendable {
    public var resolve: @Sendable () async -> URL?

    public nonisolated init(resolve: @escaping @Sendable () async -> URL?) {
        self.resolve = resolve
    }
}

extension BackendEndpointClient: DependencyKey {
    public nonisolated static var liveValue: BackendEndpointClient {
        let resolver = BackendEndpointResolver()
        return BackendEndpointClient(resolve: {
            await resolver.resolveEndpoint()
        })
    }

    public nonisolated static var testValue: BackendEndpointClient {
        BackendEndpointClient(resolve: { nil })
    }

    public nonisolated static var previewValue: BackendEndpointClient {
        BackendEndpointClient(resolve: { nil })
    }
}

public extension DependencyValues {
    nonisolated var backendEndpointClient: BackendEndpointClient {
        get { self[BackendEndpointClient.self] }
        set { self[BackendEndpointClient.self] = newValue }
    }
}

private actor BackendEndpointResolver {
    private let logger = Logger(label: "Voyager")

    func resolveEndpoint() async -> URL? {
        while true {
            for attempt in 1 ... 3 {
                if let endpoint = await resolveOnce() {
                    return endpoint
                }

                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            let shouldRetry = await MainActor.run {
                showBackendNotFoundAlert()
            }

            if shouldRetry {
                continue
            }

            await MainActor.run {
                NSApp.terminate(nil)
            }
            return nil
        }
    }

    private func resolveOnce() async -> URL? {
        let environment = BackendEndpointEnvironment()

        guard let processName = environment.processName else {
            logger.error("Missing PUBLIC_BACKEND_PROCESS_NAME in .env")
            return nil
        }

        guard let host = environment.host else {
            logger.error("Missing PUBLIC_BACKEND_HOST in .env")
            return nil
        }

        let pids = await findPids(matching: processName)
        guard !pids.isEmpty else {
            return nil
        }

        guard let port = await findListenPort(pids: pids) else {
            return nil
        }

        return URL(string: "http://\(host):\(port)")
    }

    private func findPids(matching processName: String) async -> [Int] {
        let result = await runCommand(
            launchPath: "/usr/bin/pgrep",
            arguments: ["-f", processName],
        )

        guard let result, result.exitCode == 0 else {
            return []
        }

        return result.output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .sorted(by: >)
    }

    private func findListenPort(pids: [Int]) async -> Int? {
        for pid in pids {
            if let port = await findListenPort(pid: pid) {
                return port
            }
        }
        return nil
    }

    private func findListenPort(pid: Int) async -> Int? {
        let result = await runCommand(
            launchPath: "/usr/sbin/lsof",
            arguments: ["-n", "-P", "-a", "-iTCP", "-sTCP:LISTEN", "-p", "\(pid)"],
        )

        guard let result, result.exitCode == 0 else {
            return nil
        }

        return extractListenPort(from: result.output)
    }

    private func extractListenPort(from output: String) -> Int? {
        let lines = output.split(whereSeparator: \.isNewline)
        for line in lines.dropFirst() {
            if let port = parseListenPort(line: String(line)) {
                return port
            }
        }
        return nil
    }

    private func parseListenPort(line: String) -> Int? {
        guard line.contains("(LISTEN)") else { return nil }

        let pattern = #":(\d+)\s*\(LISTEN\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let portRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        return Int(line[portRange])
    }

    private func runCommand(
        launchPath: String,
        arguments: [String],
    ) async -> CommandResult? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments

            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return nil
            }

            process.waitUntilExit()

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return CommandResult(exitCode: process.terminationStatus, output: output)
        }.value
    }
}

private struct CommandResult: Sendable {
    let exitCode: Int32
    let output: String
}

private struct BackendEndpointEnvironment {
    enum EnvironmentType: String {
        case dev
        case prod

        nonisolated var envFileName: String {
            switch self {
            case .dev: ".env.dev"
            case .prod: ".env.prod"
            }
        }
    }

    enum BackendMode: String {
        case source
        case bundled
    }

    let processName: String?
    let host: String?

    nonisolated init() {
        let environmentType = Self.detectEnvironmentType()
        let backendMode = Self.detectBackendMode()
        Self.loadEnvFile(environmentType.envFileName, for: backendMode)

        let values = Dotenv.values
        processName = Self.nonEmpty(values["PUBLIC_BACKEND_PROCESS_NAME"])
        host = Self.nonEmpty(values["PUBLIC_BACKEND_HOST"])
    }

    private nonisolated static func detectEnvironmentType() -> EnvironmentType {
        if let infoEnv = Bundle.main.infoDictionary?["APP_ENV"] as? String,
           let envType = EnvironmentType(rawValue: infoEnv)
        {
            return envType
        }
        return .dev
    }

    private nonisolated static func detectBackendMode() -> BackendMode {
        if let envMode = ProcessInfo.processInfo.environment["BACKEND_MODE"],
           let mode = BackendMode(rawValue: envMode)
        {
            return mode
        }

        if let infoMode = Bundle.main.infoDictionary?["BACKEND_MODE"] as? String,
           let mode = BackendMode(rawValue: infoMode)
        {
            return mode
        }

        return .source
    }

    private nonisolated static func loadEnvFile(_ envFileName: String, for backendMode: BackendMode) {
        switch backendMode {
        case .source:
            if let projectRoot = findProjectRoot() {
                let projectEnv = projectRoot.appendingPathComponent(envFileName)
                if FileManager.default.fileExists(atPath: projectEnv.path) {
                    try? Dotenv.configure(atPath: projectEnv.path, overwrite: true)
                }
            }
        case .bundled:
            if let resources = Bundle.main.resourceURL {
                let bundledEnv = resources.appendingPathComponent(envFileName)
                if FileManager.default.fileExists(atPath: bundledEnv.path) {
                    try? Dotenv.configure(atPath: bundledEnv.path, overwrite: true)
                }
            }
        }
    }

    private nonisolated static func findProjectRoot() -> URL? {
        if let envRoot = ProcessInfo.processInfo.environment["VOYAGER_PROJECT_ROOT"],
           !envRoot.isEmpty
        {
            return URL(fileURLWithPath: envRoot)
        }

        return inferProjectRoot(from: Bundle.main.bundleURL)
    }

    private nonisolated static func inferProjectRoot(from start: URL) -> URL? {
        let fm = FileManager.default
        var current = start

        for _ in 0 ..< 8 {
            let backendPath = current.appendingPathComponent("apps/backend")
            let macosPath = current.appendingPathComponent("apps/macos/Voyager")
            if fm.fileExists(atPath: backendPath.path) || fm.fileExists(atPath: macosPath.path) {
                return current
            }
            current.deleteLastPathComponent()
        }

        return nil
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}

@MainActor
private func showBackendNotFoundAlert() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Cannot connect to Voyager Backend"
    alert.informativeText = "Voyager couldn't find a running backend. Please wait a few seconds and retry."
    alert.addButton(withTitle: "Retry")
    alert.addButton(withTitle: "Quit")
    alert.alertStyle = .warning

    let response = alert.runModal()
    return response == .alertFirstButtonReturn
}
