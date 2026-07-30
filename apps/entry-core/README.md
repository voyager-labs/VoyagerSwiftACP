# Entry Core

Entry Core는 Voyager의 최소 Go runtime foundation입니다. 하나의 foreground daemon이 Unix Domain Socket 요청을 처리하고, 별도 CLI가 `ping`, `health`, `version` 요청을 보냅니다. 이 module은 기존 macOS Helper, XPC, Spotlight 경로와 독립적이며 Swift integration을 포함하지 않습니다.

## Module contract

- Module: `github.com/voyager-labs/voyager-app/apps/entry-core`
- Go: `1.26.5`
- Dependencies: Go standard library only
- Workspace: 없음, root와 module 어디에도 `go.work`를 만들지 않음
- Protocol version: `1`
- Default app version: `0.1.0-dev`

`mise.toml`이 build, test, smoke, check 정책의 유일한 소유자입니다. package `Makefile`은 같은 root mise task를 호출하는 얇은 adapter일 뿐입니다.

## Architecture

| Path                               | Responsibility                                                    |
| ---------------------------------- | ----------------------------------------------------------------- |
| `cmd/entry-core`                   | CLI argument, request ID, output, exit-code adapter               |
| `cmd/entry-core-daemon`            | foreground process, signal, server composition root               |
| `protocol/schema`                  | strict protocol 1 JSON request and response contract              |
| `internal/runtime`                 | lifecycle state and `ping`, `health`, `version` dispatch          |
| `internal/transport/unixsocket`    | one-shot UDS client/server, deadlines, socket ownership, shutdown |
| `integration/daemon_smoke_test.go` | real CLI and daemon process smoke owner                           |

## Canonical commands

Run these commands from the repository root:

```bash
mise run entry-core-build
mise run entry-core-test
mise run entry-core-test-race
mise run entry-core-smoke
mise run entry-core-check
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

## CLI and daemon

Both processes require an explicit absolute socket path. There is no default or production socket discovery.

```bash
entry-core-daemon --socket <absolute-path>
entry-core --socket <absolute-path> <ping|health|version>
```

The daemon runs in the foreground and writes lifecycle metadata to stderr. On success, the CLI writes one compact result JSON line to stdout. Usage and local validation failures exit `2`; transport, server, and response validation failures exit `1`; success exits `0`. Each connection carries one protocol 1 request and one response.

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

Send `SIGINT` or `SIGTERM` to start graceful shutdown. The daemon stops accepting requests, allows active handlers a bounded grace period, force-closes remaining owned connections when needed, and removes the socket only when the path still identifies the socket it created. A second signal skips the remaining grace period. Replacement paths and pre-existing paths are never removed.

## Troubleshooting

- `usage: entry-core...` or `usage: entry-core-daemon...`: pass `--socket` followed by a non-empty absolute path.
- Startup fails before socket creation: confirm the direct parent is owned by the effective user, is not a symlink, and has exact mode `0700`.
- Destination already exists: remove it only after independently confirming it is safe. Entry Core fails closed and never deletes a pre-existing path.
- CLI reports a transport failure: confirm the foreground daemon is running on the same socket and that the total request can complete within the bounded deadline.
- `entry-core-check` reports formatting files: run `find apps/entry-core -type f -name '*.go' -print0 | xargs -0 mise exec -- gofmt -w` from the repository root, then rerun the check.

Production socket discovery/defaults, launchd, reconnect, Swift integration, and Helper/XPC migration are deferred.
