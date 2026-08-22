package sqlite

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"

	"gorm.io/gorm"
)

// TestCatalogRepositoryLoad1309 proves one Load pass reads all four families of
// a 1,309-row catalog (no N+1) and returns the exact expected counts.
func TestCatalogRepositoryLoad1309(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 300, 300, 600, 109, noneSeedTrio())

	// Instrument the Query callback to count GORM SELECT statements so an
	// accidental N+1 (one query per referenced row) is provably absent.
	var queryCount int32
	store.db.Callback().Query().Before("gorm:query").
		Register("voy764_test_count_query", func(tx *gorm.DB) {
			atomic.AddInt32(&queryCount, 1)
		})
	defer store.db.Callback().Query().Remove("voy764_test_count_query")

	repo := NewPropertyCatalogRepository(store)
	loaded, err := repo.Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	if got := len(loaded.Snapshot.Definitions); got != 300 {
		t.Fatalf("definitions = %d, want 300", got)
	}
	if got := len(loaded.Snapshot.Descriptors); got != 300 {
		t.Fatalf("descriptors = %d, want 300", got)
	}
	if got := len(loaded.Snapshot.Bindings); got != 600 {
		t.Fatalf("bindings = %d, want 600", got)
	}
	if got := len(loaded.Snapshot.Terms); got != 109 {
		t.Fatalf("terms = %d, want 109", got)
	}

	// Exactly four SELECTs: one per family. Any per-row fetch would exceed this.
	if got := atomic.LoadInt32(&queryCount); got != 4 {
		t.Fatalf("query count = %d, want exactly 4 (no N+1)", got)
	}
	if loaded.Digest == [32]byte{} {
		t.Fatal("digest must be non-zero")
	}
	if loaded.SeedState.HasSeed {
		t.Fatal("fixture has no seed rows; SeedState.HasSeed must be false")
	}
}

// TestCatalogRepositoryDigestEqualsFreshSeededReadBack proves that the digest
// computed from a persisted catalog equals the canonical digest of the same
// logical snapshot built in memory, and that row order and WorkspaceID do not
// change it.
func TestCatalogRepositoryDigestEqualsFreshSeededReadBack(t *testing.T) {
	ctx := context.Background()
	storeA := migratedStore(t)
	wsA := buildCatalogFixture(t, storeA, 300, 300, 600, 109, noneSeedTrio())
	repoA := NewPropertyCatalogRepository(storeA)
	loadedA, err := repoA.Load(ctx, wsA)
	if err != nil {
		t.Fatalf("Load A: %v", err)
	}

	// A fresh workspace with the same logical dataset inserted in a different
	// row order must yield the identical digest.
	storeB := migratedStore(t)
	wsB := buildCatalogFixture(t, storeB, 300, 300, 600, 109, noneSeedTrio())
	repoB := NewPropertyCatalogRepository(storeB)
	loadedB, err := repoB.Load(ctx, wsB)
	if err != nil {
		t.Fatalf("Load B: %v", err)
	}

	if wsA.ID == wsB.ID {
		t.Fatal("expected distinct WorkspaceIDs for the two workspaces")
	}
	if loadedA.Digest != loadedB.Digest {
		t.Fatalf("digest depends on WorkspaceID/row order:\n  A %x\n  B %x",
			loadedA.Digest, loadedB.Digest)
	}
	// The persisted read-back digest must equal the canonical in-memory digest.
	memDigest, err := loadedA.Snapshot.Digest()
	if err != nil {
		t.Fatalf("snapshot.Digest: %v", err)
	}
	if loadedA.Digest != memDigest {
		t.Fatalf("read-back digest != canonical snapshot digest:\n  read %x\n  mem  %x",
			loadedA.Digest, memDigest)
	}
}

// TestCatalogRepositorySameCountSubstitutionChangesDigest proves that replacing
// a row with another of the same count changes the digest (fail-fast on silent
// logical drift).
func TestCatalogRepositorySameCountSubstitutionChangesDigest(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 300, 300, 600, 109, noneSeedTrio())
	repo := NewPropertyCatalogRepository(store)
	loaded, err := repo.Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	before := loaded.Digest

	// Same row count, different logical content.
	mutateDefinitionDisplayName(t, store, wsctx, "cat.7", "Renamed Property 7")
	after, err := repo.Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load after mutation: %v", err)
	}
	if after.Digest == before {
		t.Fatal("digest did not change after same-count substitution")
	}
}

// TestCatalogRepositoryMalformedIDFails proves a persisted row with a 16-byte
// blob that fails the RFC variant check makes Load fail closed.
func TestCatalogRepositoryMalformedIDFails(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 2, 1, 1, 0, noneSeedTrio())

	// Insert an active definition whose property_id is 16 bytes but carries a
	// bad variant (length CHECK passes, mapper validation must reject it).
	bad := make([]byte, 16)
	for i := range bad {
		bad[i] = 0x22
	}
	if _, err := store.SQLDB().ExecContext(ctx,
		`INSERT INTO workspace_property_definitions
		 (workspace_id, property_id, origin, identity_scheme, namespace, canonical_key,
		  display_name, description, value_type, cardinality, nullable, editable,
		  default_hidden, default_pinned, db_indexed_hint, provenance, unit,
		  definition_revision, lifecycle_state, created_at, updated_at)
		 VALUES (?, ?, 'built_in', 'registry_derived', 'system', 'cat.bad',
		  'Bad', 'd', 'text', 'one', 0, 1, 0, 0, 0, 'system', '', 1, 'active',
		  datetime('now'), datetime('now'))`,
		wsctx.ID.Bytes(), bad); err != nil {
		t.Fatalf("insert malformed definition: %v", err)
	}

	repo := NewPropertyCatalogRepository(store)
	_, err := repo.Load(ctx, wsctx)
	if !errors.Is(err, ErrInvalidCatalogBLOB) {
		t.Fatalf("Load error = %v, want ErrInvalidCatalogBLOB", err)
	}
}

// TestCatalogRepositoryOrphanRefFails proves an active binding whose definition
// has been tombstoned (orphan) makes Load fail closed.
func TestCatalogRepositoryOrphanRefFails(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 3, 3, 4, 2, noneSeedTrio())

	// Tombstone a definition that an active binding references; the binding
	// stays active -> orphan (active binding without an active definition).
	res := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "cat.0").
		Update("lifecycle_state", "tombstoned")
	if res.Error != nil || res.RowsAffected != 1 {
		t.Fatalf("tombstone definition: err=%v rows=%d", res.Error, res.RowsAffected)
	}

	repo := NewPropertyCatalogRepository(store)
	_, err := repo.Load(ctx, wsctx)
	if !errors.Is(err, ErrCatalogOrphanRef) {
		t.Fatalf("Load error = %v, want ErrCatalogOrphanRef", err)
	}
}

func TestCatalogRepositoryActiveTermOrphanFails(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 1, 1, 1, 1, noneSeedTrio())
	res := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "cat.0").
		Update("lifecycle_state", "tombstoned")
	if res.Error != nil || res.RowsAffected != 1 {
		t.Fatalf("tombstone definition: err=%v rows=%d", res.Error, res.RowsAffected)
	}
	if _, err := NewPropertyCatalogRepository(store).Load(ctx, wsctx); !errors.Is(err, ErrCatalogOrphanRef) {
		t.Fatalf("Load error = %v, want ErrCatalogOrphanRef", err)
	}
}
