import Foundation
import SwiftDotenv

struct Environment {
    typealias AppEnv = EnvironmentLoader.AppEnv
    typealias BackendMode = EnvironmentLoader.BackendMode

    enum BackendDirectoryError: Error, Equatable {
        case projectRootNotFound
        case resourceURLNotFound
        case backendDirectoryNotFound(path: String)
    }

    let envVars: [String: String]
    let appEnv: AppEnv
    let backendMode: BackendMode

    init() {
        appEnv = EnvironmentLoader.detectAppEnv()
        backendMode = EnvironmentLoader.detectBackendMode()

        try? EnvironmentLoader.loadEnvFiles()

        envVars = Dotenv.values
    }

    func value(for key: String) -> String? {
        if let raw = envVars[key], !raw.isEmpty {
            return raw
        }
        return nil
    }

    func backendDirectory() throws -> String {
        switch backendMode {
        case .bundled:
            try detectBundledBackendDirectory().path
        case .source:
            try detectSourceBackendDirectory().path
        }
    }

    private func detectSourceBackendDirectory() throws -> URL {
        guard let projectRoot = backendMode.projectRoot else {
            throw BackendDirectoryError.projectRootNotFound
        }

        let appsBackend = projectRoot.appendingPathComponent("apps/backend")
        let fm = FileManager.default

        guard fm.fileExists(atPath: appsBackend.appendingPathComponent("pyproject.toml").path)
            || fm.fileExists(atPath: appsBackend.appendingPathComponent("uv.lock").path)
        else {
            throw BackendDirectoryError.backendDirectoryNotFound(path: appsBackend.path)
        }

        return appsBackend
    }

    private func detectBundledBackendDirectory() throws -> URL {
        guard let resources = Bundle.main.resourceURL else {
            throw BackendDirectoryError.resourceURLNotFound
        }

        // Nuitka 바이너리 디렉토리 (server/Voyager Backend)
        let serverPath = resources.appendingPathComponent("server")

        guard FileManager.default.fileExists(atPath: serverPath.path) else {
            throw BackendDirectoryError.backendDirectoryNotFound(path: serverPath.path)
        }

        return serverPath
    }
}
