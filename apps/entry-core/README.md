# Entry Core

Entry Core는 Voyager의 최소 Go runtime foundation입니다. 현재 production foreground daemon, CLI, UDS, Swift client는 canonical wire contract에서 `ping`, `health`, `version`만 처리합니다. `--database` 모드의 daemon은 여기에 VOY-765 Property API 11개 method(`property.definition.*`, `property.option.*`, `property.assignment.list`, `property.change.prepare/execute`)를 추가로 dispatch합니다(아래 "Property API" 참고). DB-less 모드는 이전과 동일하게 lifecycle 전용입니다. canonical Entry contract의 `entry.list`/`entry.resolve` strict DTO, bounded unified application orchestration, composite continuation, injected runtime 경로는 구현되어 in-process test로 검증되지만 production UDS/CLI에는 연결되지 않았습니다. 이 module은 기존 macOS Helper, XPC, Spotlight 경로와 독립적이며 Swift integration을 포함하지 않습니다.

## Module contract

- Module: `github.com/voyager-labs/voyager-app/apps/entry-core`
- Go: `1.26.5`
- Dependencies: pure-Go runtime deps `gorm.io/gorm`, `github.com/glebarez/sqlite` (driven by `modernc.org/sqlite`, CGO-free), `github.com/golang-migrate/migrate/v4`; `go.sum` required and committed
- Dev/CI tools: Atlas CLI (`mise` aqua `ariga/atlas` 1.3.0) + Atlas GORM Provider (`ariga.io/atlas-provider-gorm`, imported only by the dev `tools/atlas-schema` loader, never by daemon code)
- Workspace: 없음, root와 module 어디에도 `go.work`를 만들지 않음
- Wire and Entry contract: one unversioned initial canonical contract
- Request/response envelope ceiling: exactly `65,536` bytes for canonical wire contract
- Default app version: `0.1.0-dev`

The contract is intentionally unversioned while there is only one canonical representation. A future version discriminator is introduced only after a concrete compatibility break requires concurrent old/new decoding or migration; it is not preallocated in envelopes, identities, cursors, property definitions, or persistence claims.

`mise.toml`이 build, test, smoke, check 정책의 유일한 소유자입니다. package `Makefile`은 같은 root mise task를 호출하는 얇은 adapter일 뿐입니다.

## Architecture

| Path                                              | Responsibility                                                                                                                                            |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cmd/entry-core`                                  | canonical wire contract CLI argument, request ID, output, exit-code adapter                                                                               |
| `cmd/entry-core-daemon`                           | canonical wire contract foreground process, signal, server composition root                                                                               |
| `protocol/schema`                                 | strict canonical wire contract JSON DTO, validation, response-size contract                                                                               |
| `internal/domain/entry`                           | transport-free Entry values and invariants                                                                                                                |
| `internal/mount`                                  | workspace mount registry, normalization, forward/reverse resolution                                                                                       |
| `internal/source`                                 | local and fake-external adapters with source-scoped cursors                                                                                               |
| `internal/application/entry`                      | bounded workspace list/resolve, fair multi-source pagination, context mapping                                                                             |
| `internal/application/property`                   | VOY-765 Property catalog (definition/option) 유스케이스와 prepare/execute 원자적 변경, CAS, 정준 read-back                                                |
| `internal/runtime`                                | lifecycle, canonical wire dispatch, injected Entry contract list/resolve                                                                                  |
| `internal/transport/unixsocket`                   | canonical wire contract one-shot UDS client/server and lifecycle                                                                                          |
| `internal/persistence/sqlite`                     | SQLite store lifecycle, versioned migrations, workspace bootstrap/restore, `WithinTx` mutation boundary (store/migrate/checksum/workspace/tx/model/embed) |
| `internal/domain/entry`                           | transport-free Entry values and invariants, typed UUIDv7 `WorkspaceID` + `WorkspaceContext`                                                               |
| `integration/entry_contract_test.go`              | unified local+fake-external canonical list/continuation/resolve proof                                                                                     |
| `integration/daemon_smoke_test.go`                | sole Go integration owner for real CLI and daemon process smoke (including persistence smoke)                                                             |
| `integration/daemon_property_persistence_test.go` | real-daemon Property UDS 통합 헬퍼(원자적 persistence, 응답 예산, sibling 실패 시나리오 러너)                                                             |
| `integration/property_smoke_test.go`              | real-daemon Property UDS 통합 헬퍼(wire 교환, 정의/옵션 fixture, 임시 파일 루트)                                                                          |

Dev/CI-only tooling (never linked into the daemon binary): `internal/persistence/sqlite/tools/atlas-schema` loads the desired GORM schema for Atlas generation and validation.

## Canonical commands

Run these commands from the repository root:

```bash
mise run entry-core-build
mise run entry-core-test
mise run entry-core-test-race
mise run entry-core-smoke
mise run entry-core-property-catalog-generate
mise run entry-core-property-catalog-validate
mise run entry-core-schema-parity
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

