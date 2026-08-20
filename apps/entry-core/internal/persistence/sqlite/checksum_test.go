package sqlite

import (
	"errors"
	"io/fs"
	"testing"
	"testing/fstest"
)

// readEmbeddedDir copies the committed migration directory from the embedded
// FS into a mutable MapFS so tests can tamper with it without touching the
// embedded (append-only) directory.
func readEmbeddedDir(t *testing.T) fstest.MapFS {
	t.Helper()
	m := fstest.MapFS{}
	for _, name := range []string{
		"migrations/0001_workspace_metadata.up.sql",
		"migrations/0001_workspace_metadata.down.sql",
		"migrations/0002_workspace_property_catalog.up.sql",
		"migrations/0002_workspace_property_catalog.down.sql",
		"migrations/atlas.sum",
	} {
		b, err := fs.ReadFile(migrationsFS, name)
		if err != nil {
			t.Fatalf("read embedded %s: %v", name, err)
		}
		m[name] = &fstest.MapFile{Data: b}
	}
	return m
}

// assertChecksumError asserts that err is ErrMigrationChecksum.
func assertChecksumError(t *testing.T, err error) {
	t.Helper()
	if !errors.Is(err, ErrMigrationChecksum) {
		t.Fatalf("got error %v, want ErrMigrationChecksum", err)
	}
}

func TestChecksumValidatesCommittedDirectory(t *testing.T) {
	if err := VerifyEmbeddedMigrations(migrationsFS); err != nil {
		t.Fatalf("VerifyEmbeddedMigrations on committed directory: %v", err)
	}
}

func TestChecksumRejectsTamperedFile(t *testing.T) {
	dir := readEmbeddedDir(t)
	up := "migrations/0001_workspace_metadata.up.sql"
	b := dir[up].Data
	flipped := make([]byte, len(b))
	copy(flipped, b)
	flipped[0] ^= 0x01 // flip one byte in the up file content
	dir[up] = &fstest.MapFile{Data: flipped}

	assertChecksumError(t, VerifyEmbeddedMigrations(dir))
}

func TestChecksumRejectsUnlistedFile(t *testing.T) {
	dir := readEmbeddedDir(t)
	// Extra .up.sql not referenced by atlas.sum.
	dir["migrations/0002_extra.up.sql"] = &fstest.MapFile{Data: []byte("CREATE TABLE extra (id integer);")}

	assertChecksumError(t, VerifyEmbeddedMigrations(dir))
}

func TestChecksumRejectsMissingEntry(t *testing.T) {
	dir := readEmbeddedDir(t)
	// atlas.sum still lists 0001_workspace_metadata.up.sql, but the file is
	// absent from the FS.
	delete(dir, "migrations/0001_workspace_metadata.up.sql")

	assertChecksumError(t, VerifyEmbeddedMigrations(dir))
}

func TestChecksumScopeIsUpFilesOnly(t *testing.T) {
	dir := readEmbeddedDir(t)
	// A byte flip in a .down.sql must NOT trip the hash check: atlas.sum hashes
	// up files only.
	down := "migrations/0001_workspace_metadata.down.sql"
	b := dir[down].Data
	flipped := make([]byte, len(b))
	copy(flipped, b)
	flipped[0] ^= 0x01
	dir[down] = &fstest.MapFile{Data: flipped}

	if err := VerifyEmbeddedMigrations(dir); err != nil {
		t.Fatalf("down file content must not be hash-verified, got error: %v", err)
	}
}

func TestChecksumRejectsOrphanDownFile(t *testing.T) {
	dir := readEmbeddedDir(t)
	// A .down.sql with no paired .up.sql must be rejected.
	dir["migrations/0002_orphan.down.sql"] = &fstest.MapFile{Data: []byte("DROP TABLE orphan;")}

	assertChecksumError(t, VerifyEmbeddedMigrations(dir))
}
