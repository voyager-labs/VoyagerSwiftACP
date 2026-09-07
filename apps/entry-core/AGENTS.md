# Entry Core Agent Guidance

## Scope and ownership

- This directory is the single Go module `github.com/voyager-labs/voyager-app/apps/entry-core` on Go `1.26.5`.
- Keep module implementation inside `apps/entry-core`. Change root integration only when the active task requires repository-level discovery or command wiring.
- `mise.toml` is the sole command-policy owner. Keep `Makefile` targets as one-line delegates to matching `entry-core-*` tasks.
- Import `internal/runtime` with the package alias `entryruntime`.

## Module and protocol boundaries

- Runtime dependencies are the pure-Go set `gorm.io/gorm`, `github.com/glebarez/sqlite` (modernc.org/sqlite, CGO-free), and `github.com/golang-migrate/migrate/v4`. Atlas CLI and the `ariga.io/atlas-provider-gorm` provider are dev/CI-only tools (loaded by `tools/atlas-schema`), never imported by daemon code. `go.sum` is required and committed; `go.work` remains forbidden (single module, no workspace). Adding a dependency, workspace, toolchain override, or code generation requires an explicitly owned task and corresponding verification-policy update.
- Preserve the unversioned initial canonical wire contract, default app version `0.1.0-dev`, one request and one response per Unix socket connection, the required absolute `--socket` contract, and the optional absolute `--database` contract (absent flag keeps DB-less behavior). Add a future version discriminator only when an observed compatibility break requires parallel decoding or migration.
- Migrations are append-only in `internal/persistence/sqlite/migrations` (currently `0001_*`–`0007_*` + `atlas.sum`); extend the GORM model, run `atlas migrate diff <name> --env gorm` then `atlas migrate hash --env gorm`, normalize the golang-migrate filename to canonical `000N_` form, and validate with `mise run entry-core-migration-validate`. Never run `.down.sql` at runtime.
- Keep logs metadata-only. Never log raw request or response payloads, params, request IDs, secrets, or credentials.

## Package ownership

- `protocol/schema` owns strict wire parsing, validation, result and error envelopes, including the 11 VOY-765 Property methods (`property.definition.*`, `property.option.*`, `property.assignment.list`, `property.change.prepare/execute`) and their bounds (envelope 65,536; `page_size` 1..256; ID/target/member arrays ≤256; scalars ≤4,096 bytes; key/name/label ≤256 bytes).
- `internal/runtime` owns lifecycle state, exact `ping`, `health`, `version` dispatch results, the injected Entry contract list/resolve path, and VOY-765 Property dispatch (composed runtime only; DB-less runtime rejects Property methods at the method gate).
- `internal/transport/unixsocket` owns client/server deadlines, framing, socket identity, and bounded shutdown.
- `cmd/entry-core` owns CLI argv, request ID, stdout/stderr, and exit mapping.
- `cmd/entry-core-daemon` owns foreground composition, signals, and process exit mapping.
- `internal/persistence/sqlite` owns the SQLite store lifecycle, the versioned embedded migrations and their checksummed directory, the workspace bootstrap/restore, the catalog seed/validate/preset-reconcile/compose seams, and the `WithinTx` transaction runner (store/migration/checksum/workspace/tx tests live in `internal/persistence/sqlite/`).
- `internal/domain/entry` owns the typed UUIDv7 `WorkspaceID` and `WorkspaceContext` value semantics plus the Property domain values (`PropertyID`, `PropertyOptionID`, definitions, options, assignments).
- `internal/application/property` owns the catalog (definition/option) use cases and the prepare/execute atomic change flow: every mutation runs in exactly one top-level `TransactionRunner.WithinTx`, CAS re-verifies definition+assignment revisions, the response budget is checked pre-commit (`scope_too_large` fail-closed, zero writes), and the response is a canonical read-back of persisted facts. Local-path targets are clean absolute UTF-8 ≤4,096 bytes, must exist and be accessible, and carry locator-derived identity without rename/move continuity.
- `integration/daemon_smoke_test.go` is the only real-process smoke owner and uses `TestDaemonProcessSmoke`, including the persistence restart, corrupt-database fail-closed, catalog seed/drift, and `property_*` phases (atomic persistence, response-budget preflight, stale/invalid targets, inaccessible path, oversized envelope).

The Atlas GORM Provider loader (`internal/persistence/sqlite/tools/atlas-schema`) and Atlas CLI are dev/CI-only tools; they are never imported or linked into the daemon binary.

Do not duplicate detailed assertions across these owners. Pair behavior changes with tests in the canonical owner and follow the repository's plan-scoped RED-to-GREEN evidence policy for executable behavior changes.

## Canonical verification

From the repository root, use `mise run entry-core-check` as the complete verification entry point. Focused commands are available as `entry-core-build`, `entry-core-test`, `entry-core-test-race`, and `entry-core-smoke`.

`entry-core-schema-parity` gates the GORM model against the migration head: it runs `atlas migrate diff` against a temp copy of the migrations dir and requires the result to be empty or to match `internal/persistence/sqlite/migration-divergence.allowlist` (the known composite-FK loader divergence, normalized for CHECK-constraint ordering). A model change without a matching migration fails this gate; regenerate the allowlist only when the accepted divergence itself changes.

When root harness or guidance changes, also run `python3 -m scripts.validate_harness` and `git diff --check`. Keep `go vet`, gofmt cleanliness, single-module output, `go.sum` presence, `go mod verify`, `go.work` absence, and the `AutoMigrate(` ban as required invariants.

## Cross-boundary changes

Do not modify Swift/Xcode, backend, CI/CD, repository hooks, user-managed configuration, or canonical documentation from an Entry Core-only task. Native macOS adapters, app integration, persistence, and migration work require an active issue that explicitly owns those boundaries.
