package sqlite

import (
	"errors"
	"strings"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// Sentinel errors for explicit row<->domain mapping. All are metadata-only; a
// failed mapping names the row class, never the row payload. The repository
// wraps any DB error unchanged and these mappers are the only validation gate
// between GORM rows and domain values — GORM rows are never exposed as domain
// values.
var (
	// ErrInvalidCatalogBLOB marks a BLOB identity column that is not a valid
	// typed UUID (wrong length or bad RFC variant bits).
	ErrInvalidCatalogBLOB = errors.New("invalid catalog blob identity")
	// ErrInvalidCatalogVersion marks a PropertyID whose version nibble does not
	// match its declared identity scheme.
	ErrInvalidCatalogVersion = errors.New("invalid catalog identity version")
	// ErrInvalidCatalogRow marks a row that fails domain value validation
	// (malformed natural ref, lifecycle, enum, or text constraint).
	ErrInvalidCatalogRow = errors.New("invalid catalog row")
	// ErrInvalidCatalogSeedMetadata marks a seed provenance trio that is
	// partially populated or carries an unrecognized seed owner.
	ErrInvalidCatalogSeedMetadata = errors.New("invalid catalog seed metadata")
)

// seedOwnerSystemPropertyRegistry is the only seed owner the persistence layer
// recognizes. Any other non-nil seed owner is rejected as invalid metadata.
const seedOwnerSystemPropertyRegistry = "system_property_registry"

// parsePropertyIDBlob converts a raw 16-byte BLOB column into a typed
// PropertyID, rejecting any blob that is not exactly 16 bytes or does not carry
// the RFC 9562 variant. It reuses the canonical text parser as the single
// variant authority so persistence never invents its own ID validation.
func parsePropertyIDBlob(raw []byte) (domainentry.PropertyID, error) {
	if len(raw) != len(domainentry.PropertyID{}) {
		return domainentry.PropertyID{}, ErrInvalidCatalogBLOB
	}
	var id domainentry.PropertyID
	copy(id[:], raw)
	if _, err := domainentry.ParsePropertyID(id.String()); err != nil {
		return domainentry.PropertyID{}, ErrInvalidCatalogBLOB
	}
	return id, nil
}

// validateWorkspaceID rejects a workspace_id BLOB that is not a valid UUIDv7.
func validateWorkspaceID(raw []byte) error {
	if _, err := domainentry.ParseWorkspaceID(raw); err != nil {
		return ErrInvalidCatalogBLOB
	}
	return nil
}

// identityVersionMatches reports whether the PropertyID version nibble is
// consistent with the declared identity scheme. This is deliberately a mapper
// validation (not digest framing); it reuses the same scheme-to-version rule as
// the domain's PropertyIdentityScheme.acceptsVersion.
func identityVersionMatches(scheme domainentry.PropertyIdentityScheme, id domainentry.PropertyID) bool {
	switch scheme {
	case domainentry.PropertyIdentitySchemeRegistryDerived:
		return id[6]>>4 == 5
	case domainentry.PropertyIdentitySchemeVoyagerIssued:
		return id[6]>>4 == 7
	default:
		return false
	}
}

// validateSeedTrio enforces the all-or-none seed provenance convention: either
// all three columns are NULL (user-defined) or all three are set with the
// recognized system seed owner. Partial trios and foreign owners are rejected.
func validateSeedTrio(owner *string, version *int, sourceVersion *string) error {
	present := 0
	if owner != nil {
		present++
	}
	if version != nil {
		present++
	}
	if sourceVersion != nil {
		present++
	}
	if present != 0 && present != 3 {
		return ErrInvalidCatalogSeedMetadata
	}
	if owner != nil && *owner != seedOwnerSystemPropertyRegistry {
		return ErrInvalidCatalogSeedMetadata
	}
	return nil
}

func mapDefinitionRow(row WorkspacePropertyDefinitionRow) (domainentry.WorkspacePropertyDefinition, error) {
	if err := validateWorkspaceID(row.WorkspaceID); err != nil {
		return domainentry.WorkspacePropertyDefinition{}, err
	}
	id, err := parsePropertyIDBlob(row.PropertyID)
	if err != nil {
		return domainentry.WorkspacePropertyDefinition{}, err
	}
	scheme := domainentry.PropertyIdentityScheme(row.IdentityScheme)
	if !identityVersionMatches(scheme, id) {
		return domainentry.WorkspacePropertyDefinition{}, ErrInvalidCatalogVersion
	}
	if err := validateSeedTrio(row.SeedOwner, row.SeedVersion, row.SeedSourceVersion); err != nil {
		return domainentry.WorkspacePropertyDefinition{}, err
	}
	// The seed stores a mapping-provenance string (system_property_registry@<v>)
	// in the SQL provenance column, but the domain definition provenance is an
	// enum. Every seed-owned definition is a system-provided built-in, so its
	// domain provenance is always system; non-seed rows keep their enum value.
	provenance := domainentry.PropertyProvenance(row.Provenance)
	if isSeedOwned(row.SeedOwner) {
		provenance = domainentry.PropertyProvenanceSystem
	}
	definition := domainentry.WorkspacePropertyDefinition{
		PropertyID:     id,
		Origin:         domainentry.PropertyOrigin(row.Origin),
		IdentityScheme: scheme,
		Namespace:      row.Namespace,
		CanonicalKey:   row.CanonicalKey,
		DisplayName:    row.DisplayName,
		Description:    row.Description,
		ValueType:      domainentry.PropertyValueType(row.ValueType),
		Cardinality:    domainentry.PropertyCardinality(row.Cardinality),
		Nullable:       row.Nullable,
		Editable:       row.Editable,
		DefaultHidden:  row.DefaultHidden,
		DefaultPinned:  row.DefaultPinned,
		DBIndexedHint:  row.DBIndexedHint,
		DefinitionRev:  row.DefinitionRev,
		Provenance:     provenance,
		Lifecycle:      domainentry.PropertyLifecycleState(row.LifecycleState),
	}
	if row.Unit != "" {
		unit := row.Unit
		definition.Unit = &unit
	}
	if err := definition.Validate(); err != nil {
		return domainentry.WorkspacePropertyDefinition{}, ErrInvalidCatalogRow
	}
	return definition, nil
}

// mapDescriptorRow maps a SourcePropertyDescriptorRow to the domain
// SourcePropertyDescriptor. The schema stores the source-issued native key as
// external_property_id; for seed-owned (macos.*) descriptors the committed
// dataset digest keys the descriptor by the full provider-prefixed system key
// (mditem:kMDItemFSName), so the prefix is reconstructed from the provider id.
// Non-seed descriptors keep external_property_id as their native key.
func mapDescriptorRow(row SourcePropertyDescriptorRow) (domainentry.SourcePropertyDescriptor, error) {
	if err := validateWorkspaceID(row.WorkspaceID); err != nil {
		return domainentry.SourcePropertyDescriptor{}, err
	}
	if err := validateSeedTrio(row.SeedOwner, row.SeedVersion, row.SeedSourceVersion); err != nil {
		return domainentry.SourcePropertyDescriptor{}, err
	}
	nativeKey := row.ExternalPropertyID
	if isSeedOwned(row.SeedOwner) {
		if prefix := strings.TrimPrefix(row.ProviderID, "macos."); prefix != row.ProviderID {
			nativeKey = prefix + ":" + row.ExternalPropertyID
		}
	}
	descriptor := domainentry.SourcePropertyDescriptor{
		Ref: domainentry.SourcePropertyRef{
			ProviderID:         row.ProviderID,
			SourceInstanceID:   row.SourceInstanceID,
			ScopeKind:          domainentry.SourceScopeKind(row.ScopeKind),
			ScopeExternalID:    row.ScopeExternalID,
			ExternalPropertyID: row.ExternalPropertyID,
		},
		NativeKey:         nativeKey,
		NativeType:        row.NativeType,
		NativeCardinality: domainentry.PropertyCardinality(row.NativeCardinality),
		Authority:         domainentry.AuthorityKind(row.AuthorityKind),
		SourceReadable:    row.SourceReadable,
		SourceQueryable:   row.SourceQueryable,
		SourceWritable:    row.SourceWritable,
		Lifecycle:         domainentry.PropertyLifecycleState(row.LifecycleState),
	}
	if err := descriptor.Validate(); err != nil {
		return domainentry.SourcePropertyDescriptor{}, ErrInvalidCatalogRow
	}
	return descriptor, nil
}

// mapBindingRow maps a PropertyBindingRow to the domain PropertyBinding. The
// row's binding_ordinal is a reviewed system-key ordering hint carried into the
// domain for scope-ambiguous disambiguation and covered by the dataset digest.
func mapBindingRow(row PropertyBindingRow) (domainentry.PropertyBinding, error) {
	if err := validateWorkspaceID(row.WorkspaceID); err != nil {
		return domainentry.PropertyBinding{}, err
	}
	id, err := parsePropertyIDBlob(row.PropertyID)
	if err != nil {
		return domainentry.PropertyBinding{}, err
	}
	if err := validateSeedTrio(row.SeedOwner, row.SeedVersion, row.SeedSourceVersion); err != nil {
		return domainentry.PropertyBinding{}, err
	}
	binding := domainentry.PropertyBinding{
		PropertyID: id,
		SourceRef: domainentry.SourcePropertyRef{
			ProviderID:         row.ProviderID,
			SourceInstanceID:   row.SourceInstanceID,
			ScopeKind:          domainentry.SourceScopeKind(row.ScopeKind),
			ScopeExternalID:    row.ScopeExternalID,
			ExternalPropertyID: row.ExternalPropertyID,
		},
		BindingOrdinal:        row.BindingOrdinal,
		ReadTransform:         row.ReadTransform,
		Direction:             row.Direction,
		EffectiveReadable:     row.EffectiveReadable,
		EffectiveQueryable:    row.EffectiveQueryable,
		EffectiveWritable:     row.EffectiveWritable,
		QueryProfile:          row.QueryProfile,
		MappingVersion:        row.MappingVersion,
		ValueContractRevision: row.ValueContractRev,
		Provenance:            row.MappingProvenance,
		ApprovalState:         row.ApprovalState,
		Lossiness:             row.Lossiness,
		Lifecycle:             domainentry.PropertyLifecycleState(row.LifecycleState),
	}
	if err := binding.Validate(); err != nil {
		return domainentry.PropertyBinding{}, ErrInvalidCatalogRow
	}
	return binding, nil
}

// mapTermRow maps a WorkspacePropertyTermRow to the domain WorkspacePropertyTerm.
func mapTermRow(row WorkspacePropertyTermRow) (domainentry.WorkspacePropertyTerm, error) {
	if err := validateWorkspaceID(row.WorkspaceID); err != nil {
		return domainentry.WorkspacePropertyTerm{}, err
	}
	id, err := parsePropertyIDBlob(row.PropertyID)
	if err != nil {
		return domainentry.WorkspacePropertyTerm{}, err
	}
	if err := validateSeedTrio(row.SeedOwner, row.SeedVersion, row.SeedSourceVersion); err != nil {
		return domainentry.WorkspacePropertyTerm{}, err
	}
	term := domainentry.WorkspacePropertyTerm{
		PropertyID: id,
		TermKind:   row.TermKind,
		Ordinal:    row.Ordinal,
		TermValue:  row.TermValue,
	}
	if err := term.Validate(); err != nil {
		return domainentry.WorkspacePropertyTerm{}, ErrInvalidCatalogRow
	}
	return term, nil
}
