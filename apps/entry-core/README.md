# Entry Core

Entry Core는 Voyager의 최소 Go runtime foundation입니다. 현재 production foreground daemon, CLI, UDS, Swift client는 canonical wire contract에서 `ping`, `health`, `version`만 처리합니다. canonical Entry contract의 `entry.list`/`entry.resolve` strict DTO, bounded unified application orchestration, composite continuation, injected runtime 경로는 구현되어 in-process test로 검증되지만 production UDS/CLI에는 연결되지 않았습니다. 이 module은 기존 macOS Helper, XPC, Spotlight 경로와 독립적이며 Swift integration을 포함하지 않습니다.

## Module contract

- Module: `github.com/voyager-labs/voyager-app/apps/entry-core`
- Go: `1.26.5`
- Dependencies: Go standard library only
- Workspace: 없음, root와 module 어디에도 `go.work`를 만들지 않음
- Wire and Entry contract: one unversioned initial canonical contract
- Request/response envelope ceiling: exactly `65,536` bytes for canonical wire contract
- Default app version: `0.1.0-dev`

The contract is intentionally unversioned while there is only one canonical representation. A future version discriminator is introduced only after a concrete compatibility break requires concurrent old/new decoding or migration; it is not preallocated in envelopes, identities, cursors, property definitions, or persistence claims.

`mise.toml`이 build, test, smoke, check 정책의 유일한 소유자입니다. package `Makefile`은 같은 root mise task를 호출하는 얇은 adapter일 뿐입니다.

## Architecture

| Path                                  | Responsibility                                                          |
| ------------------------------------- | ----------------------------------------------------------------------- |
| `cmd/entry-core`                      | canonical wire contract CLI argument, request ID, output, exit-code adapter                  |
| `cmd/entry-core-daemon`               | canonical wire contract foreground process, signal, server composition root                  |
| `protocol/schema`                     | strict canonical wire contract JSON DTO, validation, response-size contract      |
| `internal/domain/entry`               | transport-free Entry values and invariants                              |
| `internal/mount`                      | workspace mount registry, normalization, forward/reverse resolution     |
| `internal/source`                     | local and fake-external adapters with source-scoped cursors             |
| `internal/application/entry`          | bounded workspace list/resolve, fair multi-source pagination, context mapping |
| `internal/runtime`                    | lifecycle, canonical wire dispatch, injected Entry contract list/resolve |
| `internal/transport/unixsocket`       | canonical wire contract one-shot UDS client/server and lifecycle                |
| `integration/entry_contract_test.go`  | unified local+fake-external canonical list/continuation/resolve proof         |
| `integration/daemon_smoke_test.go`    | sole Go integration owner for real CLI and daemon process smoke         |

## Canonical commands

Run these commands from the repository root:

```bash
mise run entry-core-build
mise run entry-core-test
mise run entry-core-test-race
mise run entry-core-smoke
mise run entry-core-check
mise run entry-core-interop-check
```

The equivalent package adapters are:

```bash
make -C apps/entry-core build
make -C apps/entry-core test
make -C apps/entry-core test-race
make -C apps/entry-core smoke
make -C apps/entry-core check
```

`entry-core-build` compiles both real command packages without writing repository binaries. `entry-core-smoke` runs only `TestDaemonProcessSmoke`. `entry-core-check` composes build, full test, full race, canonical smoke, vet, gofmt, and module invariant checks.

## Dependency and native event decisions

- The runtime foundation is standard-library-only because the current CLI, daemon, protocol, and Unix socket lifecycle require no external package.
- VOY-663 does not adopt an FSEvents implementation. Direct CoreServices/CGO, a maintained Go package, and the existing Swift-native adapter remain separate follow-up options.
- A native event implementation must first prove event-ID replay, drop and overflow recovery, root changes, restart behavior, and signed macOS bundling. Until then, native event ingestion remains outside this module.

## Canonical Entry contract

Implemented and verified in-process:

- `protocol/schema` strictly decodes canonical Entry contract `entry.list` and `entry.resolve`, requires bounded `page_size` and `requested_properties`, keeps `page_token` opaque, derives `has_more` from token presence, maps canonical Entry DTOs, and enforces the shared 65,536-byte request/response ceiling.
- `internal/application/entry` selects at most eight active mount/source scopes in a server-selected workspace, fairly interleaves canonical entries, authenticates a composite continuation token, preserves per-source availability/freshness/revision summaries, and resolves by EntryRef plus mount or by VirtualPath.
- `internal/runtime` exposes only an injected/test canonical Entry contract list/resolve path. It snapshots lifecycle state before application I/O and maps typed application failures to stable redacted protocol errors. Default `New()` and production composition remain limited to `ping`, `health`, and `version`; Entry methods are rejected at the method gate.
- `internal/source`의 fake-external 경로는 source-owned connection resolver가 `AccessSession`을 만든 뒤 fake client를 호출하는 결정적 테스트 경계입니다. CredentialRef는 opaque reference이며 credential/token/API-key/header 값은 Entry, wire, cursor, error, log에 들어가지 않습니다.
- `integration/entry_contract_test.go` proves one root list response containing localfs and fake-external entries, opaque composite continuation without duplicate/lost entries, representative local/external resolve, available success-empty, and cached-offline normalization to stale with a `source_offline` warning.
- Canonical wire contract `ping`, `health`, `version`, `EmptyParams`, exact bytes, CLI/daemon behavior, and real-process smoke ownership are canonical.

