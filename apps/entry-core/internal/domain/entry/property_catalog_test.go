package entry

import (
	"errors"
	"testing"
)

func mustSourcePropertyRef(t *testing.T, providerID string) SourcePropertyRef {
	t.Helper()
	ref := SourcePropertyRef{
		ProviderID: providerID, SourceInstanceID: validSourceID,
		ScopeKind: SourceScopeKindSystem, ScopeExternalID: "macos",
		ExternalPropertyID: "kMDItemFSName",
	}
	if err := ref.Validate(); err != nil {
		t.Fatal(err)
	}
	return ref
}

func TestSourcePropertyCatalogContracts(t *testing.T) {
	definition := WorkspacePropertyDefinition{
		PropertyID: mustRegistryPropertyID("filesystem.extension"), Origin: PropertyOriginBuiltIn,
		IdentityScheme: PropertyIdentitySchemeRegistryDerived, Namespace: "system",
		CanonicalKey: "filesystem.extension", DisplayName: "Extension",
		ValueType: PropertyTypeSelect, Cardinality: PropertyCardinalityOne,
		Editable: false, Provenance: PropertyProvenanceSystem, Lifecycle: PropertyLifecycleActive,
	}
	if definition.Validate() != nil {
		t.Fatal("definition contract rejected")
	}
	descriptor := SourcePropertyDescriptor{
		Ref: mustSourcePropertyRef(t, "macos.mditem"), NativeKey: "kMDItemFSName",
		NativeType: "string", NativeCardinality: PropertyCardinalityOne,
		Authority: AuthorityKindSystem, SourceReadable: true, SourceQueryable: true,
		Lifecycle: PropertyLifecycleActive,
	}
	if descriptor.Validate() != nil {
		t.Fatal("descriptor contract rejected")
	}
	binding := PropertyBinding{
		PropertyID: definition.PropertyID, SourceRef: descriptor.Ref,
		ReadTransform: "filename_extension", Direction: "read", EffectiveReadable: true,
		EffectiveQueryable: false, EffectiveWritable: false, QueryProfile: "transform_unavailable",
		MappingVersion: 1, ValueContractRevision: 1, Provenance: "system_property_registry@2.4.1",
		ApprovalState: "approved", Lossiness: "none", Lifecycle: PropertyLifecycleActive,
	}
	if binding.Validate() != nil {
		t.Fatal("binding contract rejected")
	}
	term := WorkspacePropertyTerm{
		PropertyID: definition.PropertyID, TermKind: "search_alias", Ordinal: 0, TermValue: "ext",
	}
	if term.Validate() != nil {
		t.Fatal("term contract rejected")
	}

	snapshot := PropertyCatalogSnapshot{
		Definitions: []WorkspacePropertyDefinition{definition},
		Descriptors: []SourcePropertyDescriptor{descriptor},
		Bindings:    []PropertyBinding{binding},
		Terms:       []WorkspacePropertyTerm{term},
	}
	if err := snapshot.Validate(); err != nil {
		t.Fatalf("snapshot contract rejected: %v", err)
	}
	digest, err := snapshot.Digest()
	if err != nil {
		t.Fatalf("Digest() error = %v", err)
	}
	if digest == [32]byte{} {
		t.Fatal("digest must be non-zero")
	}
}

func TestSourcePropertyCatalogDigestOrderIndependence(t *testing.T) {
	definition := WorkspacePropertyDefinition{
		PropertyID: mustRegistryPropertyID("filesystem.extension"), Origin: PropertyOriginBuiltIn,
		IdentityScheme: PropertyIdentitySchemeRegistryDerived, Namespace: "system",
		CanonicalKey: "filesystem.extension", DisplayName: "Extension",
		ValueType: PropertyTypeSelect, Cardinality: PropertyCardinalityOne,
		Editable: false, Provenance: PropertyProvenanceSystem, Lifecycle: PropertyLifecycleActive,
	}
	other := definition
	other.PropertyID = mustRegistryPropertyID("filesystem.name_full")
	other.CanonicalKey = "filesystem.name_full"
	other.DisplayName = "Name Full"

	ascending := PropertyCatalogSnapshot{Definitions: []WorkspacePropertyDefinition{definition, other}}
	descending := PropertyCatalogSnapshot{Definitions: []WorkspacePropertyDefinition{other, definition}}

	ascDigest, err := ascending.Digest()
	if err != nil {
		t.Fatal(err)
	}
	descDigest, err := descending.Digest()
	if err != nil {
		t.Fatal(err)
	}
	if ascDigest != descDigest {
		t.Fatal("digest depends on definition order")
	}

	mutated := definition
	mutated.DisplayName = "Changed"
	changed := PropertyCatalogSnapshot{Definitions: []WorkspacePropertyDefinition{mutated, other}}
	changedDigest, err := changed.Digest()
	if err != nil {
		t.Fatal(err)
	}
	if changedDigest == ascDigest {
		t.Fatal("digest must change when a stable field changes")
	}
}

