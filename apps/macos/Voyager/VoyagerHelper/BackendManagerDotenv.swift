import Foundation
import SwiftDotenv

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
        // TODO: 배포 파이프라인에서 .env 대신 plist 입력을 사용하도록 하고 이 로직 손보기
        envRootURL = resolveProjectRoot()
        guard let root = envRootURL else { return }

        let rootEnv = root.appendingPathComponent(".env")
        guard FileManager.default.fileExists(atPath: rootEnv.path) else { return }

        do {
            try Dotenv.configure(atPath: rootEnv.path, overwrite: true)
            envVars = Dotenv.values
        } catch {}
    }

    private func configureLogging() {
        guard let root = envRootURL else { return }
        guard let raw = envVars["VOYAGER_LOG_FILE"], !raw.isEmpty else { return }
        let url = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : root.appendingPathComponent(raw)

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
        if let running = process, running.isRunning { return }

        let uvCommand = "uv"

        guard let root = envRootURL else { return }
        guard let rawBackendDir = envVars["BACKEND_DIR"], !rawBackendDir.isEmpty else { return }
        let backendDirectory =
            rawBackendDir.hasPrefix("/")
                ? rawBackendDir
                : root.appendingPathComponent(rawBackendDir).path

        guard FileManager.default.fileExists(atPath: backendDirectory) else { return }

        var env = ProcessInfo.processInfo.environment
        for (key, value) in envVars {
            env[key] = value
        }

        guard let appEnv = envVars["APP_ENV"], !appEnv.isEmpty else {
            print("APP_ENV 환경변수가 설정되지 않았습니다.")
            return
        }
        let proc = Process()
        proc.environment = env
        proc.currentDirectoryURL = URL(fileURLWithPath: backendDirectory)
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [uvCommand, "run", appEnv]

        if let handle = logFileHandle {
            proc.standardOutput = handle
            proc.standardError = handle
        }

        do {
            try proc.run()
            process = proc
        } catch {}
    }

    private func resolveProjectRoot(maxLevels: Int = 8) -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []

        let env = ProcessInfo.processInfo.environment
        let hintedKeys = ["VOYAGER_ROOT", "PROJECT_DIR", "SOURCE_ROOT", "SRCROOT", "PWD"]
        for key in hintedKeys {
            if let value = env[key], !value.isEmpty {
                candidates.append(URL(fileURLWithPath: value))
            }
        }

        candidates.append(Bundle.main.bundleURL)

        for candidate in candidates {
            if let root = ascendToRoot(from: candidate, maxLevels: maxLevels, fileManager: fm) {
                return root
            }
        }

        return nil
    }

    private func ascendToRoot(from start: URL, maxLevels: Int, fileManager: FileManager) -> URL? {
        var current = start
        for _ in 0 ..< maxLevels {
            let envPath = current.appendingPathComponent(".env").path
            if fileManager.fileExists(atPath: envPath) { return current }

            var isDir: ObjCBool = false
            let appsPath = current.appendingPathComponent("apps").path
            if fileManager.fileExists(atPath: appsPath, isDirectory: &isDir), isDir.boolValue {
                return current
            }

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
