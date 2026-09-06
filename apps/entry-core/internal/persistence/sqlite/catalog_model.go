package sqlite

import "time"

// This file declares the four catalog GORM row types for the append-only catalog
// migration chain. They are deliberately kept OUT of model.go
// (which owns the single-row workspace_metadata identity) so the append-only
// catalog schema is reviewable as its own unit. As with WorkspaceMetadataRow,
// no embedded gorm.Model is used: every column, type, and nullability is
// declared explicitly so the Atlas loader's generated schema matches the
// hand-written migrations. Cross-table foreign keys that Atlas cannot emit from
// these tags (composite references and the workspace ownership chain) are
// asserted through PRAGMA in TestCatalogSchemaConstraints.
//
// These types create no tables; they are only the input for the Atlas GORM
// Provider loader (tools/atlas-schema) and the VOY-765 repository layer.

// WorkspacePropertyDefinitionRow is a workspace-scoped Property definition the
// user references. Identity is (workspace_id, property_id); a workspace-scoped
// (namespace, canonical_key) is the unique lookup key.
type WorkspacePropertyDefinitionRow struct {
	WorkspaceID []byte `gorm:"column:workspace_id;type:blob;not null;check:length(workspace_id) = 16;primaryKey;uniqueIndex:idx_def_ns_key"`
	PropertyID  []byte `gorm:"column:property_id;type:blob;not null;check:length(property_id) = 16;primaryKey"`

	Origin         string `gorm:"column:origin;type:text;not null;check:origin in ('built_in','user_defined')"`
	IdentityScheme string `gorm:"column:identity_scheme;type:text;not null;check:identity_scheme in ('registry_derived','voyager_issued')"`
	Namespace      string `gorm:"column:namespace;type:text;not null;uniqueIndex:idx_def_ns_key"`
	CanonicalKey   string `gorm:"column:canonical_key;type:text;not null;uniqueIndex:idx_def_ns_key"`
	DisplayName    string `gorm:"column:display_name;type:text;not null"`
	Description    string `gorm:"column:description;type:text;not null"`
	ValueType      string `gorm:"column:value_type;type:text;not null;check:value_type in ('text','number','boolean','date','datetime','select')"`
	Cardinality    string `gorm:"column:cardinality;type:text;not null;check:cardinality in ('one','many')"`
	Nullable       bool   `gorm:"column:nullable;type:boolean;not null"`
	Editable       bool   `gorm:"column:editable;type:boolean;not null"`
	DefaultHidden  bool   `gorm:"column:default_hidden;type:boolean;not null"`
	DefaultPinned  bool   `gorm:"column:default_pinned;type:boolean;not null"`
	DBIndexedHint  bool   `gorm:"column:db_indexed_hint;type:boolean;not null"`
	Provenance     string `gorm:"column:provenance;type:text;not null"`
	Unit           string `gorm:"column:unit;type:text;not null"`
	DefinitionRev  int    `gorm:"column:definition_revision;type:integer;not null;check:definition_revision >= 0"`
	LifecycleState string `gorm:"column:lifecycle_state;type:text;not null;check:lifecycle_state in ('active','tombstoned')"`

	DefaultDisplayUnit string `gorm:"column:default_display_unit;type:text;not null;default:''"`
	UnitsJSON          string `gorm:"column:units_json;type:text;not null;default:''"`

	// Seed provenance trio: bundled rows carry all three
	// (system_property_registry / version / source version), user rows keep all
	// three NULL. All-or-none by convention, enforced at apply time.
	SeedOwner         *string `gorm:"column:seed_owner;type:text"`
	SeedVersion       *int    `gorm:"column:seed_version;type:integer"`
	SeedSourceVersion *string `gorm:"column:seed_source_version;type:text"`

	CreatedAt time.Time `gorm:"column:created_at;type:datetime;not null"`
	UpdatedAt time.Time `gorm:"column:updated_at;type:datetime;not null"`
}

// TableName returns the canonical table name.
func (WorkspacePropertyDefinitionRow) TableName() string {
	return "workspace_property_definitions"
}

// SourcePropertyDescriptorRow is a workspace-scoped descriptor of a native
// property owned by a source/provider. Identity is the source natural key
// (workspace_id, provider_id, source_instance_id, scope_kind,
// scope_external_id, external_property_id).
type SourcePropertyDescriptorRow struct {
	WorkspaceID        []byte `gorm:"column:workspace_id;type:blob;not null;check:length(workspace_id) = 16;primaryKey"`
	ProviderID         string `gorm:"column:provider_id;type:text;not null;primaryKey"`
	SourceInstanceID   string `gorm:"column:source_instance_id;type:text;not null;primaryKey"`
	ScopeKind          string `gorm:"column:scope_kind;type:text;not null;primaryKey"`
	ScopeExternalID    string `gorm:"column:scope_external_id;type:text;not null;primaryKey"`
	ExternalPropertyID string `gorm:"column:external_property_id;type:text;not null;primaryKey"`

	AuthorityKind     string `gorm:"column:authority_kind;type:text;not null;check:authority_kind in ('system','provider')"`
	NativeType        string `gorm:"column:native_type;type:text;not null"`
	NativeCardinality string `gorm:"column:native_cardinality;type:text;not null"`
	SourceReadable    bool   `gorm:"column:source_readable;type:boolean;not null"`
	SourceQueryable   bool   `gorm:"column:source_queryable;type:boolean;not null"`
	SourceWritable    bool   `gorm:"column:source_writable;type:boolean;not null"`
	LifecycleState    string `gorm:"column:lifecycle_state;type:text;not null;check:lifecycle_state in ('active','tombstoned')"`
	AvailabilityNote  string `gorm:"column:availability_note;type:text;not null"`

	SeedOwner         *string `gorm:"column:seed_owner;type:text"`
	SeedVersion       *int    `gorm:"column:seed_version;type:integer"`
	SeedSourceVersion *string `gorm:"column:seed_source_version;type:text"`

	CreatedAt time.Time `gorm:"column:created_at;type:datetime;not null"`
	UpdatedAt time.Time `gorm:"column:updated_at;type:datetime;not null"`
}

