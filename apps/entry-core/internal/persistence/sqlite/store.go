// Package sqlite owns the SQLite store lifecycle: fail-closed path
// validation, the canonical connection policy (pragmas verified by
// read-back), and a single-writer connection pool. This slice creates no
// tables; the store opens an empty database and ownership of open/close is
// the whole contract.
package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// Sentinel errors (metadata-only taxonomy). Daemon maps each to exit 1 + one
// stderr line naming the error class. Messages never embed the database path
// or any pragma value.
var (
	ErrDatabasePathInvalid   = errors.New("database path invalid")
	ErrDatabaseOpenFailed    = errors.New("database open failed")
	ErrConnectionPolicyUnmet = errors.New("connection policy not met")
	ErrDatabaseLocked        = errors.New("database is in use by another daemon")
)

// DSN constants for the canonical connection policy (glebarez/modernc
// _pragma syntax). busy_timeout stays as defense against external readers.
// Each is one `_pragma=<value>` query param applied verbatim via `pragma <v>`.
const (
	pragmaForeignKeys = "foreign_keys(1)"
	pragmaJournalMode = "journal_mode(WAL)"
	pragmaBusyTimeout = "busy_timeout(5000)"
	pragmaSynchronous = "synchronous(NORMAL)"
)

// buildDSN escapes the validated path as the file: URI Path so reserved
// characters (`?`, `#`, `%`) in a valid Unix filename are never read as query
// separators; SQLite opens exactly the requested file. The connection policy
// is emitted as repeated _pragma params, which glebarez/modernc parses via
// url.ParseQuery and applies per connection.
func buildDSN(path string) string {
	u := &url.URL{Scheme: "file", Path: path}
	q := url.Values{}
	q.Add("_pragma", pragmaForeignKeys)
	q.Add("_pragma", pragmaJournalMode)
	q.Add("_pragma", pragmaBusyTimeout)
	q.Add("_pragma", pragmaSynchronous)
	u.RawQuery = q.Encode()
	return u.String()
}

// Store owns a single-writer SQLite connection with a verified connection
// policy. It is safe for concurrent use through the underlying *sql.DB, which
// serializes all access to one connection.
type Store struct {
	db         *gorm.DB
	sqlDB      *sql.DB
	daemonLock *os.File
	closeOnce  sync.Once
	closeErr   error
	txState    txState
	gates      txGateRegistry // per-*gorm.DB serialization gates for nested SAVEPOINTs
}

// SQLDB returns the underlying *sql.DB (single-connection pool), primarily for
// pragma read-back and pool statistics.
func (s *Store) SQLDB() *sql.DB {
	return s.sqlDB
}

// Open validates path per the fail-closed database path contract, opens the
// database with the canonical connection policy, verifies the pragmas by
// read-back, and configures a single-connection pool. The database file is
// created by SQLite only after path validation passes; pre-existing files are
// never deleted or replaced.
func Open(ctx context.Context, path string) (*Store, error) {
	effectiveUID := os.Geteuid()
	if err := validateDatabasePath(path, effectiveUID); err != nil {
		return nil, err
	}

	// Acquire the lifetime daemon lock for the whole store lifetime (including
	// the migration window). A second Open on the same database fails closed
	// while the first Store holds this lock, so two daemons can never run on
	// one database. Released in Close (and auto-released by the kernel if the
	// process dies). Uses a SEPARATE lock file from the migration lock so it
	// does not contend with MigrateUpFS's own flock within this process.
	daemonLock, err := acquireDaemonLock(daemonLockPath(path))
	if err != nil {
		return nil, err
	}

	dsn := buildDSN(path)

	gormLogger := logger.New(
		log.New(io.Discard, "", log.LstdFlags),
		logger.Config{
			LogLevel:             logger.Error,
			ParameterizedQueries: true,
		},
	)

	gdb, err := gorm.Open(sqlite.Open(dsn), &gorm.Config{Logger: gormLogger})
	if err != nil {
		_ = releaseDaemonLock(daemonLock)
		return nil, fmt.Errorf("%w: %v", ErrDatabaseOpenFailed, err)
	}

	sqlDB, err := gdb.DB()
	if err != nil {
		_ = releaseDaemonLock(daemonLock)
		return nil, fmt.Errorf("%w: %v", ErrDatabaseOpenFailed, err)
	}

	// Single writer: one open + one idle connection, connections never closed
	// by idle timeout. Deterministic serialization for the whole first slice.
	sqlDB.SetMaxOpenConns(1)
	sqlDB.SetMaxIdleConns(1)
	sqlDB.SetConnMaxIdleTime(0)

	if err := verifyConnectionPolicy(ctx, sqlDB); err != nil {
		_ = sqlDB.Close()
		_ = releaseDaemonLock(daemonLock)
		return nil, err
	}

	return &Store{db: gdb, sqlDB: sqlDB, daemonLock: daemonLock, gates: txGateRegistry{gates: map[*gorm.DB]*txGate{}}}, nil
}

