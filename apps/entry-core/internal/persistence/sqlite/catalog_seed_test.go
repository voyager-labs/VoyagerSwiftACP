package sqlite

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite/seeds"
)

// TestCatalogSeed is the plan-documented entry point; it runs the full
// transactional seed state-machine and tombstone-reconciliation coverage.
func TestCatalogSeed(t *testing.T) {
	t.Run("Fresh", TestCatalogSeedFresh)
	t.Run("OlderUpgrade", TestCatalogSeedOlderUpgrade)
	t.Run("SameVersionNoOp", TestCatalogSeedSameVersionNoOp)
	t.Run("SameVersionDriftFailsClosed", TestCatalogSeedSameVersionDriftFailsClosed)
	t.Run("MixedFailsClosed", TestCatalogSeedMixedFailsClosed)
	t.Run("NewerFailsClosed", TestCatalogSeedNewerFailsClosed)
	t.Run("PartialFailsClosed", TestCatalogSeedPartialFailsClosed)
	t.Run("RemovalsTombstone", TestCatalogSeedRemovalsTombstone)
	t.Run("RemovedTermTombstone", TestCatalogSeedRemovedTermTombstone)
	t.Run("PreservesNonSeed", TestCatalogSeedPreservesNonSeed)
	t.Run("TamperedHashFailsBeforeWrite", TestCatalogSeedTamperedHashFailsBeforeWrite)
	t.Run("PartialSQLRollback", TestCatalogSeedPartialSQLRollback)
	t.Run("FullyTombstonedFailsClosed", TestCatalogSeedFullyTombstonedFailsClosed)
	t.Run("MarkerBlocksDeletedFamilies", TestCatalogSeedMarkerBlocksDeletedFamilies)
	t.Run("MarkerMismatchFailsClosed", TestCatalogSeedMarkerMismatchFailsClosed)
	t.Run("SecondOpenRejected", TestCatalogSeedSecondOpenRejected)
	t.Run("ConcurrentSerialized", TestCatalogSeedConcurrentSerialized)
	t.Run("ProviderOwnedCollisionFailsClosed", TestCatalogSeedApplyFailsClosedOnProviderOwnedCollision)
}

// seedCatalogCounts are the committed fresh seed row counts.
type seedCatalogCounts struct {
	definitions int
	descriptors int
	bindings    int
	terms       int
}

func freshSeedCounts() seedCatalogCounts {
	meta := seeds.Current()
	return seedCatalogCounts{
		definitions: meta.DefinitionCount,
		descriptors: meta.DescriptorCount,
		bindings:    meta.BindingCount,
		terms:       meta.TermCount,
	}
}

// assertLoadedCatalogCounts loads the workspace catalog and asserts the exact
// per-family counts and that the digest equals the committed dataset digest.
func assertLoadedCatalogCounts(t *testing.T, store *Store, wsctx domainentry.WorkspaceContext, want seedCatalogCounts) {
	t.Helper()
	repo := NewPropertyCatalogRepository(store)
	loaded, err := repo.Load(context.Background(), wsctx)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if got := len(loaded.Snapshot.Definitions); got != want.definitions {
		t.Fatalf("definitions = %d, want %d", got, want.definitions)
	}
	if got := len(loaded.Snapshot.Descriptors); got != want.descriptors {
		t.Fatalf("descriptors = %d, want %d", got, want.descriptors)
	}
	if got := len(loaded.Snapshot.Bindings); got != want.bindings {
		t.Fatalf("bindings = %d, want %d", got, want.bindings)
	}
	if got := len(loaded.Snapshot.Terms); got != want.terms {
		t.Fatalf("terms = %d, want %d", got, want.terms)
	}
	if !loaded.SeedState.HasSeed {
		t.Fatal("SeedState.HasSeed = false after apply")
	}
	if loaded.SeedState.Version != 1 || loaded.SeedState.SourceVersion != "2.4.1" {
		t.Fatalf("seed state = (%d,%q), want (1,\"2.4.1\")",
			loaded.SeedState.Version, loaded.SeedState.SourceVersion)
	}
	// The full-catalog digest equals the committed dataset digest ONLY when the
	// catalog is exactly the fresh seed (no preserved user rows); otherwise user
	// rows are legitimately part of the full digest and the seed digest is
	// asserted separately via assertSeedDigestMatches.
	if want == freshSeedCounts() {
		meta := seeds.Current()
		if hexEncode(loaded.Digest[:]) != meta.DatasetSHA256 {
			t.Fatalf("read-back digest %s != committed dataset digest %s",
				hexEncode(loaded.Digest[:]), meta.DatasetSHA256)
		}
	}
}

// assertSeedDigestMatches verifies the seed-owned active subset's digest equals
// the committed dataset digest, independent of preserved user rows.
func assertSeedDigestMatches(t *testing.T, store *Store, wsctx domainentry.WorkspaceContext) {
	t.Helper()
	ctx := context.Background()
	defs, descs, binds, terms, err := loadSeedRows(store.db.WithContext(ctx), wsctx)
	if err != nil {
		t.Fatalf("loadSeedRows: %v", err)
	}
	snapshot, err := assembleSnapshot(defs, descs, binds, terms)
	if err != nil {
		t.Fatalf("assemble seed snapshot: %v", err)
	}
	digest, err := catalogDigest(snapshot)
	if err != nil {
		t.Fatalf("seed digest: %v", err)
	}
	meta := seeds.Current()
	if hexEncode(digest[:]) != meta.DatasetSHA256 {
		t.Fatalf("seed-only digest %s != committed dataset digest %s",
			hexEncode(digest[:]), meta.DatasetSHA256)
	}
}

// assertRawActiveCounts counts active rows per family directly from the store,
// without mapping or seed-state validation, for fail-closed tests where Load
// would itself reject the injected corruption state.
func assertRawActiveCounts(t *testing.T, store *Store, wsctx domainentry.WorkspaceContext, want seedCatalogCounts) {
	t.Helper()
	ctx := context.Background()
	wsBytes := wsctx.ID.Bytes()
	var defs, descs, binds, terms int64
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND lifecycle_state = ?", wsBytes, "active").Count(&defs).Error; err != nil {
		t.Fatalf("count active defs: %v", err)
	}
	if err := store.db.WithContext(ctx).Model(&SourcePropertyDescriptorRow{}).
		Where("workspace_id = ? AND lifecycle_state = ?", wsBytes, "active").Count(&descs).Error; err != nil {
		t.Fatalf("count active descs: %v", err)
	}
	if err := store.db.WithContext(ctx).Model(&PropertyBindingRow{}).
		Where("workspace_id = ? AND lifecycle_state = ?", wsBytes, "active").Count(&binds).Error; err != nil {
		t.Fatalf("count active bindings: %v", err)
	}
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyTermRow{}).
		Where("workspace_id = ? AND lifecycle_state = ? AND property_id IN (SELECT property_id FROM workspace_property_definitions WHERE workspace_id = ? AND lifecycle_state = ?)", wsBytes, "active", wsBytes, "active").
		Count(&terms).Error; err != nil {
		t.Fatalf("count active terms: %v", err)
	}
	if int(defs) != want.definitions {
		t.Fatalf("active definitions = %d, want %d", defs, want.definitions)
	}
	if int(descs) != want.descriptors {
		t.Fatalf("active descriptors = %d, want %d", descs, want.descriptors)
	}
	if int(binds) != want.bindings {
		t.Fatalf("active bindings = %d, want %d", binds, want.bindings)
	}
	if int(terms) != want.terms {
		t.Fatalf("active terms = %d, want %d", terms, want.terms)
	}
}

