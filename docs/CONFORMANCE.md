# VoyagerSwiftACP Conformance

This document is the **generic test-ownership and conformance contract** for the
VoyagerSwiftACP package (ACP v1). It is package-local and public: it never
references Voyager product spec IDs and never copies private product specs into
the fork.

Scope boundary: VOY-886 delivers the generic ACP v1 foundation only. Provider
integration (`VoyagerACPClient`), Codex migration, and provider process-tree
termination are out of scope (VOY-887 / VOY-888).

## 1. Wire contracts (owner: `ACPWireConformanceTests`, `ACPModelTests`)

JSON-RPC 2.0 envelope, strict:

| Contract            | Behavior                                                                                                     |
| ------------------- | ------------------------------------------------------------------------------------------------------------ |
| `jsonrpc`           | required, exactly `"2.0"`                                                                                    |
| Request             | `method` + `id` present; `params` omitted, object, or array                                                  |
| Notification        | `method` present, `id` key absent entirely                                                                   |
| Response            | `id` present, exactly one of `result` / `error`                                                              |
| `result: null`      | valid success result, distinct from a missing key                                                            |
| Request ID          | string, signed 64-bit integer, or null                                                                       |
| Invalid ID          | bool / object / array / fraction rejected                                                                    |
| Outgoing ID         | monotonically increasing integers; never reused; exhaustion is a typed error (`requestIDExhausted`), no wrap |
| Unknown fields      | ignored on decode                                                                                            |
| Error payload       | `code` + `message` required, `data` optional, preserved                                                      |
| Batch arrays        | rejected (frames must be a JSON object)                                                                      |
| `protocolVersion`   | integer `0...65535`; strings, null, booleans rejected                                                        |
| Client capabilities | omitted fields default to "not supported"; wrong-typed booleans rejected                                     |
| `AnyCodable`        | unsupported Swift values throw `EncodingError` instead of silently encoding `null`                           |
| `params: null`      | rejected (neither omitted nor structured) — upstream-compat change vs. earlier leniency                      |

Upstream-compatible behavior changes (intentional, documented):

1. Invalid `id` values are no longer demoted to notifications (`Message` decode rejects).
2. `protocolVersion` is no longer coerced to `1`.
3. Null-ID messages remain requests instead of becoming notifications.
4. Malformed stdout frames terminate the connection instead of being resynchronized past.

## 2. Framing (owner: `ACPFramingTests`, `ACPBoundedTransportTests`)

- One frame = one UTF-8, LF-delimited JSON object on stdout/stdin.
- Clients send undelimited JSON to `Transport.send`; stdio transports append
  exactly one LF. A strict subprocess peer rejects duplicate delimiters.
- CR immediately before LF is stripped (CRLF tolerance); escaped `\n` in strings is data.
- Empty/whitespace-only frames, non-JSON frames, non-object frames, invalid UTF-8,
  and an incomplete frame at EOF are typed errors (`JSONLineFramer.FramingFailure`).
- Limits (configurable via `TransportConfiguration`, validated at startup; zero or
  negative rejected): frame ≤ 8 MiB, read chunk 64 KiB, queued frame bytes ≤ 16 MiB.
- Overflow is an explicit typed failure (`frameLimit`, `bufferOverflow`), never a
  silent drop. The earlier "discard and resync" recovery path was removed.
- The public streams use a byte-accounted queue; consumption releases the queued
  byte budget. A stopped consumer produces an overflow failure instead of unbounded retention.
- Every stdio path (client subprocess, agent stdin) shares the single internal
  `JSONLineFramer`.

## 3. Request correlation (owner: `ACPRequestCorrelationTests`)

- Registration happens in actor state before the first suspension; a response can
  never race registration.
- Every pending continuation settles exactly once (response / timeout / caller
  cancellation / shutdown); unknown, duplicate, or late response IDs are ignored
  without touching pending state.
- Deadline tasks call back into the owning actor and settle at the actual deadline.
- Caller cancellation before the wire write sends nothing.
- Numeric and string IDs correlate independently.

## 4. Initialization (owner: `ACPInitializationTests`)

