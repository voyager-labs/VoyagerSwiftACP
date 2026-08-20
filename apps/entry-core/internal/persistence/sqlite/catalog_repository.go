package sqlite

import (
	"context"
	"errors"

	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// ErrCatalogOrphanRef marks an active binding whose property or source ref has
// no active definition/descriptor in the same catalog (e.g. an active binding
// left pointing at a tombstoned definition). The load fails closed rather than
// returning a referentially-inconsistent snapshot.
var ErrCatalogOrphanRef = errors.New("catalog orphan reference")

// PropertyCatalogRepository reads the active Workspace Property catalog of a
// single Workspace. It is read-only: it performs no writes and exposes no
// public UDS surface. GORM rows are mapped to domain values and never returned
// as-is.
type PropertyCatalogRepository struct {
	store *Store
}

// NewPropertyCatalogRepository returns a repository bound to the store.
func NewPropertyCatalogRepository(store *Store) *PropertyCatalogRepository {
	return &PropertyCatalogRepository{store: store}
}

// LoadedCatalog is the result of a single catalog load: the mapped active
// snapshot, its canonical digest, and the derived seed state.
type LoadedCatalog struct {
	Snapshot  domainentry.PropertyCatalogSnapshot
	Digest    [32]byte
	SeedState SeedState
}

// Load reads one Workspace's active catalog in exactly four queries (one per
// family — no N+1): active definitions, active source descriptors, active
// bindings, and terms belonging to active definitions. Tombstoned history stays
// available only to seed reconciliation internals and is excluded here. It
// maps every row through the explicit mappers, rejects referential orphans and
// corrupt seed state, then computes the canonical digest.
func (r *PropertyCatalogRepository) Load(ctx context.Context, wsctx domainentry.WorkspaceContext) (LoadedCatalog, error) {
	defRows, descRows, bindingRows, termRows, err := loadCatalogRows(r.store.db.WithContext(ctx), wsctx)
	if err != nil {
		return LoadedCatalog{}, err
	}
	snapshot, err := assembleSnapshot(defRows, descRows, bindingRows, termRows)
	if err != nil {
		return LoadedCatalog{}, err
	}
	seedState, err := deriveSeedState(defRows, descRows, bindingRows, termRows)
	if err != nil {
		return LoadedCatalog{}, err
	}
	digest, err := catalogDigest(snapshot)
	if err != nil {
		return LoadedCatalog{}, err
	}
	return LoadedCatalog{Snapshot: snapshot, Digest: digest, SeedState: seedState}, nil
}

// loadCatalogRows reads the four active catalog families for a Workspace in
// exactly four queries (one per family, no N+1). It operates on the supplied
// *gorm.DB so the repository can read through the store connection while seed
// reconciliation reads through the transaction-scoped handle of the same
// WithinTx. GORM rows are never exposed as domain values; mapping happens in
// assembleSnapshot.
func loadCatalogRows(
	db *gorm.DB,
	wsctx domainentry.WorkspaceContext,
) ([]WorkspacePropertyDefinitionRow, []SourcePropertyDescriptorRow, []PropertyBindingRow, []WorkspacePropertyTermRow, error) {
	wsBytes := wsctx.ID.Bytes()

	var defRows []WorkspacePropertyDefinitionRow
	if err := db.Where("workspace_id = ? AND lifecycle_state = ?", wsBytes, "active").Find(&defRows).Error; err != nil {
		return nil, nil, nil, nil, err
	}

	var descRows []SourcePropertyDescriptorRow
	if err := db.Where("workspace_id = ? AND lifecycle_state = ?", wsBytes, "active").Find(&descRows).Error; err != nil {
		return nil, nil, nil, nil, err
	}

	var bindingRows []PropertyBindingRow
	if err := db.Where("workspace_id = ? AND lifecycle_state = ?", wsBytes, "active").Find(&bindingRows).Error; err != nil {
		return nil, nil, nil, nil, err
	}

	// Terms inherit their definition's lifecycle, so only terms whose property
	// is an active definition are loaded (single query, no per-term fetch).
	var termRows []WorkspacePropertyTermRow
	if err := db.Where(
		"workspace_id = ? AND property_id IN (SELECT property_id FROM workspace_property_definitions WHERE workspace_id = ? AND lifecycle_state = ?)",
		wsBytes, wsBytes, "active",
	).Find(&termRows).Error; err != nil {
		return nil, nil, nil, nil, err
	}

	return defRows, descRows, bindingRows, termRows, nil
}

// loadSeedRows reads only the active SEED-OWNED rows for the four catalog
// families of a Workspace. It is used by seed reconciliation and digest
// verification, which are scoped to the system seed dataset and must exclude
// preserved NULL-seed user/provider rows (DatasetSHA256 is inherently the
// seed-only digest).
func loadSeedRows(
	db *gorm.DB,
	wsctx domainentry.WorkspaceContext,
) ([]WorkspacePropertyDefinitionRow, []SourcePropertyDescriptorRow, []PropertyBindingRow, []WorkspacePropertyTermRow, error) {
	wsBytes := wsctx.ID.Bytes()
	owner := seedOwnerSystemPropertyRegistry

	var defRows []WorkspacePropertyDefinitionRow
	if err := db.Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?", wsBytes, owner, "active").Find(&defRows).Error; err != nil {
		return nil, nil, nil, nil, err
	}

	var descRows []SourcePropertyDescriptorRow
	if err := db.Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?", wsBytes, owner, "active").Find(&descRows).Error; err != nil {
		return nil, nil, nil, nil, err
	}

	var bindingRows []PropertyBindingRow
	if err := db.Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?", wsBytes, owner, "active").Find(&bindingRows).Error; err != nil {
		return nil, nil, nil, nil, err
	}

	var termRows []WorkspacePropertyTermRow
	if err := db.Where(
		"workspace_id = ? AND seed_owner = ? AND property_id IN (SELECT property_id FROM workspace_property_definitions WHERE workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?)",
		wsBytes, owner, wsBytes, owner, "active",
	).Find(&termRows).Error; err != nil {
		return nil, nil, nil, nil, err
	}

	return defRows, descRows, bindingRows, termRows, nil
}

