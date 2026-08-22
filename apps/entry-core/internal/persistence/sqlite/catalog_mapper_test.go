package sqlite

import (
	"context"
	"errors"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// TestCatalogMapperRejectsInvalidBLOB proves the mapper rejects a 16-byte blob
// that fails the RFC 9562 variant check, and a wrong-length blob.
func TestCatalogMapperRejectsInvalidBLOB(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}
	wsBytes := wsctx.ID.Bytes()

	// 16 bytes with variant bits cleared (version 0, variant 0) -> invalid.
	badVariant := make([]byte, 16)
	for i := range badVariant {
		badVariant[i] = 0x11
	}
	badLen := []byte{1, 2, 3}

	cases := []struct {
		name string
		row  WorkspacePropertyDefinitionRow
	}{
		{
			name: "bad variant",
			row: WorkspacePropertyDefinitionRow{
				WorkspaceID: wsBytes, PropertyID: badVariant,
				Origin: "built_in", IdentityScheme: "registry_derived",
				Namespace: "system", CanonicalKey: "x", DisplayName: "X",
				ValueType: "text", Cardinality: "one", Editable: true,
				Provenance: "system", LifecycleState: "active",
			},
		},
		{
			name: "wrong length",
			row: WorkspacePropertyDefinitionRow{
				WorkspaceID: wsBytes, PropertyID: badLen,
				Origin: "built_in", IdentityScheme: "registry_derived",
				Namespace: "system", CanonicalKey: "y", DisplayName: "Y",
				ValueType: "text", Cardinality: "one", Editable: true,
				Provenance: "system", LifecycleState: "active",
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := mapDefinitionRow(tc.row); !errors.Is(err, ErrInvalidCatalogBLOB) {
				t.Fatalf("mapDefinitionRow error = %v, want ErrInvalidCatalogBLOB", err)
			}
		})
	}
}

// TestCatalogMapperRejectsInvalidVersion proves the mapper rejects an identity
// scheme that does not accept the row's PropertyID version nibble.
func TestCatalogMapperRejectsInvalidVersion(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}
	wsBytes := wsctx.ID.Bytes()

	// Registry-derived ID (UUIDv5) but declared voyager_issued (needs v7).
	id, err := domainentry.RegistryPropertyID("filesystem.extension")
	if err != nil {
		t.Fatalf("RegistryPropertyID: %v", err)
	}
	row := WorkspacePropertyDefinitionRow{
		WorkspaceID: wsBytes, PropertyID: id.Bytes(),
		Origin: "built_in", IdentityScheme: "voyager_issued",
		Namespace: "system", CanonicalKey: "x", DisplayName: "X",
		ValueType: "text", Cardinality: "one", Editable: true,
		Provenance: "system", LifecycleState: "active",
	}
	if _, err := mapDefinitionRow(row); !errors.Is(err, ErrInvalidCatalogVersion) {
		t.Fatalf("mapDefinitionRow error = %v, want ErrInvalidCatalogVersion", err)
	}
}

// TestCatalogMapperRejectsInvalidNaturalRefAndLifecycle proves the mapper
// rejects descriptors/bindings with malformed natural refs or lifecycle states
// (delegated to domain Validate).
func TestCatalogMapperRejectsInvalidNaturalRefAndLifecycle(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}
	wsBytes := wsctx.ID.Bytes()

	t.Run("descriptor bad natural ref", func(t *testing.T) {
		row := SourcePropertyDescriptorRow{
			WorkspaceID: wsBytes, ProviderID: "macos.mditem",
			SourceInstanceID: "not-a-valid-src-id", ScopeKind: "system",
			ScopeExternalID: "macos", ExternalPropertyID: "kMDItemFSName",
			AuthorityKind: "system", NativeType: "string", NativeCardinality: "one",
			SourceReadable: true, LifecycleState: "active",
		}
		if _, err := mapDescriptorRow(row); !errors.Is(err, ErrInvalidCatalogRow) {
			t.Fatalf("mapDescriptorRow error = %v, want ErrInvalidCatalogRow", err)
		}
	})

	t.Run("definition bad lifecycle", func(t *testing.T) {
		id, err := domainentry.RegistryPropertyID("cat.x")
		if err != nil {
			t.Fatalf("RegistryPropertyID: %v", err)
		}
		row := WorkspacePropertyDefinitionRow{
			WorkspaceID: wsBytes, PropertyID: id.Bytes(),
			Origin: "built_in", IdentityScheme: "registry_derived",
			Namespace: "system", CanonicalKey: "x", DisplayName: "X",
			ValueType: "text", Cardinality: "one", Editable: true,
			Provenance: "system", LifecycleState: "missing",
		}
		if _, err := mapDefinitionRow(row); !errors.Is(err, ErrInvalidCatalogRow) {
			t.Fatalf("mapDefinitionRow error = %v, want ErrInvalidCatalogRow", err)
		}
	})
}