`entry-core-build` compiles both real command packages without writing repository binaries. `entry-core-smoke` runs only `TestDaemonProcessSmoke`. `entry-core-check` composes build, full test, full race, canonical smoke, the property-catalog validation, the migration validation, schema parity, vet, gofmt, and module invariant checks.

`entry-core-schema-parity` compares the desired GORM model schema against the migration head by running `atlas migrate diff` on a temp copy of the migrations directory. The diff must be empty or byte-match (after CHECK-constraint ordering normalization) the committed `internal/persistence/sqlite/migration-divergence.allowlist`, which records the accepted divergence: the Atlas GORM loader cannot express migration `0002`'s composite foreign keys, so a naive diff always proposes recreating the tables without them. A model edit without a matching migration fails this gate.

## Property catalog seed and condition catalog

The System Property Registry (`shared/system_property_registry.json`) and the Property Condition Registry (`shared/property_condition_registry.json`) are projected at development time into committed immutable artifacts:

- `internal/persistence/sqlite/seeds/0001_system_property_catalog_v2_4_1.sql` — full-state SQL seed (278 Workspace definitions, 294 source descriptors, 296 bindings, 441 terms = 1,309 rows). The SQL contains no transaction statements, runtime path, secret, or Registry JSON blob.
- `internal/persistence/sqlite/seeds/catalog_gen.go` — generated seed metadata (ordinal, System Registry version, SQL SHA-256, canonical dataset digest, fresh-row counts).
- `internal/domain/entry/property_condition_catalog_gen.go` — compiled Condition Registry catalog (version 2.2.0, 20 operators, all 42 `(operator, allowed_type)` relations) with typed lookup/validation in `property_condition.go`. Executable condition semantics live in Go; no SQLite condition table exists.

The generator is dev/CI-only under `internal/tools/property-catalog` (never linked into the daemon). It accepts explicit paths and `--write` or side-effect-free `--check`:

```bash
mise run entry-core-property-catalog-generate   # regenerate + write committed artifacts
mise run entry-core-property-catalog-validate   # verify committed artifacts are current (stale/missing rejected)
```

`entry-core-property-catalog-generate` rewrites the three generated artifacts from the canonical Registries; `entry-core-property-catalog-validate` fails if any committed artifact is missing or stale, and `entry-core-check` depends on it.

## Property API (VOY-765)

`--database` 모드 daemon이 UDS로 제공하는 쓰기 가능한 System Property backend다. DB-less 모드에서는 method gate에서 거절된다.

### Methods

`protocol/schema/property.go` 상수와 1:1로 대응하는 11개 canonical method:

