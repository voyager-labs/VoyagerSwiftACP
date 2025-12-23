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

        Self.loadEnvFile(environmentType.envFileName, for: backendMode)

        envVars = Dotenv.values
    }

    private static func loadEnvFile(_ envFileName: String, for backendMode: BackendMode) {
        switch backendMode {
        case .source:
            if let projectRoot = findProjectRoot() {
                let projectEnv = projectRoot.appendingPathComponent(envFileName)
                if FileManager.default.fileExists(atPath: projectEnv.path) {
                    try? Dotenv.configure(atPath: projectEnv.path, overwrite: true)
                    return
                }
            }
        case .bundled:
            if let resources = Bundle.main.resourceURL {
                let bundledEnv = resources.appendingPathComponent(envFileName)
                if FileManager.default.fileExists(atPath: bundledEnv.path) {
                    try? Dotenv.configure(atPath: bundledEnv.path, overwrite: true)
                    return
                }
            }
        }
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

        // Info.plist에서 읽기 (빌드 스크립트에서 주입)
        if let infoMode = Bundle.main.infoDictionary?["BACKEND_MODE"] as? String,
           let mode = BackendMode(rawValue: infoMode)
        {
            return mode
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
        // 환경 변수에서 프로젝트 루트 읽기 (Xcode 스킴에서 설정)
        if let envRoot = ProcessInfo.processInfo.environment["VOYAGER_PROJECT_ROOT"],
           !envRoot.isEmpty
        {
            return URL(fileURLWithPath: envRoot)
        }

        // 현재 디렉토리에서 프로젝트 루트 찾기
        let cwd = FileManager.default.currentDirectoryPath
        if !cwd.isEmpty, cwd != "/" {
            return URL(fileURLWithPath: cwd)
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
