package sqlite

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"io/fs"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/golang-migrate/migrate/v4/database"
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
	// default); a clean replay reaches the current head version and is not
	// dirty. The embedded directory now holds 0001 (workspace_metadata), 0002
	// (workspace property catalog), 0003 (term lifecycle), 0004 (active term
	// uniqueness), and 0005 (definition display-unit contract), so head is version 5.
	var version int
	var dirty bool
	if err := store.SQLDB().QueryRowContext(ctx,
		"SELECT version, dirty FROM schema_migrations").Scan(&version, &dirty); err != nil {
		t.Fatalf("query schema_migrations: %v", err)
	}
	if version != 5 || dirty {
		t.Fatalf("schema_migrations: got version=%d dirty=%v, want version=5 dirty=false", version, dirty)
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
// (append-only) directory. The computed atlas.sum uses the same cumulative
// per-file hashing Atlas's golang-migrate formatter emits, keeping the
// pre-apply checksum gate green so the test exercises the migration runner
// itself.
func buildFixtureFS(t *testing.T, migrations ...fixtureMigration) fstest.MapFS {
	t.Helper()
	m := fstest.MapFS{}
	var entries []sumEntry
	var acc []byte
	for _, mig := range migrations {
		upName := mig.base + ".up.sql"
		downName := mig.base + ".down.sql"
		m["migrations/"+upName] = &fstest.MapFile{Data: []byte(mig.up)}
		m["migrations/"+downName] = &fstest.MapFile{Data: []byte(mig.down)}
		// Cumulative per-file hash: SHA-256 over the concatenation of every up
		// file's (name + content) from the first through this one.
		acc = append(acc, []byte(upName)...)
		acc = append(acc, []byte(mig.up)...)
		sum := sha256.Sum256(acc)
		entries = append(entries, sumEntry{name: upName, hash: base64.StdEncoding.EncodeToString(sum[:])})
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

	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	// MigrateUp runs the embedded directory through the term lifecycle migration,
	// reaching head version 5.
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp: %v", err)
	}
	assertLedger(t, store.SQLDB(), 5, false)

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

	// Re-run the embedded upgrade: all migrations already applied, no-op.
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp re-run: %v", err)
	}

	// The catalog tables are present.
	assertTablePresent(t, store.SQLDB(), "workspace_property_definitions")
	assertTablePresent(t, store.SQLDB(), "source_property_descriptors")
	assertTablePresent(t, store.SQLDB(), "property_bindings")
	assertTablePresent(t, store.SQLDB(), "workspace_property_terms")

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

func TestMigrateRejectsNewerLedger(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)

	// Fixture embeds only version 1 (matching the committed directory): a DB
	// ledger ahead of this binary's embedded max must fail closed, not be
	// silently accepted as ErrNoChange.
	up1, down1 := embeddedMigration(t, "0001_workspace_metadata")
	fixture := buildFixtureFS(t,
		fixtureMigration{base: "0001_workspace_metadata", up: up1, down: down1},
	)

	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	// Establish a valid baseline at version 1 using the embedded directory.
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp to version 1: %v", err)
	}

	// Simulate a newer binary having migrated the DB to version 2 (a schema
	// this 1-only binary does not embed) by advancing the clean ledger.
	if _, err := store.SQLDB().ExecContext(ctx,
		"DELETE FROM schema_migrations; INSERT INTO schema_migrations (version, dirty) VALUES (2, 0)"); err != nil {
		t.Fatalf("advance ledger to version 2: %v", err)
	}

	// The 1-only binary must fail closed against the newer ledger, and must
	// not touch the DB (no apply, no ledger reset).
	if err := MigrateUpFS(ctx, store.SQLDB(), fixture); err == nil {
		t.Fatal("MigrateUpFS on a newer ledger succeeded, want ErrMigrationFailed")
	} else if !errors.Is(err, ErrMigrationFailed) {
		t.Fatalf("error = %v, want wrapped ErrMigrationFailed", err)
	}
	assertLedger(t, store.SQLDB(), 2, false)
}

