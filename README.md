# VoyagerSwiftACP

[![GitHub](https://img.shields.io/badge/-GitHub-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/wiedymi)
[![Twitter](https://img.shields.io/badge/-Twitter-1DA1F2?style=flat-square&logo=twitter&logoColor=white)](https://x.com/wiedymi)
[![Email](https://img.shields.io/badge/-Email-EA4335?style=flat-square&logo=gmail&logoColor=white)](mailto:contact@wiedymi.com)
[![Discord](https://img.shields.io/badge/-Discord-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/zemMZtrkSb)
[![Support me](https://img.shields.io/badge/-Support%20me-ff69b4?style=flat-square&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/vivy-company)

Swift SDK for the [Agent Client Protocol (ACP)](https://agentclientprotocol.com/). Build Apple platform applications that communicate with AI coding agents, or create your own ACP-compliant agents.

Built for [Aizen](https://aizen.win) — a native macOS app for managing git worktrees and AI coding agents. Check out the [source code](https://github.com/vivy-company/aizen).

## Features

- Core ACP protocol implementation over JSON-RPC/stdio
- Client and Agent (server) runtime support
- Multi-platform: macOS 12+, iOS 15+, tvOS 15+, watchOS 8+
- Pluggable transport layer (stdio, WebSocket)
- Actor-based concurrency for thread safety
- Async/await APIs with Swift Concurrency
- Streaming session updates via AsyncStream
- Stable `session/list` support and session metadata updates
- Boolean session config options and usage update decoding
- Built-in file system and terminal delegates
- Debug mode for inspecting raw protocol messages

## Installation

The APIs below describe the VOY-886 candidate. They become available from the
remote `production` branch only after fork review and promotion. The app currently
builds its local subtree at `apps/macos/Packages/VoyagerSwiftACP/`.

Add to your `Package.swift`:

```swift
dependencies: [
    // Voyager consumes the fork's production branch; no release tag exists yet.
    .package(url: "https://github.com/voyager-labs/VoyagerSwiftACP", branch: "production")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "ACP",           // Core client & agent runtime
        "ACPHTTP",       // Optional: WebSocket transport
        "ACPRegistry"    // Optional: Agent discovery & installation
    ]
)
```

## Packages

| Package       | Description                                                                                               |
| ------------- | --------------------------------------------------------------------------------------------------------- |
| `ACPModel`    | Platform-independent protocol types (shared by client and agent)                                          |
| `ACP`         | Core client and agent runtime for ACP communication                                                       |
| `ACPHTTP`     | WebSocket transport for network-based communication                                                       |
| `ACPRegistry` | Agent discovery and installation from the [ACP Registry](https://github.com/agentclientprotocol/registry) |

## Quick Start

```swift
import ACP

let client = Client()

// Launch an ACP-compatible agent
try await client.launch(agentPath: "/path/to/acp-agent-or-bridge")

// Advertise only callbacks implemented by this caller.
let initResponse = try await client.initialize(
    capabilities: ClientCapabilities()
)

// Start one notification consumer before session operations or prompts.
let notifications = await client.notifications
let updates = Task {
    for await notification in notifications {
        // Decode and project updates in your adapter; avoid logging raw params.
        _ = notification.method
    }
}
defer { updates.cancel() }

// Create a session
let session = try await client.newSession(workingDirectory: "/path/to/project")

// Send a prompt
let response = try await client.sendPrompt(
    sessionId: session.sessionId,
    content: [.text(TextContent(text: "Explain this codebase"))]
)

// Protocol cancellation and process cleanup are separate evidence.
let termination = await client.shutdown()
if !termination.cleanupComplete {
    // The transport did not confirm complete direct-child cleanup.
}
```

The executable must actually implement ACP stdio. An ordinary provider CLI is
not automatically an ACP agent. Install callback delegates before initialization
when advertising filesystem or terminal capabilities. The notification stream
supports one consumer; adapters own any fan-out. A stopped consumer can exhaust
the bounded queue and cause a typed overflow failure.

## Client Lifecycle

### 1. Create and Configure

```swift
let client = Client()

// Set delegate to handle agent requests
await client.setDelegate(myDelegate)

// Optional: enable debug mode
await client.enableDebugStream()
```

### 2. Launch Agent

```swift
try await client.launch(
    agentPath: "/usr/local/bin/claude-code",
    arguments: ["--some-flag"],
    workingDirectory: "/path/to/project"
)
```

### 3. Initialize

```swift
let response = try await client.initialize(
    protocolVersion: 1,
    capabilities: ClientCapabilities(
        fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
        terminal: true
    ),
    clientInfo: ClientInfo(name: "MyApp", title: "My App", version: "1.0.0"),
    timeout: 30.0
)

// Check agent capabilities
print("Agent: \(response.agentInfo?.name ?? "Unknown")")
print("Auth required: \(response.authMethods != nil)")
```

### 4. Authenticate (if required)

```swift
if let authMethods = response.authMethods {
    let authResponse = try await client.authenticate(
        authMethodId: authMethods.first!.id,
        credentials: ["token": "your-api-key"]
    )
}
```

### 5. Create Session

```swift
let session = try await client.newSession(
    workingDirectory: "/path/to/project",
    mcpServers: [] // Optional MCP server configurations
)

// Access session info
print("Session ID: \(session.sessionId.value)")
print("Current mode: \(session.modes?.currentModeId ?? "default")")
print("Current model (if the agent exposes preview model selection): \(session.models?.currentModelId ?? "default")")
```

### 6. Send Prompts

```swift
let response = try await client.sendPrompt(
    sessionId: session.sessionId,
    content: [
        .text(TextContent(text: "Create a new Swift file"))
    ]
)

switch response.stopReason {
case .endTurn:
    print("Agent completed")
case .maxTokens:
    print("Reached token limit")
case .cancelled:
    print("Request was cancelled")
default:
    break
}
```

### 7. Handle Streaming Updates

Install this consumer before sending prompts, not after waiting for a prompt
response. Keep the task handle and cancel it when the connection is retired.

```swift
let notifications = await client.notifications
let updates = Task {
    for await notification in notifications {
        guard notification.method == "session/update",
              let params = notification.params,
              let data = try? JSONEncoder().encode(params),
              let update = try? JSONDecoder().decode(SessionUpdateNotification.self, from: data) else {
            continue
        }

        switch update.update {
        case .agentMessageChunk(let content):
            if case .text(let text) = content {
                print("Agent: \(text.text)")
            }

        case .toolCall(let toolCall):
            print("Tool: \(toolCall.title ?? "Unknown") [\(toolCall.status?.rawValue ?? "unknown")]")

        case .plan(let plan):
            for entry in plan.entries {
                print("- \(entry.content) [\(entry.status)]")
            }

        case .currentModeUpdate(let mode):
            print("Mode changed to: \(mode)")

        default:
            break
        }
    }
}
```

### 8. Session Management

```swift
// Change mode
try await client.setMode(sessionId: session.sessionId, modeId: "plan")

// Change model if the agent exposes preview model-selection support
try await client.setModel(sessionId: session.sessionId, modelId: "claude-3-opus")

// Cancel ongoing operation
try await client.cancelSession(sessionId: session.sessionId)

// Discover existing sessions when the agent supports sessionCapabilities.list
let sessions = try await client.listSessions()

// Load existing session
let loaded = try await client.loadSession(
    sessionId: existingSessionId,
    cwd: "/path/to/project",
    mcpServers: []
)
```

### 9. Cleanup

```swift
let termination = await client.shutdown()
updates.cancel()
print("Direct-child cleanup confirmed: \(termination.cleanupComplete)")
```

`terminate()` remains a compatibility wrapper that discards the shutdown result.
`cancelSession` sends a notification; cancellation acknowledgement is the original
prompt's cancelled stop reason. It does not by itself prove that a child exited.
Ordinary requests default to 30 seconds, prompts have no default deadline, and
an unanswered cancelled prompt triggers connection shutdown after a 2-second grace.

## Implementing the Delegate

The delegate handles requests from the agent for file access, terminal operations, and permissions.

```swift
final class MyDelegate: ClientDelegate, Sendable {

    // File System

    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        return ReadTextFileResponse(content: content, totalLines: lines.count)
    }

    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return WriteTextFileResponse()
    }

    // Terminal

    func handleTerminalCreate(command: String, sessionId: String, args: [String]?, cwd: String?, env: [EnvVariable]?, outputByteLimit: Int?) async throws -> CreateTerminalResponse {
        // Create and track terminal process
        let terminalId = TerminalId(UUID().uuidString)
        // ... spawn process ...
        return CreateTerminalResponse(terminalId: terminalId)
    }

    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse {
        // Return current output buffer
        return TerminalOutputResponse(output: "...", exitStatus: nil, truncated: false)
    }

    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse {
        // Wait for process to complete
        return WaitForExitResponse(exitStatus: TerminalExitStatus(exitCode: 0))
    }

    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse {
        // Kill the process
        return KillTerminalResponse()
    }

    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse {
        // Release resources
        return ReleaseTerminalResponse()
    }

    // Permissions

    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        // Show UI or auto-approve based on policy
        print("Permission requested for tool call: \(request.toolCall.toolCallId)")

        if let allowOption = request.options.first(where: { $0.kind.hasPrefix("allow") }) {
            return RequestPermissionResponse(outcome: PermissionOutcome(optionId: allowOption.optionId))
        }

        return RequestPermissionResponse(outcome: PermissionOutcome(optionId: "deny"))
    }
}
```

### Using Default Delegates

For simple use cases, use the built-in delegates:

```swift
let fileDelegate = FileSystemDelegate()
let terminalDelegate = TerminalDelegate()

// Compose into your delegate or use directly
let content = try await fileDelegate.handleFileReadRequest("/path/to/file", sessionId: "s1", line: nil, limit: nil)
```

## Session Updates

The agent sends real-time updates via notifications:

| Update Type               | Description                              |
| ------------------------- | ---------------------------------------- |
| `agentMessageChunk`       | Streaming text from the agent            |
| `agentThoughtChunk`       | Agent's internal reasoning (if exposed)  |
| `toolCall`                | Tool invocation with status and content  |
| `toolCallUpdate`          | Updates to an existing tool call         |
| `plan`                    | Task plan with entries and progress      |
| `currentModeUpdate`       | Mode changed (code, chat, plan, etc.)    |
| `availableCommandsUpdate` | Available slash commands updated         |
| `configOptionUpdate`      | Configuration options changed            |
| `sessionInfoUpdate`       | Session title / metadata changed         |
| `usageUpdate`             | Context window / cumulative cost changed |

## Tool Calls

Tool calls represent agent actions like reading files, running commands, or editing code:

```swift
case .toolCall(let toolCall):
    print("Tool: \(toolCall.title ?? "")")
    print("Kind: \(toolCall.kind?.rawValue ?? "unknown")")
    print("Status: \(toolCall.status?.rawValue ?? "unknown")")

    // Tool kinds: read, edit, execute, search, delete, think, fetch, plan, switchMode, exitPlanMode, other

    for content in toolCall.content {
        switch content {
        case .content(let block):
            // ContentBlock (text, image)
        case .diff(let diff):
            print("Modified: \(diff.path)")
        case .terminal(let term):
            print("Terminal: \(term.terminalId)")
        }
    }

    if let locations = toolCall.locations {
        for loc in locations {
            print("Location: \(loc.path):\(loc.line ?? 0)")
        }
    }
```

## Debug Mode

The debug stream is metadata-only by default: direction, byte count, method, and
timestamp. Raw wire bytes are surfaced only when you install a sanitizer —
without one, no payload is ever retained or emitted.

```swift
await client.enableDebugStream(sanitizer: { data in
    // Return a payload-free summary; return nil to omit the preview.
    "frame: \(data.count) bytes"
})

Task {
    guard let stream = await client.debugMessages else { return }

    for await message in stream {
        let direction = message.direction == .outgoing ? "→" : "←"
        let method = message.method ?? "response"
        print("\(direction) \(method) (\(message.byteCount) bytes)")
        if let preview = message.rawPreview {
            print("  preview: \(preview)")
        }
    }
}

// Later: disable debug mode
await client.disableDebugStream()
```

## Error Handling

```swift
do {
    let response = try await client.sendPrompt(sessionId: session.sessionId, content: [...])
} catch ClientError.processNotRunning {
    print("Agent process is not running")
} catch ClientError.processFailed(let exitCode) {
    print("Agent exited with code: \(exitCode)")
} catch ClientError.requestTimeout {
    print("Request timed out")
} catch ClientError.agentError(let rpcError) {
    print("Agent error code: \(rpcError.code)")
} catch ClientError.delegateNotSet {
    print("No delegate set to handle agent requests")
} catch ClientError.invalidResponse {
    print("Invalid response from agent")
}
```

## MCP Server Configuration

Pass MCP (Model Context Protocol) servers when creating a session:

```swift
let session = try await client.newSession(
    workingDirectory: "/project",
    mcpServers: [
        .stdio(StdioServerConfig(
            name: "my-mcp-server",
            command: "/path/to/server",
            args: ["--port", "3000"],
            env: [EnvVariable(name: "API_KEY", value: "...")]
        )),
        .http(HTTPServerConfig(
            name: "remote-server",
            url: "https://api.example.com/mcp",
            headers: [HTTPHeader(name: "Authorization", value: "Bearer ...")]
        ))
    ]
)
```

## Building Agents (Server Mode)

The SDK supports building ACP-compliant agents that can be invoked by clients.

```swift
import ACP

// Create transport and agent
let transport = StdinTransport()
let agent = Agent(transport: transport)

// Implement the delegate
final class MyAgentDelegate: AgentDelegate, Sendable {
    let agent: Agent

    init(agent: Agent) {
        self.agent = agent
    }

    func handleInitialize(_ request: InitializeRequest) async throws -> InitializeResponse {
        return InitializeResponse(
            protocolVersion: 1,
            agentCapabilities: AgentCapabilities(),
            agentInfo: AgentInfo(name: "MyAgent", version: "1.0.0")
        )
    }

    func handleNewSession(_ request: NewSessionRequest) async throws -> NewSessionResponse {
        return NewSessionResponse(sessionId: SessionId(UUID().uuidString))
    }

    func handlePrompt(_ request: SessionPromptRequest) async throws -> SessionPromptResponse {
        // Send streaming updates
        try await agent.sendMessageChunk(sessionId: request.sessionId, text: "Processing...")

        // Return final response
        return SessionPromptResponse(stopReason: .endTurn)
    }

    func handleCancel(_ sessionId: SessionId) async throws {
        // Handle cancellation
    }
}

// Start the agent
let delegate = MyAgentDelegate(agent: agent)
await agent.setDelegate(delegate)
await transport.start()
await agent.start()
withExtendedLifetime(delegate) {} // Agent holds its delegate weakly.
```

## WebSocket Transport

For network-based communication, use the `ACPHTTP` module:

```swift
import ACPHTTP

// Connect to a WebSocket server
let transport = WebSocketTransport(url: URL(string: "ws://localhost:8080")!)
try await transport.connect()

// Send and receive messages
try await transport.send(jsonData)

for await message in transport.messages {
    // Handle incoming messages
}

await transport.close()
```

## Agent Registry

The `ACPRegistry` module provides agent discovery and installation from the [ACP Registry](https://github.com/agentclientprotocol/registry).

```swift
import ACPRegistry

// Fetch available agents
let registry = RegistryClient()
let agents = try await registry.agents()

for agent in agents {
    print("\(agent.name) v\(agent.version)")
}

// Find a specific agent
if let claude = try await registry.agent(id: "claude-acp") {
    print("Found: \(claude.name)")
}

// Install an agent
let installer = AgentInstaller()
let installed = try await installer.install(claude)

// Launch with ACP client
import ACP
let client = Client()
try await client.launch(
    agentPath: installed.executablePath,
    arguments: installed.arguments
)
```

### Distribution Types

The registry supports three distribution methods:

| Type     | Description                                                                                     |
| -------- | ----------------------------------------------------------------------------------------------- |
| `binary` | Platform-specific executables (`.zip`, `.tar.gz`, `.tgz`, `.tar.bz2`, `.tbz2`, or raw binaries) |
| `npx`    | npm packages via `npx`                                                                          |
| `uvx`    | Python packages via `uvx`                                                                       |

```swift
// Check available distribution for current platform
if let method = agent.distribution.preferred(for: .current) {
    switch method {
    case .binary(let target):
        print("Binary: \(target.archive)")
    case .npx(let pkg):
        print("NPX: \(pkg.package)")
    case .uvx(let pkg):
        print("UVX: \(pkg.package)")
    }
}
```

## Requirements

- macOS 12.0+, iOS 15.0+, tvOS 15.0+, watchOS 8.0+
- Swift 6.0+ toolchain (Swift 6 language mode, strict concurrency)

> **Note:** Process spawning (stdio transport for launching agents) is only available on macOS. Other platforms can use WebSocket transport or implement custom transports.

## Protocol Reference

This SDK implements the [Agent Client Protocol](https://agentclientprotocol.com/)
v1 specification. The package's conformance contracts (wire envelope, framing,
initialization, session lifecycle, cancellation, shutdown evidence, diagnostics)
are documented in [`docs/CONFORMANCE.md`](docs/CONFORMANCE.md).

The upstream `reference/` protocol submodules were removed during vendoring;
consult the protocol documentation online.

## License

MIT
