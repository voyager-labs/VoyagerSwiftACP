package sqlite

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// tempDBPath creates a fresh 0700 subdirectory under a temp root and returns a
// database file path inside it. t.TempDir() itself is not guaranteed to be
// exactly 0700 on every platform (macOS may report 0755), so tests that require
// the canonical 0700 parent create their own subdirectory.
func tempDBPath(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	parent := filepath.Join(root, "db")
	if err := os.Mkdir(parent, 0o700); err != nil {
		t.Fatalf("mkdir 0700 parent: %v", err)
	}
	return filepath.Join(parent, "store.db")
}

// writeSentinel creates a pre-existing regular file at dbPath with known content
// so tests can assert that a failed Open leaves it untouched.
func writeSentinel(t *testing.T, dbPath string) {
	t.Helper()
	if err := os.WriteFile(dbPath, []byte("sentinel"), 0o600); err != nil {
		t.Fatalf("write sentinel file: %v", err)
	}
}

// assertFileUntouched verifies dbPath still contains the sentinel content.
func assertFileUntouched(t *testing.T, dbPath string) {
	t.Helper()
	got, err := os.ReadFile(dbPath)
	if err != nil {
		t.Fatalf("read sentinel file after failed Open: %v", err)
	}
	if string(got) != "sentinel" {
		t.Fatalf("pre-existing file was modified after failed Open: got %q, want %q", got, "sentinel")
	}
}

// assertOpenFailsClosed asserts that Open on dbPath fails with
// ErrDatabasePathInvalid and that a pre-existing sentinel file is untouched.
func assertOpenFailsClosed(t *testing.T, dbPath string) {
	t.Helper()
	writeSentinel(t, dbPath)
	store, err := Open(t.Context(), dbPath)
	if err == nil {
		_ = store.Close()
		t.Fatalf("Open(%q) succeeded, want ErrDatabasePathInvalid", dbPath)
	}
	if !errors.Is(err, ErrDatabasePathInvalid) {
		t.Fatalf("Open(%q) error = %v, want wrapped ErrDatabasePathInvalid", dbPath, err)
	}
	assertFileUntouched(t, dbPath)
}

func TestOpenRequiresAbsolutePath(t *testing.T) {
	t.Run("relative", func(t *testing.T) {
		store, err := Open(t.Context(), filepath.Join("relative", "store.db"))
		if err == nil {
			_ = store.Close()
			t.Fatal("Open(relative path) succeeded, want ErrDatabasePathInvalid")
		}
		if !errors.Is(err, ErrDatabasePathInvalid) {
			t.Fatalf("error = %v, want wrapped ErrDatabasePathInvalid", err)
		}
	})
}

func TestOpenRejectsUnsafeParent(t *testing.T) {
	t.Run("parent mode not 0700", func(t *testing.T) {
		base := t.TempDir()
		parent := filepath.Join(base, "parent")
		if err := os.Mkdir(parent, 0o700); err != nil {
			t.Fatalf("mkdir parent: %v", err)
		}
		if err := os.Chmod(parent, 0o755); err != nil {
			t.Fatalf("chmod parent: %v", err)
		}
		assertOpenFailsClosed(t, filepath.Join(parent, "store.db"))
	})

	t.Run("symlinked parent", func(t *testing.T) {
		base := t.TempDir()
		realDir := filepath.Join(base, "real")
		if err := os.Mkdir(realDir, 0o700); err != nil {
			t.Fatalf("mkdir real dir: %v", err)
		}
		linkParent := filepath.Join(base, "link")
		if err := os.Symlink(realDir, linkParent); err != nil {
			t.Fatalf("symlink parent: %v", err)
		}
		assertOpenFailsClosed(t, filepath.Join(linkParent, "store.db"))
	})

	t.Run("foreign-owned parent", func(t *testing.T) {
		base := t.TempDir()
		parent := filepath.Join(base, "parent")
		if err := os.Mkdir(parent, 0o700); err != nil {
			t.Fatalf("mkdir parent: %v", err)
		}
		other := os.Geteuid()
		if other == 0 {
			other = 1
		} else {
			other++
		}
		if err := os.Chown(parent, other, -1); err != nil {
			// A non-root test user cannot chown to a foreign UID; the ownership
			// branch cannot be exercised without privileges, so skip.
			t.Skipf("cannot chown parent to foreign UID %d as euid %d: %v", other, os.Geteuid(), err)
		}
		assertOpenFailsClosed(t, filepath.Join(parent, "store.db"))
	})
}

