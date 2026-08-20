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