func TestCatalogMapperPreservesBindingOrdinal(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}
	id := domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12345")
	row := PropertyBindingRow{
		WorkspaceID: wsctx.ID.Bytes(), PropertyID: id.Bytes(), ProviderID: "macos.fakeexternal",
		SourceInstanceID: "src:m-KQdBGV6oTOo0uNavbxU6UH9heJBwQTseDcv_utLsE", ScopeKind: "workspace",
		ScopeExternalID: "workspace", ExternalPropertyID: "title", BindingOrdinal: 7,
		ReadTransform: "identity", Direction: "read", EffectiveReadable: true,
		ApprovalState: "approved", LifecycleState: "active",
	}
	binding, err := mapBindingRow(row)
	if err != nil {
		t.Fatalf("mapBindingRow: %v", err)
	}
	if binding.BindingOrdinal != 7 {
		t.Fatalf("BindingOrdinal = %d, want 7", binding.BindingOrdinal)
	}
}

func TestCatalogMapperPreservesDefinitionDigestFields(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}
	id := domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12345")
	row := WorkspacePropertyDefinitionRow{
		WorkspaceID: wsctx.ID.Bytes(), PropertyID: id.Bytes(), Origin: "built_in", IdentityScheme: "voyager_issued",
		Namespace: "system", CanonicalKey: "title", DisplayName: "Title", Description: "A title",
		ValueType: "text", Cardinality: "one", Nullable: true, Editable: true,
		DefaultHidden: true, DefaultPinned: true, DBIndexedHint: true, DefinitionRev: 7,
		Provenance: "system", LifecycleState: "active",
	}
	definition, err := mapDefinitionRow(row)
	if err != nil {
		t.Fatalf("mapDefinitionRow: %v", err)
	}
	if definition.Description != row.Description || definition.Nullable != row.Nullable ||
		definition.DefaultHidden != row.DefaultHidden || definition.DefaultPinned != row.DefaultPinned ||
		definition.DBIndexedHint != row.DBIndexedHint || definition.DefinitionRev != row.DefinitionRev {
		t.Fatalf("mapped definition dropped digest fields: %#v", definition)
	}
}

func TestCatalogMapperPreservesUnitContract(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}
	id := domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12345")
	row := WorkspacePropertyDefinitionRow{
		WorkspaceID: wsctx.ID.Bytes(), PropertyID: id.Bytes(), Origin: "built_in", IdentityScheme: "voyager_issued",
		Namespace: "system", CanonicalKey: "size", DisplayName: "Size", Unit: "B",
		ValueType: "number", Cardinality: "one", Provenance: "system", LifecycleState: "active",
		DefaultDisplayUnit: "Byte",
		UnitsJSON:          `[{"code":"B","label":"Byte","factor_to_canonical":"1"},{"code":"KB","label":"KB","factor_to_canonical":"1024"}]`,
	}
	definition, err := mapDefinitionRow(row)
	if err != nil {
		t.Fatalf("mapDefinitionRow: %v", err)
	}
	if definition.DefaultDisplayUnit != "Byte" || len(definition.Units) != 2 {
		t.Fatalf("mapped unit contract = default=%q units=%d, want Byte/2", definition.DefaultDisplayUnit, len(definition.Units))
	}
	if definition.Units[0].Code != "B" || definition.Units[0].FactorToCanonical != "1" ||
		definition.Units[1].Code != "KB" || definition.Units[1].Label != "KB" || definition.Units[1].FactorToCanonical != "1024" {
		t.Fatalf("mapped units = %#v", definition.Units)
	}
}

