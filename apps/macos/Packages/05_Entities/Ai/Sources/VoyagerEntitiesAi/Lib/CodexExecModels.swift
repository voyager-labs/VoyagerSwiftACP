import Foundation

enum CodexExecRawEventType: Equatable {
    case threadStarted
    case turnStarted
    case turnCompleted
    case turnFailed
    case itemStarted
    case itemUpdated
    case itemCompleted
    case error
    case unknown(String)

    var rawValue: String {
        switch self {
        case .threadStarted: "thread.started"
        case .turnStarted: "turn.started"
        case .turnCompleted: "turn.completed"
        case .turnFailed: "turn.failed"
        case .itemStarted: "item.started"
        case .itemUpdated: "item.updated"
        case .itemCompleted: "item.completed"
        case .error: "error"
        case let .unknown(value): value
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "thread.started": self = .threadStarted
        case "turn.started": self = .turnStarted
        case "turn.completed": self = .turnCompleted
        case "turn.failed": self = .turnFailed
        case "item.started": self = .itemStarted
        case "item.updated": self = .itemUpdated
        case "item.completed": self = .itemCompleted
        case "error": self = .error
        default: self = .unknown(rawValue)
        }
    }
}

struct CodexExecEventPayload: Equatable {
    let threadID: String?
    let turnID: String?
    let itemID: String?
    let itemType: String?
    let status: String?
    let text: String?
    let message: String?
    let commandExecutionEvidence: CodexExecCommandExecutionEvidence?
}

enum CodexExecCommandExecutionStatus: Equatable {
    case started
    case inProgress
    case completed
    case failed

    init?(rawValue: String) {
        switch rawValue {
        case "started": self = .started
        case "in_progress", "inProgress": self = .inProgress
        case "completed": self = .completed
        case "failed": self = .failed
        default: return nil
        }
    }
}

struct CodexExecCommandExecutionEvidence: Equatable {
    let status: CodexExecCommandExecutionStatus?
    let exitCode: Int32?
}

enum CodexExecItemType {
    static func isAgentMessage(_ value: String?) -> Bool {
        value == "agent_message" || value == "agentMessage"
    }
}

struct CodexExecDecodedEvent: Equatable {
    let type: CodexExecRawEventType
    let payload: CodexExecEventPayload
}

enum CodexExecLifecycleKind: Equatable {
    case progress
    case completed
    case failed
}

struct CodexExecLifecycleEvent: Equatable {
    let providerEventID: String
    let idempotencyKey: String
    let ordinal: UInt64
    let rawType: String
    let kind: CodexExecLifecycleKind
}

struct CodexExecTerminalResult: Equatable {
    let outcome: CodexExecLifecycleKind
    let finalAssistantText: CodexExecFinalAssistantText
    let failure: CodexExecProcessFailure?
    let diagnostics: CodexExecDiagnostics
}

struct CodexExecFinalAssistantText: Equatable {
    let value: String
}

enum CodexExecDecodeOutcome: Equatable {
    case event(CodexExecDecodedEvent)
    case unknown(type: String)
}

enum CodexExecDecodeError: Error, Equatable {
    case malformedFrame
    case incompleteFrame
    case rawLineTooLarge
    case finalAssistantItemLimit
}

struct CodexExecUnknownEvidence: Equatable {
    let types: [String]
    let totalCount: Int
}

struct CodexExecDiagnostics: Equatable {
    let stderr: String
    let unknown: CodexExecUnknownEvidence
}

enum CodexExecDiagnosticsBuilder {
    static let maximumStderrBytes = 128 * 1024
    static let maximumUnknownTypes = 32
    static let maximumUnknownCount = 128

    static func redactAndBoundStderr(_ input: String) -> String {
        let patterns = [
            (#"(?i)(bearer[ \t]+)[^\s,;|]+"#, "$1[REDACTED]"),
            (#"(?i)((?:access|refresh|id|api)?[_-]?token\s*[:=]\s*)[^\s,;]+"#, "$1[REDACTED]"),
            (#"(?i)(authorization\s*[:=]\s*)(?:bearer\s+)?[^\s,;|]+"#, "$1[REDACTED]"),
            (#"(?i)(^|[^A-Za-z0-9_-])([A-Za-z0-9_-]{1,64}_api_key[ \t]*[:=][ \t]*)[^\s,;]+"#, "$1$2[REDACTED]"),
            (#"(?i)(^|[^A-Za-z0-9_-])(api_key[ \t]*[:=][ \t]*)[^\s,;]+"#, "$1$2[REDACTED]"),
            (
                #"(?i)(^|[^A-Za-z0-9_-])((?:client[_-]secret|x[_-]api[_-]?key)[ \t]*[:=][ \t]*)[^\s,;|]+"#,
                "$1$2[REDACTED]",
            ),
            (#"(?i)(^|[^A-Za-z0-9_])((?:secret|password|codex_home)[ \t]*[:=][ \t]*)[^\s,;]+"#, "$1$2[REDACTED]"),
            (
                #"(?i)([\"']?)/(?:Volumes|Network)/[^|,;\r\n\"']*?\S(?=[\"']|[|,;\r\n]|$)"#,
                "$1[PATH REDACTED]",
            ),
            (
                #"(?i)([\"']?)/(?:Users|private|var|tmp)/[^|,;\r\n\"']*?\S(?=[\"']|[|,;\r\n]|$)"#,
                "$1[PATH REDACTED]",
            ),
            (#"(?i)/(?:Users|private|var|tmp|Volumes|Network)/[^\s,;|]+"#, "[PATH REDACTED]"),
        ]
        var redacted = input
        for (pattern, replacement) in patterns {
            redacted = redacted.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        let bytes = Array(redacted.utf8)
        var end = min(bytes.count, maximumStderrBytes)
        if let value = String(data: Data(bytes.prefix(end)), encoding: .utf8) { return value }
        while end > 0, bytes[end - 1] & 0xC0 == 0x80 {
            end -= 1
        }
        while end > 0 {
            if let value = String(data: Data(bytes.prefix(end)), encoding: .utf8) { return value }
            end -= 1
        }
        return ""
    }
}