func TestOpenRejectsNonRegularDatabaseFile(t *testing.T) {
	t.Run("symlink destination", func(t *testing.T) {
		base := filepath.Join(t.TempDir(), "db")
		if err := os.Mkdir(base, 0o700); err != nil {
			t.Fatalf("mkdir 0700 base: %v", err)
		}
		target := filepath.Join(base, "target")
		if err := os.WriteFile(target, []byte("sentinel"), 0o600); err != nil {
			t.Fatalf("write target: %v", err)
		}
		dbPath := filepath.Join(base, "store.db")
		if err := os.Symlink(target, dbPath); err != nil {
			t.Fatalf("symlink db: %v", err)
		}
		assertOpenFailsClosed(t, dbPath)
	})

	t.Run("directory destination", func(t *testing.T) {
		base := filepath.Join(t.TempDir(), "db")
		if err := os.Mkdir(base, 0o700); err != nil {
			t.Fatalf("mkdir 0700 base: %v", err)
		}
		dbPath := filepath.Join(base, "store.db")
		if err := os.Mkdir(dbPath, 0o700); err != nil {
			t.Fatalf("mkdir db destination: %v", err)
		}
		store, err := Open(t.Context(), dbPath)
		if err == nil {
			_ = store.Close()
			t.Fatal("Open(directory destination) succeeded, want ErrDatabasePathInvalid")
		}
		if !errors.Is(err, ErrDatabasePathInvalid) {
			t.Fatalf("error = %v, want wrapped ErrDatabasePathInvalid", err)
		}
	})
}

func TestConnectionPolicyApplied(t *testing.T) {
	store, err := Open(t.Context(), tempDBPath(t))
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() {
		if cerr := store.Close(); cerr != nil {
			t.Errorf("Close: %v", cerr)
		}
	}()

	db := store.SQLDB()

	var foreignKeys int
	if err := db.QueryRow("PRAGMA foreign_keys").Scan(&foreignKeys); err != nil {
		t.Fatalf("read PRAGMA foreign_keys: %v", err)
	}
	if foreignKeys != 1 {
		t.Errorf("PRAGMA foreign_keys = %d, want 1", foreignKeys)
	}

	var journalMode string
	if err := db.QueryRow("PRAGMA journal_mode").Scan(&journalMode); err != nil {
		t.Fatalf("read PRAGMA journal_mode: %v", err)
	}
	if journalMode != "wal" {
		t.Errorf("PRAGMA journal_mode = %q, want %q", journalMode, "wal")
	}

	var busyTimeout int
	if err := db.QueryRow("PRAGMA busy_timeout").Scan(&busyTimeout); err != nil {
		t.Fatalf("read PRAGMA busy_timeout: %v", err)
	}
	if busyTimeout != 5000 {
		t.Errorf("PRAGMA busy_timeout = %d, want 5000", busyTimeout)
	}
}

func TestPoolIsSingleConnection(t *testing.T) {
	store, err := Open(t.Context(), tempDBPath(t))
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() {
		if cerr := store.Close(); cerr != nil {
			t.Errorf("Close: %v", cerr)
		}
	}()

	stats := store.SQLDB().Stats()
	if stats.MaxOpenConnections != 1 {
		t.Errorf("MaxOpenConnections = %d, want 1", stats.MaxOpenConnections)
	}
}

func TestCloseIdempotent(t *testing.T) {
	store, err := Open(t.Context(), tempDBPath(t))
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if err := store.Close(); err != nil {
		t.Fatalf("first Close: %v", err)
	}
	if err := store.Close(); err != nil {
		t.Fatalf("second Close: %v", err)
	}
}
