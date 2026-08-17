package sqlite

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"io/fs"
	"strings"
	"testing"
	"testing/fstest"
)

func TestMigrateCleanReplay(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)
	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp: %v", err)
	}

	// schema_migrations is the single version/dirty ledger (golang-migrate
	// default); a clean replay reaches version 1 and is not dirty.
	var version int
	var dirty bool
	if err := store.SQLDB().QueryRowContext(ctx,
		"SELECT version, dirty FROM schema_migrations").Scan(&version, &dirty); err != nil {
		t.Fatalf("query schema_migrations: %v", err)
	}
	if version != 1 || dirty {
		t.Fatalf("schema_migrations: got version=%d dirty=%v, want version=1 dirty=false", version, dirty)
	}

	// The singleton CHECK (singleton = 1) is satisfied by the row insert, so a
	// 15-byte blob must be rejected by CHECK(length(workspace_id) = 16) — the
	// physical UUIDv7 invariant Atlas could not emit on its own.
	_, err = store.SQLDB().ExecContext(ctx,
		`INSERT INTO workspace_metadata (singleton, workspace_id, created_at, updated_at)
		 VALUES (1, ?, datetime('now'), datetime('now'))`,
		[]byte("0123456789abcde"), // 15 bytes
	)
	if err == nil {
		t.Fatal("inserting a 15-byte workspace_id blob succeeded; CHECK(length(workspace_id)=16) not enforced")
	}
	if !strings.Contains(strings.ToLower(err.Error()), "check") {
		t.Fatalf("bad-length insert failed with %q, want a CHECK constraint violation", err)
	}
}

// fixtureMigration describes a single migration file pair (up + down) used to
// build an in-test MapFS migration directory with a correctly computed
// atlas.sum.
type fixtureMigration struct {
	base string // e.g. "0001_workspace_metadata"
	up   string
	down string
}

// embeddedMigration returns the committed up/down SQL for a migration base name
// (e.g. "0001_workspace_metadata") read from the embedded directory.
func embeddedMigration(t *testing.T, base string) (up, down string) {
	t.Helper()
	upB, err := fs.ReadFile(migrationsFS, "migrations/"+base+".up.sql")
	if err != nil {
		t.Fatalf("read embedded %s up: %v", base, err)
	}
	downB, err := fs.ReadFile(migrationsFS, "migrations/"+base+".down.sql")
	if err != nil {
		t.Fatalf("read embedded %s down: %v", base, err)
	}
	return string(upB), string(downB)
}

// buildFixtureFS builds a MapFS migration directory (rooted under "migrations/")
// containing the given up/down pairs plus an atlas.sum computed over exactly
// those up files. Test-only 0002 lives only here, never in the embedded
// (append-only) directory. The computed atlas.sum keeps the pre-apply checksum
// gate green so the test exercises the migration runner itself.
func buildFixtureFS(t *testing.T, migrations ...fixtureMigration) fstest.MapFS {
	t.Helper()
	m := fstest.MapFS{}
	var entries []sumEntry
	for _, mig := range migrations {
		upName := mig.base + ".up.sql"
		downName := mig.base + ".down.sql"
		m["migrations/"+upName] = &fstest.MapFile{Data: []byte(mig.up)}
		m["migrations/"+downName] = &fstest.MapFile{Data: []byte(mig.down)}
		entries = append(entries, sumEntry{name: upName, hash: fileHash(upName, []byte(mig.up))})
	}
	var sb strings.Builder
	sb.WriteString("h1:" + sumHash(entries) + "\n")
	for _, e := range entries {
		sb.WriteString(e.name + " h1:" + e.hash + "\n")
	}
	m["migrations/atlas.sum"] = &fstest.MapFile{Data: []byte(sb.String())}
	return m
}