// assembleSnapshot maps every active row to a domain value and assembles the
// snapshot, rejecting any invalid row and any referential orphan. Mapping is
// delegated to the explicit per-row mappers in catalog_mapper.go.
func assembleSnapshot(
	defRows []WorkspacePropertyDefinitionRow,
	descRows []SourcePropertyDescriptorRow,
	bindingRows []PropertyBindingRow,
	termRows []WorkspacePropertyTermRow,
) (domainentry.PropertyCatalogSnapshot, error) {
	var snapshot domainentry.PropertyCatalogSnapshot

	activeDefIDs := make(map[domainentry.PropertyID]struct{}, len(defRows))
	for _, row := range defRows {
		definition, err := mapDefinitionRow(row)
		if err != nil {
			return domainentry.PropertyCatalogSnapshot{}, err
		}
		snapshot.Definitions = append(snapshot.Definitions, definition)
		activeDefIDs[definition.PropertyID] = struct{}{}
	}

	activeRefs := make(map[domainentry.SourcePropertyRef]struct{}, len(descRows))
	for _, row := range descRows {
		descriptor, err := mapDescriptorRow(row)
		if err != nil {
			return domainentry.PropertyCatalogSnapshot{}, err
		}
		snapshot.Descriptors = append(snapshot.Descriptors, descriptor)
		activeRefs[descriptor.Ref] = struct{}{}
	}

	for _, row := range bindingRows {
		binding, err := mapBindingRow(row)
		if err != nil {
			return domainentry.PropertyCatalogSnapshot{}, err
		}
		// An active binding must target an active definition and an active
		// source descriptor in the same catalog; otherwise the snapshot would
		// be referentially inconsistent (orphan).
		if _, ok := activeDefIDs[binding.PropertyID]; !ok {
			return domainentry.PropertyCatalogSnapshot{}, ErrCatalogOrphanRef
		}
		if _, ok := activeRefs[binding.SourceRef]; !ok {
			return domainentry.PropertyCatalogSnapshot{}, ErrCatalogOrphanRef
		}
		snapshot.Bindings = append(snapshot.Bindings, binding)
	}

	for _, row := range termRows {
		term, err := mapTermRow(row)
		if err != nil {
			return domainentry.PropertyCatalogSnapshot{}, err
		}
		snapshot.Terms = append(snapshot.Terms, term)
	}

	// The canonical snapshot Validate rejects duplicates within a family and
	// any invalid mapped value; the digest repeats that validation.
	if err := snapshot.Validate(); err != nil {
		return domainentry.PropertyCatalogSnapshot{}, ErrInvalidCatalogRow
	}
	return snapshot, nil
}
