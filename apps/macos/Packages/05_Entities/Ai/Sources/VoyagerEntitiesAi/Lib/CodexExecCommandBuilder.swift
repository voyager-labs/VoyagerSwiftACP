import Foundation

enum CodexExecSandboxMode: String, Equatable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
}

struct CodexExecCommandRequest {
    let model: String
    let prompt: String
    let workingDirectory: URL
    let sandbox: CodexExecSandboxMode
    let primaryWritableRoot: URL
    let additionalWritableRoots: [URL]
    let codexHome: URL
    let threadID: String?
    let reasoningEffort: String?
    let readablePaths: [URL]
    let skipGitRepositoryCheck: Bool

    init(
        model: String,
        prompt: String,
        workingDirectory: URL,
        sandbox: CodexExecSandboxMode,
        primaryWritableRoot: URL,
        additionalWritableRoots: [URL],
        codexHome: URL,
        threadID: String? = nil,
        reasoningEffort: String? = nil,
        readablePaths: [URL] = [],
        skipGitRepositoryCheck: Bool = false,
    ) {
        self.model = model
        self.prompt = prompt
        self.workingDirectory = workingDirectory
        self.sandbox = sandbox
        self.primaryWritableRoot = primaryWritableRoot
        self.additionalWritableRoots = additionalWritableRoots
        self.codexHome = codexHome
        self.threadID = threadID
        self.reasoningEffort = reasoningEffort
        self.readablePaths = readablePaths
        self.skipGitRepositoryCheck = skipGitRepositoryCheck
    }
}

struct CodexExecCommand: Equatable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let stdin: String
}

enum CodexExecCommandError: Error, Equatable {
    case invalidWorkingDirectory
    case invalidWritableRoot
    case writableRootOutsideWorkingDirectory(String)
    case emptyModel
    case emptyThreadID
    case invalidReadablePath
}

private enum CodexExecPermissionProfile {
    static func arguments(readablePaths: [URL]) throws -> [String] {
        let values = [":root": "deny", ":minimal": "read"]
            .merging(readablePaths.reduce(into: [String: String]()) { $0[$1.path] = "read" }) { _, value in value }
            .sorted { $0.key < $1.key }
        let encodedEntries = try values
            .map { try "\(jsonQuote($0.key))=\(jsonQuote($0.value))" }
            .joined(separator: ",")
        return [
            "-c", "default_permissions=\"voyager-reference\"",
            "-c", "permissions.voyager-reference.filesystem={\(encodedEntries)}",
        ]
    }

    private static func jsonQuote(_ value: String) throws -> String {
        var encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let encoded = String(bytes: data, encoding: .utf8) else {
            throw CodexExecCommandError.invalidReadablePath
        }
        return encoded
    }
}

enum CodexExecCommandBuilder {
    static func build(
        request: CodexExecCommandRequest,
        executableURL: URL,
    ) throws -> CodexExecCommand {
        let workingDirectory = try canonicalDirectory(request.workingDirectory)
        guard !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CodexExecCommandError.emptyModel
        }

        let primaryWritableRoot = try canonicalDirectory(request.primaryWritableRoot)
        guard request.sandbox == .readOnly || isDescendant(workingDirectory.path, of: primaryWritableRoot.path) else {
            throw CodexExecCommandError.writableRootOutsideWorkingDirectory(primaryWritableRoot.path)
        }
        let additionalWritableRoots = request.sandbox == .workspaceWrite
            ? try canonicalWritableRoots(
                (primaryWritableRoot == workingDirectory ? [] : [primaryWritableRoot])
                    + request.additionalWritableRoots,
            )
            : []
        guard request.threadID == nil || !(request.threadID ?? "").isEmpty else {
            throw CodexExecCommandError.emptyThreadID
        }

        let readablePaths = try canonicalReadablePaths([workingDirectory] + request.readablePaths)
        var arguments = ["exec", "--model", request.model]
        if let reasoningEffort = request.reasoningEffort {
            arguments.append(contentsOf: ["-c", "model_reasoning_effort=\"\(reasoningEffort)\""])
        }
        if request.threadID == nil {
            arguments.append(contentsOf: ["--json", "--color", "never", "--strict-config", "--ignore-user-config"])
        } else {
            arguments.append(contentsOf: ["--json", "--strict-config", "--ignore-user-config"])
        }
        try arguments.append(contentsOf: CodexExecPermissionProfile.arguments(readablePaths: readablePaths))
        arguments.append(contentsOf: ["--sandbox", request.sandbox.rawValue, "-C", workingDirectory.path])
        for root in additionalWritableRoots {
            arguments.append(contentsOf: ["--add-dir", root.path])
        }
        if request.skipGitRepositoryCheck {
            arguments.append("--skip-git-repo-check")
        }
        if let threadID = request.threadID {
            arguments.append(contentsOf: ["resume", threadID, "-"])
        } else {
            arguments.append("-")
        }

        return CodexExecCommand(
            executableURL: CodexPathCanonicalizer.url(executableURL),
            arguments: arguments,
            environment: AiChatProviderExecutionClient.codexProcessEnvironment(codexHomeURL: request.codexHome),
            stdin: request.prompt,
        )
    }

    private static func canonicalDirectory(_ url: URL) throws -> URL {
        let path = CodexPathCanonicalizer.path(url)
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), path != "/", !path.isEmpty,
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            throw CodexExecCommandError.invalidWorkingDirectory
        }
        return CodexPathCanonicalizer.url(url)
    }

    private static func canonicalWritableRoots(_ roots: [URL]) throws -> [URL] {
        let canonical = try roots.map { root -> URL in
            let path = CodexPathCanonicalizer.path(root)
            var isDirectory: ObjCBool = false
            guard path.hasPrefix("/"), path != "/", !path.isEmpty,
                  FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue
            else {
                throw CodexExecCommandError.invalidWritableRoot
            }
            return CodexPathCanonicalizer.url(root)
        }
        return Array(Set(canonical)).sorted { $0.path < $1.path }
    }

    private static func canonicalReadablePaths(_ paths: [URL]) throws -> [URL] {
        let canonical = try paths.map { path -> URL in
            let resolvedPath = CodexPathCanonicalizer.path(path)
            guard resolvedPath.hasPrefix("/"), !resolvedPath.isEmpty,
                  FileManager.default.fileExists(atPath: resolvedPath)
            else { throw CodexExecCommandError.invalidReadablePath }
            return CodexPathCanonicalizer.url(path)
        }
        return Array(Set(canonical)).sorted { $0.path < $1.path }
    }

    private static func isDescendant(_ path: String, of root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
