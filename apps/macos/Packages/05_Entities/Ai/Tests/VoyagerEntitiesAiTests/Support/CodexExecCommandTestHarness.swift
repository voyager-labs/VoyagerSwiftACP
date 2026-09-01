import Foundation
@testable import VoyagerEntitiesAi

struct CodexExecProbeInvocation: Equatable {
    let arguments: [String]
    let environment: [String: String]
}

final class CodexExecCommandTestHarness: @unchecked Sendable {
    private(set) var invocations: [CodexExecProbeInvocation] = []
    private(set) var mainExecutionSpawnCount = 0
    var versionOutput = "codex-cli 0.148.0\n"
    var loginExitCode = 0

    func runner(
        executableURL _: URL,
        arguments: [String],
        environment: [String: String],
    ) throws -> CodexExecProbeResult {
        invocations.append(CodexExecProbeInvocation(arguments: arguments, environment: environment))
        if arguments == ["--version"] {
            return CodexExecProbeResult(exitCode: 0, stdout: versionOutput, stderr: "")
        }
        return CodexExecProbeResult(exitCode: Int32(loginExitCode), stdout: "", stderr: "login status")
    }

    func processRunner(process: CodexExecFakeProcess) -> CodexExecProcessController.Runner {
        { [self] _ in
            mainExecutionSpawnCount += 1
            return CodexExecProcess(
                stdout: AsyncThrowingStream { continuation in
                    for chunk in process.stdout {
                        continuation.yield(chunk + Data("\n".utf8))
                    }
                    continuation.finish()
                },
                stderr: AsyncThrowingStream { continuation in continuation.finish() },
                writeStdin: { data in process.write(data) },
                closeStdin: { process.closeStdin() },
                wait: { process.terminationStatus },
                terminate: { process.terminate() },
                cleanup: { process.cleanup() },
            )
        }
    }
}