// insertUserRows inserts one NULL-seed (user/provider-owned) definition,
// descriptor, binding, and term into the given workspace so tests can prove the
// apply leaves non-seed rows untouched.
func insertUserRows(t *testing.T, store *Store, wsctx domainentry.WorkspaceContext) {
	t.Helper()
	ctx := context.Background()
	wsBytes := wsctx.ID.Bytes()
	now := time.Now()

	// UUIDv7 (version nibble 7) for a voyager_issued user-defined property.
	id := domainentry.MustPropertyID("018f8d40-ff1b-7b80-8b2a-1c2e3d4f5a6b")
	def := WorkspacePropertyDefinitionRow{
		WorkspaceID:       wsBytes,
		PropertyID:        id.Bytes(),
		Origin:            "user_defined",
		IdentityScheme:    "voyager_issued",
		Namespace:         "user",
		CanonicalKey:      "user.custom_prop",
		DisplayName:       "User Property",
		Description:       "user row",
		ValueType:         "text",
		Cardinality:       "one",
		Nullable:          true,
		Editable:          true,
		DefaultHidden:     false,
		DefaultPinned:     false,
		DBIndexedHint:     false,
		Provenance:        "user_defined",
		Unit:              "",
		DefinitionRev:     1,
		LifecycleState:    "active",
		SeedOwner:         nil,
		SeedVersion:       nil,
		SeedSourceVersion: nil,
		CreatedAt:         now,
		UpdatedAt:         now,
	}
	if err := store.db.WithContext(ctx).Create(&def).Error; err != nil {
		t.Fatalf("insert user definition: %v", err)
	}

	desc := SourcePropertyDescriptorRow{
		WorkspaceID:        wsBytes,
		ProviderID:         "user.provider",
		SourceInstanceID:   testSourceInstanceID,
		ScopeKind:          "system",
		ScopeExternalID:    "user",
		ExternalPropertyID: "userNative",
		AuthorityKind:      "provider",
		NativeType:         "string",
		NativeCardinality:  "one",
		SourceReadable:     true,
		SourceQueryable:    true,
		SourceWritable:     false,
		LifecycleState:     "active",
		AvailabilityNote:   "",
		SeedOwner:          nil,
		SeedVersion:        nil,
		SeedSourceVersion:  nil,
		CreatedAt:          now,
		UpdatedAt:          now,
	}
	if err := store.db.WithContext(ctx).Create(&desc).Error; err != nil {
		t.Fatalf("insert user descriptor: %v", err)
	}

	binding := PropertyBindingRow{
		WorkspaceID:        wsBytes,
		PropertyID:         id.Bytes(),
		ProviderID:         "user.provider",
		SourceInstanceID:   testSourceInstanceID,
		ScopeKind:          "system",
		ScopeExternalID:    "user",
		ExternalPropertyID: "userNative",
		BindingOrdinal:     0,
		ReadTransform:      "identity",
		Direction:          "read",
		EffectiveReadable:  true,
		EffectiveQueryable: true,
		EffectiveWritable:  false,
		QueryProfile:       "identity",
		MappingVersion:     1,
		ValueContractRev:   1,
		MappingProvenance:  "user",
		ApprovalState:      "approved",
		Lossiness:          "none",
		LifecycleState:     "active",
		SeedOwner:          nil,
		SeedVersion:        nil,
		SeedSourceVersion:  nil,
		CreatedAt:          now,
		UpdatedAt:          now,
	}
	if err := store.db.WithContext(ctx).Create(&binding).Error; err != nil {
		t.Fatalf("insert user binding: %v", err)
	}

	term := WorkspacePropertyTermRow{
		WorkspaceID:       wsBytes,
		PropertyID:        id.Bytes(),
		TermKind:          "search_alias",
		Ordinal:           0,
		TermValue:         "user-alias",
		LifecycleState:    "active",
		SeedOwner:         nil,
		SeedVersion:       nil,
		SeedSourceVersion: nil,
	}
	if err := store.db.WithContext(ctx).Create(&term).Error; err != nil {
		t.Fatalf("insert user term: %v", err)
	}
}

// TestCatalogSeedFresh proves a catalog with no seed-owned rows applies the
// full embedded seed and ends with exact fresh counts, digest, and seed state.
func TestCatalogSeedFresh(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio()) // bootstrap only

	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("ApplyCatalogSeed: %v", err)
	}
	assertLoadedCatalogCounts(t, store, wsctx, freshSeedCounts())
}

// TestCatalogSeedPreservesUnitContract proves the full unit_spec (canonical
// unit, default display unit, and the units conversion table) survives the
// seed apply and is restored from the workspace catalog by Load — so the daemon
// never needs the Registry JSON at runtime to reproduce misc.size display units.
func TestCatalogSeedPreservesUnitContract(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())

	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("ApplyCatalogSeed: %v", err)
	}
	repo := NewPropertyCatalogRepository(store)
	loaded, err := repo.Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	for _, def := range loaded.Snapshot.Definitions {
		if def.CanonicalKey != "misc.size" {
			continue
		}
		if def.Unit == nil || *def.Unit != "B" {
			t.Fatalf("misc.size canonical unit = %v, want B", def.Unit)
		}
		if def.DefaultDisplayUnit != "Byte" {
			t.Fatalf("misc.size default display unit = %q, want Byte", def.DefaultDisplayUnit)
		}
		want := []domainentry.PropertyUnit{
			{Code: "B", Label: "Byte", FactorToCanonical: "1"},
			{Code: "KB", Label: "KB", FactorToCanonical: "1024"},
			{Code: "MB", Label: "MB", FactorToCanonical: "1048576"},
			{Code: "GB", Label: "GB", FactorToCanonical: "1073741824"},
		}
		if len(def.Units) != len(want) {
			t.Fatalf("misc.size units = %d, want %d", len(def.Units), len(want))
		}
		for index := range want {
			if def.Units[index] != want[index] {
				t.Fatalf("misc.size unit[%d] = %#v, want %#v", index, def.Units[index], want[index])
			}
		}
		return
	}
	t.Fatal("misc.size definition not found in loaded catalog")
}