// assertLedger asserts schema_migrations holds exactly (version, dirty).
func assertLedger(t *testing.T, db *sql.DB, wantVersion int, wantDirty bool) {
	t.Helper()
	var version int
	var dirty bool
	if err := db.QueryRow("SELECT version, dirty FROM schema_migrations").Scan(&version, &dirty); err != nil {
		t.Fatalf("query schema_migrations: %v", err)
	}
	if version != wantVersion || dirty != wantDirty {
		t.Fatalf("schema_migrations: got version=%d dirty=%v, want version=%d dirty=%v",
			version, dirty, wantVersion, wantDirty)
	}
}

// assertTableAbsent asserts no table with the given name exists in the schema.
func assertTableAbsent(t *testing.T, db *sql.DB, name string) {
	t.Helper()
	var n int
	if err := db.QueryRow(
		"SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?", name).Scan(&n); err != nil {
		t.Fatalf("query sqlite_master for %q: %v", name, err)
	}
	if n != 0 {
		t.Fatalf("table %q exists (count=%d), want absent", name, n)
	}
}

func TestMigrateDirtyLedgerFailsClosed(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)

	// Fixture: valid 0001 plus a test-only 0002 with invalid SQL. The atlas.sum
	// is computed over both, so the pre-apply checksum gate passes and the
	// runner reaches 0002's invalid SQL, which fails mid-run.
	up1, down1 := embeddedMigration(t, "0001_workspace_metadata")
	fixture := buildFixtureFS(t,
		fixtureMigration{base: "0001_workspace_metadata", up: up1, down: down1},
		fixtureMigration{base: "0002_invalid", up: "CREATE TABLE bad (;", down: "DROP TABLE bad;"},
	)

	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}

	// First up: 0001 applies cleanly, 0002 fails mid-run. The ledger is left
	// dirty at the failure version (2) and MigrateUpFS wraps this as
	// ErrMigrationFailed.
	if err := MigrateUpFS(ctx, store.SQLDB(), fixture); err == nil {
		_ = store.Close()
		t.Fatal("MigrateUpFS with invalid 0002 succeeded, want ErrMigrationFailed")
	} else if !errors.Is(err, ErrMigrationFailed) {
		_ = store.Close()
		t.Fatalf("first error = %v, want wrapped ErrMigrationFailed", err)
	}
	assertLedger(t, store.SQLDB(), 2, true)

	// A subsequent MigrateUpFS on the dirty DB must fail closed: golang-migrate
	// returns ErrDirty (which MigrateUpFS maps to ErrMigrationFailed). It must
	// not auto-recover, not run .down.sql, and not reset the ledger.
	if err := MigrateUpFS(ctx, store.SQLDB(), fixture); err == nil {
		_ = store.Close()
		t.Fatal("second MigrateUpFS on dirty DB succeeded, want ErrMigrationFailed")
	} else if !errors.Is(err, ErrMigrationFailed) {
		_ = store.Close()
		t.Fatalf("second error = %v, want wrapped ErrMigrationFailed", err)
	}
	assertLedger(t, store.SQLDB(), 2, true)
	_ = store.Close()

	// Re-open the store on the same path: the dirty ledger must persist across
	// a fresh Store.Open. Opening must never clear it.
	store2, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("re-open: %v", err)
	}
	defer store2.Close()
	assertLedger(t, store2.SQLDB(), 2, true)
}

