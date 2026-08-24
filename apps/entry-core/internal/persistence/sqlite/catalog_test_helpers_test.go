package sqlite

import (
	"context"
	"fmt"
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// testSourceInstanceID is a valid src:-prefixed source instance ID (47 bytes,
// 43-byte base64url digest), satisfying domainentry.SourcePropertyRef.Validate.
const testSourceInstanceID = "src:8kHitBFXUPx-VG4Qf_M3LXM1kDu4jXaGZ1JTw9cUiyY"

// catalogSeedTrio describes the seed provenance trio applied to every row in a
// fixture. A nil owner means all three columns stay NULL (user-defined rows).
type catalogSeedTrio struct {
	owner         *string
	version       *int
	sourceVersion *string
}

// systemSeedTrio returns a seed trio owned by system_property_registry.
func systemSeedTrio(version int, sourceVersion string) catalogSeedTrio {
	owner := "system_property_registry"
	return catalogSeedTrio{owner: &owner, version: &version, sourceVersion: &sourceVersion}
}

// noneSeedTrio returns a seed trio with all three columns NULL.
func noneSeedTrio() catalogSeedTrio { return catalogSeedTrio{} }

// buildCatalogFixture bootstraps the workspace identity and inserts a valid
// cross-referenced catalog with the given per-family row counts. Every active
// binding references an active definition and an active descriptor; every term
// references an active definition. All rows share the same seed trio.
func buildCatalogFixture(
	t *testing.T,
	store *Store,
	nDefs, nDescs, nBindings, nTerms int,
	seed catalogSeedTrio,
) domainentry.WorkspaceContext {
	t.Helper()
	ctx := context.Background()

	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap workspace: %v", err)
	}
	wsBytes := wsctx.ID.Bytes()

	now := time.Now()
	valueTypes := []string{"text", "number", "boolean", "date", "datetime", "select"}
	cardinalities := []string{"one", "many"}

	// 1. Definitions.
	defIDs := make([]domainentry.PropertyID, nDefs)
	defRows := make([]WorkspacePropertyDefinitionRow, 0, nDefs)
	for i := 0; i < nDefs; i++ {
		id, err := domainentry.RegistryPropertyID(fmt.Sprintf("cat.%d", i))
		if err != nil {
			t.Fatalf("RegistryPropertyID(%d): %v", i, err)
		}
		defIDs[i] = id
		unit := ""
		if i%3 == 0 {
			unit = "px"
		}
		defRows = append(defRows, WorkspacePropertyDefinitionRow{
			WorkspaceID:       wsBytes,
			PropertyID:        id.Bytes(),
			Origin:            "built_in",
			IdentityScheme:    "registry_derived",
			Namespace:         "system",
			CanonicalKey:      fmt.Sprintf("cat.%d", i),
			DisplayName:       fmt.Sprintf("Property %d", i),
			Description:       "fixture",
			ValueType:         valueTypes[i%len(valueTypes)],
			Cardinality:       cardinalities[i%len(cardinalities)],
			Nullable:          false,
			Editable:          i%2 == 0,
			DefaultHidden:     false,
			DefaultPinned:     false,
			DBIndexedHint:     false,
			Provenance:        "system",
			Unit:              unit,
			DefinitionRev:     1,
			LifecycleState:    "active",
			SeedOwner:         seed.owner,
			SeedVersion:       seed.version,
			SeedSourceVersion: seed.sourceVersion,
			CreatedAt:         now,
			UpdatedAt:         now,
		})
	}
	if len(defRows) > 0 {
		if err := store.db.WithContext(ctx).Create(&defRows).Error; err != nil {
			t.Fatalf("insert definitions: %v", err)
		}
	}

	// 2. Descriptors.
	descRows := make([]SourcePropertyDescriptorRow, 0, nDescs)
	for i := 0; i < nDescs; i++ {
		descRows = append(descRows, SourcePropertyDescriptorRow{
			WorkspaceID:        wsBytes,
			ProviderID:         "macos.mditem",
			SourceInstanceID:   testSourceInstanceID,
			ScopeKind:          "system",
			ScopeExternalID:    "macos",
			ExternalPropertyID: fmt.Sprintf("kMDItem%04d", i),
			AuthorityKind:      "system",
			NativeType:         "string",
			NativeCardinality:  "one",
			SourceReadable:     true,
			SourceQueryable:    true,
			SourceWritable:     false,
			LifecycleState:     "active",
			AvailabilityNote:   "",
			SeedOwner:          seed.owner,
			SeedVersion:        seed.version,
			SeedSourceVersion:  seed.sourceVersion,
			CreatedAt:          now,
			UpdatedAt:          now,
		})
	}
	if len(descRows) > 0 {
		if err := store.db.WithContext(ctx).Create(&descRows).Error; err != nil {
			t.Fatalf("insert descriptors: %v", err)
		}
	}

	// 3. Bindings. b -> (property defIDs[b % nDefs], descriptor (b + b/nDefs) % nDescs)
	// so every (property, ref) pair is unique while all refs exist.
	bindingRows := make([]PropertyBindingRow, 0, nBindings)
	for b := 0; b < nBindings; b++ {
		di := b % nDefs
		sci := (b + b/nDefs) % nDescs
		bindingRows = append(bindingRows, PropertyBindingRow{
			WorkspaceID:        wsBytes,
			PropertyID:         defIDs[di].Bytes(),
			ProviderID:         "macos.mditem",
			SourceInstanceID:   testSourceInstanceID,
			ScopeKind:          "system",
			ScopeExternalID:    "macos",
			ExternalPropertyID: fmt.Sprintf("kMDItem%04d", sci),
			BindingOrdinal:     b,
			ReadTransform:      "identity",
			Direction:          "read",
			EffectiveReadable:  true,
			EffectiveQueryable: true,
			EffectiveWritable:  false,
			QueryProfile:       "mdquery_identity",
			MappingVersion:     1,
			ValueContractRev:   1,
			MappingProvenance:  "system_property_registry@2.4.1",
			ApprovalState:      "approved",
			Lossiness:          "none",
			LifecycleState:     "active",
			SeedOwner:          seed.owner,
			SeedVersion:        seed.version,
			SeedSourceVersion:  seed.sourceVersion,
			CreatedAt:          now,
			UpdatedAt:          now,
		})
	}
	if len(bindingRows) > 0 {
		if err := store.db.WithContext(ctx).Create(&bindingRows).Error; err != nil {
			t.Fatalf("insert bindings: %v", err)
		}
	}

	// 4. Terms for active definitions 0..nTerms-1.
	termRows := make([]WorkspacePropertyTermRow, 0, nTerms)
	for i := 0; i < nTerms; i++ {
		termRows = append(termRows, WorkspacePropertyTermRow{
			WorkspaceID:       wsBytes,
			PropertyID:        defIDs[i].Bytes(),
			TermKind:          "search_alias",
			Ordinal:           0,
			TermValue:         fmt.Sprintf("alias-%d", i),
			LifecycleState:    "active",
			SeedOwner:         seed.owner,
			SeedVersion:       seed.version,
			SeedSourceVersion: seed.sourceVersion,
		})
	}
	if len(termRows) > 0 {
		if err := store.db.WithContext(ctx).Create(&termRows).Error; err != nil {
			t.Fatalf("insert terms: %v", err)
		}
	}

	return wsctx
}

// mutateDefinitionDisplayName changes one active definition's display name in
// place, producing a same-count but different logical catalog.
func mutateDefinitionDisplayName(t *testing.T, store *Store, wsctx domainentry.WorkspaceContext, canonicalKey, newName string) {
	t.Helper()
	res := store.db.WithContext(context.Background()).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), canonicalKey).
		Update("display_name", newName)
	if res.Error != nil {
		t.Fatalf("update display_name: %v", res.Error)
	}
	if res.RowsAffected != 1 {
		t.Fatalf("update display_name affected %d rows, want 1", res.RowsAffected)
	}
}

func ptrInt(value int) *int { return &value }
