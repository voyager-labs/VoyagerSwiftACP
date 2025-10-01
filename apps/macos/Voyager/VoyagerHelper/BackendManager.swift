import Foundation

class BackendManager {
    private var process: Process?
    private var logFileHandle: FileHandle?

    init() {
        configureLogging()
        startBackend()
    }

    private func configureLogging() {
        guard let logPath = ProcessInfo.processInfo.environment["VOYAGER_LOG_FILE"], !logPath.isEmpty else { return }
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
        guard let handle = logFileHandle, !data.isEmpty else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {}
    }

    func startBackend() {
        // 중복 실행 방지
        if let existingProcess = process, existingProcess.isRunning {
            return
        }

        guard let uvCommand = ProcessInfo.processInfo.environment["UV_CMD"], !uvCommand.isEmpty else { return }
        guard let backendDirectory = ProcessInfo.processInfo.environment["BACKEND_DIR"],
              !backendDirectory.isEmpty else { return }

        var env = ProcessInfo.processInfo.environment
        if let customPath = env["VOYAGER_PATH"], !customPath.isEmpty {
            env["PATH"] = customPath + ":" + (env["PATH"] ?? "")
        }

        let process = Process()
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: backendDirectory)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [uvCommand, "run", "dev"]

        // 출력 캡처 설정
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.appendLog(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.appendLog(data)
        }

        do {
            try process.run()
            self.process = process
        } catch {}
    }

    func stopBackend() {
        process?.terminate()
        process = nil
        logFileHandle?.closeFile()
        logFileHandle = nil
    }
}
