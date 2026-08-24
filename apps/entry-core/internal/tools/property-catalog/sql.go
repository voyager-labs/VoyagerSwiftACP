package propertycatalog

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
)

// fixedTimestamp is a deterministic literal for created_at/updated_at so the
// committed SQL file is byte-for-byte reproducible and never depends on wall
// clock.
const fixedTimestamp = "2026-08-20T00:00:00Z"

// RenderSQL renders the full-state seed SQL for a projection. It contains no
// transaction statements, no runtime path, no secret, and no Registry JSON
// blob. Each row is an idempotent INSERT ... SELECT FROM workspace_metadata
// WHERE singleton = 1 ... ON CONFLICT DO UPDATE so the WorkspaceID is injected
// at apply time without placeholder or JSON input. Every ON CONFLICT DO UPDATE
// is guarded by WHERE seed_owner = excluded.seed_owner so a conflicting
// NULL-seed provider row is skipped instead of having its ownership taken
// over; the post-apply read-back digest gate in applyCatalogSeedInTx then
// fails the whole transaction closed.
func RenderSQL(projection ProjectedCatalog) (string, error) {
	var builder strings.Builder
	builder.WriteString(sqlHeader())
	for _, definition := range projection.Definitions {
		builder.WriteString(renderDefinition(definition))
	}
	for _, descriptor := range projection.Descriptors {
		builder.WriteString(renderDescriptor(descriptor))
	}
	for _, binding := range projection.Bindings {
		builder.WriteString(renderBinding(binding))
	}
	for _, term := range projection.Terms {
		builder.WriteString(renderTerm(term))
	}
	// Trim trailing blank lines so the committed file has no trailing blank
	// line at EOF (git diff --check cleanliness).
	return strings.TrimRight(builder.String(), "\n") + "\n", nil
}

func sqlHeader() string {
	return `-- GENERATED FILE - DO NOT EDIT
-- Source: shared/system_property_registry.json (System Registry 2.4.1)
-- Full-state Workspace property catalog seed (seed version 1).
-- 278 workspace_property_definitions
-- 294 source_property_descriptors
-- 296 property_bindings
-- 441 workspace_property_terms
--
-- Each statement resolves the active WorkspaceID from workspace_metadata
-- (singleton = 1) and upserts one catalog row. No transaction statements,
-- runtime path, secret, or Registry JSON blob are present.

`
}