// TestCatalogSeedOlderUpgrade proves a catalog carrying one older consistent
// seed tuple applies the current seed and upgrades every seed-owned row to the
// current tuple, leaving the fresh dataset.
func TestCatalogSeedOlderUpgrade(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	// Older consistent seed-owned catalog (seed_version 0, registry 2.3.0).
	wsctx := buildCatalogFixture(t, store, 3, 3, 4, 2, systemSeedTrio(0, "2.3.0"))

	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("ApplyCatalogSeed: %v", err)
	}
	assertLoadedCatalogCounts(t, store, wsctx, freshSeedCounts())

	// Every remaining ACTIVE seed-owned row now carries the current tuple.
	var defs []WorkspacePropertyDefinitionRow
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?", wsctx.ID.Bytes(), "system_property_registry", "active").
		Find(&defs).Error; err != nil {
		t.Fatalf("read seed defs: %v", err)
	}
	for _, d := range defs {
		if d.SeedVersion == nil || *d.SeedVersion != 1 || d.SeedSourceVersion == nil || *d.SeedSourceVersion != "2.4.1" {
			t.Fatalf("seed definition not upgraded: version=%v source=%q",
				d.SeedVersion, derefStr(d.SeedSourceVersion))
		}
	}
}

// TestCatalogSeedSameVersionNoOp proves a second apply of the same seed version
// with a matching digest performs NO write: seed-owned timestamps and the
// connection change counter are unchanged.
func TestCatalogSeedSameVersionNoOp(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}

	// Snapshot one seed-owned row's updated_at.
	var updatedAt time.Time
	if err := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND seed_owner = ?", wsctx.ID.Bytes(), "system_property_registry").
		Order("property_id").Limit(1).
		Pluck("updated_at", &updatedAt).Error; err != nil {
		t.Fatalf("read updated_at: %v", err)
	}

	// Connection change counter before the no-op.
	var changesBefore int
	if err := store.SQLDB().QueryRowContext(ctx, "SELECT total_changes()").Scan(&changesBefore); err != nil {
		t.Fatalf("total_changes before: %v", err)
	}

	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("second ApplyCatalogSeed: %v", err)
	}

	var changesAfter int
	if err := store.SQLDB().QueryRowContext(ctx, "SELECT total_changes()").Scan(&changesAfter); err != nil {
		t.Fatalf("total_changes after: %v", err)
	}
	if changesAfter != changesBefore {
		t.Fatalf("no-op performed %d writes (total_changes %d -> %d)",
			changesAfter-changesBefore, changesBefore, changesAfter)
	}

	var updatedAtAfter time.Time
	if err := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND seed_owner = ?", wsctx.ID.Bytes(), "system_property_registry").
		Order("property_id").Limit(1).
		Pluck("updated_at", &updatedAtAfter).Error; err != nil {
		t.Fatalf("read updated_at after: %v", err)
	}
	if !updatedAtAfter.Equal(updatedAt) {
		t.Fatalf("seed-owned updated_at changed on no-op: %v -> %v", updatedAt, updatedAtAfter)
	}
}

// TestCatalogSeedSameVersionDriftFailsClosed proves that at the same seed
// version a digest mismatch (drift) fails closed WITHOUT auto-repair: the
// drifted row is left untouched.
func TestCatalogSeedSameVersionDriftFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}

	// Introduce same-version drift: rename one seed-owned alias at the current
	// tuple -> active catalog digest no longer matches the committed dataset.
	drifted := "Drifted Alias"
	mutateDefinitionDisplayName(t, store, wsctx, "audio.apple_loop_descriptors", drifted)

	err := store.ApplyCatalogSeed(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedDigest) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedDigest", err)
	}

	// Fail closed: no auto-repair — the drifted row is unchanged.
	var name string
	if err := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "audio.apple_loop_descriptors").
		Pluck("display_name", &name).Error; err != nil {
		t.Fatalf("read drifted name: %v", err)
	}
	if name != drifted {
		t.Fatalf("drift was auto-repaired: display_name = %q, want untouched %q", name, drifted)
	}
}

// TestCatalogSeedUnitDriftFailsClosed proves same-version drift on the
// definition unit contract columns (default_display_unit / units_json) fails
// closed with ErrCatalogSeedDigest, so a tampered unit table cannot silently
// pass startup verification.
func TestCatalogSeedUnitDriftFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}

	// Tamper the default display unit of one seed-owned definition to a value
	// that is still valid (matches a declared misc.size unit code) but differs
	// from the committed seed, so the mapped snapshot remains valid and the
	// digest-mismatch path is exercised.
	res := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "misc.size").
		Update("default_display_unit", "MB")
	if res.Error != nil || res.RowsAffected != 1 {
		t.Fatalf("tamper default_display_unit: err=%v rows=%d", res.Error, res.RowsAffected)
	}

	err := store.ApplyCatalogSeed(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedDigest) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedDigest", err)
	}

	// Fail closed: the tampered value is not auto-repaired.
	var got string
	if err := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "misc.size").
		Pluck("default_display_unit", &got).Error; err != nil {
		t.Fatalf("read tampered value: %v", err)
	}
	if got != "MB" {
		t.Fatalf("drift was auto-repaired: default_display_unit = %q, want untouched MB", got)
	}
}

// TestCatalogSeedProvenanceDriftFailsClosed proves same-version drift on the
// persisted definition provenance string fails closed with ErrCatalogSeedDigest
// even though the seed-owned enum provenance is a constant: MappingProvenance
// carries the verbatim column into the dataset digest.
func TestCatalogSeedProvenanceDriftFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}

	res := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "misc.size").
		Update("provenance", "system_property_registry@9.9.9-drifted")
	if res.Error != nil || res.RowsAffected != 1 {
		t.Fatalf("tamper provenance: err=%v rows=%d", res.Error, res.RowsAffected)
	}

	err := store.ApplyCatalogSeed(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedDigest) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedDigest", err)
	}

	var got string
	if err := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "misc.size").
		Pluck("provenance", &got).Error; err != nil {
		t.Fatalf("read tampered value: %v", err)
	}
	if got != "system_property_registry@9.9.9-drifted" {
		t.Fatalf("drift was auto-repaired: provenance = %q, want untouched drifted value", got)
	}
}