func TestSourcePropertyCatalogDigestIncludesBindingOrdinal(t *testing.T) {
	propertyID := mustRegistryPropertyID("filesystem.extension")
	binding := PropertyBinding{
		PropertyID: propertyID, SourceRef: mustSourcePropertyRef(t, "macos.mditem"), BindingOrdinal: 1,
		ReadTransform: "identity", Direction: "read", EffectiveReadable: true,
		QueryProfile: "mdquery_identity", MappingVersion: 1, ValueContractRevision: 1,
		Provenance: "system_property_registry@2.4.1", ApprovalState: "approved", Lossiness: "none",
		Lifecycle: PropertyLifecycleActive,
	}
	snapshot := PropertyCatalogSnapshot{Bindings: []PropertyBinding{binding}}
	firstDigest, err := snapshot.Digest()
	if err != nil {
		t.Fatal(err)
	}
	binding.BindingOrdinal = 2
	secondDigest, err := (PropertyCatalogSnapshot{Bindings: []PropertyBinding{binding}}).Digest()
	if err != nil {
		t.Fatal(err)
	}
	if firstDigest == secondDigest {
		t.Fatal("digest must change when binding ordinal changes")
	}
}

func TestSourcePropertyCatalogDigestIncludesDefinitionFields(t *testing.T) {
	definition := WorkspacePropertyDefinition{
		PropertyID: mustRegistryPropertyID("filesystem.extension"), Origin: PropertyOriginBuiltIn,
		IdentityScheme: PropertyIdentitySchemeRegistryDerived, Namespace: "system",
		CanonicalKey: "filesystem.extension", DisplayName: "Extension", Description: "Extension",
		ValueType: PropertyTypeSelect, Cardinality: PropertyCardinalityOne, Nullable: true,
		DefaultHidden: true, DefaultPinned: true, DBIndexedHint: true, DefinitionRev: 3,
		Provenance: PropertyProvenanceSystem, Lifecycle: PropertyLifecycleActive,
	}
	base, err := (PropertyCatalogSnapshot{Definitions: []WorkspacePropertyDefinition{definition}}).Digest()
	if err != nil {
		t.Fatal(err)
	}
	mutations := []func(*WorkspacePropertyDefinition){
		func(value *WorkspacePropertyDefinition) { value.Description = "changed" },
		func(value *WorkspacePropertyDefinition) { value.Nullable = !value.Nullable },
		func(value *WorkspacePropertyDefinition) { value.DefaultHidden = !value.DefaultHidden },
		func(value *WorkspacePropertyDefinition) { value.DefaultPinned = !value.DefaultPinned },
		func(value *WorkspacePropertyDefinition) { value.DBIndexedHint = !value.DBIndexedHint },
		func(value *WorkspacePropertyDefinition) { value.DefinitionRev++ },
	}
	for index, mutate := range mutations {
		changed := definition
		mutate(&changed)
		digest, digestErr := (PropertyCatalogSnapshot{Definitions: []WorkspacePropertyDefinition{changed}}).Digest()
		if digestErr != nil {
			t.Fatalf("mutation[%d] Digest: %v", index, digestErr)
		}
		if digest == base {
			t.Fatalf("mutation[%d] did not change digest", index)
		}
	}
}