func renderDefinition(row DefinitionRow) string {
	var builder strings.Builder
	builder.WriteString("INSERT INTO workspace_property_definitions (\n")
	builder.WriteString("    workspace_id, property_id, origin, identity_scheme, namespace, canonical_key,\n")
	builder.WriteString("    display_name, description, value_type, cardinality, nullable, editable,\n")
	builder.WriteString("    default_hidden, default_pinned, db_indexed_hint, provenance, unit,\n")
	builder.WriteString("    default_display_unit, units_json, definition_revision, lifecycle_state,\n")
	builder.WriteString("    seed_owner, seed_version,\n")
	builder.WriteString("    seed_source_version, created_at, updated_at\n")
	builder.WriteString(")\nSELECT\n")
	builder.WriteString("    workspace_id,\n")
	builder.WriteString("    X'" + blobHex(row.PropertyID) + "',\n")
	builder.WriteString("    '" + row.Origin + "',\n")
	builder.WriteString("    '" + row.IdentityScheme + "',\n")
	builder.WriteString("    '" + sqlString(row.Namespace) + "',\n")
	builder.WriteString("    '" + sqlString(row.CanonicalKey) + "',\n")
	builder.WriteString("    '" + sqlString(row.DisplayName) + "',\n")
	builder.WriteString("    '" + sqlString(row.Description) + "',\n")
	builder.WriteString("    '" + row.ValueType + "',\n")
	builder.WriteString("    '" + row.Cardinality + "',\n")
	builder.WriteString(boolLiteral(row.Nullable) + ",\n")
	builder.WriteString(boolLiteral(row.Editable) + ",\n")
	builder.WriteString(boolLiteral(row.DefaultHidden) + ",\n")
	builder.WriteString(boolLiteral(row.DefaultPinned) + ",\n")
	builder.WriteString(boolLiteral(row.DBIndexedHint) + ",\n")
	builder.WriteString("    '" + sqlString(row.Provenance) + "',\n")
	builder.WriteString("    '" + sqlString(row.Unit) + "',\n")
	builder.WriteString("    '" + sqlString(row.DefaultDisplayUnit) + "',\n")
	builder.WriteString("    '" + sqlString(row.UnitsJSON) + "',\n")
	builder.WriteString(intLiteral(row.DefinitionRev) + ",\n")
	builder.WriteString("    '" + row.LifecycleState + "',\n")
	builder.WriteString("    '" + row.SeedOwner + "',\n")
	builder.WriteString(intLiteral(row.SeedVersion) + ",\n")
	builder.WriteString("    '" + row.SeedSourceVersion + "',\n")
	builder.WriteString("    '" + fixedTimestamp + "',\n")
	builder.WriteString("    '" + fixedTimestamp + "'\n")
	builder.WriteString("FROM workspace_metadata\nWHERE singleton = 1\n")
	builder.WriteString("ON CONFLICT (workspace_id, property_id) DO UPDATE SET\n")
	builder.WriteString("    display_name = excluded.display_name,\n")
	builder.WriteString("    description = excluded.description,\n")
	builder.WriteString("    value_type = excluded.value_type,\n")
	builder.WriteString("    cardinality = excluded.cardinality,\n")
	builder.WriteString("    nullable = excluded.nullable,\n")
	builder.WriteString("    editable = excluded.editable,\n")
	builder.WriteString("    default_hidden = excluded.default_hidden,\n")
	builder.WriteString("    default_pinned = excluded.default_pinned,\n")
	builder.WriteString("    db_indexed_hint = excluded.db_indexed_hint,\n")
	builder.WriteString("    provenance = excluded.provenance,\n")
	builder.WriteString("    unit = excluded.unit,\n")
	builder.WriteString("    default_display_unit = excluded.default_display_unit,\n")
	builder.WriteString("    units_json = excluded.units_json,\n")
	builder.WriteString("    definition_revision = excluded.definition_revision,\n")
	builder.WriteString("    lifecycle_state = excluded.lifecycle_state,\n")
	builder.WriteString("    seed_owner = excluded.seed_owner,\n")
	builder.WriteString("    seed_version = excluded.seed_version,\n")
	builder.WriteString("    seed_source_version = excluded.seed_source_version,\n")
	builder.WriteString("    updated_at = excluded.updated_at\n")
	builder.WriteString("WHERE seed_owner = excluded.seed_owner;\n\n")
	return builder.String()
}

func renderDescriptor(row DescriptorRow) string {
	var builder strings.Builder
	builder.WriteString("INSERT INTO source_property_descriptors (\n")
	builder.WriteString("    workspace_id, provider_id, source_instance_id, scope_kind, scope_external_id,\n")
	builder.WriteString("    external_property_id, authority_kind, native_type, native_cardinality,\n")
	builder.WriteString("    source_readable, source_queryable, source_writable, lifecycle_state,\n")
	builder.WriteString("    availability_note, seed_owner, seed_version, seed_source_version,\n")
	builder.WriteString("    created_at, updated_at\n")
	builder.WriteString(")\nSELECT\n")
	builder.WriteString("    workspace_id,\n")
	builder.WriteString("    '" + sqlString(row.Ref.ProviderID) + "',\n")
	builder.WriteString("    '" + sqlString(row.Ref.SourceInstanceID) + "',\n")
	builder.WriteString("    '" + string(row.Ref.ScopeKind) + "',\n")
	builder.WriteString("    '" + sqlString(row.Ref.ScopeExternalID) + "',\n")
	builder.WriteString("    '" + sqlString(row.Ref.ExternalPropertyID) + "',\n")
	builder.WriteString("    '" + row.Authority + "',\n")
	builder.WriteString("    '" + sqlString(row.NativeType) + "',\n")
	builder.WriteString("    '" + row.NativeCardinality + "',\n")
	builder.WriteString(boolLiteral(row.SourceReadable) + ",\n")
	builder.WriteString(boolLiteral(row.SourceQueryable) + ",\n")
	builder.WriteString(boolLiteral(row.SourceWritable) + ",\n")
	builder.WriteString("    '" + row.LifecycleState + "',\n")
	builder.WriteString("    '" + sqlString(row.AvailabilityNote) + "',\n")
	builder.WriteString("    '" + row.SeedOwner + "',\n")
	builder.WriteString(intLiteral(row.SeedVersion) + ",\n")
	builder.WriteString("    '" + row.SeedSourceVersion + "',\n")
	builder.WriteString("    '" + fixedTimestamp + "',\n")
	builder.WriteString("    '" + fixedTimestamp + "'\n")
	builder.WriteString("FROM workspace_metadata\nWHERE singleton = 1\n")
	builder.WriteString("ON CONFLICT (workspace_id, provider_id, source_instance_id, scope_kind, scope_external_id, external_property_id) DO UPDATE SET\n")
	builder.WriteString("    authority_kind = excluded.authority_kind,\n")
	builder.WriteString("    native_type = excluded.native_type,\n")
	builder.WriteString("    native_cardinality = excluded.native_cardinality,\n")
	builder.WriteString("    source_readable = excluded.source_readable,\n")
	builder.WriteString("    source_queryable = excluded.source_queryable,\n")
	builder.WriteString("    source_writable = excluded.source_writable,\n")
	builder.WriteString("    lifecycle_state = excluded.lifecycle_state,\n")
	builder.WriteString("    availability_note = excluded.availability_note,\n")
	builder.WriteString("    seed_owner = excluded.seed_owner,\n")
	builder.WriteString("    seed_version = excluded.seed_version,\n")
	builder.WriteString("    seed_source_version = excluded.seed_source_version,\n")
	builder.WriteString("    updated_at = excluded.updated_at\n")
	builder.WriteString("WHERE seed_owner = excluded.seed_owner;\n\n")
	return builder.String()
}