// TestCatalogSeedFullyTombstonedFailsClosed proves a catalog whose current
// seed-owned definition, descriptor, binding, and term rows are ALL tombstoned
// is rejected as corruption instead of being misread as fresh and silently
// reactivated through the seed SQL ON CONFLICT path.
func TestCatalogSeedFullyTombstonedFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}

	// Corrupt every seed-owned family to tombstoned at the current tuple.
	wsBytes := wsctx.ID.Bytes()
	for _, family := range []any{
		&WorkspacePropertyDefinitionRow{},
		&SourcePropertyDescriptorRow{},
		&PropertyBindingRow{},
		&WorkspacePropertyTermRow{},
	} {
		res := store.db.WithContext(ctx).Model(family).
			Where("workspace_id = ? AND seed_owner = ?", wsBytes, "system_property_registry").
			Update("lifecycle_state", "tombstoned")
		if res.Error != nil || res.RowsAffected == 0 {
			t.Fatalf("tombstone %T: err=%v rows=%d", family, res.Error, res.RowsAffected)
		}
	}

	err := store.ApplyCatalogSeed(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedStateCorrupt) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedStateCorrupt", err)
	}

	// Fail closed: no row was reactivated by a re-apply.
	var activeDefs, activeTerms int64
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?", wsBytes, "system_property_registry", "active").
		Count(&activeDefs).Error; err != nil {
		t.Fatalf("count active defs: %v", err)
	}
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyTermRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?", wsBytes, "system_property_registry", "active").
		Count(&activeTerms).Error; err != nil {
		t.Fatalf("count active terms: %v", err)
	}
	if activeDefs != 0 || activeTerms != 0 {
		t.Fatalf("corruption auto-repaired: active defs=%d terms=%d, want 0/0", activeDefs, activeTerms)
	}
}

// TestCatalogSeedMarkerBlocksDeletedFamilies는 workspace_metadata의 시드 적용
// 마커가 seed-owned 카탈로그의 물리 삭제를 corrupt로 판정함을 증명한다. 마커가
// 무장된 상태에서 active seed 집합이 비어 있으면 fresh로 재분류되어 시드 SQL을
// 재실행할 수 없다. 마커 이전 DB가 no-op 재조정 경로로 마커를 무장함도 함께
// 증명한다.
func TestCatalogSeedMarkerBlocksDeletedFamilies(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}

	readMarker := func() (int, string) {
		t.Helper()
		var row WorkspaceMetadataRow
		if err := store.db.WithContext(ctx).Where("singleton = ?", 1).First(&row).Error; err != nil {
			t.Fatalf("read workspace_metadata: %v", err)
		}
		if row.CatalogSeedOrdinal == nil || row.CatalogSeedSourceVersion == nil {
			t.Fatalf("seed marker not armed after apply: ordinal=%v source=%v", row.CatalogSeedOrdinal, row.CatalogSeedSourceVersion)
		}
		return *row.CatalogSeedOrdinal, *row.CatalogSeedSourceVersion
	}

	// fresh 적용은 적용된 튜플로 마커를 무장한다.
	if ordinal, source := readMarker(); ordinal != 1 || source != "2.4.1" {
		t.Fatalf("armed marker = (%d,%q), want (1,\"2.4.1\")", ordinal, source)
	}

	// 마커 컬럼이 NULL인 0006 이전 DB를 시뮬레이션한다. 데이터가 온전하면
	// no-op 재조정이 재적용 없이 마커를 무장해야 한다.
	if err := store.db.WithContext(ctx).Model(&WorkspaceMetadataRow{}).
		Where("singleton = ?", 1).
		Updates(map[string]any{"catalog_seed_ordinal": nil, "catalog_seed_source_version": nil}).Error; err != nil {
		t.Fatalf("clear marker: %v", err)
	}
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("no-op ApplyCatalogSeed after marker clear: %v", err)
	}
	readMarker()

	// 네 family의 seed-owned row를 전부 물리 삭제한다. FK 제약이 있으므로
	// 자식(terms, bindings)부터 삭제한다. 마커가 무장된 상태면 반드시 corrupt로
	// 실패 닫기하며 절대 재적용하지 않는다.
	wsBytes := wsctx.ID.Bytes()
	for _, family := range []any{
		&WorkspacePropertyTermRow{},
		&PropertyBindingRow{},
		&SourcePropertyDescriptorRow{},
		&WorkspacePropertyDefinitionRow{},
	} {
		res := store.db.WithContext(ctx).Where("workspace_id = ? AND seed_owner = ?", wsBytes, "system_property_registry").Delete(family)
		if res.Error != nil || res.RowsAffected == 0 {
			t.Fatalf("delete %T: err=%v rows=%d", family, res.Error, res.RowsAffected)
		}
	}

	if err := store.ApplyCatalogSeed(ctx, wsctx); !errors.Is(err, ErrCatalogSeedStateCorrupt) {
		t.Fatalf("ApplyCatalogSeed after wipe error = %v, want ErrCatalogSeedStateCorrupt", err)
	}

	// 실패 닫기: 재적용으로 어떤 seed row도 되살아나지 않는다.
	var activeDefs int64
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND seed_owner = ?", wsBytes, "system_property_registry").
		Count(&activeDefs).Error; err != nil {
		t.Fatalf("count seed defs after wipe: %v", err)
	}
	if activeDefs != 0 {
		t.Fatalf("wipe auto-repaired: active seed definitions = %d, want 0", activeDefs)
	}
}

// TestCatalogSeedMarkerMismatchFailsClosed는 무장된 마커가 활성 seed 튜플과도
// 메타데이터와도 불일치할 때(더 높은 ordinal, drift source version, 부분
// 기록) 재조정이 마커를 현재 tuple로 덮어써 증거를 지우지 못하게 함을
// 증명한다. 정상 no-op 경로는 회복 후에도 유지된다.
func TestCatalogSeedMarkerMismatchFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}
	wsBytes := wsctx.ID.Bytes()
	wantDefs := freshSeedCounts().definitions

	readMarker := func() (*int, *string) {
		t.Helper()
		var row WorkspaceMetadataRow
		if err := store.db.WithContext(ctx).Where("singleton = ?", 1).First(&row).Error; err != nil {
			t.Fatalf("read workspace_metadata: %v", err)
		}
		return row.CatalogSeedOrdinal, row.CatalogSeedSourceVersion
	}
	setMarker := func(ordinal *int, source *string) {
		t.Helper()
		if err := store.db.WithContext(ctx).Model(&WorkspaceMetadataRow{}).
			Where("singleton = ?", 1).
			Updates(map[string]any{"catalog_seed_ordinal": ordinal, "catalog_seed_source_version": source}).Error; err != nil {
			t.Fatalf("set marker: %v", err)
		}
	}

	for _, tc := range []struct {
		name    string
		ordinal *int
		source  *string
	}{
		{name: "newer ordinal", ordinal: ptrInt(2), source: ptrString("2.4.1")},
		{name: "same ordinal drifted source", ordinal: ptrInt(1), source: ptrString("2.4.2")},
		{name: "partial ordinal only", ordinal: ptrInt(1), source: nil},
		{name: "partial source only", ordinal: nil, source: ptrString("2.4.1")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			setMarker(tc.ordinal, tc.source)

			if err := store.ApplyCatalogSeed(ctx, wsctx); !errors.Is(err, ErrCatalogSeedStateCorrupt) {
				t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedStateCorrupt", err)
			}
			gotOrdinal, gotSource := readMarker()
			if (gotOrdinal == nil) != (tc.ordinal == nil) || (gotOrdinal != nil && *gotOrdinal != *tc.ordinal) ||
				(gotSource == nil) != (tc.source == nil) || (gotSource != nil && *gotSource != *tc.source) {
				t.Fatalf("marker overwritten to (%v,%v), want preserved (%v,%v)",
					gotOrdinal, gotSource, tc.ordinal, tc.source)
			}
			var activeDefs int64
			if err := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
				Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?", wsBytes, "system_property_registry", "active").
				Count(&activeDefs).Error; err != nil {
				t.Fatalf("count active defs: %v", err)
			}
			if int(activeDefs) != wantDefs {
				t.Fatalf("active seed definitions = %d, want %d", activeDefs, wantDefs)
			}
		})
	}

	// 올바른 튜플 복원 후에는 정상 no-op으로 회복한다.
	setMarker(ptrInt(1), ptrString("2.4.1"))
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("recovered ApplyCatalogSeed: %v", err)
	}
}