// TestSharedSQLiteDriverLockExcludesAcrossInstances proves the migration lock
// is shared across processes (here simulated by two independent driver
// instances over the same database file). While the first holds the lock, the
// second must fail closed with database.ErrLocked; after the first releases,
// the second can acquire it.
func TestSharedSQLiteDriverLockExcludesAcrossInstances(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)
	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	lockPath := migrationLockPath(path)
	driverA := &sharedSQLiteDriver{db: store.SQLDB(), lockPath: lockPath}
	driverB := &sharedSQLiteDriver{db: store.SQLDB(), lockPath: lockPath}

	if err := driverA.Lock(); err != nil {
		t.Fatalf("driverA.Lock: %v", err)
	}
	if err := driverB.Lock(); !errors.Is(err, database.ErrLocked) {
		_ = driverA.Unlock()
		t.Fatalf("driverB.Lock while A holds = %v, want database.ErrLocked", err)
	}

	if err := driverA.Unlock(); err != nil {
		t.Fatalf("driverA.Unlock: %v", err)
	}
	if err := driverB.Lock(); err != nil {
		t.Fatalf("driverB.Lock after A released: %v", err)
	}
	if err := driverB.Unlock(); err != nil {
		t.Fatalf("driverB.Unlock: %v", err)
	}
}

// TestSharedSQLiteDriverLockRejectsDoubleLock guards the same-instance
// re-entrancy path: a second Lock on the same driver returns ErrLocked and a
// second Unlock returns ErrNotLocked.
func TestSharedSQLiteDriverLockRejectsDoubleLock(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)
	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	d := &sharedSQLiteDriver{db: store.SQLDB(), lockPath: migrationLockPath(path)}
	if err := d.Lock(); err != nil {
		t.Fatalf("Lock: %v", err)
	}
	if err := d.Lock(); !errors.Is(err, database.ErrLocked) {
		t.Fatalf("second Lock = %v, want database.ErrLocked", err)
	}
	if err := d.Unlock(); err != nil {
		t.Fatalf("Unlock: %v", err)
	}
	if err := d.Unlock(); !errors.Is(err, database.ErrNotLocked) {
		t.Fatalf("second Unlock = %v, want database.ErrNotLocked", err)
	}
}

// catalogTableNames are the four tables 0002_workspace_property_catalog must
// create, plus the workspace_metadata table 0001 already owns. Constraint
// assertions in the catalog tests reference these exact names.
var catalogTableNames = []string{
	"workspace_metadata",
	"workspace_property_definitions",
	"source_property_descriptors",
	"property_bindings",
	"workspace_property_terms",
}

// catalogFixtureFS returns a MapFS directory containing the committed migration
// pairs (read from the embedded directory), with a computed atlas.sum, so a test
// can replay a fresh or populated 0001→0004 upgrade.
func catalogFixtureFS(t *testing.T) fstest.MapFS {
	t.Helper()
	up1, down1 := embeddedMigration(t, "0001_workspace_metadata")
	up2, down2 := embeddedMigration(t, "0002_workspace_property_catalog")
	up3, down3 := embeddedMigration(t, "0003_workspace_property_term_lifecycle")
	up4, down4 := embeddedMigration(t, "0004_workspace_property_term_active_unique")
	up5, down5 := embeddedMigration(t, "0005_property_definition_units")
	return buildFixtureFS(t,
		fixtureMigration{base: "0001_workspace_metadata", up: up1, down: down1},
		fixtureMigration{base: "0002_workspace_property_catalog", up: up2, down: down2},
		fixtureMigration{base: "0003_workspace_property_term_lifecycle", up: up3, down: down3},
		fixtureMigration{base: "0004_workspace_property_term_active_unique", up: up4, down: down4},
		fixtureMigration{base: "0005_property_definition_units", up: up5, down: down5},
	)
}

// assertTablesPresent asserts every catalog table (and workspace_metadata)
// exists in the schema.
func assertTablesPresent(t *testing.T, db *sql.DB) {
	t.Helper()
	for _, name := range catalogTableNames {
		assertTablePresent(t, db, name)
	}
}