func renderBinding(row BindingRow) string {
	var builder strings.Builder
	builder.WriteString("INSERT INTO property_bindings (\n")
	builder.WriteString("    workspace_id, property_id, provider_id, source_instance_id, scope_kind,\n")
	builder.WriteString("    scope_external_id, external_property_id, binding_ordinal, read_transform,\n")
	builder.WriteString("    direction, effective_readable, effective_queryable, effective_writable,\n")
	builder.WriteString("    query_profile, mapping_version, value_contract_revision, mapping_provenance,\n")
	builder.WriteString("    approval_state, lossiness, lifecycle_state, seed_owner, seed_version,\n")
	builder.WriteString("    seed_source_version, created_at, updated_at\n")
	builder.WriteString(")\nSELECT\n")
	builder.WriteString("    workspace_id,\n")
	builder.WriteString("    X'" + blobHex(row.PropertyID) + "',\n")
	builder.WriteString("    '" + sqlString(row.SourceRef.ProviderID) + "',\n")
	builder.WriteString("    '" + sqlString(row.SourceRef.SourceInstanceID) + "',\n")
	builder.WriteString("    '" + string(row.SourceRef.ScopeKind) + "',\n")
	builder.WriteString("    '" + sqlString(row.SourceRef.ScopeExternalID) + "',\n")
	builder.WriteString("    '" + sqlString(row.SourceRef.ExternalPropertyID) + "',\n")
	builder.WriteString(intLiteral(row.BindingOrdinal) + ",\n")
	builder.WriteString("    '" + sqlString(row.ReadTransform) + "',\n")
	builder.WriteString("    '" + row.Direction + "',\n")
	builder.WriteString(boolLiteral(row.EffectiveReadable) + ",\n")
	builder.WriteString(boolLiteral(row.EffectiveQueryable) + ",\n")
	builder.WriteString(boolLiteral(row.EffectiveWritable) + ",\n")
	builder.WriteString("    '" + sqlString(row.QueryProfile) + "',\n")
	builder.WriteString(intLiteral(row.MappingVersion) + ",\n")
	builder.WriteString(intLiteral(row.ValueContractRevision) + ",\n")
	builder.WriteString("    '" + sqlString(row.MappingProvenance) + "',\n")
	builder.WriteString("    '" + row.ApprovalState + "',\n")
	builder.WriteString("    '" + sqlString(row.Lossiness) + "',\n")
	builder.WriteString("    '" + row.LifecycleState + "',\n")
	builder.WriteString("    '" + row.SeedOwner + "',\n")
	builder.WriteString(intLiteral(row.SeedVersion) + ",\n")
	builder.WriteString("    '" + row.SeedSourceVersion + "',\n")
	builder.WriteString("    '" + fixedTimestamp + "',\n")
	builder.WriteString("    '" + fixedTimestamp + "'\n")
	builder.WriteString("FROM workspace_metadata\nWHERE singleton = 1\n")
	builder.WriteString("ON CONFLICT (workspace_id, property_id, provider_id, source_instance_id, scope_kind, scope_external_id, external_property_id) DO UPDATE SET\n")
	builder.WriteString("    binding_ordinal = excluded.binding_ordinal,\n")
	builder.WriteString("    read_transform = excluded.read_transform,\n")
	builder.WriteString("    direction = excluded.direction,\n")
	builder.WriteString("    effective_readable = excluded.effective_readable,\n")
	builder.WriteString("    effective_queryable = excluded.effective_queryable,\n")
	builder.WriteString("    effective_writable = excluded.effective_writable,\n")
	builder.WriteString("    query_profile = excluded.query_profile,\n")
	builder.WriteString("    mapping_version = excluded.mapping_version,\n")
	builder.WriteString("    value_contract_revision = excluded.value_contract_revision,\n")
	builder.WriteString("    mapping_provenance = excluded.mapping_provenance,\n")
	builder.WriteString("    approval_state = excluded.approval_state,\n")
	builder.WriteString("    lossiness = excluded.lossiness,\n")
	builder.WriteString("    lifecycle_state = excluded.lifecycle_state,\n")
	builder.WriteString("    seed_owner = excluded.seed_owner,\n")
	builder.WriteString("    seed_version = excluded.seed_version,\n")
	builder.WriteString("    seed_source_version = excluded.seed_source_version,\n")
	builder.WriteString("    updated_at = excluded.updated_at\n")
	builder.WriteString("WHERE seed_owner = excluded.seed_owner;\n\n")
	return builder.String()
}