func ptrString(value string) *string { return &value }

// TestCatalogSeedHistoricalNewerTupleFailsClosed proves an empty active seed
// set whose only history carries a NEWER seed ordinal is rejected as seed
// state, not misclassified as fresh and silently reactivated.
func TestCatalogSeedHistoricalNewerTupleFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}
	wsBytes := wsctx.ID.Bytes()
	for _, family := range []any{
		&WorkspacePropertyDefinitionRow{},
		&SourcePropertyDescriptorRow{},
		&PropertyBindingRow{},
		&WorkspacePropertyTermRow{},
	} {
		res := store.db.WithContext(ctx).Model(family).
			Where("workspace_id = ? AND seed_owner = ?", wsBytes, "system_property_registry").
			Updates(map[string]any{"lifecycle_state": "tombstoned", "seed_version": 2})
		if res.Error != nil || res.RowsAffected == 0 {
			t.Fatalf("retuple %T: err=%v rows=%d", family, res.Error, res.RowsAffected)
		}
	}

	err := store.ApplyCatalogSeed(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedState) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedState", err)
	}
	var active int64
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?", wsBytes, "system_property_registry", "active").
		Count(&active).Error; err != nil {
		t.Fatalf("count active defs: %v", err)
	}
	if active != 0 {
		t.Fatalf("newer-tuple history auto-reactivated: %d active defs", active)
	}
}

// TestCatalogSeedHistoricalSourceVersionDriftFailsClosed proves an empty
// active seed set whose history carries the same ordinal under a different
// registry source version is rejected as drift instead of a fresh apply.
func TestCatalogSeedHistoricalSourceVersionDriftFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}
	wsBytes := wsctx.ID.Bytes()
	for _, family := range []any{
		&WorkspacePropertyDefinitionRow{},
		&SourcePropertyDescriptorRow{},
		&PropertyBindingRow{},
		&WorkspacePropertyTermRow{},
	} {
		res := store.db.WithContext(ctx).Model(family).
			Where("workspace_id = ? AND seed_owner = ?", wsBytes, "system_property_registry").
			Updates(map[string]any{"lifecycle_state": "tombstoned", "seed_source_version": "9.9.9"})
		if res.Error != nil || res.RowsAffected == 0 {
			t.Fatalf("retuple %T: err=%v rows=%d", family, res.Error, res.RowsAffected)
		}
	}

	err := store.ApplyCatalogSeed(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedState) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedState", err)
	}
	var active int64
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyTermRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?", wsBytes, "system_property_registry", "active").
		Count(&active).Error; err != nil {
		t.Fatalf("count active terms: %v", err)
	}
	if active != 0 {
		t.Fatalf("source-version drift auto-reactivated: %d active terms", active)
	}
}

// TestCatalogSeedPartiallyTombstonedTermsFailClosed proves the sibling
// mixed-history case: current-tuple terms tombstoned while the other families
// stay active keep HasSeed=true, so the digest drift path refuses the apply.
func TestCatalogSeedPartiallyTombstonedTermsFailClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}

	res := store.db.WithContext(ctx).Model(&WorkspacePropertyTermRow{}).
		Where("workspace_id = ? AND seed_owner = ?", wsctx.ID.Bytes(), "system_property_registry").
		Update("lifecycle_state", "tombstoned")
	if res.Error != nil || res.RowsAffected == 0 {
		t.Fatalf("tombstone terms: err=%v rows=%d", res.Error, res.RowsAffected)
	}

	err := store.ApplyCatalogSeed(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedDigest) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedDigest", err)
	}

	var activeTerms int64
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyTermRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?", wsctx.ID.Bytes(), "system_property_registry", "active").
		Count(&activeTerms).Error; err != nil {
		t.Fatalf("count active terms: %v", err)
	}
	if activeTerms != 0 {
		t.Fatalf("corruption auto-repaired: active terms=%d, want 0", activeTerms)
	}
}

// TestCatalogSeedMixedFailsClosed proves mixed seed tuples fail closed before
// any mutation.
func TestCatalogSeedMixedFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 3, 3, 4, 2, systemSeedTrio(1, "2.4.1"))

	// Re-point one seed-owned definition to a different tuple -> mixed.
	res := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "cat.0").
		Updates(map[string]any{"seed_version": 2, "seed_source_version": "3.0.0"})
	if res.Error != nil || res.RowsAffected != 1 {
		t.Fatalf("repoint seed tuple: err=%v rows=%d", res.Error, res.RowsAffected)
	}

	err := store.ApplyCatalogSeed(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedStateCorrupt) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedStateCorrupt", err)
	}

	// No mutation: catalog still the small fixture, not the 1309-row seed.
	assertRawActiveCounts(t, store, wsctx, seedCatalogCounts{3, 3, 4, 2})
}

// TestCatalogSeedNewerFailsClosed proves a catalog carrying a NEWER seed tuple
// than this binary's embedded seed fails closed WITHOUT executing the SQL.
func TestCatalogSeedNewerFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	// Newer consistent tuple (version 2 > embedded 1).
	wsctx := buildCatalogFixture(t, store, 3, 3, 4, 2, systemSeedTrio(2, "3.0.0"))

	err := store.ApplyCatalogSeed(ctx, wsctx)
	if !errors.Is(err, ErrCatalogSeedState) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedState", err)
	}

	// No SQL executed: the catalog is still the small fixture.
	assertRawActiveCounts(t, store, wsctx, seedCatalogCounts{3, 3, 4, 2})
}

// TestCatalogSeedPartialFailsClosed proves a partially-populated seed
// provenance trio (partial seed-owned state) fails closed before mutation.
func TestCatalogSeedPartialFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 3, 3, 4, 2, systemSeedTrio(1, "2.4.1"))

	// Null out only seed_version on one row -> partial trio.
	res := store.db.WithContext(ctx).
		Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "cat.0").
		Update("seed_version", gorm.Expr("NULL"))
	if res.Error != nil || res.RowsAffected != 1 {
		t.Fatalf("null seed_version: err=%v rows=%d", res.Error, res.RowsAffected)
	}

	err := store.ApplyCatalogSeed(ctx, wsctx)
	if !errors.Is(err, ErrInvalidCatalogSeedMetadata) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrInvalidCatalogSeedMetadata", err)
	}

	assertRawActiveCounts(t, store, wsctx, seedCatalogCounts{3, 3, 4, 2})
}

