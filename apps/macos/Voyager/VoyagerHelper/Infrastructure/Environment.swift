import Foundation
import SwiftDotenv

struct Environment {
    typealias AppEnv = EnvironmentLoader.AppEnv
    typealias BackendMode = EnvironmentLoader.BackendMode

    enum BackendDirectoryError: Error, Equatable {
        case projectRootNotFound
        case resourceURLNotFound
        case backendDirectoryNotFound(path: String)
        case backendModeNotSet
    }

    init() {
        try? EnvironmentLoader.loadEnvFiles()
    }

    func backendDirectory() throws -> String {
        guard let backendMode = Dotenv.backendMode else {
            throw BackendDirectoryError.backendModeNotSet
        }
        switch backendMode {
        case .bundled:
            return try detectBundledBackendDirectory().path
        case .source:
            return try detectSourceBackendDirectory().path
        }
    }

    private func detectSourceBackendDirectory() throws -> URL {
        guard let projectRoot = Dotenv.backendMode?.projectRoot else {
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