- Production major version is `{1}`; the client proposes `1`.
- State machine: `idle → starting → connected → initializing → ready`;
  failures converge to terminal `failed`; `shutdown` to `closing → closed`.
- Unsupported negotiated version, invalid response payloads, timeouts, and
  cancellations are terminal: the connection refuses further initialization.
- `initialize` while in progress → `initializationInProgress`; after ready →
  `alreadyInitialized`.
- Session operations before initialization are rejected locally (`notInitialized`);
  no wire write occurs.
- Omitted capability booleans mean "not supported"; image/audio prompt content is
  gated on the negotiated `promptCapabilities`.
- Delegates install synchronously with the connection (`setDelegate`), so callbacks
  that arrive before or during initialization are never missed.

## 5. Sessions (owner: `ACPSessionLifecycleTests`, `ACPSessionLoadingTests`)

- Session IDs are agent-generated and opaque.
- `session/new` success registers the session; reusing an already tracked ID in
  a new-session response is a protocol failure. Successful load/resume/fork may
  re-announce an existing ID; adoption preserves its current snapshot.
- One active prompt per session: second prompt → `sessionBusy`; closed session →
  `sessionClosed`; unknown session → `unknownSession` without a wire write.
- Every `session/update` must target a tracked session or a pending load. Unknown variants for
  tracked sessions pass through raw without state changes; malformed known
  variants are protocol failures.
- Pending `session/load` requests authorize history updates for their requested
  session IDs before the response. Updates use the existing bounded notification
  queue in wire order. Response, failure, timeout, cancellation, or shutdown removes
  this temporary authorization; only successful load registers the session.
- `session/cancel` is an idempotent notification (no id on the wire). A prompt turn
  ends only with its terminal response (`stopReason: "cancelled"`), which returns
  the session to `idle`; updates preceding the terminal response are still delivered.
- Pending `session/request_permission` is answered exactly once with
  `PermissionOutcome(cancelled: true)` on cancel; late delegate outcomes are dropped.
- If no terminal response arrives within `cancellationGrace` (default 2 s), the
  connection shuts down and every pending request fails.
- Protocol cancellation, caller cancellation (`CancellationError` once), and process
  shutdown are distinct paths.

## 6. Transport lifecycle (owner: `ACPTransportLifecycleTests`, `ACPConformanceTests`)

- `ACPProcessManager` is the single owner of the direct child process and pipes.
- Startup failure reclaims every pipe and reports `.failure(.startup)` evidence.
- stdout EOF is terminal even while the child is alive; it drives a bounded
  shutdown and reports `.stdoutEOF`.
- Natural exit delivers already-completed frames before termination evidence.
- Bounded shutdown: block new writes → close stdin → SIGTERM → wait ≤ 2 s →
  SIGKILL → wait ≤ 1 s; `cleanupComplete` is true only when the direct child exit
  was confirmed. An uncooperative child is reaped via SIGKILL escalation.
- Blocking pipe I/O never runs on a cooperative executor (serial write queue,
  event-driven readability handlers).
- `shutdown()` is idempotent. Returned `TransportTermination` values are immutable;
  the stored evidence preserves the first cause while incorporating subsequently
  confirmed exit status, signal and cleanup completion.
- `deinit` fails continuations synchronously, cancels owned tasks, and schedules
  transport cleanup; callers needing exit evidence must `await shutdown()`.
- The default launch path never touches `ProcessRegistry.shared` disk state.

## 7. Diagnostics (owner: `ACPDiagnosticsTests`)

- Default debug output is metadata only: direction, byte count, method, timestamp.
- Raw payload bytes are exposed exclusively through a caller-provided sanitizer
  installed with `enableDebugStream(sanitizer:)`; without one, no wire bytes are
  retained or emitted.
- Malformed-frame failure reasons are fixed, payload-free strings.
- Remote error payloads are preserved on the API surface (`ClientError.agentError`)
  but never logged verbatim.
- stderr is drained (never blocks the child) and is not logged by the package;
  the existing `stderrLines()` observation API is retained as explicit opt-in raw
  observation, with bounded buffering. Callers own redaction before logging it.