// TestCatalogSeedRemovalsTombstone proves removed seed-owned identities are
// tombstoned (identity preserved, never hard-deleted) and removed native keys
// tombstone only their binding/descriptor while removed Registry descriptors
// tombstone their definition and all bindings.
func TestCatalogSeedRemovalsTombstone(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	// Older seed-owned catalog whose rows are NOT in the current seed, plus a
	// NULL-seed user row.
	wsctx := buildCatalogFixture(t, store, 2, 2, 2, 1, systemSeedTrio(0, "2.3.0"))
	insertUserRows(t, store, wsctx)

	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("ApplyCatalogSeed: %v", err)
	}

	wsBytes := wsctx.ID.Bytes()

	// Removed seed-owned definitions are tombstoned (identity preserved).
	var removedDefs []WorkspacePropertyDefinitionRow
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND seed_owner = ? AND canonical_key LIKE 'cat.%'", wsBytes, "system_property_registry").
		Find(&removedDefs).Error; err != nil {
		t.Fatalf("read removed defs: %v", err)
	}
	if len(removedDefs) != 2 {
		t.Fatalf("removed defs = %d, want 2", len(removedDefs))
	}
	for _, d := range removedDefs {
		if d.LifecycleState != "tombstoned" {
			t.Fatalf("removed definition %q not tombstoned (state=%q)", d.CanonicalKey, d.LifecycleState)
		}
	}

	// Removed seed-owned descriptors are tombstoned. Filter by the tombstoned
	// lifecycle so the real (active) seed descriptors are not matched.
	var removedDescs []SourcePropertyDescriptorRow
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ? AND external_property_id LIKE 'kMDItem%'", wsBytes, "system_property_registry", "tombstoned").
		Find(&removedDescs).Error; err != nil {
		t.Fatalf("read removed descs: %v", err)
	}
	if len(removedDescs) != 2 {
		t.Fatalf("removed descs = %d, want 2", len(removedDescs))
	}
	for _, d := range removedDescs {
		if d.LifecycleState != "tombstoned" {
			t.Fatalf("removed descriptor %q not tombstoned (state=%q)", d.ExternalPropertyID, d.LifecycleState)
		}
	}

	// Removed seed-owned bindings are tombstoned.
	var removedBindings []PropertyBindingRow
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ? AND external_property_id LIKE 'kMDItem%'", wsBytes, "system_property_registry", "tombstoned").
		Find(&removedBindings).Error; err != nil {
		t.Fatalf("read removed bindings: %v", err)
	}
	if len(removedBindings) != 2 {
		t.Fatalf("removed bindings = %d, want 2", len(removedBindings))
	}
	for _, b := range removedBindings {
		if b.LifecycleState != "tombstoned" {
			t.Fatalf("removed binding not tombstoned (state=%q)", b.LifecycleState)
		}
	}

	// Historical terms preserved (rows remain, but excluded from active view).
	var historicalTerms int64
	if err := store.db.WithContext(ctx).
		Model(&WorkspacePropertyTermRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND term_value LIKE 'alias-%'", wsBytes, "system_property_registry").
		Count(&historicalTerms).Error; err != nil {
		t.Fatalf("count historical terms: %v", err)
	}
	if historicalTerms != 1 {
		t.Fatalf("historical terms = %d, want 1 preserved (not deleted)", historicalTerms)
	}
	var historicalTerm WorkspacePropertyTermRow
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND seed_owner = ? AND term_value = ?", wsBytes, "system_property_registry", "alias-0").
		First(&historicalTerm).Error; err != nil {
		t.Fatalf("read historical term: %v", err)
	}
	if historicalTerm.LifecycleState != "tombstoned" {
		t.Fatalf("historical term state = %q, want tombstoned", historicalTerm.LifecycleState)
	}

	// Active catalog = fresh seed dataset + the one preserved user row each.
	meta := seeds.Current()
	assertLoadedCatalogCounts(t, store, wsctx, seedCatalogCounts{
		definitions: meta.DefinitionCount + 1,
		descriptors: meta.DescriptorCount + 1,
		bindings:    meta.BindingCount + 1,
		terms:       meta.TermCount + 1,
	})
	assertSeedDigestMatches(t, store, wsctx)
}

func TestCatalogSeedRemovedTermTombstone(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 1, 1, 1, 1, systemSeedTrio(1, "2.4.1"))

	if result := store.db.WithContext(ctx).Model(&WorkspacePropertyTermRow{}).
		Where("workspace_id = ? AND term_value = ?", wsctx.ID.Bytes(), "alias-0").
		Updates(map[string]any{"seed_version": 0, "seed_source_version": "2.3.0"}); result.Error != nil || result.RowsAffected != 1 {
		t.Fatalf("repoint term seed tuple: err=%v rows=%d", result.Error, result.RowsAffected)
	}

	if err := store.WithinTx(ctx, func(tx *gorm.DB) error {
		return reconcileSeedOwned(tx, wsctx.ID.Bytes(), seeds.Current())
	}); err != nil {
		t.Fatalf("reconcileSeedOwned: %v", err)
	}

	var term WorkspacePropertyTermRow
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND term_value = ?", wsctx.ID.Bytes(), "alias-0").
		First(&term).Error; err != nil {
		t.Fatalf("read term: %v", err)
	}
	if term.LifecycleState != "tombstoned" {
		t.Fatalf("term lifecycle_state = %q, want tombstoned", term.LifecycleState)
	}

	loaded, err := NewPropertyCatalogRepository(store).Load(ctx, wsctx)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(loaded.Snapshot.Definitions) != 1 || len(loaded.Snapshot.Terms) != 0 {
		t.Fatalf("loaded catalog counts = definitions:%d terms:%d, want 1 and 0", len(loaded.Snapshot.Definitions), len(loaded.Snapshot.Terms))
	}
}

func TestCatalogSeedTombstonedTermValueCanBeReused(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 2, 1, 1, 2, systemSeedTrio(0, "2.3.0"))
	propertyID, err := domainentry.RegistryPropertyID("cat.0")
	if err != nil {
		t.Fatalf("RegistryPropertyID: %v", err)
	}

	if err := store.WithinTx(ctx, func(tx *gorm.DB) error {
		return reconcileSeedOwned(tx, wsctx.ID.Bytes(), seeds.Current())
	}); err != nil {
		t.Fatalf("reconcileSeedOwned: %v", err)
	}

	seed := systemSeedTrio(1, "2.4.1")
	err = store.db.WithContext(ctx).Create(&WorkspacePropertyTermRow{
		WorkspaceID:       wsctx.ID.Bytes(),
		PropertyID:        propertyID.Bytes(),
		TermKind:          "search_alias",
		Ordinal:           2,
		TermValue:         "alias-0",
		LifecycleState:    "active",
		SeedOwner:         seed.owner,
		SeedVersion:       seed.version,
		SeedSourceVersion: seed.sourceVersion,
	}).Error
	if err != nil {
		t.Fatalf("reuse tombstoned term value: %v", err)
	}
}