| Method                        | 소유 유스케이스 (`internal/application/property`)                            |
| ----------------------------- | ---------------------------------------------------------------------------- |
| `property.definition.list`    | 워크스페이스 정의 bounded 목록(`page_size` 1..256, opaque `next_page_token`) |
| `property.definition.create`  | 사용자 정의 생성(`user` namespace, UUIDv7 ID 발급, 첫 revision 1)            |
| `property.definition.update`  | 표시 이름 메타데이터 갱신(CAS on `definition_revision`)                      |
| `property.definition.disable` | 정의 비활성화(물리 삭제 없음, CAS)                                           |
| `property.option.create`      | select 정의에 선택지 추가(소유 정의 revision +1)                             |
| `property.option.update`      | 선택지 label 변경(rename/recolor, CAS)                                       |
| `property.option.reorder`     | 선택지 ordinal 재배열(CAS)                                                   |
| `property.option.disable`     | 선택지 비활성화(CAS)                                                         |
| `property.assignment.list`    | local_path 대상 1개의 assignment fact bounded 읽기(PropertyID 오름차순)      |
| `property.change.prepare`     | 변경안을 비내구 계산(저장 없음, before/after와 `requires_confirmation` 반환) |
| `property.change.execute`     | 단일 트랜잭션 원자적 적용 + 정준 read-back 반환                              |

### Limits

- Request/response envelope: exactly `65,536` bytes (shared `MaxWireBytes`)
- `page_size`: 1..256; result rows도 동일 상한
- 요청 PropertyID 배열 / prepare·execute 변경 대상 수 / many-value 멤버 수: each ≤256
- 스칼라 값(text/URL/email/local path): ≤4,096 bytes UTF-8
- definition key/name, option label: ≤256 bytes
- request ID: ≤128 bytes

### Bootstrap order (`--database`)

`cmd/entry-core-daemon/main.go` 순서 그대로, 어느 단계든 실패하면 socket 생성 전 fail-closed(exit 1):

1. store open (`sqlite.Open`, connection policy read-back 검증 포함)
2. embedded migration (`Migrate`)
3. workspace bootstrap/restore (`BootstrapOrRestoreWorkspace`)
4. catalog seed apply (`ApplyCatalogSeed`, 멱등)
5. active catalog validate (`ValidateActiveCatalog`, 고아/invalid snapshot 거절)
6. preset reconcile (`ApplyPropertyPresets`, Status/Project/Priority 멱등 재조정, 사용자 편집 행 미덮쓰기)
7. service compose (`ComposeServices`, catalog+change 서비스를 runtime에 조합)
8. ready — `workspace metadata initialized|restored` 로그 후 socket bind, `started in foreground`

### Atomicity and read-back

- 모든 mutation은 정확히 하나의 top-level `TransactionRunner.WithinTx` 안에서 수행된다. 물리 삭제 경로는 없고, 성공 시 소유 정의의 `definition_revision`은 정확히 1 올라간다.
- `property.change.execute`는 하나의 트랜잭션 안에서 **CAS 재검증 → 응답 예산 사전 검사 → 일괄 적용 → 정준 read-back → 예산 재검사** 순서를 강제한다. CAS는 definition revision과 assignment revision 모두를 검사하고, expected assignment revision 0은 implicit unset@0(set→clear ABA 포함)을 의미한다. Stale revision은 protocol `conflict`로 매핑된다. wire `expected_assignment_revision`은 도메인 revision과 1:1이다 — 0은 implicit unset@0 첫 쓰기(set→clear ABA 포함), 이후 변경은 read-back 응답의 revision을 그대로 CAS 토큰으로 전달한다(definition CAS와 대칭).
- commit 전에 staged fact로 예상 read-back 성공 응답 바이트를 계산해 봉투 초과 시 `scope_too_large`로 실패 닫기한다(쓰기 0). 커밋 직전 persisted fact를 재조회해 정준 read-back 행을 만들고 요청 순서대로 반환한다.
- `internal/application/property/change_readback.go`의 반영 인코더는 protocol `EncodedSuccessBytes`와 바이트 parity 테스트(`TestEncodedExecuteResponseBytesMatchProtocolEnvelope`)로 잠겨 있다.
- 알려진 스펙 편차: 계획의 `property_response_budget_preflight` fixture(32×4096바이트 스칼라 요청이 봉투 안에 들어가는 시나리오)는 요청 자체가 봉투를 초과해 구조적으로 불가능하다. 구현된 subtest는 도달 가능한 절반을 증명한다 — oversized 요청이 dispatch 전 `request_too_large`로 실패 닫기됨, production `EncodedSuccessBytes(projected)`가 65,536 초과임, mutation 0임. "요청 ≤65,536 AND 예상 응답 >65,536" 단정은 존재하지 않으며 통과할 수 없는 단정으로 문서화하지 않는다.