## 8. Swift 6 concurrency (owner: strict build + `ACPConcurrencyTests`)

- Package builds in Swift 6 language mode with complete concurrency checking.
- Shared mutable utility state (logger subsystem, shell cache) lives in immutable
  static boxes with documented lock invariants; no `nonisolated(unsafe)`, no
  suppression pragmas.
- Ingress readers and deadline tasks hold the client weakly; `deinit` remains
  reachable and performs synchronous cleanup plus scheduled transport close.

## 9. Offline required suite (owner: `ACPConformanceTests`, `RegistryTests`)

- The synthetic fixture agent is a package test resource compiled at setup with
  `xcrun swiftc -swift-version 6`; it uses Foundation only and never imports the
  package under test (golden wire behavior).
- Scenarios: normal transcript, hold-prompt/cancel, malformed output, stdout EOF,
  exit-17, ignore-TERM.
- Registry tests run against a URLProtocol stub with a unique, test-local cache
  directory; no external network and no shared user cache is a test precondition.
- Required suite: `swift test --package-path <package>` exits 0 with zero skips
  among mandatory scenarios.

## 10. Verification commands

From the app repository root:

```bash
xcrun swift build --package-path apps/macos/Packages/VoyagerSwiftACP \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors

xcrun swift test --package-path apps/macos/Packages/VoyagerSwiftACP \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Consumer evidence ("app consumer 검증 완료") additionally requires the real Xcode
run of `VoyagerTests/VoyagerSwiftACPConsumerTests` and `mise run macos-build`.

```bash
mise run macos-test -- -only-testing:VoyagerTests/VoyagerSwiftACPConsumerTests
mise run macos-build
```

In an independent fork checkout, run `xcrun swift test` with the same strict flags
but without the app-relative `--package-path`. The app's mise tasks do not exist
in that checkout. The consumer suite is app-hosted XCTest using a fake transport
with the real public Client; it proves import/link and API consumption, not UI
E2E, real-provider execution or subprocess transport. Subprocess evidence comes
from the package's separate synthetic-agent suite.

### Outbound framing regression

App revision `8bda0277f` appended LF in both Client and `ACPProcessManager.write`.
The client now sends undelimited JSON and leaves the delimiter to the transport.
`ACPTransportLifecycleTests.testClientWritesExactlyOneLinePerRequest` exercises
initialize/new/prompt against a subprocess that exits on an empty line. This
regression fails on the duplicate-delimiter implementation.

## 11. Bridge handoff

A bridge speaks ACP v1 JSON-RPC on stdout and reserves stderr for diagnostics.
The consumer installs its delegate before initialization, launches a stdio client
(or connects a supplied `Transport` and calls `start()`), and initializes with the
capabilities it actually implements. It must retain agent-issued session IDs and
consume `notifications` while prompts are active.

`cancelSession` sends a notification; the original prompt's cancelled stop reason
is protocol evidence. Caller task cancellation settles the caller immediately,
while the client continues tracking the turn and sends protocol cancellation.
Use `shutdown()` when process exit evidence is required; inspect both termination
reason and `cleanupComplete`. Protocol cancellation alone does not prove child exit.

Provider installation, authentication, credentials, event-to-product mapping,
workspace consent, persistence, and UI remain the adapter consumer's responsibility.
These tests use synthetic agents and do not establish real-provider readiness.

## 12. Public API compatibility

The explicit `Client.init()`, `StdinTransport.init()`, two-argument
`TransportConfiguration.init(maxMessageSize:bufferSize:)`, and
`Client.sendCancelNotification(sessionId:)` entry points remain available.
`DebugMessage.rawData` and `jsonString` remain compatibility views, but expose only
sanitizer output (empty data / nil by default), never unfiltered wire bytes.

An API-digester comparison against the production baseline reports the intentional
new `ClientError` cases and `RequestId.null`; consumers with exhaustive switches
must handle those cases. It also reports the `sendRequest` generic representation
change from a named `T: Encodable` to `some Encodable`, as produced by the repository
formatter. The callable method and its Encodable input contract remain present.
This is a source-level migration requiring Swift 6, not a binary-compatibility claim.
