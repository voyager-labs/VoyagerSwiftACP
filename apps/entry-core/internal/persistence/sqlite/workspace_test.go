package sqlite

import (
	"context"
	"errors"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// migratedStore opens a fresh temp DB and runs MigrateUp so the
// workspace_metadata table (migration 0001) exists before bootstrap tests
// exercise it.
func migratedStore(t *testing.T) *Store {
	t.Helper()
	store, err := Open(context.Background(), tempDBPath(t))
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() {
		if cerr := store.Close(); cerr != nil {
			t.Errorf("Close: %v", cerr)
		}
	})
	if err := MigrateUp(context.Background(), store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp: %v", err)
	}
	return store
}

func TestWorkspaceBootstrapCreatesUUIDv7(t *testing.T) {
	store := migratedStore(t)

	ctx, err := store.BootstrapOrRestoreWorkspace(context.Background())
	if err != nil {
		t.Fatalf("BootstrapOrRestoreWorkspace: %v", err)
	}

	// The generated ID must parse as a UUIDv7: version nibble 7 + RFC 9562
	// variant, enforced by domainentry.ParseWorkspaceID.
	parsed, err := domainentry.ParseWorkspaceID(ctx.ID.Bytes())
	if err != nil {
		t.Fatalf("context ID does not parse as UUIDv7: %v", err)
	}
	if parsed != ctx.ID {
		t.Fatalf("parsed ID %v != context ID %v", parsed, ctx.ID)
	}

	// The singleton row exists.
	var count int
	if err := store.SQLDB().QueryRowContext(context.Background(),
		"SELECT COUNT(*) FROM workspace_metadata").Scan(&count); err != nil {
		t.Fatalf("count singleton rows: %v", err)
	}
	if count != 1 {
		t.Fatalf("workspace_metadata has %d rows, want exactly 1", count)
	}
}

func TestWorkspaceRestoreSameID(t *testing.T) {
	// First lifecycle: open + migrate + bootstrap.
	path := tempDBPath(t)
	store, err := Open(context.Background(), path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if err := MigrateUp(context.Background(), store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp: %v", err)
	}
	first, err := store.BootstrapOrRestoreWorkspace(context.Background())
	if err != nil {
		t.Fatalf("first bootstrap: %v", err)
	}
	if err := store.Close(); err != nil {
		t.Fatalf("first Close: %v", err)
	}

	// Second lifecycle: reopen the same path and restore identity.
	store2, err := Open(context.Background(), path)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer func() {
		if cerr := store2.Close(); cerr != nil {
			t.Errorf("second Close: %v", cerr)
		}
	}()
	if err := MigrateUp(context.Background(), store2.SQLDB()); err != nil {
		t.Fatalf("second MigrateUp: %v", err)
	}
	second, err := store2.BootstrapOrRestoreWorkspace(context.Background())
	if err != nil {
		t.Fatalf("second bootstrap: %v", err)
	}

	// Restore must return byte-identical identity (restart-stable).
	if second.ID != first.ID {
		t.Fatalf("restore identity mismatch:\n  expected (first) %x\n  actual   (second) %x",
			first.ID.Bytes(), second.ID.Bytes())
	}
}

func TestWorkspaceCorruptFailsClosed(t *testing.T) {
	store := migratedStore(t)

	// Establish a real row first so there is persisted identity to corrupt.
	if _, err := store.BootstrapOrRestoreWorkspace(context.Background()); err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	// Corrupt the persisted ID to exactly 16 all-zero bytes. The DDL
	// CHECK(length(workspace_id) = 16) accepts the write, but the UUIDv7
	// version nibble (high nibble of byte 6, zero-indexed) is 0, not 7, so
	// ParseWorkspaceID rejects the restored value on the next bootstrap.
	if _, err := store.SQLDB().ExecContext(context.Background(),
		"UPDATE workspace_metadata SET workspace_id = X'00000000000000000000000000000000'"); err != nil {
		t.Fatalf("corrupt UPDATE: %v", err)
	}

	_, err := store.BootstrapOrRestoreWorkspace(context.Background())
	if !errors.Is(err, ErrWorkspaceCorrupt) {
		t.Fatalf("bootstrap after corruption = %v, want ErrWorkspaceCorrupt", err)
	}

	// Fail closed: no auto-repair — the row is untouched (still all zeros).
	var raw []byte
	if err := store.SQLDB().QueryRowContext(context.Background(),
		"SELECT workspace_id FROM workspace_metadata WHERE singleton = 1").Scan(&raw); err != nil {
		t.Fatalf("read back workspace_id: %v", err)
	}
	want := make([]byte, 16)
	for i := range want {
		want[i] = 0
	}
	if string(raw) != string(want) {
		t.Fatalf("auto-repair occurred: workspace_id = %x, want untouched all-zero %x", raw, want)
	}
}

func TestWorkspaceSecondRowRejected(t *testing.T) {
	store := migratedStore(t)

	if _, err := store.BootstrapOrRestoreWorkspace(context.Background()); err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	// A second row with singleton = 2 fails the CHECK (singleton = 1); a second
	// row with singleton = 1 fails the primary key. Either is a rejected second
	// row, proving the single-row invariant is physically enforced.
	_, err := store.SQLDB().ExecContext(context.Background(),
		`INSERT INTO workspace_metadata (singleton, workspace_id, created_at, updated_at)
		 VALUES (2, X'018F0000000000000000000000000000', datetime('now'), datetime('now'))`)
	if err == nil {
		t.Fatal("inserting a second singleton row succeeded; single-row constraint not enforced")
	}
}