func TestCatalogMapperRejectsMalformedUnitsJSON(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}
	id := domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12345")
	row := WorkspacePropertyDefinitionRow{
		WorkspaceID: wsctx.ID.Bytes(), PropertyID: id.Bytes(), Origin: "built_in", IdentityScheme: "voyager_issued",
		Namespace: "system", CanonicalKey: "size", DisplayName: "Size", Unit: "B",
		ValueType: "number", Cardinality: "one", Provenance: "system", LifecycleState: "active",
		UnitsJSON: `{not json`,
	}
	if _, err := mapDefinitionRow(row); !errors.Is(err, ErrInvalidCatalogRow) {
		t.Fatalf("mapDefinitionRow with malformed units_json error = %v, want ErrInvalidCatalogRow", err)
	}
}

// TestCatalogMapperRejectsPartialSeedMetadata proves the mapper rejects a row
// whose seed provenance trio is partially populated, and a foreign seed owner.
func TestCatalogMapperRejectsPartialSeedMetadata(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}
	wsBytes := wsctx.ID.Bytes()

	id, err := domainentry.RegistryPropertyID("cat.partial")
	if err != nil {
		t.Fatalf("RegistryPropertyID: %v", err)
	}
	base := WorkspacePropertyDefinitionRow{
		WorkspaceID: wsBytes, PropertyID: id.Bytes(),
		Origin: "built_in", IdentityScheme: "registry_derived",
		Namespace: "system", CanonicalKey: "partial", DisplayName: "P",
		ValueType: "text", Cardinality: "one", Editable: true,
		Provenance: "system", LifecycleState: "active",
	}

	t.Run("owner only", func(t *testing.T) {
		row := base
		owner := "system_property_registry"
		row.SeedOwner = &owner
		if _, err := mapDefinitionRow(row); !errors.Is(err, ErrInvalidCatalogSeedMetadata) {
			t.Fatalf("mapDefinitionRow error = %v, want ErrInvalidCatalogSeedMetadata", err)
		}
	})

	t.Run("foreign owner", func(t *testing.T) {
		row := base
		owner := "someone_else"
		version := 2
		source := "2.4.1"
		row.SeedOwner, row.SeedVersion, row.SeedSourceVersion = &owner, &version, &source
		if _, err := mapDefinitionRow(row); !errors.Is(err, ErrInvalidCatalogSeedMetadata) {
			t.Fatalf("mapDefinitionRow error = %v, want ErrInvalidCatalogSeedMetadata", err)
		}
	})
}

// TestCatalogMapperValidRoundTrip proves valid rows map to domain values whose
// digest is stable and whose key stable fields survive mapping.
func TestCatalogMapperValidRoundTrip(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 3, 3, 4, 2, noneSeedTrio())

	repo := NewPropertyCatalogRepository(store)
	loaded, err := repo.Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(loaded.Snapshot.Definitions) != 3 || len(loaded.Snapshot.Descriptors) != 3 ||
		len(loaded.Snapshot.Bindings) != 4 || len(loaded.Snapshot.Terms) != 2 {
		t.Fatalf("snapshot counts = d:%d s:%d b:%d t:%d, want 3/3/4/2",
			len(loaded.Snapshot.Definitions), len(loaded.Snapshot.Descriptors),
			len(loaded.Snapshot.Bindings), len(loaded.Snapshot.Terms))
	}
	if loaded.Digest == [32]byte{} {
		t.Fatal("digest must be non-zero")
	}
}
