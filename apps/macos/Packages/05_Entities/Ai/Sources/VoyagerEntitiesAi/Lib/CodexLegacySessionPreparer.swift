import Foundation

actor CodexLegacySessionPreparer {
    typealias GitRunner = @Sendable (URL, [String], [String: String]) throws -> String

    private let gitRunner: GitRunner

    init(gitRunner: @escaping GitRunner = CodexLegacySessionPreparer.runGit) {
        self.gitRunner = gitRunner
    }

    func prepare(codexHome: URL) throws -> URL {
        let canonicalHome = CodexPathCanonicalizer.url(codexHome)
        let session = canonicalHome.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)

        let canonicalSession = CodexPathCanonicalizer.url(session)
        guard Self.isContained(canonicalSession, in: canonicalHome) else {
            throw CodexLegacySessionPreparerError.sessionOutsideHome
        }

        let template = canonicalHome.appendingPathComponent(".voyager-empty-git-template", isDirectory: true)
        try FileManager.default.createDirectory(at: template, withIntermediateDirectories: true)
        _ = try gitRunner(
            URL(fileURLWithPath: "/usr/bin/git"),
            [
                "init", "--quiet", "--initial-branch=voyager-session",
                "--template=" + template.path,
                canonicalSession.path,
            ],
            Self.gitEnvironment,
        )

        try Self.validateRepository(canonicalSession: canonicalSession, gitRunner: gitRunner)
        return canonicalSession
    }

    private static func validateRepository(
        canonicalSession: URL,
        gitRunner: GitRunner,
    ) throws {
        let validation = try gitRunner(
            URL(fileURLWithPath: "/usr/bin/git"),
            ["-C", canonicalSession.path, "rev-parse", "--is-inside-work-tree"],
            Self.gitEnvironment,
        )
        guard validation.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw CodexLegacySessionPreparerError.repositoryMissing
        }

        let absoluteGitDirectory = try gitRunner(
            URL(fileURLWithPath: "/usr/bin/git"),
            ["-C", canonicalSession.path, "rev-parse", "--absolute-git-dir"],
            Self.gitEnvironment,
        )
        let gitDirectory = canonicalSession.appendingPathComponent(".git", isDirectory: true)
        let absoluteGitDirectoryPath = absoluteGitDirectory
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard absoluteGitDirectoryPath.count == 1,
              let reportedGitDirectory = absoluteGitDirectoryPath.first,
              !reportedGitDirectory.isEmpty
        else {
            throw CodexLegacySessionPreparerError.repositoryMissing
        }
        let canonicalReportedGitDirectory = CodexPathCanonicalizer.url(
            URL(fileURLWithPath: String(reportedGitDirectory), isDirectory: true),
        )
        guard canonicalReportedGitDirectory.path == gitDirectory.path,
              Self.isContained(canonicalReportedGitDirectory, in: canonicalSession),
              Self.isRealDirectory(gitDirectory)
        else {
            throw CodexLegacySessionPreparerError.repositoryMissing
        }
    }

    private static let gitEnvironment = [
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
    ]

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = candidate.path
        let rootPath = root.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func runGit(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CodexLegacySessionPreparerError.gitFailed(process.terminationStatus)
        }
        return String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8,
        ) ?? ""
    }
}

enum CodexLegacySessionPreparerError: Error, Equatable {
    case sessionOutsideHome
    case repositoryMissing
    case gitFailed(Int32)
}