func TestMigratePopulatedUpgrade(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)

	up1, down1 := embeddedMigration(t, "0001_workspace_metadata")
	twoStep := buildFixtureFS(t,
		fixtureMigration{base: "0001_workspace_metadata", up: up1, down: down1},
		fixtureMigration{
			base: "0002_benign",
			up:   "CREATE TABLE `app_meta` (`key` text PRIMARY KEY, `value` text NOT NULL);",
			down: "DROP TABLE `app_meta`;",
		},
	)

	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	// Create the DB at version 1 using the embedded directory (0001 only).
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp to version 1: %v", err)
	}

	// Insert a populated workspace_metadata singleton row (16-byte UUIDv7 blob
	// satisfies the length CHECK).
	row := []byte("0123456789abcdef")
	if _, err := store.SQLDB().ExecContext(ctx,
		`INSERT INTO workspace_metadata (singleton, workspace_id, created_at, updated_at)
		 VALUES (1, ?, datetime('now'), datetime('now'))`, row); err != nil {
		t.Fatalf("insert populated row: %v", err)
	}

	// Capture the stored row state before the upgrade (SQLite may normalize
	// datetime literals, so compare against the actually-stored value).
	before := readWorkspaceRow(t, ctx, store.SQLDB())

	// Run the full two-step upgrade: 0001 (already applied, no-op) then 0002.
	if err := MigrateUpFS(ctx, store.SQLDB(), twoStep); err != nil {
		t.Fatalf("MigrateUpFS to version 2: %v", err)
	}
	assertLedger(t, store.SQLDB(), 2, false)

	// The benign 0002 table is present.
	assertTablePresent(t, store.SQLDB(), "app_meta")

	// The populated workspace_metadata row survived byte-for-byte.
	after := readWorkspaceRow(t, ctx, store.SQLDB())
	if !bytes.Equal(after.workspaceID, before.workspaceID) {
		t.Fatalf("workspace_id = %x, want %x (row corrupted by upgrade)", after.workspaceID, before.workspaceID)
	}
	if after.createdAt != before.createdAt || after.updatedAt != before.updatedAt {
		t.Fatalf("timestamps changed across upgrade: before=(%q,%q) after=(%q,%q)",
			before.createdAt, before.updatedAt, after.createdAt, after.updatedAt)
	}
}

// workspaceRow is the raw storage state of the workspace_metadata singleton
// row, used to prove byte-for-byte survival across an upgrade.
type workspaceRow struct {
	workspaceID []byte
	createdAt   string
	updatedAt   string
}

// readWorkspaceRow reads the singleton workspace_metadata row's storage state.
func readWorkspaceRow(t *testing.T, ctx context.Context, db *sql.DB) workspaceRow {
	t.Helper()
	var w workspaceRow
	if err := db.QueryRowContext(ctx,
		"SELECT workspace_id, created_at, updated_at FROM workspace_metadata WHERE singleton=1").
		Scan(&w.workspaceID, &w.createdAt, &w.updatedAt); err != nil {
		t.Fatalf("read workspace_metadata row: %v", err)
	}
	return w
}

// assertTablePresent asserts a table with the given name exists in the schema.
func assertTablePresent(t *testing.T, db *sql.DB, name string) {
	t.Helper()
	var got string
	if err := db.QueryRow(
		"SELECT name FROM sqlite_master WHERE type='table' AND name=?", name).Scan(&got); err != nil {
		t.Fatalf("query sqlite_master for %q: %v", name, err)
	}
	if got != name {
		t.Fatalf("table name = %q, want %q", got, name)
	}
}

func TestMigrateRejectsChecksumMismatchBeforeApply(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)

	up1, down1 := embeddedMigration(t, "0001_workspace_metadata")
	fixture := buildFixtureFS(t,
		fixtureMigration{base: "0001_workspace_metadata", up: up1, down: down1},
	)
	// Tamper with 0001's up content after the atlas.sum was computed. The
	// pre-apply checksum gate must reject it before any migration SQL runs.
	tampered := append([]byte("-- tampered\n"), []byte(up1)...)
	fixture["migrations/0001_workspace_metadata.up.sql"] = &fstest.MapFile{Data: tampered}

	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	if err := MigrateUpFS(ctx, store.SQLDB(), fixture); err == nil {
		t.Fatal("MigrateUpFS with tampered checksum succeeded, want ErrMigrationChecksum")
	} else if !errors.Is(err, ErrMigrationChecksum) {
		t.Fatalf("error = %v, want wrapped ErrMigrationChecksum", err)
	}

	// The checksum gate ran before any SQL: neither the ledger nor the table
	// may exist.
	assertTableAbsent(t, store.SQLDB(), "schema_migrations")
	assertTableAbsent(t, store.SQLDB(), "workspace_metadata")
}
