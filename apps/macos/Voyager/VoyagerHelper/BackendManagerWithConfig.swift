import Foundation

class BackendManagerWithConfig {
    private var process: Process?
    private var logFileHandle: FileHandle?

    private var envVars: [String: String] = [:]

    init() {
        loadEnvConfig() // xcconfig 파일에서 환경변수 로드
        configureLogging() // 로그 파일 설정
        startBackend() // 백엔드 서버 시작
    }

    private func loadEnvConfig() {
        // Bundle에서 xcconfig 파일 읽기
        guard let configURL = Bundle.main.url(forResource: "Backend", withExtension: "xcconfig") else {
            return
        }

        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return
        }

        // xcconfig 파일 파싱 (KEY=VALUE 형태)
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                let value = String(parts[1])
                envVars[parts[0]] = value
            }
        }

        // $(SRCROOT) 변수를 실제 경로로 해석
        let bundlePath = Bundle.main.bundlePath
        let srcRoot = URL(fileURLWithPath: bundlePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        if var backendDir = envVars["BACKEND_DIR"] {
            if backendDir.contains("$(SRCROOT)") {
                backendDir = backendDir.replacingOccurrences(of: "$(SRCROOT)", with: srcRoot)
                envVars["BACKEND_DIR"] = backendDir
            }
        }

        if var logFile = envVars["VOYAGER_LOG_FILE"] {
            if logFile.contains("$(SRCROOT)") {
                logFile = logFile.replacingOccurrences(of: "$(SRCROOT)", with: srcRoot)
                envVars["VOYAGER_LOG_FILE"] = logFile
            }
        }
    }

    private func configureLogging() {
        // 로그 파일 설정 (xcconfig에서 지정된 경로)
        guard let logPath = envVars["VOYAGER_LOG_FILE"], !logPath.isEmpty else { return }
        let url = URL(fileURLWithPath: logPath)
        do {
            if !FileManager.default.fileExists(atPath: logPath) {
                FileManager.default.createFile(atPath: logPath, contents: nil)
            }
            logFileHandle = try FileHandle(forWritingTo: url)
            try logFileHandle?.seekToEnd()
        } catch {
            logFileHandle = nil
        }
    }

    private func appendLog(_ data: Data) {
        // 백엔드 출력을 로그 파일에 기록
        guard let handle = logFileHandle, !data.isEmpty else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // 로그 쓰기 실패 시 무시
        }
    }

    func startBackend() {
        // 중복 실행 방지
        if let existingProcess = process, existingProcess.isRunning {
            return
        }

        // xcconfig에서 필요한 환경변수 확인
        guard let uvCommand = envVars["UV_CMD"], !uvCommand.isEmpty else {
            return
        }
        guard let backendDirectory = envVars["BACKEND_DIR"], !backendDirectory.isEmpty else {
            return
        }

        // 환경변수 설정 (xcconfig 값들을 추가)
        var env = ProcessInfo.processInfo.environment
        for (key, value) in envVars {
            env[key] = value
        }

        // 백엔드 프로세스 설정
        let process = Process()
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: backendDirectory)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [uvCommand, "run", "dev"] // uv run dev 명령어 실행

        // 백엔드 출력 캡처 설정
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // 출력을 로그 파일에 기록
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.appendLog(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.appendLog(data)
        }

        do {
            try process.run() // 백엔드 프로세스 시작
            self.process = process
        } catch {
            // 백엔드 시작 실패 시 무시
        }
    }

    func stopBackend() {
        // 백엔드 프로세스 종료
        process?.terminate()
        process = nil
        // 로그 파일 핸들 정리
        logFileHandle?.closeFile()
        logFileHandle = nil
    }
}
