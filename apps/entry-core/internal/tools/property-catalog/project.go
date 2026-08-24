package propertycatalog

import (
	"encoding/json"
	"fmt"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

// Canonical seed metadata shared by every generated row and the seed metadata
// record. These values are the reviewed System Registry projection contract.
const (
	// SeedOwner is the all-or-none provenance owner of bundled rows.
	SeedOwner = "system_property_registry"
	// SeedVersion is the immutable seed ordinal (1 for the first full-state seed).
	SeedVersion = 1
	// SeedSourceVersion is the System Registry version the seed was projected from.
	SeedSourceVersion = "2.4.1"
	// Provenance is the reviewed mapping provenance carried by every seed row.
	Provenance = SeedOwner + "@" + SeedSourceVersion
	// ApprovalState marks the reviewed binding approval.
	ApprovalState = "approved"
	// MappingVersion and ValueContractRevision are the transform/value contract versions.
	MappingVersion = 1
	// ValueContractRevision is the canonical value-contract revision.
	ValueContractRevision = 1

	// SourceInstanceID is the canonical built-in macOS metadata source identity
	// derived by source.DeriveSourceIdentity("macos-metadata", "built-in",
	// stable). It is frozen as a literal; runtime never recomputes it.
	SourceInstanceID = "src:C-AqodQY5xZfdP1ejkuCjkjmLeWd0Ws01zflCLYITkU"
	// SourceScopeKind is the scope of the built-in macOS source.
	SourceScopeKind = "system"
	// SourceScopeExternalID is the external scope identifier of the macOS source.
	SourceScopeExternalID = "macos"
)

// providerByPrefix maps the Registry system-key prefix to the provider_id used
// in the source natural reference.
var providerByPrefix = map[string]string{
	"mditem":     "macos.mditem",
	"nsurl":      "macos.nsurl",
	"mdimporter": "macos.mdimporter",
}

// readTransformOverride maps a canonical_key to its reviewed read_transform.
// Only transform-dependent properties are overridden; everything else uses
// identity.
var readTransformOverride = map[string]string{
	"filesystem.name_full": "identity",
	"filesystem.extension": "filename_extension",
	"filesystem.name_stem": "filename_stem",
}

// queryProfileOverride maps a canonical_key to its reviewed query_profile.
var queryProfileOverride = map[string]string{
	"filesystem.name_full": "mdquery_identity",
	"filesystem.extension": "transform_unavailable",
	"filesystem.name_stem": "transform_unavailable",
}

var nativeTypeOverride = map[string]string{
	"mditem:kMDItemFSName":            "string",
	"mditem:kMDItemUserTags":          "string_list",
	"nsurl:NSURLTagNamesKey":          "string_list",
	"nsurl:NSURLKeysOfUnsetValuesKey": "string_list",
}

// ProjectSystemRegistry는 System Registry를 정확한 active-set
// PropertyCatalogSnapshot(278 정의, 294 source descriptor, 296 binding, 441
// term)과 전체 SQL row model로 투영한다. 투영된 snapshot은 검증되고 canonical
// dataset digest가 함께 반환된다.
func ProjectSystemRegistry(registry *SystemPropertyRegistry) (ProjectedCatalog, error) {
	// row의 seed_source_version/provenance는 reviewed 상수, metadata는 입력
	// registry.Version을 쓴다. 두 값이 어긋나면 fresh seed 적용 뒤 다음 시작에서
	// source-version drift로 차단되므로 generation 시점에 실패시킨다.
	if registry.Version != SeedSourceVersion {
		return ProjectedCatalog{}, fmt.Errorf("system registry version %q does not match SeedSourceVersion %q; update project.go constants and regenerate", registry.Version, SeedSourceVersion)
	}
	var projection ProjectedCatalog

	descriptorByRef := make(map[string]entry.SourcePropertyDescriptor)
	descriptorRowByRef := make(map[string]DescriptorRow)
	bindingOrdinal := make(map[entry.PropertyID]int)

	for _, category := range registry.CategoriesSorted() {
		for _, key := range registry.KeysSorted(category) {
			descriptor := registry.Categories[category][key]
			canonicalKey := category + "." + key

			propertyID, err := entry.RegistryPropertyID(canonicalKey)
			if err != nil {
				return ProjectedCatalog{}, fmt.Errorf("derive id for %s: %w", canonicalKey, err)
			}

			valueType, cardinality, mapped := canonicalTypeMapping(descriptor.Type, canonicalKey)
			if !mapped {
				return ProjectedCatalog{}, fmt.Errorf("registry type %q for %s has no canonical mapping; add a reviewed mapping or fix the registry", descriptor.Type, canonicalKey)
			}
			unit := ""
			if descriptor.UnitSpec != nil {
				unit = descriptor.UnitSpec.CanonicalUnit
			}

			projection.Snapshot.Definitions = append(projection.Snapshot.Definitions, entry.WorkspacePropertyDefinition{
				PropertyID:         propertyID,
				Origin:             entry.PropertyOriginBuiltIn,
				IdentityScheme:     entry.PropertyIdentitySchemeRegistryDerived,
				Namespace:          "system",
				CanonicalKey:       canonicalKey,
				DisplayName:        descriptor.UILabel,
				Description:        descriptor.Description,
				ValueType:          valueType,
				Cardinality:        cardinality,
				Nullable:           false,
				Editable:           false,
				DefaultHidden:      descriptor.UIHidden,
				DefaultPinned:      descriptor.UIPinned,
				DBIndexedHint:      descriptor.DBIndexed,
				DefinitionRev:      ValueContractRevision,
				Provenance:         entry.PropertyProvenanceSystem,
				MappingProvenance:  Provenance,
				Unit:               strPtrOrNil(unit),
				DefaultDisplayUnit: defaultDisplayUnit(descriptor.UnitSpec),
				Units:              propertyUnits(descriptor.UnitSpec),
				Lifecycle:          entry.PropertyLifecycleActive,
			})
			projection.Definitions = append(projection.Definitions, DefinitionRow{
				PropertyID:         propertyID,
				Origin:             string(entry.PropertyOriginBuiltIn),
				IdentityScheme:     string(entry.PropertyIdentitySchemeRegistryDerived),
				Namespace:          "system",
				CanonicalKey:       canonicalKey,
				DisplayName:        descriptor.UILabel,
				Description:        descriptor.Description,
				ValueType:          string(valueType),
				Cardinality:        string(cardinality),
				Nullable:           false,
				Editable:           false,
				DefaultHidden:      descriptor.UIHidden,
				DefaultPinned:      descriptor.UIPinned,
				DBIndexedHint:      descriptor.DBIndexed,
				Provenance:         Provenance,
				Unit:               unit,
				DefaultDisplayUnit: defaultDisplayUnit(descriptor.UnitSpec),
				UnitsJSON:          unitsJSON(descriptor.UnitSpec),
				DefinitionRev:      ValueContractRevision,
				LifecycleState:     string(entry.PropertyLifecycleActive),
				SeedOwner:          SeedOwner,
				SeedVersion:        SeedVersion,
				SeedSourceVersion:  SeedSourceVersion,
			})

			readTransform := readTransformOverride[canonicalKey]
			if readTransform == "" {
				readTransform = "identity"
			}
			queryProfile := queryProfileOverride[canonicalKey]

			for _, systemKey := range descriptor.SystemKeys {
				provider, suffix, ok := splitSystemKey(systemKey)
				if !ok {
					return ProjectedCatalog{}, fmt.Errorf("malformed system key %q", systemKey)
				}
				providerID, ok := providerByPrefix[provider]
				if !ok {
					return ProjectedCatalog{}, fmt.Errorf("unknown system key prefix %q", provider)
				}
				ref := entry.SourcePropertyRef{
					ProviderID:         providerID,
					SourceInstanceID:   SourceInstanceID,
					ScopeKind:          entry.SourceScopeKindSystem,
					ScopeExternalID:    SourceScopeExternalID,
					ExternalPropertyID: suffix,
				}

				// A source descriptor exists once per unique natural ref. The
				// FSName key appears in three properties but is one descriptor.
				refKey := ref.ProviderID + "\x00" + ref.SourceInstanceID + "\x00" + ref.ExternalPropertyID
				if _, exists := descriptorByRef[refKey]; !exists {
					sourceQueryable := providerID != "macos.nsurl"
					descriptorByRef[refKey] = entry.SourcePropertyDescriptor{
						Ref:               ref,
						NativeKey:         systemKey,
						NativeType:        nativeTypeForKey(systemKey, descriptor.Type),
						NativeCardinality: nativeCardinality(nativeTypeForKey(systemKey, descriptor.Type)),
						Authority:         entry.AuthorityKindSystem,
						SourceReadable:    true,
						SourceQueryable:   sourceQueryable,
						SourceWritable:    false,
						AvailabilityNote:  descriptor.Availability,
						Lifecycle:         entry.PropertyLifecycleActive,
					}
					descriptorRowByRef[refKey] = DescriptorRow{
						Ref:               ref,
						NativeKey:         systemKey,
						NativeType:        nativeTypeForKey(systemKey, descriptor.Type),
						NativeCardinality: string(nativeCardinality(nativeTypeForKey(systemKey, descriptor.Type))),
						Authority:         string(entry.AuthorityKindSystem),
						SourceReadable:    true,
						SourceQueryable:   sourceQueryable,
						SourceWritable:    false,
						LifecycleState:    string(entry.PropertyLifecycleActive),
						AvailabilityNote:  descriptor.Availability,
						SeedOwner:         SeedOwner,
						SeedVersion:       SeedVersion,
						SeedSourceVersion: SeedSourceVersion,
					}
				}

				ordinal := bindingOrdinal[propertyID]
				bindingOrdinal[propertyID] = ordinal + 1

				effectiveReadable := true
				effectiveQueryable := queryProfile == "mdquery" || queryProfile == "mdquery_identity"
				lossiness := "none"
				if readTransform != "identity" {
					lossiness = "transform"
				}

				binding := entry.PropertyBinding{
					PropertyID:            propertyID,
					SourceRef:             ref,
					BindingOrdinal:        ordinal,
					ReadTransform:         readTransform,
					Direction:             "read",
					EffectiveReadable:     effectiveReadable,
					EffectiveQueryable:    effectiveQueryable,
					EffectiveWritable:     false,
					QueryProfile:          queryProfile,
					MappingVersion:        MappingVersion,
					ValueContractRevision: ValueContractRevision,
					Provenance:            Provenance,
					ApprovalState:         ApprovalState,
					Lossiness:             lossiness,
					Lifecycle:             entry.PropertyLifecycleActive,
				}
				projection.Snapshot.Bindings = append(projection.Snapshot.Bindings, binding)
				projection.Bindings = append(projection.Bindings, BindingRow{
					PropertyID:            propertyID,
					SourceRef:             ref,
					BindingOrdinal:        ordinal,
					ReadTransform:         readTransform,
					Direction:             "read",
					EffectiveReadable:     effectiveReadable,
					EffectiveQueryable:    effectiveQueryable,
					EffectiveWritable:     false,
					QueryProfile:          queryProfile,
					MappingVersion:        MappingVersion,
					ValueContractRevision: ValueContractRevision,
					MappingProvenance:     Provenance,
					ApprovalState:         ApprovalState,
					Lossiness:             lossiness,
					LifecycleState:        string(entry.PropertyLifecycleActive),
					SeedOwner:             SeedOwner,
					SeedVersion:           SeedVersion,
					SeedSourceVersion:     SeedSourceVersion,
				})
			}

			// Terms: search aliases then legacy keys, each zero-based ordinal.
			searchOrdinal := 0
			for _, alias := range descriptor.SearchAliases {
				term := workspaceTerm(propertyID, "search_alias", searchOrdinal, alias)
				projection.Snapshot.Terms = append(projection.Snapshot.Terms, term)
				projection.Terms = append(projection.Terms, TermRow{
					PropertyID:        propertyID,
					TermKind:          "search_alias",
					Ordinal:           searchOrdinal,
					TermValue:         alias,
					LifecycleState:    string(entry.PropertyLifecycleActive),
					SeedOwner:         SeedOwner,
					SeedVersion:       SeedVersion,
					SeedSourceVersion: SeedSourceVersion,
				})
				searchOrdinal++
			}
			legacyOrdinal := 0
			for _, legacyKey := range descriptor.LegacyKeys {
				term := workspaceTerm(propertyID, "legacy_alias", legacyOrdinal, legacyKey)
				projection.Snapshot.Terms = append(projection.Snapshot.Terms, term)
				projection.Terms = append(projection.Terms, TermRow{
					PropertyID:        propertyID,
					TermKind:          "legacy_alias",
					Ordinal:           legacyOrdinal,
					TermValue:         legacyKey,
					LifecycleState:    string(entry.PropertyLifecycleActive),
					SeedOwner:         SeedOwner,
					SeedVersion:       SeedVersion,
					SeedSourceVersion: SeedSourceVersion,
				})
				legacyOrdinal++
			}
		}
	}

	// Descriptors are emitted in deterministic natural-ref order.
	refKeys := make([]string, 0, len(descriptorByRef))
	for refKey := range descriptorByRef {
		refKeys = append(refKeys, refKey)
	}
	sortStrings(refKeys)
	for _, refKey := range refKeys {
		projection.Snapshot.Descriptors = append(projection.Snapshot.Descriptors, descriptorByRef[refKey])
		projection.Descriptors = append(projection.Descriptors, descriptorRowByRef[refKey])
	}

	if err := projection.Snapshot.Validate(); err != nil {
		return ProjectedCatalog{}, fmt.Errorf("projected snapshot invalid: %w", err)
	}
	digest, err := projection.Snapshot.Digest()
	if err != nil {
		return ProjectedCatalog{}, fmt.Errorf("compute dataset digest: %w", err)
	}
	projection.Digest = digest
	return projection, nil
}

// WorkspaceTerm은 search/legacy alias term 값을 생성한다.
func workspaceTerm(propertyID entry.PropertyID, termKind string, ordinal int, termValue string) entry.WorkspacePropertyTerm {
	return entry.WorkspacePropertyTerm{
		PropertyID: propertyID,
		TermKind:   termKind,
		Ordinal:    ordinal,
		TermValue:  termValue,
	}
}

// canonicalTypeMapping maps a Registry native type to the canonical Workspace
// value type and cardinality, applying reviewed overrides. An unmapped type
// reports ok=false so projection fails closed instead of silently projecting
// an unknown contract as text/one.
func canonicalTypeMapping(registryType, canonicalKey string) (entry.PropertyType, entry.PropertyCardinality, bool) {
	switch registryType {
	case "string":
		if canonicalKey == "misc.keys_of_unset_values" {
			// reviewed override: nsurl:NSURLKeysOfUnsetValuesKey returns an
			// array of NSString keys, so the canonical contract is text/many.
			return entry.PropertyTypeText, entry.PropertyCardinalityMany, true
		}
		return entry.PropertyTypeText, entry.PropertyCardinalityOne, true
	case "number":
		return entry.PropertyTypeNumber, entry.PropertyCardinalityOne, true
	case "boolean":
		return entry.PropertyTypeBoolean, entry.PropertyCardinalityOne, true
	case "date":
		return entry.PropertyTypeDateTime, entry.PropertyCardinalityOne, true
	case "string_list":
		return entry.PropertyTypeText, entry.PropertyCardinalityMany, true
	case "categorical":
		if canonicalKey == "misc.tag_names" {
			// reviewed override: source tag array is select + many
			return entry.PropertyTypeSelect, entry.PropertyCardinalityMany, true
		}
		return entry.PropertyTypeSelect, entry.PropertyCardinalityOne, true
	default:
		return entry.PropertyTypeText, entry.PropertyCardinalityOne, false
	}
}

// nativeCardinality maps a Registry native type to the source native
// cardinality (one unless it is a multi-valued list).
func nativeCardinality(registryType string) entry.PropertyCardinality {
	if registryType == "string_list" {
		return entry.PropertyCardinalityMany
	}
	return entry.PropertyCardinalityOne
}

func nativeTypeForKey(systemKey, registryType string) string {
	if override := nativeTypeOverride[systemKey]; override != "" {
		return override
	}
	return registryType
}

func strPtrOrNil(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

// defaultDisplayUnit은 UnitSpec의 default_display_unit을 추출한다.
func defaultDisplayUnit(spec *UnitSpec) string {
	if spec == nil {
		return ""
	}
	return spec.DefaultDisplayUnit
}

// propertyUnits은 UnitSpec의 units 변환표를 도메인 값으로 투영한다. Registry
// 배열 순서가 곧 ordinal 순서다.
func propertyUnits(spec *UnitSpec) []entry.PropertyUnit {
	if spec == nil {
		return nil
	}
	units := make([]entry.PropertyUnit, 0, len(spec.Units))
	for _, unit := range spec.Units {
		units = append(units, entry.PropertyUnit{
			Code: unit.Code, Label: unit.Label, FactorToCanonical: unit.FactorToCanonical,
		})
	}
	return units
}

// unitsJSON은 units 변환표를 canonical JSON 인코딩으로 직렬화한다. 필드 순서는
// 구조체 태그 순서로 고정되고 배열 순서는 Registry 문서 순서를 따르므로 결정적이다.
func unitsJSON(spec *UnitSpec) string {
	units := propertyUnits(spec)
	if len(units) == 0 {
		return ""
	}
	entries := make([]unitsJSONEntry, 0, len(units))
	for _, unit := range units {
		entries = append(entries, unitsJSONEntry{
			Code: unit.Code, Label: unit.Label, FactorToCanonical: unit.FactorToCanonical,
		})
	}
	data, err := json.Marshal(entries)
	if err != nil {
		panic("unitsJSON marshal failed: " + err.Error())
	}
	return string(data)
}

// unitsJSONEntry는 units_json 컬럼의 canonical JSON 항목이다. generator와
// persistence mapper가 동일한 필드 순서를 공유한다.
type unitsJSONEntry struct {
	Code              string `json:"code"`
	Label             string `json:"label"`
	FactorToCanonical string `json:"factor_to_canonical"`
}

// DeriveSourceInstanceID returns the exact canonical built-in macOS source
// identity. It is exposed for the parity test so the frozen literal is
// continuously proven against the derivation function.
func DeriveSourceInstanceID() string {
	identity, err := source.DeriveSourceIdentity("macos-metadata", "built-in", entry.IdentityStrengthStable)
	if err != nil {
		return ""
	}
	return identity.SourceID
}