// TableName returns the canonical table name.
func (SourcePropertyDescriptorRow) TableName() string {
	return "source_property_descriptors"
}

// PropertyBindingRow links a workspace Property definition to a source
// property descriptor and owns the transform/precedence/effective-capability.
// Identity combines the definition identity with the source natural key; no
// surrogate binding ID is created.
type PropertyBindingRow struct {
	WorkspaceID        []byte `gorm:"column:workspace_id;type:blob;not null;check:length(workspace_id) = 16;primaryKey"`
	PropertyID         []byte `gorm:"column:property_id;type:blob;not null;check:length(property_id) = 16;primaryKey"`
	ProviderID         string `gorm:"column:provider_id;type:text;not null;primaryKey"`
	SourceInstanceID   string `gorm:"column:source_instance_id;type:text;not null;primaryKey"`
	ScopeKind          string `gorm:"column:scope_kind;type:text;not null;primaryKey"`
	ScopeExternalID    string `gorm:"column:scope_external_id;type:text;not null;primaryKey"`
	ExternalPropertyID string `gorm:"column:external_property_id;type:text;not null;primaryKey"`

	BindingOrdinal     int    `gorm:"column:binding_ordinal;type:integer;not null;check:binding_ordinal >= 0"`
	ReadTransform      string `gorm:"column:read_transform;type:text;not null"`
	Direction          string `gorm:"column:direction;type:text;not null;check:direction in ('read','write','bidirectional')"`
	EffectiveReadable  bool   `gorm:"column:effective_readable;type:boolean;not null"`
	EffectiveQueryable bool   `gorm:"column:effective_queryable;type:boolean;not null"`
	EffectiveWritable  bool   `gorm:"column:effective_writable;type:boolean;not null"`
	QueryProfile       string `gorm:"column:query_profile;type:text;not null"`
	MappingVersion     int    `gorm:"column:mapping_version;type:integer;not null;check:mapping_version >= 0"`
	ValueContractRev   int    `gorm:"column:value_contract_revision;type:integer;not null;check:value_contract_revision >= 0"`
	MappingProvenance  string `gorm:"column:mapping_provenance;type:text;not null"`
	ApprovalState      string `gorm:"column:approval_state;type:text;not null;check:approval_state in ('approved','pending','rejected')"`
	Lossiness          string `gorm:"column:lossiness;type:text;not null"`
	LifecycleState     string `gorm:"column:lifecycle_state;type:text;not null;check:lifecycle_state in ('active','tombstoned')"`

	SeedOwner         *string `gorm:"column:seed_owner;type:text"`
	SeedVersion       *int    `gorm:"column:seed_version;type:integer"`
	SeedSourceVersion *string `gorm:"column:seed_source_version;type:text"`

	CreatedAt time.Time `gorm:"column:created_at;type:datetime;not null"`
	UpdatedAt time.Time `gorm:"column:updated_at;type:datetime;not null"`
}

// TableName returns the canonical table name.
func (PropertyBindingRow) TableName() string {
	return "property_bindings"
}

// WorkspacePropertyTermRow stores an ordered search/legacy alias for a
// workspace Property. It is keyed by (workspace_id, property_id, term_kind,
// ordinal); a term_kind's term_value is unique per property. Native source
// keys are not terms (they live in source_property_descriptors).
type WorkspacePropertyTermRow struct {
	WorkspaceID    []byte `gorm:"column:workspace_id;type:blob;not null;check:length(workspace_id) = 16;primaryKey;uniqueIndex:idx_term_value,where:lifecycle_state = 'active'"`
	PropertyID     []byte `gorm:"column:property_id;type:blob;not null;check:length(property_id) = 16;primaryKey;uniqueIndex:idx_term_value,where:lifecycle_state = 'active'"`
	TermKind       string `gorm:"column:term_kind;type:text;not null;check:term_kind in ('search_alias','legacy_alias');primaryKey"`
	Ordinal        int    `gorm:"column:ordinal;type:integer;not null;check:ordinal >= 0;primaryKey"`
	TermValue      string `gorm:"column:term_value;type:text;not null;uniqueIndex:idx_term_value,where:lifecycle_state = 'active'"`
	LifecycleState string `gorm:"column:lifecycle_state;type:text;not null;default:'active';check:lifecycle_state in ('active','tombstoned')"`

	SeedOwner         *string `gorm:"column:seed_owner;type:text"`
	SeedVersion       *int    `gorm:"column:seed_version;type:integer"`
	SeedSourceVersion *string `gorm:"column:seed_source_version;type:text"`
}

// TableName returns the canonical table name.
func (WorkspacePropertyTermRow) TableName() string {
	return "workspace_property_terms"
}