Not production-wired and still deferred:

- The production daemon, Unix-socket transport, CLI, and Swift client use canonical wire contract but expose no canonical Entry contract list/resolve route.
- Localfs and fakeexternal are deterministic fixture adapters for this boundary, not production provider connectors. Real providers, OAuth browser/callback/code exchange, token/API-key storage or refresh, secure-store integration, network behavior, retry/rate limiting, and provider configuration are deferred.
- Databases, migrations, durable Entry/Property/revision storage, indexes, search/query projections, cache authority, restart-stable composite tokens, mutation/operation engines, and content streaming are deferred.
- Swift/macOS models and UI, Helper/XPC integration, native filesystem observation, and production Mirage execution are deferred.
- VOY-665 receives only the ownership/coexistence/rollback handoff defined by the canonical contract. Its migration and implementation remain owned by VOY-665 and are not implemented here.

## CLI and daemon

Both processes require an explicit absolute socket path. There is no default or production socket discovery.

```bash
entry-core-daemon --socket <absolute-path>
entry-core --socket <absolute-path> <ping|health|version>
```

The daemon runs in the foreground and writes lifecycle metadata to stderr. On success, the CLI writes one compact result JSON line to stdout. Usage and local validation failures exit `2`; transport, server, and response validation failures exit `1`; success exits `0`. Each connection carries one canonical request and one canonical response.

For a local manual run, place binaries outside the repository:

```bash
tmp_dir="$(mktemp -d)"
(cd apps/entry-core && mise exec -- go build -o "$tmp_dir/entry-core-daemon" ./cmd/entry-core-daemon)
(cd apps/entry-core && mise exec -- go build -o "$tmp_dir/entry-core" ./cmd/entry-core)
"$tmp_dir/entry-core-daemon" --socket "$tmp_dir/entry-core.sock"
```

In another terminal:

```bash
"$tmp_dir/entry-core" --socket "$tmp_dir/entry-core.sock" ping
```

## Shutdown and cleanup

Send `SIGINT` or `SIGTERM` to start graceful shutdown. The daemon stops accepting requests, allows active handlers a bounded grace period, force-closes remaining owned connections when needed, and performs a best-effort identity check before removing the socket it created. A second signal skips the remaining grace period. Pre-existing destinations are never removed during startup. During cleanup, replacement preservation is guaranteed only between cooperating Entry Core daemon instances that honor the same persistent lifecycle lock; it is not guaranteed against a non-cooperating process running as the same effective UID.

The daemon serializes the socket lifecycle with a persistent `<socket>.lock` file. It acquires an exclusive advisory lock before inspecting or binding the socket and releases it only after startup rollback or shutdown cleanup finishes. The lock file must be a non-symlink regular file owned by the effective user, have exact mode `0600`, and have exactly one link. It remains after a clean shutdown so later daemon starts can reuse the same inode safely. Entry Core fails closed without changing the socket or lock when the lock is active or its metadata is unsafe. The lock is advisory: it coordinates Entry Core instances that acquire the same lock, but it cannot prevent a process with the same effective UID from changing the socket or lock pathname. The `0700` parent excludes other users, not processes sharing that effective UID.

## Troubleshooting

- `usage: entry-core...` or `usage: entry-core-daemon...`: pass `--socket` followed by a non-empty absolute path.
- Startup fails before socket creation: confirm the direct parent is owned by the effective user, is not a symlink, and has exact mode `0700`.
- Destination already exists: remove it only after independently confirming it is safe. Entry Core fails closed and never deletes a pre-existing path.
- CLI reports a transport failure: confirm the foreground daemon is running on the same socket and that the total request can complete within the bounded deadline.
- `entry-core-check` reports formatting files: run `find apps/entry-core -type f -name '*.go' -print0 | xargs -0 mise exec -- gofmt -w` from the repository root, then rerun the check.

Production socket discovery/defaults, launchd, reconnect, Entry operation production wiring, real providers/auth, DB/migration/index/storage, mutation/operation execution, Swift/macOS UI, Helper/XPC, Mirage production execution, and VOY-665 migration are deferred.
