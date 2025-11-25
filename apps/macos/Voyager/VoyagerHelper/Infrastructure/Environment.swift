import Foundation
import SwiftDotenv

struct Environment {
    let envVars: [String: String]

    init() {
        try? Dotenv.configure()
        envVars = Dotenv.values
    }

    func value(for key: String) -> String? {
        guard let raw = envVars[key], !raw.isEmpty else { return nil }
        return raw
    }

    func backendDirectory() -> String? {
        let appEnv = value(for: "APP_ENV") ?? "dev"

        if appEnv == "prod" {
            // Prod: 번들 리소스에서 백엔드 찾기
            if let bundled = detectBundledBackendDirectory() {
                return bundled.path
            }
        } else {
            // Dev: 소스 디렉토리에서 백엔드 찾기
            if let detected = detectSourceBackendDirectory() {
                return detected.path
            }
        }

        return nil
    }

    /// Dev 스킴: 소스 디렉토리에서 백엔드 찾기 (로컬 uv 사용)
    private func detectSourceBackendDirectory() -> URL? {
        let fm = FileManager.default
        let helperBundle = Bundle.main.bundleURL

        // Helper 번들 위치에서 시작해서 백엔드 찾기
        var current = helperBundle
        for _ in 0 ..< 8 {
            // pyproject.toml이 있는 디렉토리 = 백엔드 디렉토리
            let pyprojectPath = current.appendingPathComponent("pyproject.toml")
            if fm.fileExists(atPath: pyprojectPath.path) {
                return current
            }

            // uv.lock이 있는 디렉토리 = 백엔드 디렉토리
            let uvLockPath = current.appendingPathComponent("uv.lock")
            if fm.fileExists(atPath: uvLockPath.path) {
                return current
            }

            // 현재 디렉토리에 backend 서브디렉토리가 있는지 확인
            let backendSubdir = current.appendingPathComponent("backend")
            let backendPyproject = backendSubdir.appendingPathComponent("pyproject.toml")
            if fm.fileExists(atPath: backendPyproject.path) {
                return backendSubdir
            }

            // Helper 근처에 backend 디렉토리 확인
            let parent = current.deletingLastPathComponent()
            let nearbyBackend = parent.appendingPathComponent("backend")
            let nearbyPyproject = nearbyBackend.appendingPathComponent("pyproject.toml")
            if fm.fileExists(atPath: nearbyPyproject.path) {
                return nearbyBackend
            }

            // 상위로 이동
            if parent.path == current.path { break }
            current = parent
        }

        return nil
    }

    /// Prod 스킴: 번들 리소스에서 백엔드 찾기 (번들된 휠과 venv 사용)
    private func detectBundledBackendDirectory() -> URL? {
        let fm = FileManager.default

        // 번들 리소스에서 backend-venv 찾기
        if let resources = Bundle.main.resourceURL {
            // backend-venv가 번들 리소스에 있는 경우
            let venvPath = resources.appendingPathComponent("backend-venv")
            if fm.fileExists(atPath: venvPath.path) {
                // venv 내부에 백엔드 코드가 있는지 확인
                // 일반적으로 venv/lib/python*/site-packages/에 휠이 설치됨
                // 하지만 실행을 위해서는 venv 자체가 working directory가 될 수 있음
                return venvPath
            }

            // 번들 리소스에 backend 디렉토리가 있는 경우
            let backendPath = resources.appendingPathComponent("backend")
            if fm.fileExists(atPath: backendPath.path) {
                return backendPath
            }
        }

        return nil
    }
}