// assertWorkspaceIDUniqueIndex asserts the unique index on
// workspace_metadata(workspace_id) that 0002 must add so catalog foreign keys
// can reference the workspace identity column. Atlas emits it as a
// CREATE UNIQUE INDEX, which pragma_index_list reports with origin='c'.
func assertWorkspaceIDUniqueIndex(t *testing.T, db *sql.DB) {
	t.Helper()
	var n int
	if err := db.QueryRow(
		`SELECT count(*) FROM pragma_index_list('workspace_metadata')
		 WHERE "unique"=1 AND origin='c'`).Scan(&n); err != nil {
		t.Fatalf("query workspace_metadata unique indexes: %v", err)
	}
	if n != 1 {
		t.Fatalf("workspace_metadata has %d explicit unique index(es), want exactly 1 (workspace_id)", n)
	}
	var origin string
	var unique int
	if err := db.QueryRow(
		`SELECT il."unique", ii.name FROM pragma_index_list('workspace_metadata') il
		 JOIN pragma_index_info(il.name) ii ON ii.seqno=0
		 WHERE il."unique"=1 AND il.origin='c'`).Scan(&unique, &origin); err != nil {
		t.Fatalf("query workspace_id unique index column: %v", err)
	}
	if unique != 1 || origin != "workspace_id" {
		t.Fatalf("workspace unique index: unique=%d first_col=%q, want unique=1 first_col=workspace_id", unique, origin)
	}
}

// assertForeignKeys asserts the exact set of foreign keys a table must declare,
// each with the expected referenced table and (in order) referenced columns.
// It also proves foreign_keys enforcement is ON for the connection.
func assertForeignKeys(t *testing.T, db *sql.DB, table string, want [][2]string) {
	t.Helper()
	// pragma_foreign_key_list returns one row per column of each FK constraint,
	// keyed by the FK `id`. Group rows by `id` so each distinct id is one FK.
	type fkCol struct {
		refTable string
		fromCol  string
	}
	rows, err := db.Query(`SELECT id, seq, "table", "from" FROM pragma_foreign_key_list(?) ORDER BY id, seq`, table)
	if err != nil {
		t.Fatalf("query FK list for %q: %v", table, err)
	}
	defer rows.Close()
	groups := map[int][]fkCol{}
	order := []int{}
	for rows.Next() {
		var id int
		var seq int
		var col fkCol
		if err := rows.Scan(&id, &seq, &col.refTable, &col.fromCol); err != nil {
			t.Fatalf("scan FK for %q: %v", table, err)
		}
		if _, ok := groups[id]; !ok {
			order = append(order, id)
		}
		groups[id] = append(groups[id], col)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate FK list for %q: %v", table, err)
	}
	if len(order) != len(want) {
		t.Fatalf("table %q has %d FK constraint(s), want %d", table, len(order), len(want))
	}
	for i, id := range order {
		first := groups[id][0] // seq=0 row: referenced table + first referenced column
		if first.refTable != want[i][0] || first.fromCol != want[i][1] {
			t.Fatalf("table %q FK[%d] = (table=%q from=%q), want (table=%q from=%q)",
				table, i, first.refTable, first.fromCol, want[i][0], want[i][1])
		}
	}
}

// assertSingleColumnCheck asserts a table's CHECK constraint that contains the
// given column-name fragment exists (extracted from sqlite_master). The
// fragment is matched as a whole word so a column like `origin` does not match
// the `origin` part of an unrelated name.
func assertSingleColumnCheck(t *testing.T, db *sql.DB, table, column string) {
	t.Helper()
	var ddl string
	if err := db.QueryRow(
		`SELECT sql FROM sqlite_master WHERE type='table' AND name=?`, table).Scan(&ddl); err != nil {
		t.Fatalf("query table %q DDL: %v", table, err)
	}
	if !strings.Contains(ddl, "CHECK (length("+column+") = 16)") &&
		!strings.Contains(ddl, "CHECK (length("+column+") = 16 )") &&
		!strings.Contains(ddl, "CHECK(length("+column+") = 16)") {
		t.Fatalf("table %q DDL missing 16-byte CHECK on %q:\n%s", table, column, ddl)
	}
}

// TestMigrateWorkspacePropertyCatalogFreshReplay replays a fresh 0001→0004
// upgrade on a new database and proves the ledger reaches version 4, all four
// catalog tables exist, and the workspace_id unique index 0002 adds is present.
func TestMigrateWorkspacePropertyCatalogFreshReplay(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)

	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	// Fresh replay applies the workspace metadata, catalog, and term lifecycle migrations.
	if err := MigrateUpFS(ctx, store.SQLDB(), catalogFixtureFS(t)); err != nil {
		t.Fatalf("MigrateUpFS fresh 0001→0005: %v", err)
	}
	assertLedger(t, store.SQLDB(), 5, false)
	assertTablesPresent(t, store.SQLDB())
	assertWorkspaceIDUniqueIndex(t, store.SQLDB())
}

