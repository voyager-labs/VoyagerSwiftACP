package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"

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
	// passes integrity verification. Once verified, the directory is trusted.
	if err := VerifyEmbeddedMigrations(fsys); err != nil {
		return err
	}

	// Fail closed if the DB ledger is AHEAD of this binary's embedded max: a
	// newer binary migrated it to a schema this older binary does not know, so
	// m.Up() would report ErrNoChange and the daemon would silently connect to
	// an incompatible future schema. maxVer is threaded into the driver so the
	// guard itself runs inside Lock(), under the cross-process flock.
	maxVer, err := maxEmbeddedVersion(fsys)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrMigrationFailed, err)
	}
	dbPath, err := sqliteDBFilePath(sqlDB)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrMigrationFailed, err)
	}
	// maxVersion is threaded into the driver so the future-version gate runs
	// WHILE the cross-process flock is held (in Lock()), not before it. This
	// closes the TOCTOU window: an old binary that read the ledger at version
	// N before a newer binary migrated it to N+1 re-reads under the lock and
	// fails closed instead of serving on an incompatible schema.
	databaseDriver := &sharedSQLiteDriver{
		db:         sqlDB,
		lockPath:   migrationLockPath(dbPath),
		maxVersion: maxVer,
	}
	// ensureVersionTable must run before m.Up() so the version-gate read inside
	// Lock() (and golang-migrate's own Version()) finds the ledger table even on
	// a fresh database (otherwise the SELECT errors instead of returning
	// NilVersion). It is idempotent and cheap.
	if err := databaseDriver.ensureVersionTable(); err != nil {
		return fmt.Errorf("%w: %v", ErrMigrationFailed, err)
	}

	sourceDriver, err := migrateiofs.New(fsys, "migrations")
	if err != nil {
		return fmt.Errorf("%w: source: %v", ErrMigrationFailed, err)
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

// maxEmbeddedVersion returns the highest migration version embedded in fsys's
// migrations directory, parsed from the canonical golang-migrate leading
// integer prefix (000N) of each *.up.sql filename.
func maxEmbeddedVersion(fsys fs.FS) (int, error) {
	migFS, err := fs.Sub(fsys, "migrations")
	if err != nil {
		return 0, err
	}
	upNames, err := fs.Glob(migFS, "*.up.sql")
	if err != nil {
		return 0, err
	}
	max := 0
	for _, name := range upNames {
		prefix := name
		if i := strings.IndexByte(name, '_'); i > 0 {
			prefix = name[:i]
		}
		v, err := strconv.Atoi(prefix)
		if err != nil {
			return 0, fmt.Errorf("malformed migration filename %q: %v", name, err)
		}
		if v > max {
			max = v
		}
	}
	return max, nil
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
//
// Locking is cross-PROCESS. The in-memory isLocked guard only rejects a
// second Lock on the SAME driver instance; the real mutual exclusion across
// daemons sharing one database file is a flock on a lock file derived from
// the database path (mirroring internal/transport/unixsocket). This is what
// prevents two daemons with the same --database from interleaving their
// separate ledger-update and migration-SQL transactions and leaving the
// schema_migrations ledger dirty.
type sharedSQLiteDriver struct {
	db         *sql.DB
	lockPath   string   // flock file path ("" disables cross-process locking)
	lockFile   *os.File // open flock'd descriptor while the lock is held
	isLocked   atomic.Bool
	maxVersion int // embedded max ledger version; <=0 disables the future-version gate
}

var _ database.Driver = (*sharedSQLiteDriver)(nil)

// sqliteDBFilePath resolves the on-disk path of the main database from the
// connection's PRAGMA database_list, so the migration lock can be derived
// without threading the path through the public MigrateUpFS signature.
func sqliteDBFilePath(sqlDB *sql.DB) (string, error) {
	var seq int
	var name, file string
	if err := sqlDB.QueryRow("PRAGMA database_list").Scan(&seq, &name, &file); err != nil {
		return "", fmt.Errorf("read database file path: %w", err)
	}
	if file == "" || file == ":memory:" {
		return "", errors.New("database is not file-backed")
	}
	return file, nil
}

// migrationLockPath derives the flock file path for a database file path. The
// lock file lives beside the database and persists (it is never unlinked) so
// every process opening the same database flocks the same inode.
func migrationLockPath(dbPath string) string {
	return dbPath + ".migrate.lock"
}

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
	if err := d.acquireFileLock(); err != nil {
		d.isLocked.Store(false)
		return err
	}
	// Future-version gate: while the cross-process flock is held, re-read the
	// ledger and fail closed if it is ahead of this binary's embedded max. A
	// newer binary may have migrated the DB between any earlier version read
	// and this lock acquisition, so the check must run here (under the lock),
	// not before Lock(). On failure release the flock and reset state so the
	// lock is never leaked; golang-migrate returns the error from Up() without
	// calling Unlock() in this path.
	if d.maxVersion > 0 {
		ver, _, verErr := d.Version()
		if verErr == nil && ver != database.NilVersion && ver > d.maxVersion {
			_ = d.Unlock()
			return fmt.Errorf("%w: database schema version %d is newer than embedded max %d", ErrMigrationFailed, ver, d.maxVersion)
		}
	}
	return nil
}

func (d *sharedSQLiteDriver) Unlock() error {
	if !d.isLocked.CompareAndSwap(true, false) {
		return database.ErrNotLocked
	}
	if d.lockFile != nil {
		_ = syscall.Flock(int(d.lockFile.Fd()), syscall.LOCK_UN)
		_ = d.lockFile.Close()
		d.lockFile = nil
	}
	return nil
}

// acquireFileLock takes a non-blocking exclusive flock on the driver's lock
// file. flock exclusion is per open file description, so a second driver (or
// daemon) over the same database contends here even within one process. A
// held lock maps to database.ErrLocked (fail closed) instead of blocking.
func (d *sharedSQLiteDriver) acquireFileLock() error {
	if d.lockPath == "" {
		return nil
	}
	fd, err := syscall.Open(d.lockPath, syscall.O_RDWR|syscall.O_NOFOLLOW|syscall.O_CLOEXEC|syscall.O_CREAT, 0o600)
	if err != nil {
		return fmt.Errorf("open migration lock: %w", err)
	}
	file := os.NewFile(uintptr(fd), d.lockPath)
	if file == nil {
		_ = syscall.Close(fd)
		return errors.New("open migration lock: invalid file descriptor")
	}
	if err := syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = file.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) || errors.Is(err, syscall.EAGAIN) {
			return database.ErrLocked
		}
		return fmt.Errorf("acquire migration lock: %w", err)
	}
	d.lockFile = file
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
