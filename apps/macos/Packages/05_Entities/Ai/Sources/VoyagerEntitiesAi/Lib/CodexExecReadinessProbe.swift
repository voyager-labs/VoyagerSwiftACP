import Foundation

private final class CodexExecProbeOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return CodexExecDiagnosticsBuilder.redactAndBoundStderr(String(decoding: storage, as: UTF8.self))
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data.prefix(max(0, CodexExecDiagnosticsBuilder.maximumStderrBytes - storage.count)))
        lock.unlock()
    }
}

struct CodexExecProbeResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum CodexExecReadinessError: Error, Equatable {
    case executableMissing
    case versionUnreadable
    case unsupportedVersion(String)
    case loginRequired
    case loginProbeFailed(Int32)
}

struct CodexExecReadiness: Equatable {
    let executableURL: URL
    let version: String
}

struct CodexExecReadinessProbe {
    typealias Runner = @Sendable (URL, [String], [String: String]) throws -> CodexExecProbeResult

    private let runner: Runner

    init(runner: @escaping Runner) {
        self.runner = runner
    }

    init() {
        self.init { executableURL, arguments, environment in
            try Self.runProcess(executableURL: executableURL, arguments: arguments, environment: environment)
        }
    }

    static func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
    ) throws -> CodexExecProbeResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let stdoutCollector = CodexExecProbeOutputCollector()
        let stderrCollector = CodexExecProbeOutputCollector()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = error
        output.fileHandleForReading.readabilityHandler = { handle in
            stdoutCollector.append(handle.availableData)
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            stderrCollector.append(handle.availableData)
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            error.fileHandleForReading.readabilityHandler = nil
            try? output.fileHandleForReading.close()
            try? error.fileHandleForReading.close()
        }
        try process.run()
        process.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        stdoutCollector.append(output.fileHandleForReading.readDataToEndOfFile())
        stderrCollector.append(error.fileHandleForReading.readDataToEndOfFile())
        return CodexExecProbeResult(
            exitCode: process.terminationStatus,
            stdout: stdoutCollector.value,
            stderr: stderrCollector.value,
        )
    }

    func check(
        executableURL: URL?,
        environment: [String: String],
        discover: @escaping @Sendable () -> URL? = { Self.discoverExecutable() },
    ) throws -> CodexExecReadiness {
        guard let executableURL = executableURL ?? discover() else {
            throw CodexExecReadinessError.executableMissing
        }
        let versionResult = try runner(executableURL, ["--version"], environment)
        guard versionResult.exitCode == 0, let version = Self.parseVersion(versionResult.stdout) else {
            throw CodexExecReadinessError.versionUnreadable
        }
        guard version.range(of: #"\A0\.148\.[0-9]+\z"#, options: .regularExpression) != nil else {
            throw CodexExecReadinessError.unsupportedVersion(version)
        }
        let loginResult = try runner(executableURL, ["login", "status"], environment)
        guard loginResult.exitCode == 0 else {
            throw CodexExecReadinessError.loginProbeFailed(loginResult.exitCode)
        }
        return CodexExecReadiness(executableURL: CodexPathCanonicalizer.url(executableURL), version: version)
    }

    static func discoverExecutable(
        fileManager: FileManager = .default,
        paths: [String] = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"],
    ) -> URL? {
        paths.first(where: { fileManager.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    static func parseVersion(_ output: String) -> String? {
        let pattern = #"(?m)\bcodex(?:-cli)?\s+(\S+)"#
        guard let match = output.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(output[match])
        guard let token = matched.split(whereSeparator: \.isWhitespace).last.map(String.init),
              token.range(of: Self.semanticVersionPattern, options: .regularExpression) != nil
        else { return nil }
        return token
    }

    private static let semanticVersionPattern =
        #"\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"#
            + #"(?:-(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"#
            + #"(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?"#
            + #"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z"#
}