func TestSourcePropertyCatalogDigestIncludesUnitContract(t *testing.T) {
	// baseDefinition returns a fresh deep-valued misc.size contract per call so
	// every mutation is applied independently: sharing the Units backing array
	// across iterations would let an earlier in-place mutation mask a missing
	// framing field of a later one.
	baseDefinition := func() WorkspacePropertyDefinition {
		unit := "B"
		return WorkspacePropertyDefinition{
			PropertyID: mustRegistryPropertyID("misc.size"), Origin: PropertyOriginBuiltIn,
			IdentityScheme: PropertyIdentitySchemeRegistryDerived, Namespace: "system",
			CanonicalKey: "misc.size", DisplayName: "Size",
			ValueType: PropertyTypeNumber, Cardinality: PropertyCardinalityOne,
			Provenance: PropertyProvenanceSystem, Lifecycle: PropertyLifecycleActive,
			Unit: &unit, DefaultDisplayUnit: "Byte",
			Units: []PropertyUnit{
				{Code: "B", Label: "Byte", FactorToCanonical: "1"},
				{Code: "KB", Label: "KB", FactorToCanonical: "1024"},
				{Code: "MB", Label: "MB", FactorToCanonical: "1048576"},
			},
		}
	}
	base, err := (PropertyCatalogSnapshot{Definitions: []WorkspacePropertyDefinition{baseDefinition()}}).Digest()
	if err != nil {
		t.Fatal(err)
	}
	mutations := []struct {
		name   string
		mutate func(*WorkspacePropertyDefinition)
	}{
		{"canonical_unit", func(value *WorkspacePropertyDefinition) {
			changed := "bytes"
			value.Unit = &changed
		}},
		{"default_display_unit", func(value *WorkspacePropertyDefinition) { value.DefaultDisplayUnit = "MB" }},
		{"unit_code", func(value *WorkspacePropertyDefinition) { value.Units[1].Code = "KIB" }},
		{"unit_label", func(value *WorkspacePropertyDefinition) { value.Units[1].Label = "KiB" }},
		{"unit_factor", func(value *WorkspacePropertyDefinition) { value.Units[1].FactorToCanonical = "1000" }},
		{"unit_order", func(value *WorkspacePropertyDefinition) {
			value.Units[0], value.Units[1] = value.Units[1], value.Units[0]
		}},
		{"unit_count_drop", func(value *WorkspacePropertyDefinition) { value.Units = value.Units[:2] }},
		{"unit_count_append", func(value *WorkspacePropertyDefinition) {
			value.Units = append(value.Units, PropertyUnit{Code: "TB", Label: "TB", FactorToCanonical: "1099511627776"})
		}},
	}
	for _, mutation := range mutations {
		changed := baseDefinition()
		mutation.mutate(&changed)
		digest, digestErr := (PropertyCatalogSnapshot{Definitions: []WorkspacePropertyDefinition{changed}}).Digest()
		if digestErr != nil {
			t.Fatalf("mutation[%s] Digest: %v", mutation.name, digestErr)
		}
		if digest == base {
			t.Fatalf("mutation[%s] did not change digest", mutation.name)
		}
	}
}

func TestSourcePropertyCatalogRejectsInvalidUnitContract(t *testing.T) {
	definition := WorkspacePropertyDefinition{
		PropertyID: mustRegistryPropertyID("misc.size"), Origin: PropertyOriginBuiltIn,
		IdentityScheme: PropertyIdentitySchemeRegistryDerived, Namespace: "system",
		CanonicalKey: "misc.size", DisplayName: "Size",
		ValueType: PropertyTypeNumber, Cardinality: PropertyCardinalityOne,
		Provenance: PropertyProvenanceSystem, Lifecycle: PropertyLifecycleActive,
		Units: []PropertyUnit{{Code: "B", Label: "Byte", FactorToCanonical: "1"}},
	}
	if definition.Validate() != nil {
		t.Fatal("valid unit contract rejected")
	}
	// default_display_unit must reference a declared unit code.
	invalid := definition
	invalid.DefaultDisplayUnit = "KB"
	if invalid.Validate() == nil {
		t.Fatal("default_display_unit outside units accepted")
	}
	// unit codes must be unique.
	dup := definition
	dup.Units = append(dup.Units, PropertyUnit{Code: "B", Label: "Duplicate", FactorToCanonical: "2"})
	if dup.Validate() == nil {
		t.Fatal("duplicate unit code accepted")
	}
	// empty factor is invalid.
	emptyFactor := definition
	emptyFactor.Units[0].FactorToCanonical = ""
	if emptyFactor.Validate() == nil {
		t.Fatal("empty unit factor accepted")
	}
}

func TestSourcePropertyCatalogDigestIncludesAvailabilityNote(t *testing.T) {
	descriptor := SourcePropertyDescriptor{
		Ref: mustSourcePropertyRef(t, "macos.mditem"), NativeKey: "mditem:kMDItemFSSize",
		NativeType: "number", NativeCardinality: PropertyCardinalityOne,
		Authority: AuthorityKindSystem, SourceReadable: true, SourceQueryable: true,
		AvailabilityNote: "available", Lifecycle: PropertyLifecycleActive,
	}
	base, err := (PropertyCatalogSnapshot{Descriptors: []SourcePropertyDescriptor{descriptor}}).Digest()
	if err != nil {
		t.Fatal(err)
	}
	changed := descriptor
	changed.AvailabilityNote = "requires_spotlight_index"
	digest, digestErr := (PropertyCatalogSnapshot{Descriptors: []SourcePropertyDescriptor{changed}}).Digest()
	if digestErr != nil {
		t.Fatalf("changed Digest: %v", digestErr)
	}
	if digest == base {
		t.Fatal("availability_note mutation did not change digest")
	}
}