// Close closes the underlying *sql.DB, which checkpoints WAL, and releases the
// lifetime daemon lock. Idempotent.
func (s *Store) Close() error {
	if s == nil {
		return nil
	}
	s.closeOnce.Do(func() {
		if s.daemonLock != nil {
			s.closeErr = errors.Join(s.sqlDB.Close(), releaseDaemonLock(s.daemonLock))
			s.daemonLock = nil
		} else {
			s.closeErr = s.sqlDB.Close()
		}
	})
	return s.closeErr
}

// daemonLockPath derives the lifetime lock file path for a database file path.
// It lives beside the database and persists (never unlinked), so every process
// opening the same database flocks the same inode. It is deliberately a
// DIFFERENT file from the migration lock (<db>.migrate.lock): flock exclusion
// is per open-file-description, so holding a lifetime flock on the same file
// as MigrateUpFS's own flock would contend within this process and break
// migration.
func daemonLockPath(dbPath string) string {
	return dbPath + ".daemon.lock"
}

// acquireDaemonLock takes a non-blocking exclusive flock on the lifetime lock
// file for the store's whole lifetime. On contention it fails closed with
// ErrDatabaseLocked (metadata-only, no path) instead of blocking.
func acquireDaemonLock(path string) (*os.File, error) {
	fd, err := syscall.Open(path, syscall.O_RDWR|syscall.O_NOFOLLOW|syscall.O_CLOEXEC|syscall.O_CREAT, 0o600)
	if err != nil {
		return nil, fmt.Errorf("%w: cannot open daemon lock", ErrDatabaseLocked)
	}
	file := os.NewFile(uintptr(fd), path)
	if file == nil {
		_ = syscall.Close(fd)
		return nil, fmt.Errorf("%w: invalid daemon lock descriptor", ErrDatabaseLocked)
	}
	if err := syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = file.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) || errors.Is(err, syscall.EAGAIN) {
			return nil, ErrDatabaseLocked
		}
		return nil, fmt.Errorf("%w: cannot acquire daemon lock", ErrDatabaseLocked)
	}
	return file, nil
}

// releaseDaemonLock unlocks and closes the lifetime lock descriptor. It is
// idempotent: a nil descriptor is a no-op, and a second call on a released
// descriptor is safe because the Store nils it out on Close.
func releaseDaemonLock(file *os.File) error {
	if file == nil {
		return nil
	}
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_UN); err != nil {
		return err
	}
	return file.Close()
}

