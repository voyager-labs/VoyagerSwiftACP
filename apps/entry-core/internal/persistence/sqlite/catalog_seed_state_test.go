package sqlite

import (
	"context"
	"errors"
	"testing"

	"gorm.io/gorm"
)

// TestCatalogSeedStateEmpty proves a catalog with no seed-owned rows reports an
// empty seed state and loads successfully.
func TestCatalogSeedStateEmpty(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 5, 5, 6, 2, noneSeedTrio())

	repo := NewPropertyCatalogRepository(store)
	loaded, err := repo.Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if loaded.SeedState.HasSeed {
		t.Fatal("HasSeed = true for empty-seed catalog")
	}
}

// TestCatalogSeedStateSingleTuple proves a catalog where every seed-owned row
// shares one (seed_version, seed_source_version) tuple yields that seed state.
func TestCatalogSeedStateSingleTuple(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 5, 5, 6, 2, systemSeedTrio(2, "2.4.1"))

	repo := NewPropertyCatalogRepository(store)
	loaded, err := repo.Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !loaded.SeedState.HasSeed {
		t.Fatal("HasSeed = false for seed-owned catalog")
	}
	if loaded.SeedState.Version != 2 || loaded.SeedState.SourceVersion != "2.4.1" {
		t.Fatalf("seed state = (%d,%q), want (2,\"2.4.1\")",
			loaded.SeedState.Version, loaded.SeedState.SourceVersion)
	}
}

// TestCatalogSeedStateMixedTuplesIsCorruption proves distinct seed tuples across
// the catalog fail closed with ErrCatalogSeedStateCorrupt.
func TestCatalogSeedStateMixedTuplesIsCorruption(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 5, 5, 6, 2, systemSeedTrio(2, "2.4.1"))

	// Re-point one definition's seed version to a different tuple.
	res := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "cat.0").
		Updates(map[string]any{"seed_version": 3, "seed_source_version": "3.0.0"})
	if res.Error != nil || res.RowsAffected != 1 {
		t.Fatalf("repoint seed tuple: err=%v rows=%d", res.Error, res.RowsAffected)
	}

	repo := NewPropertyCatalogRepository(store)
	_, err := repo.Load(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedStateCorrupt) {
		t.Fatalf("Load error = %v, want ErrCatalogSeedStateCorrupt", err)
	}
}

// TestCatalogSeedStateZeroBindingsIsCorruption proves seed-owned rows with zero
// active seed-owned bindings fail closed.
func TestCatalogSeedStateZeroBindingsIsCorruption(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	// Seed-owned definitions/descriptors/terms, but bindings are user-owned.
	wsctx := buildCatalogFixture(t, store, 5, 5, 6, 2, systemSeedTrio(2, "2.4.1"))

	// Clear the seed trio on every active binding so bindings are user-owned
	// while other families keep seed provenance.
	res := store.db.WithContext(ctx).
		Model(&PropertyBindingRow{}).
		Where("workspace_id = ?", wsctx.ID.Bytes()).
		Updates(map[string]any{"seed_owner": gorm.Expr("NULL"), "seed_version": gorm.Expr("NULL"), "seed_source_version": gorm.Expr("NULL")})
	if res.Error != nil {
		t.Fatalf("clear binding seed trio: %v", res.Error)
	}
	if res.RowsAffected != 6 {
		t.Fatalf("cleared %d binding seed trios, want 6", res.RowsAffected)
	}

	repo := NewPropertyCatalogRepository(store)
	_, err := repo.Load(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedStateCorrupt) {
		t.Fatalf("Load error = %v, want ErrCatalogSeedStateCorrupt", err)
	}
}
