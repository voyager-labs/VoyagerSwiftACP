package sqlite

import (
	"context"
	"errors"
	"testing"

	"gorm.io/gorm"
)

// assertFailure is a non-nil sentinel error the tx tests return to force a
// rollback (or, inside a nested call, a rollback to the savepoint only).
var assertFailure = errors.New("assert: force rollback")

// txRowCount returns the number of workspace_metadata rows, for asserting
// transaction commit/rollback visibility.
func txRowCount(t *testing.T, store *Store) int {
	t.Helper()
	var count int
	if err := store.SQLDB().QueryRowContext(context.Background(),
		"SELECT COUNT(*) FROM workspace_metadata").Scan(&count); err != nil {
		t.Fatalf("count rows: %v", err)
	}
	return count
}

// insertWorkspaceRow inserts a dummy workspace_metadata row (singleton = 1)
// inside the given tx, returning the tx's error.
func insertWorkspaceRow(tx *gorm.DB) error {
	return tx.Exec(
		`INSERT INTO workspace_metadata (singleton, workspace_id, created_at, updated_at)
		 VALUES (1, X'018F0000000000000000000000000000', datetime('now'), datetime('now'))`,
	).Error
}

func TestWithinTxCommitsOnNil(t *testing.T) {
	store := migratedStore(t)

	err := store.WithinTx(context.Background(), func(tx *gorm.DB) error {
		if err := insertWorkspaceRow(tx); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		t.Fatalf("WithinTx: %v", err)
	}

	if got := txRowCount(t, store); got != 1 {
		t.Fatalf("row count after committed tx = %d, want 1", got)
	}
}

func TestWithinTxRollbacksOnError(t *testing.T) {
	store := migratedStore(t)

	err := store.WithinTx(context.Background(), func(tx *gorm.DB) error {
		if err := insertWorkspaceRow(tx); err != nil {
			return err
		}
		return assertFailure // non-nil error -> rollback
	})
	if err == nil {
		t.Fatal("WithinTx returned nil, want the propagated error")
	}

	if got := txRowCount(t, store); got != 0 {
		t.Fatalf("row count after errored tx = %d, want 0 (rolled back)", got)
	}
}

func TestWithinTxRollbacksOnPanic(t *testing.T) {
	store := migratedStore(t)

	func() {
		defer func() {
			if r := recover(); r == nil {
				t.Fatal("expected fn panic to propagate")
			}
		}()
		_ = store.WithinTx(context.Background(), func(tx *gorm.DB) error {
			if err := insertWorkspaceRow(tx); err != nil {
				return err
			}
			panic("boom")
		})
	}()

	if got := txRowCount(t, store); got != 0 {
		t.Fatalf("row count after panicked tx = %d, want 0 (rolled back)", got)
	}
}

func TestWithinTxNestedSavepoint(t *testing.T) {
	store := migratedStore(t)

	err := store.WithinTx(context.Background(), func(outer *gorm.DB) error {
		if err := insertWorkspaceRow(outer); err != nil {
			return err
		}

		// Nested WithinTx uses GORM SAVEPOINT semantics: the inner tx may
		// roll back without rolling back the outer transaction.
		innerErr := store.WithinTx(context.Background(), func(inner *gorm.DB) error {
			if err := insertWorkspaceRow(inner); err != nil {
				return err
			}
			return assertFailure // inner rolls back to savepoint only
		})
		if innerErr == nil {
			t.Fatal("inner WithinTx returned nil, want error")
		}

		// Outer still commits: exactly one row.
		return nil
	})
	if err != nil {
		t.Fatalf("outer WithinTx: %v", err)
	}

	if got := txRowCount(t, store); got != 1 {
		t.Fatalf("row count after nested tx = %d, want 1 (inner rolled back only)", got)
	}
}