// validateDatabasePath enforces the fail-closed path contract: an absolute
// path whose parent is a non-symlink 0700 directory owned by the effective
// user; if the database file already exists it must be a non-symlink regular
// file owned by the effective user. Pre-existing files are never touched.
func validateDatabasePath(path string, effectiveUID int) error {
	if !filepath.IsAbs(path) {
		return fmt.Errorf("%w: path must be absolute", ErrDatabasePathInvalid)
	}

	// SQLite derives auxiliary files (-wal, -shm, -journal) from the database
	// path by appending the suffix. A database whose basename already ends in
	// one of these suffixes would occupy another database's auxiliary file
	// namespace (e.g. /dir/foo-wal collides with /dir/foo's WAL), letting two
	// daemons open "different" paths that physically collide and one's WAL
	// overwrite/delete the other's database. On case-insensitive filesystems
	// (e.g. macOS default) a mixed-case suffix (-WAL, -Shm, -JOURNAL) also
	// case-insensitively collides with a lowercase auxiliary namespace, so the
	// basename is normalized to lowercase before matching. Fail closed on such
	// basenames.
	if base := strings.ToLower(filepath.Base(path)); strings.HasSuffix(base, "-wal") ||
		strings.HasSuffix(base, "-shm") ||
		strings.HasSuffix(base, "-journal") {
		return fmt.Errorf("%w: database file name conflicts with a SQLite auxiliary file", ErrDatabasePathInvalid)
	}

	parent, err := os.Lstat(filepath.Dir(path))
	if err != nil {
		return fmt.Errorf("%w: cannot inspect parent directory", ErrDatabasePathInvalid)
	}
	if err := validateSecureParent(parent, effectiveUID); err != nil {
		return err
	}

	if fi, err := os.Lstat(path); err == nil {
		if fi.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("%w: database file must not be a symlink", ErrDatabasePathInvalid)
		}
		if !fi.Mode().IsRegular() {
			return fmt.Errorf("%w: database file must be a regular file", ErrDatabasePathInvalid)
		}
		stat, ok := fi.Sys().(*syscall.Stat_t)
		if !ok || int(stat.Uid) != effectiveUID {
			return fmt.Errorf("%w: database file must be owned by the effective user", ErrDatabasePathInvalid)
		}
		if stat.Nlink != 1 {
			return fmt.Errorf("%w: database file must not be hard-linked", ErrDatabasePathInvalid)
		}
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("%w: cannot inspect database file", ErrDatabasePathInvalid)
	}

	return nil
}

// validateSecureParent mirrors the unixsocket validateSecureDirectory
// contract: non-symlink directory with exact mode 0700 owned by the effective
// UID.
func validateSecureParent(info os.FileInfo, effectiveUID int) error {
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return fmt.Errorf("%w: parent must be a non-symlink directory", ErrDatabasePathInvalid)
	}
	if info.Mode().Perm() != 0o700 {
		return fmt.Errorf("%w: parent mode must be 0700", ErrDatabasePathInvalid)
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || int(stat.Uid) != effectiveUID {
		return fmt.Errorf("%w: parent must be owned by the effective user", ErrDatabasePathInvalid)
	}
	return nil
}

// verifyConnectionPolicy reads back the connection-level pragmas and fails
// closed unless the canonical policy holds.
func verifyConnectionPolicy(ctx context.Context, sqlDB *sql.DB) error {
	var foreignKeys int
	if err := sqlDB.QueryRowContext(ctx, "PRAGMA foreign_keys").Scan(&foreignKeys); err != nil {
		return fmt.Errorf("%w: foreign_keys read-back: %v", ErrConnectionPolicyUnmet, err)
	}
	if foreignKeys != 1 {
		return fmt.Errorf("%w: foreign_keys", ErrConnectionPolicyUnmet)
	}

	var journalMode string
	if err := sqlDB.QueryRowContext(ctx, "PRAGMA journal_mode").Scan(&journalMode); err != nil {
		return fmt.Errorf("%w: journal_mode read-back: %v", ErrConnectionPolicyUnmet, err)
	}
	if journalMode != "wal" {
		return fmt.Errorf("%w: journal_mode", ErrConnectionPolicyUnmet)
	}

	var busyTimeout int
	if err := sqlDB.QueryRowContext(ctx, "PRAGMA busy_timeout").Scan(&busyTimeout); err != nil {
		return fmt.Errorf("%w: busy_timeout read-back: %v", ErrConnectionPolicyUnmet, err)
	}
	if busyTimeout != 5000 {
		return fmt.Errorf("%w: busy_timeout", ErrConnectionPolicyUnmet)
	}

	var synchronous int
	if err := sqlDB.QueryRowContext(ctx, "PRAGMA synchronous").Scan(&synchronous); err != nil {
		return fmt.Errorf("%w: synchronous read-back: %v", ErrConnectionPolicyUnmet, err)
	}
	if synchronous != 1 {
		return fmt.Errorf("%w: synchronous", ErrConnectionPolicyUnmet)
	}

	return nil
}
