import Foundation
import SwiftDotenv

struct EnvironmentLoader {
    private init() {}

    enum LoadError: Error, Equatable {
        case projectRootNotFound
        case resourceURLNotFound
        case fileNotFound(path: String)
    }

    nonisolated private static let projectRootKey = "VOYAGER_PROJECT_ROOT"

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

    nonisolated static func detectAppEnv(bundle: Bundle = .main) -> AppEnv {
        var appEnv: AppEnv = .dev
        if let infoEnv = bundle.infoDictionary?["APP_ENV"] as? String,
           let envType = AppEnv(rawValue: infoEnv)
        {
            appEnv = envType
        }

        Dotenv.set(value: appEnv.rawValue, forKey: "APP_ENV", overwrite: true)
        return appEnv
    }

    nonisolated static func loadEnvFilesWithProjectRootInference(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
    ) throws {
        var resolvedEnvironment = environment

        if resolvedEnvironment[projectRootKey]?.isEmpty != false {
            if let inferredFromBundle = inferProjectRoot(from: bundle.bundleURL) {
                resolvedEnvironment[projectRootKey] = inferredFromBundle.path
            }
        }

        try loadEnvFiles(environment: resolvedEnvironment, bundle: bundle)
    }

    nonisolated static func loadEnvFiles(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
    ) throws {
        let appEnv = detectAppEnv(bundle: bundle)

        let projectRoot = resolveProjectRoot(environment: environment, bundle: bundle)
        if let projectRoot {
            do {
                try loadEnvFile(at: projectRoot.appendingPathComponent(appEnv.envFileName))
                return
            } catch LoadError.fileNotFound {}
        }

        guard let resources = bundle.resourceURL else {
            if projectRoot == nil {
                throw LoadError.projectRootNotFound
            }
            throw LoadError.resourceURLNotFound
        }
        try loadEnvFile(at: resources.appendingPathComponent(appEnv.envFileName))
    }

    nonisolated private static func resolveProjectRoot(
        environment: [String: String],
        bundle: Bundle,
    ) -> URL? {
        if let envRoot = environment[projectRootKey], !envRoot.isEmpty {
            return URL(fileURLWithPath: envRoot)
        }

        return inferProjectRoot(from: bundle.bundleURL)
    }

    nonisolated private static func inferProjectRoot(from start: URL) -> URL? {
        let fm = FileManager.default
        var current = start
        let rootPath = current.pathComponents.first ?? "/"

        while true {
            let macosPath = current.appendingPathComponent("apps/macos/Voyager")
            let xcodeprojPath = current.appendingPathComponent("apps/macos/Voyager/Voyager.xcodeproj")
            if fm.fileExists(atPath: macosPath.path), fm.fileExists(atPath: xcodeprojPath.path) {
                return current
            }

            if current.path == rootPath {
                return nil
            }
            current.deleteLastPathComponent()
        }
    }

    nonisolated private static func loadEnvFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.fileNotFound(path: url.path)
        }

        try? Dotenv.configure(atPath: url.path, overwrite: true)
    }
}

extension Dotenv {
    static var appEnv: EnvironmentLoader.AppEnv? {
        guard let value = self["APP_ENV"]?.stringValue else {
            return nil
        }
        return EnvironmentLoader.AppEnv(rawValue: value)
    }
}