### Local-path target limitation

변경 대상은 clean 절대 UTF-8 로컬 경로(1..4,096 bytes, `/` 시작, NUL·비정규·상대 경로 거절)만 지원한다. 경로는 존재하고 접근 가능해야 하며, identity는 locator에서 유도된 transitional 대상(`locator_derived` 분류)이다. rename/move 연속성은 보장되지 않는다 — 경로가 옮겨지면 같은 파일이라도 새 대상으로 취급된다.

### Verification

```bash
mise run entry-core-check   # build + test + race + smoke(위 property_* subtests 포함) + catalog/migration/schema-parity/vet/gofmt/invariants
```

## Dependency and native event decisions

- The runtime foundation uses a pure-Go persistence stack: GORM (`gorm.io/gorm`) as the ORM, the `github.com/glebarez/sqlite` driver backed by `modernc.org/sqlite` (pure Go, so `CGO_ENABLED=0` builds work), and `github.com/golang-migrate/migrate/v4` for schema migrations. Atlas CLI (dev/CI only, pinned `mise` aqua `ariga/atlas` 1.3.0) plus the `ariga.io/atlas-provider-gorm` provider generate and validate migrations from GORM models. `go.sum` is committed and required; the module stays single (no `go.work` anywhere).
- VOY-663 does not adopt an FSEvents implementation. Direct CoreServices/CGO, a maintained Go package, and the existing Swift-native adapter remain separate follow-up options.
- A native event implementation must first prove event-ID replay, drop and overflow recovery, root changes, restart behavior, and signed macOS bundling. Until then, native event ingestion remains outside this module.

## Canonical Entry contract

Implemented and verified in-process:

- `protocol/schema` strictly decodes canonical Entry contract `entry.list` and `entry.resolve`, requires bounded `page_size` and `requested_properties`, keeps `page_token` opaque, derives `has_more` from token presence, maps canonical Entry DTOs, and enforces the shared 65,536-byte request/response ceiling.
- `internal/application/entry` selects at most eight active mount/source scopes in a server-selected workspace, fairly interleaves canonical entries, authenticates a composite continuation token, preserves per-source availability/freshness/revision summaries, and resolves by EntryRef plus mount or by VirtualPath.
- `internal/runtime` exposes only an injected/test canonical Entry contract list/resolve path. It snapshots lifecycle state before application I/O and maps typed application failures to stable redacted protocol errors. Default `New()` and DB-less composition remain limited to `ping`, `health`, and `version`; Entry methods are rejected at the method gate. With `--database`, the composed runtime additionally dispatches the 11 VOY-765 Property methods through the catalog/change services; Entry contract methods stay method-gate-rejected.
- `internal/source`의 fake-external 경로는 source-owned connection resolver가 `AccessSession`을 만든 뒤 fake client를 호출하는 결정적 테스트 경계입니다. CredentialRef는 opaque reference이며 credential/token/API-key/header 값은 Entry, wire, cursor, error, log에 들어가지 않습니다.
- `integration/entry_contract_test.go` proves one root list response containing localfs and fake-external entries, opaque composite continuation without duplicate/lost entries, representative local/external resolve, available success-empty, and cached-offline normalization to stale with a `source_offline` warning.
- Canonical wire contract `ping`, `health`, `version`, `EmptyParams`, exact bytes, CLI/daemon behavior, and real-process smoke ownership are canonical.

Not production-wired and still deferred:

- The production daemon, Unix-socket transport, CLI, and Swift client use canonical wire contract but expose no canonical Entry contract list/resolve route.
- Localfs and fakeexternal are deterministic fixture adapters for this boundary, not production provider connectors. Real providers, OAuth browser/callback/code exchange, token/API-key storage or refresh, secure-store integration, network behavior, retry/rate limiting, and provider configuration are deferred.
- The SQLite store, embedded migrations, workspace metadata persistence, and the VOY-765 durable Property catalog/assignment storage are implemented; durable Entry/revision storage, indexes, search/query projections, cache authority, restart-stable composite tokens, mutation/operation engines, and content streaming are deferred.
- Swift/macOS models and UI, Helper/XPC integration, native filesystem observation, and production Mirage execution are deferred.
- VOY-665 receives only the ownership/coexistence/rollback handoff defined by the canonical contract. Its migration and implementation remain owned by VOY-665 and are not implemented here.

