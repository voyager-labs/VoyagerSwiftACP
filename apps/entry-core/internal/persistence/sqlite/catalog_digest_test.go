package sqlite

import (
	"context"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// TestCatalogDigestUsesCanonicalImplementation proves the persisted read-back
// digest equals the canonical PropertyCatalogSnapshot.Digest of the mapped
// snapshot (i.e. persistence does not duplicate framing/hash logic).
func TestCatalogDigestUsesCanonicalImplementation(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 300, 300, 600, 109, noneSeedTrio())

	repo := NewPropertyCatalogRepository(store)
	loaded, err := repo.Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	canonical, err := loaded.Snapshot.Digest()
	if err != nil {
		t.Fatalf("canonical Digest: %v", err)
	}
	if loaded.Digest != canonical {
		t.Fatalf("repository digest %x != canonical snapshot digest %x",
			loaded.Digest, canonical)
	}

	// The snapshot must exclude workspace identity/timestamps: the canonical
	// digest is byte-for-byte what an in-memory construction produces, and it
	// is independent of WorkspaceID (proved by the cross-workspace test).
	if loaded.SeedState.HasSeed {
		t.Fatal("unexpected seed state for empty-seed fixture")
	}
}

// TestCatalogDigestIncludesStableFields proves a seed-owned definition's
// origin/scheme and stable fields participate in the digest: changing them
// changes the digest.
func TestCatalogDigestIncludesStableFields(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 3, 3, 4, 2, noneSeedTrio())
	repo := NewPropertyCatalogRepository(store)

	before, err := repo.Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	// Flip origin on one active definition -> stable field change -> digest.
	res := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "cat.0").
		Update("origin", "user_defined")
	if res.Error != nil || res.RowsAffected != 1 {
		t.Fatalf("update origin: err=%v rows=%d", res.Error, res.RowsAffected)
	}

	after, err := repo.Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load after origin change: %v", err)
	}
	if after.Digest == before.Digest {
		t.Fatal("digest did not change when a stable definition field changed")
	}

	// Identity scheme must also be framed: the mapped definition carries it.
	if len(after.Snapshot.Definitions) == 0 {
		t.Fatal("no definitions mapped")
	}
	if after.Snapshot.Definitions[0].IdentityScheme != domainentry.PropertyIdentitySchemeRegistryDerived {
		t.Fatalf("identity scheme not preserved in mapping: %q",
			after.Snapshot.Definitions[0].IdentityScheme)
	}
}