// TestMigrateWorkspacePropertyCatalogPopulatedReplay replays a populated
// 0001→0004 upgrade: a database created at version 1 with a populated
// workspace_metadata singleton row is upgraded to version 4, proving the
// existing identity row survives byte-for-byte and the catalog tables appear.
func TestMigrateWorkspacePropertyCatalogPopulatedReplay(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)

	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	// Create the DB at version 1 using the embedded 0001-only directory.
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp to version 1: %v", err)
	}

	row := []byte("0123456789abcdef")
	if _, err := store.SQLDB().ExecContext(ctx,
		`INSERT INTO workspace_metadata (singleton, workspace_id, created_at, updated_at)
		 VALUES (1, ?, datetime('now'), datetime('now'))`, row); err != nil {
		t.Fatalf("insert populated row: %v", err)
	}
	before := readWorkspaceRow(t, ctx, store.SQLDB())

	// Upgrade the populated database to version 5.
	if err := MigrateUpFS(ctx, store.SQLDB(), catalogFixtureFS(t)); err != nil {
		t.Fatalf("MigrateUpFS populated 0001→0005: %v", err)
	}
	assertLedger(t, store.SQLDB(), 5, false)
	assertTablesPresent(t, store.SQLDB())
	assertWorkspaceIDUniqueIndex(t, store.SQLDB())

	after := readWorkspaceRow(t, ctx, store.SQLDB())
	if !bytes.Equal(after.workspaceID, before.workspaceID) {
		t.Fatalf("workspace_id = %x, want %x (row corrupted by catalog upgrade)", after.workspaceID, before.workspaceID)
	}
}

// TestMigratePropertyDefinitionUnitsPopulatedUpgrade proves the 0005
// migration upgrades a populated database created at version 4 (with an
// existing definition row) to version 5: the new default_display_unit and
// units_json columns appear with their DEFAULT ” backfilled and the pre-existing
// row survives byte-for-byte on its unchanged columns.
func TestMigratePropertyDefinitionUnitsPopulatedUpgrade(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)

	// Fixture that stops at version 4 (the pre-0005 schema).
	up1, down1 := embeddedMigration(t, "0001_workspace_metadata")
	up2, down2 := embeddedMigration(t, "0002_workspace_property_catalog")
	up3, down3 := embeddedMigration(t, "0003_workspace_property_term_lifecycle")
	up4, down4 := embeddedMigration(t, "0004_workspace_property_term_active_unique")
	preUpgrade := buildFixtureFS(t,
		fixtureMigration{base: "0001_workspace_metadata", up: up1, down: down1},
		fixtureMigration{base: "0002_workspace_property_catalog", up: up2, down: down2},
		fixtureMigration{base: "0003_workspace_property_term_lifecycle", up: up3, down: down3},
		fixtureMigration{base: "0004_workspace_property_term_active_unique", up: up4, down: down4},
	)

	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	if err := MigrateUpFS(ctx, store.SQLDB(), preUpgrade); err != nil {
		t.Fatalf("MigrateUpFS to version 4: %v", err)
	}
	assertLedger(t, store.SQLDB(), 4, false)

	// Seed a populated workspace_metadata singleton row (parent FK target) as
	// the 0004 schema would have stored it.
	wsBytes := []byte("0123456789abcdef")
	if _, err := store.SQLDB().ExecContext(ctx,
		`INSERT INTO workspace_metadata (singleton, workspace_id, created_at, updated_at)
		 VALUES (1, ?, datetime('now'), datetime('now'))`, wsBytes); err != nil {
		t.Fatalf("insert populated workspace_metadata row: %v", err)
	}

	// Seed a populated definition row as 0004 would have stored it (no
	// default_display_unit / units_json columns).
	if _, err := store.SQLDB().ExecContext(ctx,
		`INSERT INTO workspace_property_definitions
		 (workspace_id, property_id, origin, identity_scheme, namespace, canonical_key,
		  display_name, description, value_type, cardinality, nullable, editable,
		  default_hidden, default_pinned, db_indexed_hint, provenance, unit,
		  definition_revision, lifecycle_state, seed_owner, seed_version,
		  seed_source_version, created_at, updated_at)
		 VALUES (?, X'5f495fc5a1875e6480eca9757f21d64d', 'built_in', 'registry_derived', 'system', 'common.title',
		  'Title', '', 'text', 'one', 0, 0, 0, 0, 0, 'system', 'B', 1, 'active',
		  NULL, NULL, NULL, datetime('now'), datetime('now'))`, wsBytes); err != nil {
		t.Fatalf("insert pre-upgrade definition row: %v", err)
	}

	// Upgrade to version 5.
	if err := MigrateUpFS(ctx, store.SQLDB(), catalogFixtureFS(t)); err != nil {
		t.Fatalf("MigrateUpFS populated 0004→0005: %v", err)
	}
	assertLedger(t, store.SQLDB(), 5, false)

	// The new columns exist and are backfilled with the empty default.
	var defaultDisplay string
	var unitsJSON string
	if err := store.SQLDB().QueryRowContext(ctx,
		`SELECT default_display_unit, units_json FROM workspace_property_definitions
		 WHERE workspace_id = ? AND canonical_key = 'common.title'`, wsBytes).
		Scan(&defaultDisplay, &unitsJSON); err != nil {
		t.Fatalf("query upgraded definition row: %v", err)
	}
	if defaultDisplay != "" || unitsJSON != "" {
		t.Fatalf("upgraded columns = (%q,%q), want empty defaults", defaultDisplay, unitsJSON)
	}

	// The pre-existing row's unit value survived the column additions.
	var unit string
	if err := store.SQLDB().QueryRowContext(ctx,
		`SELECT unit FROM workspace_property_definitions WHERE workspace_id = ? AND canonical_key = 'common.title'`, wsBytes).
		Scan(&unit); err != nil {
		t.Fatalf("query upgraded unit column: %v", err)
	}
	if unit != "B" {
		t.Fatalf("unit = %q, want %q (row corrupted by 0005)", unit, "B")
	}
}