## CLI and daemon

Both processes require an explicit absolute socket path. There is no default or production socket discovery. The daemon additionally accepts an optional database path.

```bash
entry-core-daemon --socket <absolute-path> [--database <absolute-path>]
entry-core --socket <absolute-path> <ping|health|version>
```

`--socket` is required and must be an absolute path. `--database` is optional; when present it must be a non-empty absolute path. The two flags may appear in either order, each at most once. With `--database` absent, the daemon runs byte-identically to the DB-less behavior (no store is opened and no database log line is emitted).

The daemon runs in the foreground and writes lifecycle metadata to stderr. On success, the CLI writes one compact result JSON line to stdout. Usage and local validation failures exit `2`; transport, server, and response validation failures exit `1`; success exits `0`. Each connection carries one canonical request and one canonical response.

When `--database` is present, the daemon opens the store, runs the embedded migrations, and bootstraps or restores the workspace identity before binding the socket. A fresh database file logs `workspace metadata initialized`; a pre-existing file logs `workspace metadata restored`. Any pre-listen failure (invalid path, corrupt database, migration failure) exits `1` with a single metadata-only stderr line and never creates the socket. The WorkspaceID value is never logged.

For a local manual run, place binaries outside the repository:

```bash
tmp_dir="$(mktemp -d)"
mkdir -m 0700 "$tmp_dir/db"
(cd apps/entry-core && mise exec -- go build -o "$tmp_dir/entry-core-daemon" ./cmd/entry-core-daemon)
(cd apps/entry-core && mise exec -- go build -o "$tmp_dir/entry-core" ./cmd/entry-core)
"$tmp_dir/entry-core-daemon" --socket "$tmp_dir/entry-core.sock" --database "$tmp_dir/db/entry-core.db"
```

In another terminal:

```bash
"$tmp_dir/entry-core" --socket "$tmp_dir/entry-core.sock" ping
```

## Shutdown and cleanup

Send `SIGINT` or `SIGTERM` to start graceful shutdown. The daemon stops accepting requests, allows active handlers a bounded grace period, force-closes remaining owned connections when needed, and performs a best-effort identity check before removing the socket it created. A second signal skips the remaining grace period. Pre-existing destinations are never removed during startup. During cleanup, replacement preservation is guaranteed only between cooperating Entry Core daemon instances that honor the same persistent lifecycle lock; it is not guaranteed against a non-cooperating process running as the same effective UID.

The daemon serializes the socket lifecycle with a persistent `<socket>.lock` file. It acquires an exclusive advisory lock before inspecting or binding the socket and releases it only after startup rollback or shutdown cleanup finishes. The lock file must be a non-symlink regular file owned by the effective user, have exact mode `0600`, and have exactly one link. It remains after a clean shutdown so later daemon starts can reuse the same inode safely. Entry Core fails closed without changing the socket or lock when the lock is active or its metadata is unsafe. The lock is advisory: it coordinates Entry Core instances that acquire the same lock, but it cannot prevent a process with the same effective UID from changing the socket or lock pathname. The `0700` parent excludes other users, not processes sharing that effective UID.

## Database and migrations

### Path contract

The `--database` path must be absolute. Its parent must be a non-symlink directory owned by the effective user with exact mode `0700`; the parent must already exist (Entry Core fails closed rather than auto-creating it). If the database file already exists, it must be a non-symlink regular file owned by the effective user. Pre-existing files are never deleted or replaced; SQLite creates the file only after path validation passes. This mirrors the socket parent contract: the `0700` parent excludes other users.

### Connection policy

The store opens the database with a canonical, verified-by-read-back connection policy:

