import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatProviderExecutionCodexPromptTests: XCTestCase {
    func testMakeCodexPrompt_withoutWorkingDirectoryKeepsPathsReferenceOnly() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-root-default-\(UUID().uuidString).txt")
        try createFile(at: fileURL, contents: "root default\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try withoutCodexWorkingDirectoryOverride {
            let prompt = try AiChatProviderExecutionClient.makeCodexPrompt(payload: makePayload(
                requestContext: .init(
                    parts: [makeCodexPathScopePart(displayPath: fileURL.path, canonicalPath: fileURL.path)],
                ),
            ))

            XCTAssertTrue(prompt.contains("working_directory: unavailable"), prompt)
            XCTAssertTrue(prompt.contains("working_directory_note: Codex working directory is unavailable"), prompt)
            XCTAssertTrue(prompt.contains("path: \(fileURL.path)"), prompt)
            XCTAssertTrue(prompt.contains("status: reference_only"), prompt)
            XCTAssertTrue(prompt.contains("access: reference-only"), prompt)
            XCTAssertFalse(prompt.contains("status: in_scope"), prompt)
        }
    }

    func testMakeCodexPrompt_marksInWorkdirPathAsScopedFilesystemReference() throws {
        let workspaceURL = try makeTemporaryDirectory(named: "codex-workspace")
        let fileURL = workspaceURL.appendingPathComponent("Sources/Feature.swift")
        try createFile(at: fileURL, contents: "struct Feature {}\n")

        try withCodexWorkingDirectory(workspaceURL) {
            let prompt = try AiChatProviderExecutionClient.makeCodexPrompt(payload: makePayload(
                requestContext: .init(
                    parts: [makeCodexPathScopePart(displayPath: fileURL.path, canonicalPath: fileURL.path)],
                ),
            ))

            XCTAssertTrue(prompt.contains("codex_filesystem_references:"))
            XCTAssertTrue(prompt.contains("path: \(fileURL.path)"))
            XCTAssertTrue(prompt.contains("access: referenced path (Codex filesystem access)"), prompt)
            XCTAssertTrue(prompt.contains("status: in_scope"), prompt)
            XCTAssertTrue(prompt.contains("may be read through Codex filesystem access"), prompt)
            XCTAssertFalse(prompt.localizedCaseInsensitiveContains("uploaded"))
        }
    }

    func testMakeCodexPrompt_rendersCanonicalPathWhenDisplayPathIsBasename() throws {
        let workspaceURL = try makeTemporaryDirectory(named: "codex-workspace")
        let fileURL = workspaceURL.appendingPathComponent("Sources/Feature.swift")
        try createFile(at: fileURL, contents: "struct Feature {}\n")

        try withCodexWorkingDirectory(workspaceURL) {
            let prompt = try AiChatProviderExecutionClient.makeCodexPrompt(payload: makePayload(
                requestContext: .init(
                    parts: [makeCodexPathScopePart(displayPath: "Feature.swift", canonicalPath: fileURL.path)],
                ),
            ))

            XCTAssertTrue(prompt.contains("path: \(fileURL.path)"), prompt)
            XCTAssertFalse(prompt.contains("\n  - path: Feature.swift"), prompt)
            XCTAssertTrue(prompt.contains("status: in_scope"), prompt)
        }
    }

    func testMakeCodexPrompt_marksOutOfWorkdirPathAsReferenceOnly() throws {
        let workspaceURL = try makeTemporaryDirectory(named: "codex-workspace")
        let outsideRootURL = try makeTemporaryDirectory(named: "codex-outside")
        let outsideFileURL = outsideRootURL.appendingPathComponent("Notes/outside.txt")
        try createFile(at: outsideFileURL, contents: "outside\n")

        try withCodexWorkingDirectory(workspaceURL) {
            let prompt = try AiChatProviderExecutionClient.makeCodexPrompt(payload: makePayload(
                requestContext: .init(
                    parts: [
                        makeCodexPathScopePart(
                            displayPath: outsideFileURL.path,
                            canonicalPath: outsideFileURL.path,
                        ),
                    ],
                ),
            ))

            XCTAssertTrue(prompt.contains("path: \(outsideFileURL.path)"))
            XCTAssertTrue(prompt.contains("access: reference-only"))
            XCTAssertTrue(prompt.contains("status: out_of_scope"))
            XCTAssertTrue(prompt.contains("resolves outside the Codex working directory"))
        }
    }

    func testMakeCodexPrompt_treatsWorkspaceSymlinkEscapeAsOutOfScope() throws {
        let workspaceURL = try makeTemporaryDirectory(named: "codex-workspace")
        let outsideRootURL = try makeTemporaryDirectory(named: "codex-outside")
        let targetURL = outsideRootURL.appendingPathComponent("Assets/secret.txt")
        try createFile(at: targetURL, contents: "secret\n")

        let linkedFolderURL = workspaceURL.appendingPathComponent("Linked", isDirectory: true)
        try FileManager.default.createDirectory(at: linkedFolderURL, withIntermediateDirectories: true)
        let symlinkURL = linkedFolderURL.appendingPathComponent("secret.txt")
        try FileManager.default.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: targetURL.path)

        let resolvedTargetPath = symlinkURL.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path

        try withCodexWorkingDirectory(workspaceURL) {
            let prompt = try AiChatProviderExecutionClient.makeCodexPrompt(payload: makePayload(
                requestContext: .init(
                    parts: [
                        makeCodexPathScopePart(displayPath: symlinkURL.path, canonicalPath: resolvedTargetPath),
                    ],
                ),
            ))

            XCTAssertTrue(prompt.contains("path: \(symlinkURL.path)"))
            XCTAssertTrue(prompt.contains("access: reference-only"))
            XCTAssertTrue(prompt.contains("status: out_of_scope"))
            XCTAssertTrue(prompt.contains("resolves_to: \(resolvedTargetPath)"))
            XCTAssertTrue(prompt.contains("symlink escape"), prompt)
        }
    }

    func testCodexArguments_doNotEmitAddDir() {
        let arguments = AiChatProviderExecutionClient.codexArguments(
            model: "gpt-5-codex",
            outputURL: URL(fileURLWithPath: "/tmp/codex-output.txt"),
            prompt: "Use the referenced files",
            thinking: .effort(.medium),
        )

        XCTAssertFalse(arguments.contains("--add-dir"))
        XCTAssertTrue(arguments.contains("--skip-git-repo-check"))
    }

    func testMakeCodexPrompt_marksAssistantTurnsAsTranscriptHistory() throws {
        let prompt = try AiChatProviderExecutionClient.makeCodexPrompt(payload: makePayload(
            requestContext: .init(),
            messages: [
                AiChatProviderMessage(role: .user, content: "First question"),
                AiChatProviderMessage(role: .assistant, content: "First answer"),
                AiChatProviderMessage(role: .user, content: "Follow-up question"),
            ],
        ))

        XCTAssertTrue(prompt.contains("Conversation transcript:"), prompt)
        XCTAssertTrue(prompt.contains("Treat earlier Assistant and Tool entries as prior transcript history."), prompt)
        XCTAssertTrue(prompt.contains("Respond to the final User message only, continuing from that history."), prompt)
        XCTAssertTrue(prompt.contains("User:\nFirst question"), prompt)
        XCTAssertTrue(prompt.contains("Assistant:\nFirst answer"), prompt)
        XCTAssertTrue(prompt.contains("User:\nFollow-up question"), prompt)
    }

    private func makePayload(
        requestContext: AiChatLockedRequestContextSnapshot,
        messages: [AiChatProviderMessage] = [
            AiChatProviderMessage(
                role: .user,
                content: "Inspect the referenced files",
            ),
        ],
    ) throws -> AiChatProviderRequestPayload {
        let requestUUID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let runUUID = try XCTUnwrap(UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA"))
        return AiChatProviderRequestPayload(
            provider: .chatgptCodex,
            rawModelID: "gpt-5-codex",
            messages: messages,
            context: AiChatProviderContextBundle(
                sessionID: nil,
                requestID: AiChatRequestID(rawValue: requestUUID),
                runID: AiChatRunID(rawValue: runUUID),
                requestContext: requestContext,
                promptSummary: "Inspect the referenced files",
                submittedAtMs: 1_700_000_000_000,
            ),
            thinking: nil,
        )
    }

    private func makeCodexPathScopePart(displayPath: String, canonicalPath: String) -> AiChatLockedContextPartSnapshot {
        AiChatLockedContextPartSnapshot(
            source: .attachment,
            resolution: .providerNativeFile(
                kind: .codexPathScope,
                mimeType: "text/plain",
                metadata: [
                    "path": displayPath,
                    "displayPath": displayPath,
                    "filePath": canonicalPath,
                ],
            ),
            canonicalPath: canonicalPath,
            displayPath: displayPath,
            fileKind: .file,
            displayTitle: URL(fileURLWithPath: displayPath).lastPathComponent,
            byteCount: 128,
            mimeType: "text/plain",
        )
    }

    private func makeTemporaryDirectory(named prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true,
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func withoutCodexWorkingDirectoryOverride<T>(perform: () throws -> T) throws -> T {
        let key = "VOYAGER_CODEX_WORKING_DIRECTORY"
        let originalValue = ProcessInfo.processInfo.environment[key]
        unsetenv(key)
        defer {
            if let originalValue {
                setenv(key, originalValue, 1)
            } else {
                unsetenv(key)
            }
        }
        return try perform()
    }

    private func withCodexWorkingDirectory<T>(_ url: URL, perform: () throws -> T) throws -> T {
        let key = "VOYAGER_CODEX_WORKING_DIRECTORY"
        let previousValue = getenv(key).map { String(cString: $0) }
        setenv(key, url.path, 1)
        defer {
            if let previousValue {
                setenv(key, previousValue, 1)
            } else {
                unsetenv(key)
            }
        }
        return try perform()
    }
}
