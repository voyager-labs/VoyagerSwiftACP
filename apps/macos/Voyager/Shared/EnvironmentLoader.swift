import Foundation
import SwiftDotenv

struct EnvironmentLoader {
    private init() {}

    enum LoadError: Error, Equatable {
        case projectRootNotFound
        case resourceURLNotFound
        case fileNotFound(path: String)
    }

    enum BackendMode: String {
        case source
        case bundled

        private nonisolated static let projectRootKey = "VOYAGER_PROJECT_ROOT"

        nonisolated var envFileName: String {
            switch self {
            case .source:
                ".env.source"
            case .bundled:
                ".env.bundled"
            }
        }

        /// 프로젝트 루트 디렉토리 경로를 반환합니다.
        ///
        /// **source 모드**:
        /// - 프로젝트 루트가 필요한 이유: `.env.dev` 또는 `.env.prod` 파일을 프로젝트 루트에서 찾기 위함
        /// - 우선순위:
        ///   1. 환경 변수 `VOYAGER_PROJECT_ROOT` (Xcode 스킴에서 주입되거나 런타임에 설정)
        ///   2. Bundle 경로에서 상위 디렉토리로 탐색하여 `apps/backend` 또는 `apps/macos/Voyager` 디렉토리를 찾음
        ///
        /// **bundled 모드**:
        /// - 프로젝트 루트가 필요 없는 이유: `.env.prod` 파일이 앱 번들 리소스(`Bundle.main.resourceURL`)에 포함되어 있음
        /// - `loadEnvFiles`에서 번들 리소스 경로를 직접 사용하므로 project root 탐색이 불필요
        /// - 반환값: `nil` (번들 리소스에서 환경 파일을 로드)
        nonisolated var projectRoot: URL? {
            switch self {
            case .source:
                if let envRoot = ProcessInfo.processInfo.environment[BackendMode.projectRootKey],
                   !envRoot.isEmpty
                {
                    return URL(fileURLWithPath: envRoot)
                }
                return BackendMode.inferProjectRoot(from: Bundle.main.bundleURL)
            case .bundled:
                return nil
            }
        }

        nonisolated static func inferProjectRoot(from start: URL, maxDepth: Int = 8) -> URL? {
            let fm = FileManager.default
            var current = start

            for _ in 0 ..< maxDepth {
                let backendPath = current.appendingPathComponent("apps/backend")
                let macosPath = current.appendingPathComponent("apps/macos/Voyager")
                if fm.fileExists(atPath: backendPath.path) || fm.fileExists(atPath: macosPath.path) {
                    return current
                }
                current.deleteLastPathComponent()
            }

            return nil
        }
    }

    enum AppEnv: String {
        case dev
        case prod

        nonisolated var envFileName: String {
            switch self {
            case .dev:
                ".env.dev"
            case .prod:
                ".env.prod"
            }
        }
    }

    nonisolated static func detectBackendMode(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
    ) -> BackendMode {
        if let envMode = environment["BACKEND_MODE"],
           let mode = BackendMode(rawValue: envMode)
        {
            return mode
        }

        if let infoMode = bundle.infoDictionary?["BACKEND_MODE"] as? String,
           let mode = BackendMode(rawValue: infoMode)
        {
            return mode
        }

        return .source
    }

    nonisolated static func detectAppEnv(bundle: Bundle = .main) -> AppEnv {
        if let infoEnv = bundle.infoDictionary?["APP_ENV"] as? String,
           let envType = AppEnv(rawValue: infoEnv)
        {
            return envType
        }
        return .dev
    }

    /// `appEnv`와 `backendMode`를 자동으로 감지한 후 해당하는 환경 파일들을 로드합니다.
    ///
    /// - Throws: `LoadError` 환경 파일을 찾을 수 없거나 로드에 실패한 경우
    nonisolated static func loadEnvFiles(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
    ) throws {
        let appEnv = detectAppEnv(bundle: bundle)
        let backendMode = detectBackendMode(environment: environment, bundle: bundle)

        let baseURL: URL
        switch backendMode {
        case .source:
            guard let projectRoot = backendMode.projectRoot else {
                throw LoadError.projectRootNotFound
            }
            baseURL = projectRoot
        case .bundled:
            guard let resources = bundle.resourceURL else {
                throw LoadError.resourceURLNotFound
            }
            baseURL = resources
        }

        try loadEnvFile(at: baseURL.appendingPathComponent(backendMode.envFileName))
        try loadEnvFile(at: baseURL.appendingPathComponent(appEnv.envFileName))
    }

    private nonisolated static func loadEnvFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.fileNotFound(path: url.path)
        }

        try? Dotenv.configure(atPath: url.path, overwrite: true)
    }
}
