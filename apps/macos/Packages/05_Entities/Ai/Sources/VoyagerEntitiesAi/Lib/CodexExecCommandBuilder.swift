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

        var arguments = ["exec"]
        if let threadID = request.threadID {
            arguments.append(contentsOf: ["resume", "--model", request.model])
            if let reasoningEffort = request.reasoningEffort {
                arguments.append(contentsOf: ["-c", "model_reasoning_effort=\"\(reasoningEffort)\""])
            }
            arguments.append(contentsOf: [
                "--json", "--strict-config", "--ignore-user-config", threadID, "-",
            ])
        } else {
            arguments.append(contentsOf: ["--model", request.model])
            if let reasoningEffort = request.reasoningEffort {
                arguments.append(contentsOf: ["-c", "model_reasoning_effort=\"\(reasoningEffort)\""])
            }
            arguments.append(contentsOf: [
                "--json", "--color", "never", "--strict-config", "--ignore-user-config",
                "--sandbox",
                request.sandbox.rawValue, "-C", workingDirectory.path,
            ])
            for root in additionalWritableRoots {
                arguments.append(contentsOf: ["--add-dir", root.path])
            }
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

    private static func isDescendant(_ path: String, of root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