- `foreign_keys=ON`
- `journal_mode=WAL`
- `busy_timeout=5000`
- `synchronous=NORMAL`
- Single-connection pool (`SetMaxOpenConns(1)`, `SetMaxIdleConns(1)`, no idle-connection timeout), serializing all access through one writer connection.

The pragmas are read back and verified at open; any mismatch fails closed with `connection policy not met` before the daemon proceeds. `synchronous=NORMAL` under WAL risks a torn last transaction on power loss but never corruption; `FULL` is a one-line DSN change if durability requirements tighten.

### Migration directory

Migrations live in `internal/persistence/sqlite/migrations` in golang-migrate format and are embedded into the daemon via `//go:embed`. The directory is append-only and currently contains exactly `0001_workspace_metadata.{up,down}.sql` through `0007_entry_properties.{up,down}.sql` (VOY-765 property catalog/term/assignment tables) plus `atlas.sum`. The `.down.sql` files exist for ADR-014 artifact-format compliance; they are never executed at runtime. The `atlas.sum` is verified before any migration SQL runs, so a tampered directory fails closed without creating the ledger table.

The 16-byte `workspace_id` CHECK is emitted directly by the GORM model's `check:` tags during Atlas generation; no hand-finishing is required. The schema ledger is golang-migrate's `schema_migrations` table.

### Append-only migration workflow

The desired schema is produced from GORM models by the Atlas GORM Provider loader in `internal/persistence/sqlite/tools/atlas-schema` (dev/CI only, never imported by daemon code), driven by `atlas.hcl`. Run these from `apps/entry-core` using the pinned `mise` tool:

```bash
# 1. Extend the GORM model (model.go), then generate the next migration.
mise exec -- atlas migrate diff <name> --env gorm

# 2. Hand-review the generated SQL (add any physical invariants Atlas omits).

# 3. Normalize the golang-migrate filename to the canonical form and regenerate
#    the checksum. With --dir-format golang-migrate, Atlas emits timestamped
#    names (e.g. 20260817082128_initial_workspace.up.sql); the committed
#    directory uses canonical 0001_..., 0002_... names. Rename, then:
mise exec -- atlas migrate hash --env gorm

# 4. Validate the directory (dir hash + format) via the canonical task.
mise run entry-core-migration-validate
```

`entry-core-migration-validate` runs `atlas migrate validate --dir-format golang-migrate --dir file://internal/persistence/sqlite/migrations` and fails if a file is missing, unlisted, or its checksum is stale. Committed migrations are append-only: never edit or delete an applied migration, never re-run a `.down.sql` at runtime. Extend the MapFS fixture pattern in `migrate_test.go` with populated prior-schema upgrade tests when adding a new migration.

### Driver caveat

The module uses a custom golang-migrate `database.Driver` (`sharedSQLiteDriver`) over the store's shared `*sql.DB`. It deliberately does **not** import `github.com/golang-migrate/migrate/v4/database/sqlite`: that package blank-imports `modernc.org/sqlite`, which registers the `sqlite` driver and collides with `github.com/glebarez/sqlite`'s registration, panicking with `sql: Register called twice for driver sqlite`. The shared driver also treats `Close` as a no-op because the Store owns the connection lifecycle.

### SQLite/GORM implementation gotchas

