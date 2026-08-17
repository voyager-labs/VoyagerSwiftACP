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
	"os"
	"path/filepath"
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
)

// DSN constants for the canonical connection policy (glebarez/modernc
// _pragma syntax). busy_timeout stays as defense against external readers.
const (
	pragmaForeignKeys = "_pragma=foreign_keys(1)"
	pragmaJournalMode = "_pragma=journal_mode(WAL)"
	pragmaBusyTimeout = "_pragma=busy_timeout(5000)"
	pragmaSynchronous = "_pragma=synchronous(NORMAL)"
)

// Store owns a single-writer SQLite connection with a verified connection
// policy. It is safe for concurrent use through the underlying *sql.DB, which
// serializes all access to one connection.
type Store struct {
	db        *gorm.DB
	sqlDB     *sql.DB
	closeOnce sync.Once
	closeErr  error
	txState   txState
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

	dsn := fmt.Sprintf(
		"file:%s?%s&%s&%s&%s",
		path, pragmaForeignKeys, pragmaJournalMode, pragmaBusyTimeout, pragmaSynchronous,
	)

	gormLogger := logger.New(
		log.New(io.Discard, "", log.LstdFlags),
		logger.Config{
			LogLevel:             logger.Error,
			ParameterizedQueries: true,
		},
	)

	gdb, err := gorm.Open(sqlite.Open(dsn), &gorm.Config{Logger: gormLogger})
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrDatabaseOpenFailed, err)
	}

	sqlDB, err := gdb.DB()
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrDatabaseOpenFailed, err)
	}

	// Single writer: one open + one idle connection, connections never closed
	// by idle timeout. Deterministic serialization for the whole first slice.
	sqlDB.SetMaxOpenConns(1)
	sqlDB.SetMaxIdleConns(1)
	sqlDB.SetConnMaxIdleTime(0)

	if err := verifyConnectionPolicy(ctx, sqlDB); err != nil {
		_ = sqlDB.Close()
		return nil, err
	}

	return &Store{db: gdb, sqlDB: sqlDB}, nil
}

// Close closes the underlying *sql.DB, which checkpoints WAL. Idempotent.
func (s *Store) Close() error {
	if s == nil {
		return nil
	}
	s.closeOnce.Do(func() {
		s.closeErr = s.sqlDB.Close()
	})
	return s.closeErr
}

// validateDatabasePath enforces the fail-closed path contract: an absolute
// path whose parent is a non-symlink 0700 directory owned by the effective
// user; if the database file already exists it must be a non-symlink regular
// file owned by the effective user. Pre-existing files are never touched.
func validateDatabasePath(path string, effectiveUID int) error {
	if !filepath.IsAbs(path) {
		return fmt.Errorf("%w: path must be absolute", ErrDatabasePathInvalid)
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

	return nil
}