func TestSourcePropertyCatalogRejectsIdentitySchemeVersionMismatch(t *testing.T) {
	definition := WorkspacePropertyDefinition{
		PropertyID: mustRegistryPropertyID("misc.size"), Origin: PropertyOriginBuiltIn,
		IdentityScheme: PropertyIdentitySchemeVoyagerIssued, Namespace: "system",
		CanonicalKey: "misc.size", DisplayName: "Size",
		ValueType: PropertyTypeNumber, Cardinality: PropertyCardinalityOne,
		Provenance: PropertyProvenanceSystem, Lifecycle: PropertyLifecycleActive,
	}
	// registry-derived UUIDv5 paired with voyager_issued must fail closed so a
	// hand-built catalog cannot smuggle a definition whose runtime conversion
	// would later be dropped silently.
	if definition.Validate() == nil {
		t.Fatal("scheme/version mismatch accepted")
	}
	matched := definition
	matched.IdentityScheme = PropertyIdentitySchemeRegistryDerived
	if matched.Validate() != nil {
		t.Fatal("consistent scheme/version rejected")
	}
}

func TestSourcePropertyCatalogContractsRejectInvalidNaturalRef(t *testing.T) {
	valid := mustSourcePropertyRef(t, "macos.mditem")
	candidates := []SourcePropertyRef{
		func() SourcePropertyRef { value := valid; value.ProviderID = ""; return value }(),
		func() SourcePropertyRef { value := valid; value.SourceInstanceID = "not-a-src-id"; return value }(),
		func() SourcePropertyRef { value := valid; value.ScopeKind = SourceScopeKind("other"); return value }(),
		func() SourcePropertyRef { value := valid; value.ScopeExternalID = ""; return value }(),
		func() SourcePropertyRef { value := valid; value.ExternalPropertyID = ""; return value }(),
	}
	for index, candidate := range candidates {
		if candidate.Validate() == nil {
			t.Fatalf("candidate[%d] accepted invalid natural ref", index)
		}
	}
}

func TestSourcePropertyCatalogRejectDuplicateSourceRefs(t *testing.T) {
	ref := mustSourcePropertyRef(t, "macos.mditem")
	descriptor := SourcePropertyDescriptor{
		Ref: ref, NativeKey: "kMDItemFSName", NativeType: "string",
		NativeCardinality: PropertyCardinalityOne, Authority: AuthorityKindSystem,
		SourceReadable: true, Lifecycle: PropertyLifecycleActive,
	}
	snapshot := PropertyCatalogSnapshot{Descriptors: []SourcePropertyDescriptor{descriptor, descriptor}}
	if err := snapshot.Validate(); !errors.Is(err, ErrInvalidPropertyCatalogSnapshot) {
		t.Fatalf("duplicate source refs error = %v", err)
	}
}

func TestSourcePropertyCatalogRejectInvalidBindingTarget(t *testing.T) {
	// binding의 PropertyID가 정의 패밀리에 없는 orphan binding은 유효하지 않다.
	binding := PropertyBinding{
		PropertyID:    mustRegistryPropertyID("filesystem.extension"),
		SourceRef:     mustSourcePropertyRef(t, "macos.mditem"),
		ReadTransform: "identity", Direction: "read", EffectiveReadable: true,
		EffectiveQueryable: false, EffectiveWritable: false, QueryProfile: "mdquery_identity",
		MappingVersion: 1, ValueContractRevision: 1, Provenance: "system_property_registry@2.4.1",
		ApprovalState: "approved", Lossiness: "none", Lifecycle: PropertyLifecycleActive,
	}
	if binding.Validate() != nil {
		t.Fatal("binding contract rejected")
	}
	// 잘못된 enum/생명주기 값은 Validate에서 거부된다.
	invalidBinding := binding
	invalidBinding.Lifecycle = PropertyLifecycleState("missing")
	if invalidBinding.Validate() == nil {
		t.Fatal("invalid lifecycle accepted")
	}
	invalidRef := binding
	invalidRef.SourceRef = SourcePropertyRef{ProviderID: "", SourceInstanceID: "bad", ScopeKind: SourceScopeKind("x")}
	if invalidRef.Validate() == nil {
		t.Fatal("invalid binding target accepted")
	}
}
