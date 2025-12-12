import Foundation
import SwiftDotenv

struct Environment {
    enum EnvironmentType: String {
        case dev // Debug builds configuration
        case prod // Release builds configuration

        var envFileName: String {
            switch self {
            case .dev: ".env.dev"
            case .prod: ".env.prod"
            }
        }
    }

    enum BackendMode: String {
        case source // 로컬 uv 사용 (*-Dev 스킴)
        case bundled // 번들 venv 사용 (*-Prod 스킴)
    }

    let envVars: [String: String]
    let environmentType: EnvironmentType
    let backendMode: BackendMode

    init() {
        environmentType = Self.detectEnvironmentType()
        backendMode = Self.detectBackendMode()

        Self.loadEnvFile(environmentType.envFileName)

        envVars = Dotenv.values
    }

    private static func loadEnvFile(_ envFileName: String) {
        if let resources = Bundle.main.resourceURL {
            let bundledEnv = resources.appendingPathComponent(envFileName)
            if FileManager.default.fileExists(atPath: bundledEnv.path) {
                try? Dotenv.configure(atPath: bundledEnv.path, overwrite: true)
                return
            }
        }

        if let projectRoot = findProjectRoot() {
            let projectEnv = projectRoot.appendingPathComponent(envFileName)
            if FileManager.default.fileExists(atPath: projectEnv.path) {
                try? Dotenv.configure(atPath: projectEnv.path, overwrite: true)
                return
            }
        }

        try? Dotenv.configure()
    }

    private static func detectEnvironmentType() -> EnvironmentType {
        if let infoEnv = Bundle.main.infoDictionary?["APP_ENV"] as? String,
           let envType = EnvironmentType(rawValue: infoEnv)
        {
            return envType
        }
        return .dev
    }

    private static func detectBackendMode() -> BackendMode {
        // 스킴에서 주입된 환경변수 (Xcode Run 시)
        if let envMode = ProcessInfo.processInfo.environment["BACKEND_MODE"],
           let mode = BackendMode(rawValue: envMode)
        {
            return mode
        }

        // backend-venv 존재 시 bundled, 없으면 source
        if let resources = Bundle.main.resourceURL {
            let venvPath = resources.appendingPathComponent("backend-venv")
            if FileManager.default.fileExists(atPath: venvPath.path) {
                return .bundled
            }
        }

        return .source
    }

    func value(for key: String) -> String? {
        if let raw = envVars[key], !raw.isEmpty {
            return raw
        }
        return nil
    }

    func backendDirectory() -> String? {
        switch backendMode {
        case .bundled:
            detectBundledBackendDirectory()?.path
        case .source:
            detectSourceBackendDirectory()?.path
        }
    }

    private func detectSourceBackendDirectory() -> URL? {
        guard let projectRoot = Self.findProjectRoot() else { return nil }

        let appsBackend = projectRoot.appendingPathComponent("apps/backend")
        if Self.hasBackendMarker(in: appsBackend) {
            return appsBackend
        }
        return nil
    }

    private static func findProjectRoot() -> URL? {
        let envFiles = [".env", ".env.dev", ".env.prod"]
        let startPoints = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            Bundle.main.bundleURL,
        ]

        for start in startPoints {
            if let found = searchUpwards(from: start, for: envFiles, maxDepth: 20) {
                return found
            }
        }
        return nil
    }

    private static func searchUpwards(from start: URL, for markerFiles: [String], maxDepth: Int) -> URL? {
        let fm = FileManager.default
        var current = start

        for _ in 0 ..< maxDepth {
            for marker in markerFiles where fm.fileExists(atPath: current.appendingPathComponent(marker).path) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    private static func hasBackendMarker(in directory: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: directory.appendingPathComponent("pyproject.toml").path)
            || fm.fileExists(atPath: directory.appendingPathComponent("uv.lock").path)
    }

    private func detectBundledBackendDirectory() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let fm = FileManager.default

        let venvPath = resources.appendingPathComponent("backend-venv")
        if fm.fileExists(atPath: venvPath.path) {
            return venvPath
        }

        let backendPath = resources.appendingPathComponent("backend")
        if fm.fileExists(atPath: backendPath.path) {
            return backendPath
        }

        return nil
    }
}