- modernc SQLite 빌드는 `DELETE ... LIMIT 1`을 지원하지 않는다. 제한 삭제가 필요하면 먼저 대상 키를 조회한 뒤 일반 `DELETE ... WHERE key = ?`를 사용한다.
- `workspace_property_terms`에는 `lifecycle_state`가 없다. 다른 catalog family의 lifecycle 조건을 이 테이블에 복사하지 말고 seed 소유권과 실제 스키마를 기준으로 조회한다.
- 같은 database path에 두 번째 `sqlite.Store`를 열면 lifetime flock 때문에 `ErrDatabaseLocked`가 발생한다. 테스트도 동시에 두 store를 열 수 있다고 가정하지 않는다.
- catalog seed digest와 lifecycle state는 seed-owned row에만 적용한다. 사용자 또는 preset 소유 row를 seed drift 계산에 포함하지 않는다.
- 한 GORM field에 `check:` tag를 여러 번 쓰면 앞 tag가 덮어써진다. 여러 조건은 하나의 `check:(condition_a AND condition_b)` 식으로 합친다.
- GORM의 `check:name:expr` 형식은 이 loader에서 name을 expression에 섞는다. 이름 없는 `check:(expr)`를 사용하고 Atlas가 생성한 constraint name을 migration SQL과 맞춘다.
- composite `uniqueIndex`는 참여하는 모든 field에 같은 index name을 붙여야 한다. 한 field에만 tag를 두면 composite index가 생성되지 않는다.
- SQLite `pragma foreign_key_list` 결과는 선언 순서의 역순으로 반환될 수 있다. FK 구조 테스트의 expected order는 pragma의 실제 반환 계약을 따른다.
- `.down.sql`을 직접 실행해도 golang-migrate의 `schema_migrations` ledger version은 자동으로 내려가지 않는다. down-then-up 테스트는 재적용 전에 ledger를 해당 이전 version으로 맞춘다.

## VOY-765 handoff

> VOY-765는 이어받은 표면 위에 쓰기 가능한 Property backend를 이미 구현했다(위 "Property API (VOY-765)" 섹션). 아래는 VOY-663가 남긴 원본 인계 기록이다.

This slice creates no property tables and no repository methods. It hands the writable Property backend (VOY-765) a frozen mutation surface:

- `sqlite.Store` with `Open` / `MigrateUp` (via the daemon seam) / `Close`, workspace-ready after open + migrate.
- `Store.WithinTx(ctx, func(tx *gorm.DB) error) error` is the **only** mutation boundary VOY-765 repositories are allowed to use. Repositories receive the tx-scoped `*gorm.DB` and own their table mapping. Nested `WithinTx` calls run as GORM SAVEPOINTs.
- `domainentry.WorkspaceID` / `domainentry.WorkspaceContext` are the identity surface; VOY-765 copies the typed-ID pattern for `PropertyID` / `PropertyOptionID`.
- Migration append rule: extend `model.go`, run `atlas migrate diff <name> --env gorm` (external-schema program mode via `atlas.hcl` + the loader), hand-review the SQL, `atlas migrate hash --env gorm`, and commit `0002+` append-only.

Inherited rules for VOY-765: no `AutoMigrate` anywhere, no writes outside `WithinTx`, `workspace_id` in every durable key, metadata-only logs and errors.

## Troubleshooting

- `usage: entry-core...` or `usage: entry-core-daemon...`: pass `--socket` followed by a non-empty absolute path, and optionally `--database` with a non-empty absolute path.
- Startup fails before socket creation: confirm the direct parent is owned by the effective user, is not a symlink, and has exact mode `0700`.
- Destination already exists: remove it only after independently confirming it is safe. Entry Core fails closed and never deletes a pre-existing path.
- CLI reports a transport failure: confirm the foreground daemon is running on the same socket and that the total request can complete within the bounded deadline.
- `entry-core-check` reports formatting files: run `find apps/entry-core -type f -name '*.go' -print0 | xargs -0 mise exec -- gofmt -w` from the repository root, then rerun the check.
- Daemon exits `1` with `startup failed: migration failed: dirty ledger at version N`: a previous migration was interrupted or failed, leaving the `schema_migrations` ledger dirty. The store never self-heals (no auto-down, no ledger reset) by design. To recover, inspect the failed migration, fix it forward with a new `0002+` migration, or manually repair the ledger only after independently confirming the database state is safe.
- Daemon exits `1` with `startup failed: workspace identity corrupt` or `database open failed`: the persisted workspace blob is not a valid UUIDv7, or the file is not a usable SQLite database. Fail-closed by design: the store never auto-repairs and never derives identity from path, environment, or account. Restore from a known-good backup or re-initialize after confirming the database is safe to discard.

Production socket discovery/defaults, launchd, reconnect, Entry operation production wiring, real providers/auth, mutation/operation execution, search/query projections, cache authority, Swift/macOS UI, Helper/XPC, Mirage production execution, and VOY-665 migration are deferred.
