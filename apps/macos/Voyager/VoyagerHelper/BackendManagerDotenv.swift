import Foundation
import SwiftDotenv

/// 헬퍼 앱: .env로 백엔드 구동
final class BackendManagerDotenv {
    private var process: Process?
    private var logFileHandle: FileHandle?

    private var envVars: [String: String] = [:]
    private var envRootURL: URL?

    init() {
        loadEnvConfig()
        configureLogging()
        startBackend()
    }

    private func loadEnvConfig() {
        // 프로젝트 루트 추정 후 루트/.env 로드
        envRootURL = inferRootFromBundle(start: Bundle.main.bundleURL)
        if let root = envRootURL {
            let rootEnv = root.appendingPathComponent(".env")
            try? Dotenv.configure(atPath: rootEnv.path, overwrite: true)
            envVars = Dotenv.values
        }
    }

    private func configureLogging() {
        // VOYAGER_LOG_FILE이 상대경로면 루트 기준으로 해석
        guard let root = envRootURL else { return }
        guard let raw = envVars["VOYAGER_LOG_FILE"], !raw.isEmpty else { return }
        let url = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : root.appendingPathComponent(raw)

        // 상위 디렉터리 생성
        let dirURL = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {}

        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            logFileHandle = try FileHandle(forWritingTo: url)
            try logFileHandle?.seekToEnd()
        } catch {
            logFileHandle = nil
        }
    }

    func startBackend() {
        // 중복 실행 방지
        if let running = process, running.isRunning { return }

        // UV_CMD 기본: "uv"
        let uvCommand = "uv"

        // BACKEND_DIR 해석 (상대면 루트 기준)
        guard let root = envRootURL else { return }
        guard let rawBackendDir = envVars["BACKEND_DIR"], !rawBackendDir.isEmpty else { return }
        let backendDirectory =
            rawBackendDir.hasPrefix("/")
                ? rawBackendDir
                : root.appendingPathComponent(rawBackendDir).path

        // 존재 확인
        guard FileManager.default.fileExists(atPath: backendDirectory) else { return }

        // 환경 구성
        var env = ProcessInfo.processInfo.environment
        for (key, value) in envVars {
            env[key] = value
        }

        // APP_ENV 환경변수로 uv 명령어 실행
        guard let appEnv = envVars["APP_ENV"], !appEnv.isEmpty else {
            print("APP_ENV 환경변수가 설정되지 않았습니다.")
            return
        }
        let proc = Process()
        proc.environment = env
        proc.currentDirectoryURL = URL(fileURLWithPath: backendDirectory)
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [uvCommand, "run", appEnv]

        // 백엔드 stdout/stderr을 파일로 직접 리다이렉션
        if let handle = logFileHandle {
            proc.standardOutput = handle
            proc.standardError = handle
        }

        do {
            try proc.run()
            process = proc
        } catch {}
    }

    // 번들 경로에서 상향 이동하며 'apps' 폴더가 있는 경로를 루트로 간주
    private func inferRootFromBundle(start: URL, maxLevels: Int = 64) -> URL? {
        var current = start
        for _ in 0 ..< maxLevels {
            let apps = current.appendingPathComponent("apps")
            if FileManager.default.fileExists(atPath: apps.path, isDirectory: nil) { return current }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    func stopBackend() {
        process?.terminate()
        process = nil
        logFileHandle?.closeFile()
        logFileHandle = nil
    }
}