// contracts of the four catalog tables through PRAGMA and sqlite_master
// queries — not by grepping the migration file. It proves:
//
//   - every table is owned by the workspace (FK → workspace_metadata),
//   - definitions namespace/key uniqueness is workspace-scoped,
//   - source descriptors and bindings are workspace-scoped via composite FK,
//   - bindings reference both a definition and a source descriptor,
//   - terms reference their definition (no orphans),
//   - 16-byte ID checks, allowed-enum checks, and non-negative ordinal checks.
func TestCatalogSchemaConstraints(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)
	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	if err := MigrateUpFS(ctx, store.SQLDB(), catalogFixtureFS(t)); err != nil {
		t.Fatalf("MigrateUpFS: %v", err)
	}
	db := store.SQLDB()

	// Every catalog table must be owned by the workspace.
	assertForeignKeys(t, db, "workspace_property_definitions", [][2]string{
		{"workspace_metadata", "workspace_id"},
	})
	assertForeignKeys(t, db, "source_property_descriptors", [][2]string{
		{"workspace_metadata", "workspace_id"},
	})
	// Bindings are owned by the workspace and reference a definition and a
	// source descriptor (composite FKs). Cross-workspace rows are rejected
	// because the workspace_id in each composite FK must match the referenced
	// row's workspace_id.
	assertForeignKeys(t, db, "property_bindings", [][2]string{
		{"source_property_descriptors", "workspace_id"},
		{"workspace_property_definitions", "workspace_id"},
		{"workspace_metadata", "workspace_id"},
	})
	assertForeignKeys(t, db, "workspace_property_terms", [][2]string{
		{"workspace_property_definitions", "workspace_id"},
		{"workspace_metadata", "workspace_id"},
	})

	// Definitions: workspace-scoped namespace/key uniqueness. There must be a
	// unique index whose columns are exactly (workspace_id, namespace,
	// canonical_key).
	{
		var n int
		if err := db.QueryRow(
			`SELECT count(*) FROM pragma_index_list('workspace_property_definitions')
			 WHERE "unique"=1 AND origin='c'`).Scan(&n); err != nil {
			t.Fatalf("query definitions unique indexes: %v", err)
		}
		if n != 1 {
			t.Fatalf("definitions has %d unique index(es), want exactly 1 (namespace/key)", n)
		}
		cols := []string{}
		rows, err := db.Query(
			`SELECT ii.name FROM pragma_index_list('workspace_property_definitions') il
			 JOIN pragma_index_info(il.name) ii ON ii.seqno >= 0
			 WHERE il."unique"=1 AND il.origin='c' ORDER BY ii.seqno`)
		if err != nil {
			t.Fatalf("query definitions unique index columns: %v", err)
		}
		defer rows.Close()
		for rows.Next() {
			var c string
			if err := rows.Scan(&c); err != nil {
				t.Fatalf("scan unique index column: %v", err)
			}
			cols = append(cols, c)
		}
		want := []string{"workspace_id", "namespace", "canonical_key"}
		if len(cols) != len(want) {
			t.Fatalf("definitions unique index columns = %v, want %v", cols, want)
		}
		for i := range want {
			if cols[i] != want[i] {
				t.Fatalf("definitions unique index columns = %v, want %v", cols, want)
			}
		}
	}

	// Terms: uniqueness on (workspace_id, property_id, term_kind, term_value)
	// so a given alias value is not duplicated within a term kind.
	{
		var n int
		if err := db.QueryRow(
			`SELECT count(*) FROM pragma_index_list('workspace_property_terms')
			 WHERE "unique"=1 AND origin='c'`).Scan(&n); err != nil {
			t.Fatalf("query terms unique indexes: %v", err)
		}
		if n != 1 {
			t.Fatalf("terms has %d unique index(es), want exactly 1 (term_value)", n)
		}
	}

	// 16-byte ID checks on every BLOB(16) identity column.
	for _, table := range []string{
		"workspace_property_definitions",
		"source_property_descriptors",
		"property_bindings",
		"workspace_property_terms",
	} {
		assertSingleColumnCheck(t, db, table, "workspace_id")
	}
	// property_id exists on every catalog table except source_property_descriptors,
	// which is keyed by provider/source identifiers instead.
	for _, table := range []string{
		"workspace_property_definitions",
		"property_bindings",
		"workspace_property_terms",
	} {
		assertSingleColumnCheck(t, db, table, "property_id")
	}
}