// TestCatalogSeedPreservesNonSeed proves NULL-seed user/provider rows are left
// untouched by apply.
func TestCatalogSeedPreservesNonSeed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	insertUserRows(t, store, wsctx)

	// Snapshot the user definition before apply.
	var userBefore WorkspacePropertyDefinitionRow
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "user.custom_prop").
		First(&userBefore).Error; err != nil {
		t.Fatalf("read user def before: %v", err)
	}

	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("ApplyCatalogSeed: %v", err)
	}

	// User rows survive and are untouched (still active, seed trio NULL).
	var userAfter WorkspacePropertyDefinitionRow
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND canonical_key = ?", wsctx.ID.Bytes(), "user.custom_prop").
		First(&userAfter).Error; err != nil {
		t.Fatalf("read user def after: %v", err)
	}
	if userAfter.LifecycleState != "active" {
		t.Fatalf("user definition no longer active (state=%q)", userAfter.LifecycleState)
	}
	if userAfter.SeedOwner != nil || userAfter.SeedVersion != nil || userAfter.SeedSourceVersion != nil {
		t.Fatal("user definition seed trio was mutated by apply")
	}
	if userAfter.UpdatedAt != userBefore.UpdatedAt || userAfter.DisplayName != userBefore.DisplayName {
		t.Fatal("user definition content was mutated by apply")
	}

	// Active catalog = fresh seed + the one preserved user definition.
	meta := seeds.Current()
	assertLoadedCatalogCounts(t, store, wsctx, seedCatalogCounts{
		definitions: meta.DefinitionCount + 1,
		descriptors: meta.DescriptorCount + 1,
		bindings:    meta.BindingCount + 1,
		terms:       meta.TermCount + 1,
	})
	assertSeedDigestMatches(t, store, wsctx)
}

// TestCatalogSeedTamperedHashFailsBeforeWrite proves an embedded SQL SHA-256
// mismatch fails closed BEFORE any write and leaves the catalog unchanged.
func TestCatalogSeedTamperedHashFailsBeforeWrite(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())

	// Metadata whose SQLSHA256 does not match its body -> tampered hash.
	meta := seeds.Current()
	meta.SQLSHA256 = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

	err := store.applyCatalogSeedMeta(ctx, wsctx, meta)
	if !errors.Is(err, ErrCatalogSeedChecksum) {
		t.Fatalf("apply error = %v, want ErrCatalogSeedChecksum", err)
	}

	// No write happened: the catalog is still empty.
	var defCount int64
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ?", wsctx.ID.Bytes()).Count(&defCount).Error; err != nil {
		t.Fatalf("count defs: %v", err)
	}
	if defCount != 0 {
		t.Fatalf("definitions written despite checksum failure: %d", defCount)
	}
}

func TestCatalogSeedTamperedBodyFailsAgainstGeneratedHash(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	meta := seeds.Current()
	meta.SQLBody += "\n-- tampered embedded artifact"
	if err := store.applyCatalogSeedMeta(ctx, wsctx, meta); !errors.Is(err, ErrCatalogSeedChecksum) {
		t.Fatalf("apply error = %v, want ErrCatalogSeedChecksum", err)
	}
	var count int64
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ?", wsctx.ID.Bytes()).Count(&count).Error; err != nil {
		t.Fatalf("count definitions: %v", err)
	}
	if count != 0 {
		t.Fatalf("definitions written despite embedded body checksum failure: %d", count)
	}
}

// TestCatalogSeedPartialSQLRollback proves a seed whose SQL executes but whose
// read-back digest does not match rolls back the entire transaction, leaving
// the pre-call (empty) state.
func TestCatalogSeedPartialSQLRollback(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())

	// A tampered-but-self-consistent seed body: valid SQL that inserts a
	// different dataset (so its read-back digest differs from DatasetSHA256).
	meta := seeds.Current()
	meta.SQLBody = "INSERT INTO workspace_property_definitions " +
		"(workspace_id, property_id, origin, identity_scheme, namespace, canonical_key, " +
		"display_name, description, value_type, cardinality, nullable, editable, " +
		"default_hidden, default_pinned, db_indexed_hint, provenance, unit, " +
		"definition_revision, lifecycle_state, seed_owner, seed_version, " +
		"seed_source_version, created_at, updated_at) " +
		"SELECT workspace_id, X'ba1b77a400675c4cb67eedadcae0853b', 'built_in', 'registry_derived', " +
		"'system', 'partial.only', 'Partial', 'p', 'text', 'one', 0, 1, 0, 0, 0, 'system_property_registry@2.4.1', " +
		"'', 1, 'active', 'system_property_registry', 1, '2.4.1', '2026-08-20T00:00:00Z', '2026-08-20T00:00:00Z' " +
		"FROM workspace_metadata WHERE singleton = 1 " +
		"ON CONFLICT (workspace_id, property_id) DO UPDATE SET display_name = excluded.display_name"
	// Keep SQLSHA256 self-consistent with the tampered body so the checksum gate
	// passes and the failure surfaces at read-back/digest verification instead.
	meta.SQLSHA256 = sha256Hex(meta.SQLBody)

	err := store.applyCatalogSeedMeta(ctx, wsctx, meta)
	if !errors.Is(err, ErrCatalogSeedDigest) {
		t.Fatalf("apply error = %v, want ErrCatalogSeedDigest", err)
	}

	// The whole transaction rolled back: no partial row remains.
	var defCount int64
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ?", wsctx.ID.Bytes()).Count(&defCount).Error; err != nil {
		t.Fatalf("count defs: %v", err)
	}
	if defCount != 0 {
		t.Fatalf("partial SQL leaked %d rows after rollback", defCount)
	}
}

// TestCatalogSeedSecondOpenRejected proves the existing lifetime database lock
// rejects a second Open against the same file before seed execution and leaves
// the first Store's catalog unchanged.
func TestCatalogSeedSecondOpenRejected(t *testing.T) {
	ctx := context.Background()
	dbPath := tempDBPath(t)

	storeA, err := Open(ctx, dbPath)
	if err != nil {
		t.Fatalf("Open A: %v", err)
	}
	defer storeA.Close()
	if err := MigrateUp(ctx, storeA.SQLDB()); err != nil {
		t.Fatalf("MigrateUp A: %v", err)
	}
	wsctx, err := storeA.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap A: %v", err)
	}
	if err := storeA.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("ApplyCatalogSeed A: %v", err)
	}
	assertLoadedCatalogCounts(t, storeA, wsctx, freshSeedCounts())

	// A second Open must fail before seed execution (lifetime lock held).
	if _, err := Open(ctx, dbPath); !errors.Is(err, ErrDatabaseLocked) {
		t.Fatalf("second Open error = %v, want ErrDatabaseLocked", err)
	}

	// The first Store's catalog is unchanged.
	assertLoadedCatalogCounts(t, storeA, wsctx, freshSeedCounts())
}