func renderTerm(row TermRow) string {
	var builder strings.Builder
	builder.WriteString("INSERT INTO workspace_property_terms (\n")
	builder.WriteString("    workspace_id, property_id, term_kind, ordinal, term_value, lifecycle_state,\n")
	builder.WriteString("    seed_owner, seed_version, seed_source_version\n")
	builder.WriteString(")\nSELECT\n")
	builder.WriteString("    workspace_id,\n")
	builder.WriteString("    X'" + blobHex(row.PropertyID) + "',\n")
	builder.WriteString("    '" + row.TermKind + "',\n")
	builder.WriteString(intLiteral(row.Ordinal) + ",\n")
	builder.WriteString("    '" + sqlString(row.TermValue) + "',\n")
	builder.WriteString("    '" + row.LifecycleState + "',\n")
	builder.WriteString("    '" + row.SeedOwner + "',\n")
	builder.WriteString(intLiteral(row.SeedVersion) + ",\n")
	builder.WriteString("    '" + row.SeedSourceVersion + "'\n")
	builder.WriteString("FROM workspace_metadata\nWHERE singleton = 1\n")
	builder.WriteString("ON CONFLICT (workspace_id, property_id, term_kind, ordinal) DO UPDATE SET\n")
	builder.WriteString("    term_value = excluded.term_value,\n")
	builder.WriteString("    lifecycle_state = excluded.lifecycle_state,\n")
	builder.WriteString("    seed_owner = excluded.seed_owner,\n")
	builder.WriteString("    seed_version = excluded.seed_version,\n")
	builder.WriteString("    seed_source_version = excluded.seed_source_version\n")
	builder.WriteString("WHERE seed_owner = excluded.seed_owner;\n\n")
	return builder.String()
}

// SQLSHA256 computes the SHA-256 of the rendered SQL body.
func SQLSHA256(sqlBody string) string {
	sum := sha256.Sum256([]byte(sqlBody))
	return hex.EncodeToString(sum[:])
}

// DatasetDigestHex returns the canonical dataset digest as hex.
func DatasetDigestHex(projection ProjectedCatalog) string {
	return hex.EncodeToString(projection.Digest[:])
}

func blobHex(id [16]byte) string {
	return hex.EncodeToString(id[:])
}

func boolLiteral(value bool) string {
	if value {
		return "1"
	}
	return "0"
}

func intLiteral(value int) string {
	return fmt.Sprintf("%d", value)
}

// sqlString escapes a string literal for SQLite single-quoted text.
func sqlString(value string) string {
	return strings.ReplaceAll(value, "'", "''")
}