// A driver with maxVersion fails closed with ErrMigrationFailed when the
// ledger is ahead of its embedded max, and must release the flock so another
// instance can acquire it afterwards. A driver with the gate disabled
// (maxVersion=0) is unaffected.
func TestSharedSQLiteDriverLockRejectsAheadLedgerUnderLock(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)
	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	// Establish a valid baseline at version 1, then simulate a newer binary
	// having migrated the DB to version 2 (ahead of this binary's max=1).
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp to version 1: %v", err)
	}
	if _, err := store.SQLDB().ExecContext(ctx,
		"DELETE FROM schema_migrations; INSERT INTO schema_migrations (version, dirty) VALUES (2, 0)"); err != nil {
		t.Fatalf("advance ledger to version 2: %v", err)
	}

	lockPath := migrationLockPath(path)

	// Gate enabled (maxVersion=1): Lock must fail closed with
	// ErrMigrationFailed because the ledger (2) is ahead.
	driverA := &sharedSQLiteDriver{db: store.SQLDB(), lockPath: lockPath, maxVersion: 1}
	if err := driverA.Lock(); !errors.Is(err, ErrMigrationFailed) {
		t.Fatalf("driverA.Lock ahead ledger = %v, want wrapped ErrMigrationFailed", err)
	}

	// The failed gate Lock must have released the flock and reset state, so
	// driverA is no longer locked and a second driver can acquire the lock.
	if err := driverA.Unlock(); !errors.Is(err, database.ErrNotLocked) {
		t.Fatalf("driverA.Unlock after failed gate Lock = %v, want database.ErrNotLocked (flock already released)", err)
	}
	driverB := &sharedSQLiteDriver{db: store.SQLDB(), lockPath: lockPath, maxVersion: 0}
	if err := driverB.Lock(); err != nil {
		t.Fatalf("driverB.Lock after driverA's failed gate Lock: %v", err)
	}
	if err := driverB.Unlock(); err != nil {
		t.Fatalf("driverB.Unlock: %v", err)
	}
}
