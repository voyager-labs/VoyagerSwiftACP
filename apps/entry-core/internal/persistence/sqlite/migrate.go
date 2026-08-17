package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"sync/atomic"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database"
	migrateiofs "github.com/golang-migrate/migrate/v4/source/iofs"
)

// ErrMigrationFailed is returned when applying migrations fails (including a
// dirty ledger). The daemon maps it to exit 1 and never auto-replays .down.sql.
var ErrMigrationFailed = errors.New("migration failed")

// MigrateUp applies the embedded migrations to the shared *sql.DB. It
// delegates to MigrateUpFS with the embedded directory.
func MigrateUp(ctx context.Context, sqlDB *sql.DB) error {
	return MigrateUpFS(ctx, sqlDB, migrationsFS)
}

// MigrateUpFS applies the migrations in fsys to the shared *sql.DB. It first
// verifies the directory against its atlas.sum (checksum gate), then runs
// golang-migrate Up over the store's single shared connection, treating
// migrate.ErrNoChange as success. The schema_migrations table is the single
// version/dirty ledger. It is fail-closed: a dirty ledger never self-heals
// (no auto-down, no ledger reset) and is mapped to ErrMigrationFailed.
func MigrateUpFS(ctx context.Context, sqlDB *sql.DB, fsys fs.FS) error {
	// Checksum gate ordering: no migration SQL executes unless the directory
	// passes integrity verification.
	if err := VerifyEmbeddedMigrations(fsys); err != nil {
		return err
	}

	sourceDriver, err := migrateiofs.New(fsys, "migrations")
	if err != nil {
		return fmt.Errorf("%w: source: %v", ErrMigrationFailed, err)
	}
	databaseDriver := &sharedSQLiteDriver{db: sqlDB}
	if err := databaseDriver.ensureVersionTable(); err != nil {
		return fmt.Errorf("%w: %v", ErrMigrationFailed, err)
	}

	m, err := migrate.NewWithInstance("iofs", sourceDriver, "sqlite", databaseDriver)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrMigrationFailed, err)
	}
	defer m.Close()

	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		// A dirty ledger must never self-heal: map it (and any other failure)
		// to ErrMigrationFailed. golang-migrate returns migrate.ErrDirty when
		// Up is invoked on an already-dirty database; any run failure leaves
		// the ledger dirty at the failing version.
		var dirty migrate.ErrDirty
		if errors.As(err, &dirty) {
			return fmt.Errorf("%w: dirty ledger at version %d", ErrMigrationFailed, dirty.Version)
		}
		return fmt.Errorf("%w: %v", ErrMigrationFailed, err)
	}
	return nil
}

// migrationsTable is the single version/dirty ledger table (ADR-014). It is
// golang-migrate's default name so the ledger contract matches the canonical
// tooling.
const migrationsTable = "schema_migrations"

// sharedSQLiteDriver is a golang-migrate database.Driver that runs migrations
// over an already-open *sql.DB owned by the Store. It deliberately does NOT
// import golang-migrate's database/sqlite package (which blank-imports
// modernc.org/sqlite, colliding with glebarez's "sqlite" driver registration)
// and does NOT close the shared connection (the Store owns open/close).
//
// Behavior mirrors golang-migrate's MIT sqlite driver: each migration runs in
// a transaction, and schema_migrations tracks version/dirty state.
type sharedSQLiteDriver struct {
	db       *sql.DB
	isLocked atomic.Bool
}

var _ database.Driver = (*sharedSQLiteDriver)(nil)

// ensureVersionTable creates the schema_migrations ledger table if absent,
// mirroring golang-migrate's WithInstance setup so Version() never reads a
// missing table on a fresh database.
func (d *sharedSQLiteDriver) ensureVersionTable() error {
	_, err := d.db.Exec(
		"CREATE TABLE IF NOT EXISTS " + migrationsTable + " (version uint64, dirty bool);" +
			"CREATE UNIQUE INDEX IF NOT EXISTS version_unique ON " + migrationsTable + " (version);",
	)
	return err
}

func (d *sharedSQLiteDriver) Open(_ string) (database.Driver, error) {
	return d, nil
}

// Close is a no-op: the Store owns the underlying *sql.DB lifecycle.
func (d *sharedSQLiteDriver) Close() error {
	return nil
}

func (d *sharedSQLiteDriver) Lock() error {
	if !d.isLocked.CompareAndSwap(false, true) {
		return database.ErrLocked
	}
	return nil
}

func (d *sharedSQLiteDriver) Unlock() error {
	if !d.isLocked.CompareAndSwap(true, false) {
		return database.ErrNotLocked
	}
	return nil
}

func (d *sharedSQLiteDriver) Run(migration io.Reader) error {
	query, err := io.ReadAll(migration)
	if err != nil {
		return err
	}
	tx, err := d.db.Begin()
	if err != nil {
		return &database.Error{OrigErr: err, Err: "transaction start failed"}
	}
	if _, err := tx.Exec(string(query)); err != nil {
		_ = tx.Rollback()
		return &database.Error{OrigErr: err, Query: query}
	}
	if err := tx.Commit(); err != nil {
		return &database.Error{OrigErr: err, Err: "transaction commit failed"}
	}
	return nil
}

func (d *sharedSQLiteDriver) SetVersion(version int, dirty bool) error {
	tx, err := d.db.Begin()
	if err != nil {
		return &database.Error{OrigErr: err, Err: "transaction start failed"}
	}
	if _, err := tx.Exec("DELETE FROM " + migrationsTable); err != nil {
		_ = tx.Rollback()
		return &database.Error{OrigErr: err, Query: []byte("DELETE FROM " + migrationsTable)}
	}
	if version >= 0 || (version == database.NilVersion && dirty) {
		if _, err := tx.Exec(
			"INSERT INTO "+migrationsTable+" (version, dirty) VALUES (?, ?)",
			version, dirty,
		); err != nil {
			_ = tx.Rollback()
			return &database.Error{OrigErr: err, Query: []byte("INSERT INTO " + migrationsTable)}
		}
	}
	if err := tx.Commit(); err != nil {
		return &database.Error{OrigErr: err, Err: "transaction commit failed"}
	}
	return nil
}

func (d *sharedSQLiteDriver) Version() (version int, dirty bool, err error) {
	err = d.db.QueryRow(
		"SELECT version, dirty FROM "+migrationsTable+" LIMIT 1",
	).Scan(&version, &dirty)
	if errors.Is(err, sql.ErrNoRows) {
		return database.NilVersion, false, nil
	}
	if err != nil {
		return 0, false, &database.Error{OrigErr: err, Query: []byte("SELECT version FROM " + migrationsTable)}
	}
	return version, dirty, nil
}

func (d *sharedSQLiteDriver) Drop() error {
	// Never called by MigrateUp. Kept for interface conformance; the store
	// owns destructive operations and the down files exist only for ADR-014
	// artifact-format compliance.
	return nil
}
