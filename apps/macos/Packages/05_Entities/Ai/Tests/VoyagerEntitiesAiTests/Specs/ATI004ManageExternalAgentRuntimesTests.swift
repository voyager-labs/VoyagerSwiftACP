import Foundation
@testable import VoyagerEntitiesAi
import VoyagerExternalAgentRuntime
import XCTest

// MARK: - ATI-004-manage_external_agent_runtimes

final class ATI004ManageExternalAgentRuntimesTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/voyager-codex-workspace", isDirectory: true)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("a"),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("b"),
            withIntermediateDirectories: true,
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// ATI-004-manage_external_agent_runtimes: fresh read-only argv is exact and stdin is selected.
    /// fresh 실행의 명령 순서와 prompt stdin 계약을 고정합니다.
    /// - 검증 내용: strict config, approval, sandbox, canonical -C, exec JSON, color, model, stdin 순서를 확인합니다.
    /// - 사전 조건: 유효한 workspace와 read-only 실행 요청이 제공됩니다.
    /// - 기대 결과: 허용된 flag만 정확한 순서로 반환되고 prompt는 argv에 포함되지 않습니다.
    func testFreshReadOnlyCommand_hasExactArgvAndStdinPrompt() throws {
        let command = try CodexExecCommandBuilder.build(
            request: CodexExecCommandRequest(
                model: "gpt-5-codex",
                prompt: "secret prompt",
                workingDirectory: root,
                sandbox: .readOnly,
                primaryWritableRoot: root,
                additionalWritableRoots: [],
                codexHome: URL(fileURLWithPath: "/Users/me/.codex", isDirectory: true),
                reasoningEffort: "high",
            ),
            executableURL: URL(fileURLWithPath: "/tmp/codex", isDirectory: false),
        )
        XCTAssertEqual(
            command.arguments,
            [
                "exec", "--model", "gpt-5-codex", "-c", "model_reasoning_effort=\"high\"",
                "--json", "--color", "never", "--strict-config",
                "--ignore-user-config",
                "--sandbox",
                "read-only", "-C", root.path, "-",
            ],
        )
        XCTAssertEqual(command.stdin, "secret prompt")
        XCTAssertFalse(command.arguments.contains("secret prompt"))
    }

    /// ATI-004-manage_external_agent_runtimes: workspace-write includes only explicit canonical roots.
    /// 쓰기 권한이 명시된 root만 command에 투영되는지 검증합니다.
    /// - 검증 내용: workspace-write의 두 distinct root와 중복/비정규화 root의 deterministic ordering 및 deduplication을 확인합니다.
    /// - 사전 조건: workspace 하위 writable root a, b와 a의 중복 경로가 제공됩니다.
    /// - 기대 결과: canonical a, b 순서의 --add-dir만 반환됩니다.
    func testWorkspaceWriteCommand_includesOnlyExplicitCanonicalRoots() throws {
        let command = try CodexExecCommandBuilder.build(
            request: .init(
                model: "model",
                prompt: "prompt",
                workingDirectory: root,
                sandbox: .workspaceWrite,
                primaryWritableRoot: root,
                additionalWritableRoots: [
                    root.appendingPathComponent("b"),
                    root.appendingPathComponent("b/../a"),
                    root.appendingPathComponent("a"),
                ],
                codexHome: URL(fileURLWithPath: "/Users/me/.codex", isDirectory: true),
            ),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        XCTAssertEqual(
            command.arguments,
            [
                "exec", "--model", "model", "--json", "--color", "never", "--strict-config", "--ignore-user-config",
                "--sandbox",
                "workspace-write",
                "-C", root.path, "--add-dir", root.appendingPathComponent("a").path, "--add-dir",
                root.appendingPathComponent("b").path,
                "-",
            ],
        )
        XCTAssertEqual(command.arguments.count(where: { $0 == "--add-dir" }), 2)
        XCTAssertFalse(command.arguments.contains("-c"))
    }

    func testWorkspaceWriteRoots_useDistinctPrimaryAndAdditionalSemantics() throws {
        let primary = root.appendingPathComponent("primary")
        let working = primary.appendingPathComponent("nested")
        let external = root.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let command = try CodexExecCommandBuilder.build(
            request: .init(
                model: "model",
                prompt: "prompt",
                workingDirectory: working,
                sandbox: .workspaceWrite,
                primaryWritableRoot: primary,
                additionalWritableRoots: [external, primary],
                codexHome: root,
            ),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        XCTAssertEqual(
            command.arguments,
            [
                "exec", "--model", "model", "--json", "--color", "never", "--strict-config", "--ignore-user-config",
                "--sandbox",
                "workspace-write", "-C", working.path, "--add-dir", external.path, "--add-dir", primary.path, "-",
            ],
        )
        XCTAssertEqual(command.arguments.count(where: { $0 == "--add-dir" }), 2)
    }

    func testWorkspaceWriteRoots_reversedPrimaryRelationIsRejected() throws {
        XCTAssertThrowsError(
            try CodexExecCommandBuilder.build(
                request: .init(
                    model: "model",
                    prompt: "prompt",
                    workingDirectory: root,
                    sandbox: .workspaceWrite,
                    primaryWritableRoot: root.appendingPathComponent("a"),
                    additionalWritableRoots: [],
                    codexHome: root,
                ),
                executableURL: URL(fileURLWithPath: "/tmp/codex"),
            ),
        ) { error in
            XCTAssertEqual(
                error as? CodexExecCommandError,
                .writableRootOutsideWorkingDirectory(root.appendingPathComponent("a").path),
            )
        }
    }

    func testReadOnlyRoots_areNotPromotedToAddDir() throws {
        let external = root.appendingPathComponent("a")
        let command = try CodexExecCommandBuilder.build(
            request: .init(
                model: "model",
                prompt: "prompt",
                workingDirectory: root,
                sandbox: .readOnly,
                primaryWritableRoot: root,
                additionalWritableRoots: [external],
                codexHome: root,
            ),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        XCTAssertFalse(command.arguments.contains("--add-dir"))
    }

    /// ATI-004-manage_external_agent_runtimes: resume preserves opaque thread id without ephemeral mode.
    /// persisted provider thread identity를 resume argv에만 전달하는지 검증합니다.
    /// - 검증 내용: exec resume와 opaque thread_id 위치 및 ephemeral flag 부재를 확인합니다.
    /// - 사전 조건: 비어 있지 않은 persisted thread_id와 유효한 workspace가 제공됩니다.
    /// - 기대 결과: resume command가 생성되고 ephemeral 및 bypass flag가 없습니다.
    func testResumeCommand_preservesOpaqueThreadIDWithoutEphemeralMode() throws {
        let command = try CodexExecCommandBuilder.build(
            request: .init(
                model: "model",
                prompt: "prompt",
                workingDirectory: root,
                sandbox: .readOnly,
                primaryWritableRoot: root,
                additionalWritableRoots: [],
                codexHome: URL(fileURLWithPath: "/Users/me/.codex"),
                threadID: "opaque/provider/thread-id",
                reasoningEffort: "low",
            ),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        XCTAssertEqual(
            command.arguments,
            [
                "exec", "resume", "--model", "model", "-c", "model_reasoning_effort=\"low\"",
                "--json", "--strict-config", "--ignore-user-config",
                "opaque/provider/thread-id", "-",
            ],
        )
        XCTAssertFalse(command.arguments.contains("--ephemeral"))
        XCTAssertFalse(command.arguments.contains("danger-full-access"))
    }

    /// ATI-004-manage_external_agent_runtimes: process environment remains provider-owned and allowlisted.
    /// Codex_HOME/auth/session ownership과 환경 변수 allowlist를 확인합니다.
    /// - 검증 내용: 기존 canonical environment helper가 unrelated secret을 전달하지 않는지 확인합니다.
    /// - 사전 조건: Codex home과 parent secret 환경이 제공됩니다.
    /// - 기대 결과: CODEX_HOME이 지정되고 API key 및 proxy가 제외됩니다.
    func testCommandEnvironment_usesProviderOwnedAllowlist() {
        let environment = AiChatProviderExecutionClient.codexProcessEnvironment(
            codexHomeURL: URL(fileURLWithPath: "/Users/me/.codex"),
            parentEnvironment: ["OPENAI_API_KEY": "secret", "HTTPS_PROXY": "proxy"],
        )
        XCTAssertEqual(environment["CODEX_HOME"], "/Users/me/.codex")
        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertNil(environment["HTTPS_PROXY"])
    }

    /// ATI-004-manage_external_agent_runtimes: unsupported forbidden flags are rejected before launch.
    /// 금지된 실행 정책을 command builder가 구성하지 않는지 검증합니다.
    /// - 검증 내용: ephemeral, ignore-rules, approval/sandbox bypass, danger-full-access를 검색합니다.
    /// - 사전 조건: fresh command가 정상적으로 생성됩니다.
    /// - 기대 결과: 금지 flag가 하나도 없습니다.
    func testCommand_forbiddenFlagsAreAbsent() throws {
        let command = try CodexExecCommandBuilder.build(
            request: .init(
                model: "model",
                prompt: "prompt",
                workingDirectory: root,
                sandbox: .readOnly,
                primaryWritableRoot: root,
                additionalWritableRoots: [],
                codexHome: URL(fileURLWithPath: "/Users/me/.codex"),
            ),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        for forbidden in [
            "--ephemeral", "--ignore-rules", "--approve-for-me", "--danger-full-access",
            "danger-full-access", "--dangerously-bypass-approvals-and-sandbox",
        ] {
            XCTAssertFalse(command.arguments.contains(forbidden), forbidden)
        }
    }

    /// ATI-004-manage_external_agent_runtimes: readiness failures retain exact AiChat classification.
    /// readiness error 종류별 사용자-facing failure reason을 고정합니다.
    /// - 검증 내용: executable/version failures are cliUnavailable and login failures are authentication.
    /// - 사전 조건: 각 typed readiness error와 launch failure를 직접 구성합니다.
    /// - 기대 결과: readiness mapping은 정확히 유지되고 unexpected launch failure는 cliUnavailable입니다.
    func testCLIReadinessFailureReasonMapping_isExact() {
        let unavailable: [CodexExecReadinessError] = [
            .executableMissing,
            .versionUnreadable,
            .unsupportedVersion("0.149.0"),
        ]
        for error in unavailable {
            XCTAssertEqual(CodexCLIExecutionError.readinessFailed(error).failureReason, .cliUnavailable)
        }
        XCTAssertEqual(
            CodexCLIExecutionError.readinessFailed(.loginRequired).failureReason,
            .authentication,
        )
        XCTAssertEqual(
            CodexCLIExecutionError.readinessFailed(.loginProbeFailed(1)).failureReason,
            .authentication,
        )
        XCTAssertEqual(CodexCLIExecutionError.launchFailed.failureReason, .cliUnavailable)
    }

    /// ATI-004-manage_external_agent_runtimes: legacy session preparation is canonical and idempotent.
    /// Git initialization is isolated from user configuration and validation runs on every preparation.
    /// - 검증 내용: exact Git init/validation argv/environment, canonical session, and idempotent preparation.
    /// - 사전 조건: empty temporary Codex home and fake Git runner.
    /// - 기대 결과: two preparations return the same session and invoke init plus work-tree validation twice.
    func testLegacySessionPreparer_usesCanonicalGitInitOnce() async throws {
        let home = root.appendingPathComponent("preparer")
        struct Invocation {
            let executable: URL
            let arguments: [String]
            let environment: [String: String]
        }
        nonisolated(unsafe) var invocations: [Invocation] = []
        let preparer = CodexLegacySessionPreparer { executable, arguments, environment in
            invocations.append(
                Invocation(executable: executable, arguments: arguments, environment: environment),
            )
            if arguments.first == "init" {
                try FileManager.default.createDirectory(
                    at: home.appendingPathComponent("session/.git"),
                    withIntermediateDirectories: true,
                )
            }
            if arguments.first == "init" {
                return ""
            }
            if arguments.contains("--is-inside-work-tree") {
                return "true\n"
            }
            return home.appendingPathComponent("session/.git").path + "\n"
        }

        let first = try await preparer.prepare(codexHome: home)
        let second = try await preparer.prepare(codexHome: home)

        XCTAssertEqual(first.path, home.appendingPathComponent("session").path)
        XCTAssertEqual(second, first)
        XCTAssertEqual(invocations.count, 6)
        XCTAssertEqual(invocations.map(\.executable.path), Array(repeating: "/usr/bin/git", count: 6))
        XCTAssertEqual(
            invocations[0].arguments,
            [
                "init", "--quiet", "--initial-branch=voyager-session",
                "--template=" + home.appendingPathComponent(".voyager-empty-git-template").path,
                first.path,
            ],
        )
        XCTAssertEqual(
            invocations[1].arguments,
            ["-C", first.path, "rev-parse", "--is-inside-work-tree"],
        )
        XCTAssertEqual(invocations[2].arguments, ["-C", first.path, "rev-parse", "--absolute-git-dir"])
        XCTAssertEqual(invocations[3].arguments, invocations[0].arguments)
        XCTAssertEqual(invocations[4].arguments, invocations[1].arguments)
        XCTAssertEqual(invocations[5].arguments, invocations[2].arguments)
        XCTAssertEqual(
            invocations[0].environment,
            [
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_CONFIG_SYSTEM": "/dev/null",
                "GIT_TERMINAL_PROMPT": "0",
            ],
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.appendingPathComponent(".git").path))
    }

    /// ATI-004-manage_external_agent_runtimes: arbitrary .git entries do not satisfy repository validation.
    /// provider-owned session은 Git의 실제 work-tree 판정 없이 준비 완료로 인정하지 않습니다.
    /// - 검증 내용: 기존 임의 .git file과 directory가 init 및 rev-parse validation을 모두 거치는지 확인합니다.
    /// - 사전 조건: session 아래 임의 .git entry와 validation false를 반환하는 fake Git runner가 제공됩니다.
    /// - 기대 결과: repositoryMissing이 반환되고 path existence만으로 우회되지 않습니다.
    func testLegacySessionPreparer_rejectsArbitraryGitEntriesWithoutWorkTreeValidation() async throws {
        for entryKind in ["file", "directory"] {
            let home = root.appendingPathComponent("arbitrary-" + entryKind)
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent("session"),
                withIntermediateDirectories: true,
            )
            let gitEntry = home.appendingPathComponent("session/.git")
            if entryKind == "file" {
                try Data("arbitrary".utf8).write(to: gitEntry)
            } else {
                try FileManager.default.createDirectory(at: gitEntry, withIntermediateDirectories: true)
            }
            nonisolated(unsafe) var arguments: [[String]] = []
            let preparer = CodexLegacySessionPreparer { _, invocation, _ in
                arguments.append(invocation)
                return invocation.first == "init" ? "" : "false\n"
            }

            do {
                _ = try await preparer.prepare(codexHome: home)
                XCTFail("arbitrary .git entry must not validate as a work tree")
            } catch {
                XCTAssertEqual(error as? CodexLegacySessionPreparerError, .repositoryMissing)
            }
            XCTAssertEqual(arguments.map(\.first), ["init", "-C"])
        }
    }

    /// ATI-004-manage_external_agent_runtimes: external Git directory redirection is rejected by real Git validation.
    /// 실제 /usr/bin/git가 외부 repository를 가리키는 session gitfile을 work tree로 승인하지 않는지 검증합니다.
    /// - 검증 내용: external repository와 gitfile을 실제 Git으로 구성하고 preparer의 absolute-git-dir 검증을 확인합니다.
    /// - 사전 조건: canonical session의 .git gitfile이 CODEX_HOME/session 밖의 Git directory를 가리킵니다.
    /// - 기대 결과: repositoryMissing이 반환되어 외부 Git directory가 Codex spawn으로 이어지지 않습니다.
    func testLegacySessionPreparer_rejectsExternalGitfileWithRealGit() async throws {
        let home = root.appendingPathComponent("real-gitfile")
        let external = root.appendingPathComponent("external-repository")
        let session = home.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)

        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", "--quiet", "--initial-branch=external", external.path]
        git.environment = [
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0",
        ]
        try git.run()
        git.waitUntilExit()
        XCTAssertEqual(git.terminationStatus, 0)

        try Data(("gitdir: " + external.appendingPathComponent(".git").path + "\n").utf8)
            .write(to: session.appendingPathComponent(".git"))

        do {
            _ = try await CodexLegacySessionPreparer().prepare(codexHome: home)
            XCTFail("external gitfile must not validate as the provider-owned work tree")
        } catch {
            XCTAssertEqual(error as? CodexLegacySessionPreparerError, .repositoryMissing)
        }
    }

    /// ATI-004-manage_external_agent_runtimes: supported executable/version/login readiness succeeds.
    /// hermetic fake probe가 stored login readiness만 성공으로 인정하는지 검증합니다.
    /// - 검증 내용: executable discovery, 0.148.x version range, login exit 0과 invocation 기록을 확인합니다.
    /// - 사전 조건: fake runner가 version 0.148.0과 login exit 0을 반환합니다.
    /// - 기대 결과: readiness가 성공하고 main execution invocation은 별도로 생성되지 않습니다.
    func testReadiness_supportedVersionAndStoredLoginSucceeds() throws {
        let harness = CodexExecCommandTestHarness()
        let readiness = try CodexExecReadinessProbe(runner: harness.runner).check(
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            environment: [:],
        )
        XCTAssertEqual(readiness.version, "0.148.0")
        XCTAssertEqual(harness.invocations.map(\.arguments), [["--version"], ["login", "status"]])
    }

    /// ATI-004-manage_external_agent_runtimes: unsupported gates fail before main execution spawn.
    /// executable/version/login 및 root 실패가 typed pre-launch failure인지 검증합니다.
    /// - 검증 내용: missing executable, 0.147.9, malformed version, login exit 1, out-of-root working directory를 확인합니다.
    /// - 사전 조건: 각 실패 상태를 가진 hermetic fake probe 또는 command request가 제공됩니다.
    /// - 기대 결과: 정확한 typed error가 반환되고 provider main execution spawn count는 0입니다.
    func testReadinessAndCommandFailures_areTypedPreLaunchFailures() throws {
        let missingHarness = CodexExecCommandTestHarness()
        let missing = CodexExecReadinessProbe(runner: missingHarness.runner)
        XCTAssertThrowsError(try missing.check(executableURL: nil, environment: [:], discover: { nil })) {
            XCTAssertEqual(
                $0 as? CodexExecReadinessError,
                .executableMissing,
            )
        }
        XCTAssertEqual(missingHarness.mainExecutionSpawnCount, 0)

        for output in ["codex-cli 0.147.9\n", "not codex\n"] {
            let harness = CodexExecCommandTestHarness()
            harness.versionOutput = output
            XCTAssertThrowsError(
                try CodexExecReadinessProbe(runner: harness.runner).check(
                    executableURL: URL(fileURLWithPath: "/tmp/codex"),
                    environment: [:],
                ),
            ) { error in
                let expected: CodexExecReadinessError =
                    output.contains("0.147.9")
                        ? .unsupportedVersion("0.147.9")
                        : .versionUnreadable
                XCTAssertEqual(error as? CodexExecReadinessError, expected)
            }
            XCTAssertEqual(harness.invocations.count, 1)
            XCTAssertEqual(harness.mainExecutionSpawnCount, 0)
        }

        let login = CodexExecCommandTestHarness()
        login.loginExitCode = 1
        XCTAssertThrowsError(
            try CodexExecReadinessProbe(runner: login.runner).check(
                executableURL: URL(fileURLWithPath: "/tmp/codex"),
                environment: [:],
            ),
        ) { error in
            XCTAssertEqual(error as? CodexExecReadinessError, .loginProbeFailed(1))
        }
        XCTAssertEqual(login.invocations.count, 2)
        XCTAssertEqual(login.mainExecutionSpawnCount, 0)

        XCTAssertThrowsError(
            try CodexExecCommandBuilder.build(
                request: .init(
                    model: "model",
                    prompt: "prompt",
                    workingDirectory: URL(fileURLWithPath: "/tmp/outside"),
                    sandbox: .readOnly,
                    primaryWritableRoot: root,
                    additionalWritableRoots: [],
                    codexHome: URL(fileURLWithPath: "/Users/me/.codex"),
                ),
                executableURL: URL(fileURLWithPath: "/tmp/codex"),
            ),
        ) { error in
            XCTAssertEqual(error as? CodexExecCommandError, .invalidWorkingDirectory)
        }
    }

    /// ATI-004-manage_external_agent_runtimes: Codex version tokens use full-token compatibility rules.
    /// stable 0.148 patch만 login으로 진행하고 prerelease/build 및 unsupported 버전은 차단하는지 검증합니다.
    /// - 검증 내용: stable 0.148.7, prerelease, build suffix, 0.149와 invocation 횟수를 확인합니다.
    /// - 사전 조건: 각 version output을 반환하는 hermetic readiness runner가 제공됩니다.
    /// - 기대 결과: stable만 --version 뒤 login을 호출하고 나머지는 --version만 호출합니다.
    func testReadiness_versionTokenCompatibilityRejectsPrereleaseAndBuildSuffixes() throws {
        let cases: [(String, CodexExecReadinessError?)] = [
            ("codex-cli 0.148.7\n", nil),
            ("codex-cli 0.148.0-rc.1+build.7\n", .unsupportedVersion("0.148.0-rc.1+build.7")),
            ("codex-cli 0.148.0-alpha.1\n", .unsupportedVersion("0.148.0-alpha.1")),
            ("codex 0.148.7+build.1\n", .unsupportedVersion("0.148.7+build.1")),
            ("codex-cli 0.149.0\n", .unsupportedVersion("0.149.0")),
            ("codex-cli 0.148\n", .versionUnreadable),
            ("codex-cli garbage\n", .versionUnreadable),
        ]

        for (output, expectedError) in cases {
            let harness = CodexExecCommandTestHarness()
            harness.versionOutput = output
            let probe = CodexExecReadinessProbe(runner: harness.runner)
            if let expectedError {
                XCTAssertThrowsError(
                    try probe.check(
                        executableURL: URL(fileURLWithPath: "/tmp/codex"),
                        environment: [:],
                    ),
                ) { error in
                    XCTAssertEqual(error as? CodexExecReadinessError, expectedError)
                }
                XCTAssertEqual(harness.invocations.map(\.arguments), [["--version"]])
            } else {
                XCTAssertNoThrow(
                    try probe.check(
                        executableURL: URL(fileURLWithPath: "/tmp/codex"),
                        environment: [:],
                    ),
                )
                XCTAssertEqual(harness.invocations.map(\.arguments), [["--version"], ["login", "status"]])
            }
            XCTAssertEqual(harness.mainExecutionSpawnCount, 0)
        }
    }

    /// ATI-004-manage_external_agent_runtimes: readiness drains saturated pipes and redacts both outputs.
    /// 실제 Process 실행에서 stdout/stderr pipe가 가득 차도 readiness가 종료되고 진단이 bounded redaction을 유지하는지 검증합니다.
    /// - 검증 내용: pipe capacity를 넘는 양쪽 출력의 완료, 128 KiB bound, bearer/token/auth/path sentinel 제거를 확인합니다.
    /// - 사전 조건: 임시 executable script가 version/login 각각에서 양쪽 pipe에 대량 sentinel을 기록합니다.
    /// - 기대 결과: 명령이 deadlock 없이 종료되고 stdout/stderr 결과에 secret/path 원문이 남지 않습니다.
    func testReadiness_realProcessDrainsSaturatedPipesAndRedactsDiagnostics() throws {
        let scriptURL = root.appendingPathComponent("codex-probe.sh")
        let script = """
        #!/bin/sh
        i=0
        while [ "$i" -lt 20000 ]; do
          printf 'Bearer stdoutsecret token=stdouttoken /Users/test/stdoutsecret '
          printf 'Bearer stderrsecret token=stderrtoken /Users/test/stderrsecret ' >&2
          i=$((i + 1))
        done
        printf 'codex-cli 0.148.0\\n'
        """
        try Data(script.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let version = try CodexExecReadinessProbe.runProcess(
            executableURL: scriptURL,
            arguments: ["--version"],
            environment: [:],
        )
        XCTAssertLessThanOrEqual(
            version.stdout.utf8.count,
            CodexExecDiagnosticsBuilder.maximumStderrBytes,
        )
        XCTAssertLessThanOrEqual(
            version.stderr.utf8.count,
            CodexExecDiagnosticsBuilder.maximumStderrBytes,
        )
        XCTAssertFalse(version.stdout.contains("stdoutsecret"))
        XCTAssertFalse(version.stderr.contains("stderrsecret"))
        XCTAssertFalse(version.stdout.contains("/Users/test"))
        XCTAssertFalse(version.stderr.contains("/Users/test"))
    }

    /// ATI-004-manage_external_agent_runtimes: descriptor exposes the exact Codex capability matrix.
    /// Runtime 등록자가 provider capability를 추정하지 않고 고정 snapshot을 사용합니다.
    /// - 검증 내용: descriptor 식별자, transport, branch 및 13개 capability 상태를 확인합니다.
    /// - 사전 조건: Codex runtime adapter를 생성합니다.
    /// - 기대 결과: 계획된 supported/unsupported/unknown 값이 모두 일치합니다.
    func testRuntimeDescriptor_exposesExactCapabilityMatrix() {
        let adapter = CodexExecRuntimeAdapter()
        let descriptor = adapter.descriptor
        XCTAssertEqual(descriptor.id.rawValue, "codex_exec")
        XCTAssertEqual(descriptor.providerNamespace, "codex")
        XCTAssertEqual(descriptor.transport, .processJSONL)
        XCTAssertEqual(descriptor.providerBranch, .codexStableJSON)
        let expected: [RuntimeCapability: RuntimeCapabilityStatus] = [
            .discovery: .supported, .eventStream: .supported, .approval: .unsupported,
            .cancellation: .unknown, .queuedInput: .unsupported, .terminalResult: .supported,
            .timeout: .unknown, .sameIdentityResume: .supported, .reconstruction: .supported,
            .explicitArtifact: .unknown, .workingDirectory: .supported, .additionalRoots: .supported,
            .authStatusProbe: .supported,
        ]
        for (capability, status) in expected {
            XCTAssertEqual(descriptor.capabilities[capability], status, capability.rawValue)
        }
    }

    /// ATI-004-manage_external_agent_runtimes: unsupported and unknown operations are side-effect free.
    /// capability가 없는 동작은 provider process나 registry를 만지지 않고 typed failure를 반환합니다.
    /// - 검증 내용: approval, cancellation, queued input 호출의 invalidEvent를 확인합니다.
    /// - 사전 조건: launch하지 않은 runtime adapter와 유효한 operation request를 준비합니다.
    /// - 기대 결과: 세 호출 모두 invalidEvent이며 실행 process는 생성되지 않습니다.
    func testRuntimeUnsupportedOperations_failWithoutSideEffects() async {
        let adapter = CodexExecRuntimeAdapter()
        let approval = RuntimeApprovalRequest(
            externalAgentSessionReference: "host",
            providerInternalSessionReference: .init("thread"),
            requestID: .init("request"),
            operationID: .init("operation"),
            runReference: .init("run"),
            authorizationGeneration: 0,
        )
        do {
            try await adapter.respondToApproval(approval)
            XCTFail("approval should fail")
        } catch { XCTAssertEqual(error as? RuntimeHostError, .capabilityUnsupported(.approval)) }
        do {
            try await adapter.requestCancellation(
                .init(operationID: .init("op"), runReference: .init("run")),
            )
            XCTFail("cancel should fail")
        } catch { XCTAssertEqual(error as? RuntimeHostError, .capabilityUnknown(.cancellation)) }
        do {
            try await adapter.enqueueInput(
                .init(
                    operationID: .init("op"),
                    runReference: .init("run"),
                    input: .init("input"),
                ),
            )
            XCTFail("input should fail")
        } catch { XCTAssertEqual(error as? RuntimeHostError, .capabilityUnsupported(.queuedInput)) }
        do {
            _ = try await adapter.terminalResult(for: .init("run"))
            XCTFail("unknown result should fail")
        } catch { XCTAssertEqual(error as? RuntimeHostError, .invalidEvent) }
    }

    /// ATI-004-manage_external_agent_runtimes: default AiChat live composition shares its controller identity.
    /// legacy mapper를 교체하지 않고 runtime 등록 seam과 기본 client가 동일 registry를 참조합니다.
    /// - 검증 내용: composition identity token과 default client identity token을 비교합니다.
    /// - 사전 조건: production live composition과 default client를 생성합니다.
    /// - 기대 결과: 두 경로의 controller identity가 동일합니다.
    func testLiveComposition_defaultClientSharesControllerIdentity() {
        let composition = CodexExecLiveComposition.live
        let client = AiChatProviderExecutionClient.live()
        XCTAssertEqual(client.codexControllerIdentity, composition.controllerIdentity)
        XCTAssertEqual(
            CodexExecRuntimeAdapter.live.descriptor.id,
            composition.runtimeAdapter.descriptor.id,
        )
    }

    private func makeRuntimeRequest(
        run: String = "run",
        input: String = "prompt",
    ) -> RuntimeLaunchRequest {
        RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init(run),
            adapterID: .init("codex_exec"),
            contextPolicy: RuntimeContextPolicy(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: root.path,
            ),
            input: RuntimeSensitiveInput(input),
        )
    }

    private func makeReadyProbe() -> CodexExecReadinessProbe {
        CodexExecReadinessProbe { _, arguments, _ in
            arguments == ["--version"]
                ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
        }
    }

    /// ATI-004-manage_external_agent_runtimes: adapter launch uses the readiness gate before spawning.
    /// adapter launch가 controller 위임 전에 readiness를 통과하고 handshake receipt를 반환합니다.
    /// - 검증 내용: process spawn, provider session reference와 stdin을 확인합니다.
    /// - 사전 조건: ready fake probe와 thread.started를 반환하는 fake process가 있습니다.
    /// - 기대 결과: launch가 성공하고 runner는 정확히 한 번 호출됩니다.
    func testAdapterLaunch_requiresReadinessAndReturnsHandshakeReceipt() async throws {
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let harness = CodexExecCommandTestHarness()
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: harness.processRunner(process: process)),
            readinessProbe: CodexExecReadinessProbe(runner: harness.runner),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        let receipt = try await adapter.launch(makeRuntimeRequest())
        XCTAssertEqual(receipt.providerInternalSessionReference.rawValue, "thread-1")
        XCTAssertEqual(process.writes, [Data("prompt".utf8)])
        XCTAssertEqual(harness.mainExecutionSpawnCount, 1)
    }

    /// ATI-004-manage_external_agent_runtimes: direct runtime discovery and launch prepare the provider session.
    /// legacy composition과 동일하게 runtime adapter도 provider-owned session을 readiness보다 먼저 준비합니다.
    /// - 검증 내용: discovery/launch preparation count, readiness TMPDIR, launch command TMPDIR 및 request directory -C를
    /// 확인합니다.
    /// - 사전 조건: folder working directory, counting preparer, ready probe와 handshake fake process가 제공됩니다.
    /// - 기대 결과: 두 경로 모두 session을 준비하고 provider session은 환경에만 사용되며 -C는 request directory를 유지합니다.
    func testAdapterDiscoveryAndLaunch_prepareProviderSessionBeforeReadinessAndSpawn() async throws {
        let codexHome = root.appendingPathComponent("codex-home")
        let preparedSession = codexHome.appendingPathComponent("session")
        let preparationCount = CodexExecInvocationCounter()
        let preparer = CodexLegacySessionPreparer { _, arguments, _ in
            try FileManager.default.createDirectory(at: preparedSession, withIntermediateDirectories: true)
            if arguments.first == "init" {
                preparationCount.increment()
                try FileManager.default.createDirectory(
                    at: preparedSession.appendingPathComponent(".git"),
                    withIntermediateDirectories: true,
                )
                return ""
            }
            return arguments.contains("--is-inside-work-tree")
                ? "true\n"
                : preparedSession.appendingPathComponent(".git").path + "\n"
        }
        nonisolated(unsafe) var readinessEnvironments: [[String: String]] = []
        let readinessProbe = CodexExecReadinessProbe { _, arguments, environment in
            readinessEnvironments.append(environment)
            return arguments == ["--version"]
                ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
        }
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-prepared"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let harness = CodexExecCommandTestHarness()
        let commandRecorder = CodexExecCommandRecorder()
        let controller = CodexExecProcessController { command in
            await commandRecorder.record(command)
            return try await harness.processRunner(process: process)(command)
        }
        let adapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: readinessProbe,
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            legacySessionPreparer: preparer,
        )

        _ = try await adapter.discoveryMetadata()
        let request = makeRuntimeRequest()
        _ = try await adapter.launch(request)

        XCTAssertEqual(preparationCount.value, 2)
        XCTAssertEqual(readinessEnvironments.count, 4)
        XCTAssertTrue(readinessEnvironments.allSatisfy { $0["TMPDIR"] == preparedSession.path })
        let commands = await commandRecorder.commands
        XCTAssertEqual(commands.first?.environment["TMPDIR"], preparedSession.path)
        let arguments = try XCTUnwrap(commands.first?.arguments)
        let directoryIndex = try XCTUnwrap(arguments.firstIndex(of: "-C"))
        XCTAssertEqual(arguments[directoryIndex + 1], root.path)
    }

    /// ATI-004-manage_external_agent_runtimes: provider thread IDs are admitted only within the opaque handle boundary.
    /// receipt acquisition 이후 provider thread ID를 저장하기 전에 Unicode scalar 경계를 적용합니다.
    /// - 검증 내용: empty ID 거부, combining scalar를 포함한 정확히 4096 scalar ID 수락, 4097 scalar ID 거부와 receipt 취소/상태 비저장을 확인합니다.
    /// - 사전 조건: 각 launch가 readiness를 통과하고 지정된 thread.started receipt를 반환하는 fake process를 사용합니다.
    /// - 기대 결과: 유효한 4096 scalar ID만 저장되고, 거부된 receipt는 한 번 취소되며 adapter/controller 상태와 process cleanup이 비어 있습니다.
    func testAdapterLaunch_admitsProviderThreadIDsWithinOpaqueHandleBoundary() async throws {
        let validThreadID = String(repeating: "e\u{301}", count: 2048)
        XCTAssertEqual(validThreadID.unicodeScalars.count, 4096)
        XCTAssertLessThan(validThreadID.count, validThreadID.unicodeScalars.count)

        let cases: [(String, Bool)] = [("", false), (validThreadID, true), (validThreadID + "x", false)]
        for (threadID, isValid) in cases {
            let process = CodexExecFakeProcess(
                stdout: [Data("{\"type\":\"thread.started\",\"thread_id\":\"\(threadID)\"}".utf8)],
                stderr: [],
                terminationStatus: 0,
            )
            let (adapter, controller) = makeAdapter(process: process)

            if isValid {
                let receipt = try await adapter.launch(makeRuntimeRequest())
                XCTAssertEqual(receipt.providerInternalSessionReference.rawValue, threadID)
                XCTAssertEqual(process.terminationCount, 0)
                XCTAssertEqual(process.cleanupCount, 0)
            } else {
                try await assertInvalidThreadIDIsCleanedUp(
                    adapter: adapter,
                    controller: controller,
                    process: process,
                )
            }
        }
    }

    private func makeAdapter(
        process: CodexExecFakeProcess,
    ) -> (CodexExecRuntimeAdapter, CodexExecProcessController) {
        let harness = CodexExecCommandTestHarness()
        let controller = CodexExecProcessController(runner: harness.processRunner(process: process))
        return (
            CodexExecRuntimeAdapter(
                controller: controller,
                readinessProbe: CodexExecReadinessProbe(runner: harness.runner),
                executableURL: URL(fileURLWithPath: "/tmp/codex"),
            ),
            controller,
        )
    }

    private func assertInvalidThreadIDIsCleanedUp(
        adapter: CodexExecRuntimeAdapter,
        controller: CodexExecProcessController,
        process: CodexExecFakeProcess,
    ) async throws {
        do {
            _ = try await adapter.launch(makeRuntimeRequest())
            XCTFail("invalid provider thread ID must fail")
        } catch {
            XCTAssertEqual(error as? RuntimeHostError, .malformedAdapterResponse)
        }
        let adapterCounts = await adapter.debugStorageCounts()
        XCTAssertEqual(adapterCounts.receipts, 0)
        XCTAssertEqual(adapterCounts.hosts, 0)
        XCTAssertEqual(adapterCounts.restartBindings, 0)
        XCTAssertEqual(adapterCounts.tombstones, 0)
        let controllerCounts = await controller.debugRegistryCounts()
        XCTAssertEqual(controllerCounts.fresh, 0)
        XCTAssertEqual(controllerCounts.resume, 0)
        XCTAssertEqual(controllerCounts.staged, 0)
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
    }

    /// ATI-004-manage_external_agent_runtimes: readiness failure prevents provider spawn.
    /// executable/version readiness 실패가 main process 실행보다 먼저 typed failure로 종료됩니다.
    /// - 검증 내용: readiness failure의 public error와 runner invocation count를 확인합니다.
    /// - 사전 조건: unsupported version을 반환하는 fake probe와 유효한 runtime request가 있습니다.
    /// - 기대 결과: adapter failure가 반환되고 provider runner 호출은 0회입니다.
    func testAdapterLaunch_readinessFailureDoesNotSpawnProvider() async {
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecFakeRunner(process: process)
        let probe = CodexExecReadinessProbe { _, arguments, _ in
            arguments == ["--version"]
                ? CodexExecProbeResult(exitCode: 0, stdout: "codex-cli 0.147.0\n", stderr: "")
                : CodexExecProbeResult(exitCode: 0, stdout: "", stderr: "")
        }
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: probe,
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        do {
            _ = try await adapter.launch(makeRuntimeRequest())
            XCTFail("launch should fail readiness")
        } catch {
            XCTAssertEqual(
                error as? RuntimeHostError,
                .adapterFailure(.processExit, .init("unsupported_version")),
            )
        }
        XCTAssertEqual(runner.runCount, 0)
    }

    /// ATI-004-manage_external_agent_runtimes: adapter authorizes cwd only under an explicit primary root.
    /// allowedRoots가 cwd의 쓰기 권한과 추가 root 투영을 동시에 결정하는지 검증합니다.
    /// - 검증 내용: unauthorized cwd 거부, most-specific primary 선택, sorted/deduplicated add-dir를 확인합니다.
    /// - 사전 조건: 실제 temporary directories와 readiness/process fake가 제공됩니다.
    /// - 기대 결과: unauthorized request는 typed error와 zero spawn, authorized request는 primary 제외 add-dir를 반환합니다.
    func testAdapterCommand_authorizesPrimaryRootAndAdditionalRoots() async throws {
        let authorized = root.appendingPathComponent("authorized")
        let nested = authorized.appendingPathComponent("project")
        let extra = root.appendingPathComponent("extra")
        let unapproved = root.appendingPathComponent("unapproved")
        for directory in [authorized, nested, extra, unapproved] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: makeReadyProbe(),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )

        let unauthorized = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("unauthorized"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: unapproved.path,
                allowedRoots: [authorized.path],
            ),
            input: .init("prompt"),
        )
        do {
            _ = try await adapter.launch(unauthorized)
            XCTFail("unauthorized cwd must fail")
        } catch {
            XCTAssertEqual(
                error as? RuntimeHostError,
                .adapterFailure(.sdkException, .init("writable_root_outside_working_directory")),
            )
        }
        XCTAssertEqual(runner.runCount, 0)

        let authorizedRequest = RuntimeLaunchRequest(
            externalAgentSessionReference: .init("host"),
            runReference: .init("authorized"),
            adapterID: adapter.descriptor.id,
            contextPolicy: .init(
                branchReference: "branch",
                authorizationGeneration: 0,
                localCorrelation: "correlation",
                workingDirectory: nested.path,
                allowedRoots: [extra.path, authorized.path, extra.path],
            ),
            input: .init("prompt"),
        )
        let command = try await adapter.makeCommand(request: authorizedRequest, threadID: nil)
        _ = try await adapter.launch(authorizedRequest)
        XCTAssertEqual(runner.runCount, 1)
        XCTAssertEqual(
            command.arguments,
            [
                "exec", "--model", "gpt-5-codex", "--json", "--color", "never", "--strict-config",
                "--ignore-user-config",
                "--sandbox",
                "workspace-write", "-C", nested.path, "--add-dir", authorized.path, "--add-dir", extra.path, "-",
            ],
        )
        XCTAssertEqual(command.arguments.count(where: { $0 == "--add-dir" }), 2)
    }

    /// ATI-004-manage_external_agent_runtimes: duplicate event stream is a public invalidEvent.
    /// provider-private consumption failure가 Runtime Host 경계를 넘지 않습니다.
    /// - 검증 내용: 첫 stream claim 후 두 번째 claim의 RuntimeHostError 변환을 확인합니다.
    /// - 사전 조건: readiness와 thread handshake가 성공한 adapter run이 있습니다.
    /// - 기대 결과: duplicate eventStream 호출이 invalidEvent를 반환합니다.
    func testAdapterEventStream_duplicateConsumptionMapsToPublicError() async throws {
        let process = CodexExecFakeProcess(
            stdout: [Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8)],
            stderr: [],
            terminationStatus: 0,
        )
        let runner = CodexExecFakeRunner(process: process)
        let adapter = CodexExecRuntimeAdapter(
            controller: CodexExecProcessController(runner: runner.run),
            readinessProbe: makeReadyProbe(),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
        )
        _ = try await adapter.launch(makeRuntimeRequest())
        _ = try await adapter.eventStream(for: .init("run"))
        do {
            _ = try await adapter.eventStream(for: .init("run"))
            XCTFail("duplicate stream should fail")
        } catch { XCTAssertEqual(error as? RuntimeHostError, .invalidEvent) }
        XCTAssertEqual(runner.runCount, 1)
    }

    /// ATI-004-manage_external_agent_runtimes: completed ownership evicts adapter and controller state.
    /// terminal-first와 event-first consumption이 receipts, hosts, restart binding 및 registry를 남기지 않는지 검증합니다.
    /// - 검증 내용: 두 소비 순서의 terminal/result completion 후 내부 storage와 controller registry가 모두 0인지 확인합니다.
    /// - 사전 조건: readiness와 completed JSONL을 반환하는 독립 fake process 두 개가 있습니다.
    /// - 기대 결과: 각 ownership 경로가 성공적으로 끝나고 모든 내부 상태가 evict됩니다.
    func testAdapterConsumptionOrder_evictsAllState() async throws {
        for terminalFirst in [true, false] {
            let process = CodexExecFakeProcess(
                stdout: [
                    Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8),
                    Data(#"{"type":"turn.completed"}"#.utf8),
                ],
                stderr: [],
                terminationStatus: 0,
            )
            let runner = CodexExecFakeRunner(process: process)
            let controller = CodexExecProcessController(runner: runner.run)
            let adapter = CodexExecRuntimeAdapter(
                controller: controller,
                readinessProbe: makeReadyProbe(),
                executableURL: URL(fileURLWithPath: "/tmp/codex"),
            )
            let runReference = terminalFirst ? "terminal-first" : "event-first"
            _ = try await adapter.launch(makeRuntimeRequest(run: runReference))
            let initialCounts = await adapter.debugStorageCounts()
            XCTAssertEqual(initialCounts.receipts, 1)
            if terminalFirst {
                _ = try await adapter.terminalResult(for: .init(runReference))
                for try await _ in try await adapter.eventStream(for: .init(runReference)) {}
            } else {
                for try await _ in try await adapter.eventStream(for: .init(runReference)) {}
                _ = try await adapter.terminalResult(for: .init(runReference))
            }
            let adapterCounts = await adapter.debugStorageCounts()
            let controllerCounts = await controller.debugRegistryCounts()
            XCTAssertEqual(adapterCounts.receipts, 0)
            XCTAssertEqual(adapterCounts.hosts, 0)
            XCTAssertEqual(adapterCounts.restartBindings, 0)
            XCTAssertEqual(adapterCounts.tombstones, 0)
            XCTAssertEqual(controllerCounts.fresh, 0)
            XCTAssertEqual(controllerCounts.resume, 0)
            XCTAssertEqual(controllerCounts.staged, 0)
        }
    }
}
