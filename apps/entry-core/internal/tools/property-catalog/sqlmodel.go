package propertycatalog

import (
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// DefinitionRow carries every column of a workspace_property_definitions row.
// It is separate from the digest snapshot because the digest intentionally
// excludes SQL-only presentation/flag columns (description, nullable,
// default_hidden, ...) and workspace_id.
type DefinitionRow struct {
	PropertyID        entry.PropertyID
	Origin            string
	IdentityScheme    string
	Namespace         string
	CanonicalKey      string
	DisplayName       string
	Description       string
	ValueType         string
	Cardinality       string
	Nullable          bool
	Editable          bool
	DefaultHidden     bool
	DefaultPinned     bool
	DBIndexedHint     bool
	Provenance        string
	Unit              string
	DefinitionRev     int
	LifecycleState    string
	SeedOwner         string
	SeedVersion       int
	SeedSourceVersion string
}

// DescriptorRow carries every column of a source_property_descriptors row.
type DescriptorRow struct {
	Ref               entry.SourcePropertyRef
	NativeKey         string
	NativeType        string
	NativeCardinality string
	Authority         string
	SourceReadable    bool
	SourceQueryable   bool
	SourceWritable    bool
	LifecycleState    string
	AvailabilityNote  string
	SeedOwner         string
	SeedVersion       int
	SeedSourceVersion string
}

// BindingRow carries every column of a property_bindings row.
type BindingRow struct {
	PropertyID            entry.PropertyID
	SourceRef             entry.SourcePropertyRef
	BindingOrdinal        int
	ReadTransform         string
	Direction             string
	EffectiveReadable     bool
	EffectiveQueryable    bool
	EffectiveWritable     bool
	QueryProfile          string
	MappingVersion        int
	ValueContractRevision int
	MappingProvenance     string
	ApprovalState         string
	Lossiness             string
	LifecycleState        string
	SeedOwner             string
	SeedVersion           int
	SeedSourceVersion     string
}

// TermRow carries every column of a workspace_property_terms row.
type TermRow struct {
	PropertyID        entry.PropertyID
	TermKind          string
	Ordinal           int
	TermValue         string
	LifecycleState    string
	SeedOwner         string
	SeedVersion       int
	SeedSourceVersion string
}

// ProjectedCatalog is the full projection result: the digest snapshot plus the
// SQL row models for rendering.
type ProjectedCatalog struct {
	Snapshot    entry.PropertyCatalogSnapshot
	Digest      [32]byte
	Definitions []DefinitionRow
	Descriptors []DescriptorRow
	Bindings    []BindingRow
	Terms       []TermRow
}
