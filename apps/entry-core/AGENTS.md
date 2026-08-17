# Entry Core Agent Guidance

## Scope and ownership

- This directory is the single Go module `github.com/voyager-labs/voyager-app/apps/entry-core` on Go `1.26.5`.
- Keep module implementation inside `apps/entry-core`. Change root integration only when the active task requires repository-level discovery or command wiring.
- `mise.toml` is the sole command-policy owner. Keep `Makefile` targets as one-line delegates to matching `entry-core-*` tasks.
- Import `internal/runtime` with the package alias `entryruntime`.

## Module and protocol boundaries

- Runtime dependencies are the pure-Go set `gorm.io/gorm`, `github.com/glebarez/sqlite` (modernc.org/sqlite, CGO-free), and `github.com/golang-migrate/migrate/v4`. Atlas CLI and the `ariga.io/atlas-provider-gorm` provider are dev/CI-only tools (loaded by `tools/atlas-schema`), never imported by daemon code. `go.sum` is required and committed; `go.work` remains forbidden (single module, no workspace). Adding a dependency, workspace, toolchain override, or code generation requires an explicitly owned task and corresponding verification-policy update.
- Preserve the unversioned initial canonical wire contract, default app version `0.1.0-dev`, one request and one response per Unix socket connection, and the required absolute `--socket` contract. Add a future version discriminator only when an observed compatibility break requires parallel decoding or migration.
- Keep logs metadata-only. Never log raw request or response payloads, params, request IDs, secrets, or credentials.

## Package ownership

- `protocol/schema` owns strict wire parsing, validation, result and error envelopes.
- `internal/runtime` owns lifecycle state and exact `ping`, `health`, `version` dispatch results.
- `internal/transport/unixsocket` owns client/server deadlines, framing, socket identity, and bounded shutdown.
- `cmd/entry-core` owns CLI argv, request ID, stdout/stderr, and exit mapping.
- `cmd/entry-core-daemon` owns foreground composition, signals, and process exit mapping.
- `integration/daemon_smoke_test.go` is the only real-process smoke owner and uses `TestDaemonProcessSmoke`.

Do not duplicate detailed assertions across these owners. Pair behavior changes with tests in the canonical owner and follow the repository's plan-scoped RED-to-GREEN evidence policy for executable behavior changes.

## Canonical verification

From the repository root, use `mise run entry-core-check` as the complete verification entry point. Focused commands are available as `entry-core-build`, `entry-core-test`, `entry-core-test-race`, and `entry-core-smoke`.

When root harness or guidance changes, also run `python3 -m scripts.validate_harness` and `git diff --check`. Keep `go vet`, gofmt cleanliness, single-module output, `go.sum` presence, `go.work` absence, the pinned module allowlist (`go list -m all | sort` diff), and the `AutoMigrate(` ban as required invariants.

## Cross-boundary changes

Do not modify Swift/Xcode, backend, CI/CD, repository hooks, user-managed configuration, or canonical documentation from an Entry Core-only task. Native macOS adapters, app integration, persistence, and migration work require an active issue that explicitly owns those boundaries.