// TestCatalogSeedConcurrentSerialized proves two concurrent ApplyCatalogSeed
// calls through the same Store serialize (apply then no-op) without mixed or
// partial state.
func TestCatalogSeedConcurrentSerialized(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())

	var wg sync.WaitGroup
	errs := make([]error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			errs[i] = store.ApplyCatalogSeed(ctx, wsctx)
		}(i)
	}
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Fatalf("concurrent ApplyCatalogSeed[%d]: %v", i, err)
		}
	}

	// No mixed/partial state: the catalog is exactly the fresh seed dataset.
	assertLoadedCatalogCounts(t, store, wsctx, freshSeedCounts())
}

func derefStr(p *string) string {
	if p == nil {
		return "<nil>"
	}
	return *p
}

// TestCatalogSeedApplyFailsClosedOnProviderOwnedCollision proves the upsert
// ownership guard: a restored DB may hold a provider-authored row (NULL
// seed_owner) whose natural key the incoming seed also claims. The ON CONFLICT
// DO UPDATE clauses are guarded by `WHERE seed_owner = excluded.seed_owner`,
// so the colliding row must NOT be overwritten; the seed read-back digest then
// mismatches and the whole transaction rolls back fail-closed, leaving the
// provider row byte-for-byte intact (comment #3837853209).
func TestCatalogSeedApplyFailsClosedOnProviderOwnedCollision(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())

	meta := seeds.Current()

	// First incoming seed definition's property_id hex becomes the collision key.
	marker := "INSERT INTO workspace_property_definitions"
	start := strings.Index(meta.SQLBody, marker)
	if start < 0 {
		t.Fatalf("seed body missing definitions statement")
	}
	rest := meta.SQLBody[start:]
	hx := strings.Index(rest, "X'")
	if hx < 0 {
		t.Fatalf("seed body missing property_id literal")
	}
	hxStart := hx + 2
	hxEnd := strings.Index(rest[hxStart:], "'")
	if hxEnd < 0 {
		t.Fatalf("unterminated property_id literal")
	}
	propertyIDHex := rest[hxStart : hxStart+hxEnd]
	propertyIDBytes, err := hex.DecodeString(propertyIDHex)
	if err != nil {
		t.Fatalf("decode property_id: %v", err)
	}

	// Provider-authored row occupying that exact natural key, seed_owner NULL.
	insertSQL := "INSERT INTO workspace_property_definitions " +
		"(workspace_id, property_id, origin, identity_scheme, namespace, canonical_key, " +
		"display_name, description, value_type, cardinality, nullable, editable, " +
		"default_hidden, default_pinned, db_indexed_hint, provenance, unit, " +
		"default_display_unit, units_json, definition_revision, lifecycle_state, " +
		"seed_owner, seed_version, seed_source_version, created_at, updated_at) VALUES (" +
		"X'" + fmt.Sprintf("%x", wsctx.ID.Bytes()) + "', X'" + propertyIDHex + "', " +
		"'built_in', 'registry_derived', 'system', 'provider.colliding', " +
		"'Provider Owned', 'p', 'text', 'one', 0, 1, 0, 0, 0, " +
		"'system_property_registry@2.4.1', '', '', '', 1, 'active', " +
		"NULL, NULL, NULL, '2026-08-20T00:00:00Z', '2026-08-20T00:00:00Z')"
	if err := store.db.WithContext(ctx).Exec(insertSQL).Error; err != nil {
		t.Fatalf("insert provider row: %v", err)
	}

	// Fail-closed contract: the apply must NOT succeed and must NOT overwrite the
	// provider-owned row. Which internal gate trips first (read-back digest vs
	// orphan-reference assembly check) depends on whether the collided seed
	// definition has dependents, so only the outcome is pinned here.
	if err := store.applyCatalogSeedMeta(ctx, wsctx, meta); err == nil {
		t.Fatalf("apply succeeded despite provider-owned collision; want fail-closed")
	}

	var providerRow WorkspacePropertyDefinitionRow
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND property_id = ?", wsctx.ID.Bytes(), propertyIDBytes).
		First(&providerRow).Error; err != nil {
		t.Fatalf("provider row vanished after failed apply: %v", err)
	}
	if providerRow.SeedOwner != nil {
		t.Fatalf("provider row was taken over: seed_owner=%q", *providerRow.SeedOwner)
	}
	if providerRow.DisplayName != "Provider Owned" {
		t.Fatalf("provider display_name = %q, want preserved", providerRow.DisplayName)
	}

	var seedOwned int64
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND seed_owner = ?", wsctx.ID.Bytes(), "system_property_registry").
		Count(&seedOwned).Error; err != nil {
		t.Fatalf("count seed-owned rows: %v", err)
	}
	if seedOwned != 0 {
		t.Fatalf("seed-owned rows leaked after rollback: %d", seedOwned)
	}
}

// TestCatalogSeedActiveCurrentWithNewerHistoryFailsClosed proves a healthy
// active current seed (otherwise a no-op) is still rejected when seed-owned
// history carries a newer ordinal: the downgrade/corrupt history must not be
// ignored while the daemon reports ready.
func TestCatalogSeedActiveCurrentWithNewerHistoryFailsClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	wsctx := buildCatalogFixture(t, store, 0, 0, 0, 0, noneSeedTrio())
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("first ApplyCatalogSeed: %v", err)
	}

	// Inject one tombstoned definition row from a FUTURE seed tuple; the
	// active current set and its digest stay untouched.
	futureID, err := domainentry.RegistryPropertyID("corrupt.future")
	if err != nil {
		t.Fatal(err)
	}
	owner := "system_property_registry"
	source := seeds.Current().SystemRegistryVersion
	future := WorkspacePropertyDefinitionRow{
		WorkspaceID: wsctx.ID.Bytes(), PropertyID: futureID.Bytes(),
		Origin: "built_in", IdentityScheme: "registry_derived", Namespace: "system",
		CanonicalKey: "corrupt.future", DisplayName: "Future", Description: "",
		ValueType: "text", Cardinality: "one", Nullable: false, Editable: false,
		DefinitionRev: 1, LifecycleState: "tombstoned",
		SeedOwner: &owner, SeedVersion: ptrInt(2), SeedSourceVersion: &source,
	}
	if err := store.db.WithContext(ctx).Create(&future).Error; err != nil {
		t.Fatalf("inject future tuple row: %v", err)
	}

	if err := store.ApplyCatalogSeed(ctx, wsctx); !errors.Is(err, ErrCatalogSeedState) {
		t.Fatalf("ApplyCatalogSeed error = %v, want ErrCatalogSeedState", err)
	}
}
