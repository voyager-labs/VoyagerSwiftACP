package source

import (
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

func TestResourceAdapterContract(t *testing.T) {
	sourceRef, mountRef := adapterContractRefs(t)
	request, err := NewAdapterListRequest(sourceRef, mountRef, "", 2, nil, []string{"name", "title"})
	if err != nil {
		t.Fatal(err)
	}
	if request.PageQuota != 2 || len(request.RequestedProperties) != 2 {
		t.Fatalf("request = %#v", request)
	}

	cursor := "child"
	if _, err := NewAdapterListRequest(sourceRef, mountRef, "", 0, nil, nil); !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("zero quota error = %v", err)
	}
	if _, err := NewAdapterListRequest(sourceRef, mountRef, "", 1, &cursor, []string{"title", "name"}); !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("unsorted properties error = %v", err)
	}
	oversized := strings.Repeat("x", 257)
	if _, err := NewAdapterListRequest(sourceRef, mountRef, "", 1, &oversized, nil); !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("oversized child cursor error = %v", err)
	}

	result := adapterContractResult(t, request, 2, nil)
	if err := result.Validate(request.PageQuota); err != nil {
		t.Fatalf("valid result error = %v", err)
	}
	over := adapterContractResult(t, request, 3, nil)
	if !errors.Is(over.Validate(request.PageQuota), ErrAdapterFailure) {
		t.Fatal("adapter over-return accepted")
	}
	emptyWithCursor := adapterContractResult(t, request, 0, &cursor)
	if !errors.Is(emptyWithCursor.Validate(request.PageQuota), ErrAdapterFailure) {
		t.Fatal("zero items with cursor accepted")
	}
}

func TestAdapterListResultRejectsDuplicateRelativePath(t *testing.T) {
	sourceRef, mountRef := adapterContractRefs(t)
	request, err := NewAdapterListRequest(sourceRef, mountRef, "", 2, nil, []string{})
	if err != nil {
		t.Fatal(err)
	}
	result := adapterContractResult(t, request, 2, nil)
	result.Items[1] = result.Items[0]

	if !errors.Is(result.Validate(request.PageQuota), ErrAdapterFailure) {
		t.Fatal("duplicate relative path accepted")
	}
}

func TestRequestedProperties(t *testing.T) {
	sourceRef, mountRef := adapterContractRefs(t)
	request, err := NewAdapterResolveRequest(sourceRef, mountRef, nil, stringPointer("item"), []string{"title"})
	if err != nil {
		t.Fatal(err)
	}
	if request.EntryRef != nil || request.RelativePath == nil || *request.RelativePath != "item" {
		t.Fatalf("resolve request = %#v", request)
	}
	if _, err := NewAdapterResolveRequest(sourceRef, mountRef, nil, nil, nil); !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("missing selector error = %v", err)
	}
	ref := adapterContractEntry(t, sourceRef, "item", nil).EntryRef
	if _, err := NewAdapterResolveRequest(sourceRef, mountRef, &ref, stringPointer("item"), nil); !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("double selector error = %v", err)
	}
}

func adapterContractRefs(t *testing.T) (entry.SourceRef, entry.MountRef) {
	t.Helper()
	identity, err := DeriveSourceIdentity("fakeexternal", "contract", entry.IdentityStrengthStable)
	if err != nil {
		t.Fatal(err)
	}
	available, _ := entry.NewAvailability(entry.AvailabilityStateAvailable)
	sourceRef, err := entry.NewSourceRef(identity.SourceID, "fakeexternal", "contract", available, entry.IdentityStrengthStable)
	if err != nil {
		t.Fatal(err)
	}
	path, err := entry.NewResolvedVirtualPath("mount", "/", "1")
	if err != nil {
		t.Fatal(err)
	}
	mountRef, err := entry.NewMountRef("mount", "workspace", identity.SourceID, path, available, entry.CachePolicyNone)
	if err != nil {
		t.Fatal(err)
	}
	return sourceRef, mountRef
}

func adapterContractResult(t *testing.T, request AdapterListRequest, count int, cursor *string) AdapterListResult {
	t.Helper()
	items := make([]AdapterEntry, count)
	for index := range count {
		items[index] = adapterContractEntry(t, request.SourceRef, "item-"+string(rune('a'+index)), request.RequestedProperties)
	}
	revision, _ := entry.NewRevision(entry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := entry.NewSourceRevision(revision)
	observed := time.Unix(1, 0).UTC()
	freshness, _ := entry.NewFreshness(entry.FreshnessStateCurrent, observed, sourceRevision, nil, nil)
	return AdapterListResult{
		Items: items, NextChildCursor: cursor, SourceRevision: revision,
		Availability: entry.Availability{State: entry.AvailabilityStateAvailable}, Freshness: freshness,
		Warnings: []Warning{},
	}
}

func adapterContractEntry(t *testing.T, sourceRef entry.SourceRef, key string, requested []string) AdapterEntry {
	t.Helper()
	locator, err := entry.NewLocatorRef("loc:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
	if err != nil {
		t.Fatal(err)
	}
	ref, err := entry.NewEntryRef(entry.DeriveEntryID(sourceRef.SourceInstanceID, "document", key), sourceRef.SourceInstanceID, key, "document", locator, sourceRef.IdentityStrength)
	if err != nil {
		t.Fatal(err)
	}
	revision, _ := entry.NewRevision(entry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := entry.NewSourceRevision(revision)
	observedRevision, _ := entry.NewObservedRevision(1)
	observed := time.Unix(1, 0).UTC()
	freshness, _ := entry.NewFreshness(entry.FreshnessStateCurrent, observed, sourceRevision, nil, nil)
	snapshot, err := entry.NewCanonicalEntrySnapshot(ref, key, nil, []entry.PropertyValue{}, sourceRevision, observedRevision, observed, nil, entry.Availability{State: entry.AvailabilityStateAvailable}, freshness)
	if err != nil {
		t.Fatal(err)
	}
	return AdapterEntry{RelativePath: key, EntryRef: ref, EntrySnapshot: snapshot, Capabilities: entry.Capabilities{Readable: true}}
}

func stringPointer(value string) *string { return &value }

func TestResourceAdapterResolveEnvelopeConsistency(t *testing.T) {
	sourceRef, mountRef := adapterContractRefs(t)
	request, err := NewAdapterResolveRequest(sourceRef, mountRef, nil, stringPointer("item"), []string{})
	if err != nil {
		t.Fatal(err)
	}
	item := adapterContractEntry(t, sourceRef, "item", []string{})
	result := AdapterResolveResult{Item: &item, SourceRevision: item.EntrySnapshot.SourceRevision.Revision, Availability: item.EntrySnapshot.Availability, Freshness: item.EntrySnapshot.Freshness, Warnings: []Warning{}}
	if err := result.Validate(); err != nil {
		t.Fatalf("valid resolve result = %v", err)
	}
	result.Availability = entry.Availability{State: entry.AvailabilityStateReadOnly}
	if !errors.Is(result.Validate(), ErrAdapterFailure) {
		t.Fatal("resolve envelope mismatch accepted")
	}
	_ = request
}

func catalogTestEntryID() string {
	return "ent:" + strings.Repeat("A", 43)
}

func catalogTitleDefinition(t *testing.T) entry.PropertyDefinition {
	t.Helper()
	definition, err := entry.NewPropertyDefinition(entry.PropertyDefinition{
		PropertyID:     entry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64d"),
		IdentityScheme: entry.PropertyIdentitySchemeRegistryDerived,
		Namespace:      "system",
		Key:            "common.title",
		DisplayName:    "Title",
		ValueType:      entry.PropertyTypeText,
		Cardinality:    entry.PropertyCardinalityOne,
		Provenance:     entry.PropertyProvenanceSystem,
	})
	if err != nil {
		t.Fatal(err)
	}
	return definition
}

func TestCanonicalPropertyValuePreservesCatalogContract(t *testing.T) {
	intValue := int64(7)
	token := "rev-1"
	revision, err := entry.NewRevision(entry.RevisionStrengthProvider, &token)
	if err != nil {
		t.Fatal(err)
	}
	sourceRevision, err := entry.NewSourceRevision(revision)
	if err != nil {
		t.Fatal(err)
	}
	property := entry.Property{Key: "title", Value: entry.PropertyValue{Type: entry.PropertyValueTypeInt64, Int64Value: &intValue}}
	if _, err := canonicalPropertyValue(property, "identity", catalogTitleDefinition(t), catalogTestEntryID(), time.Unix(10, 0).UTC(), sourceRevision, entry.PropertyProvenanceFilesystem); !errors.Is(err, ErrAdapterFailure) {
		t.Fatalf("int64 payload against text catalog error = %v", err)
	}

	textValue := "Roadmap"
	textProperty := entry.Property{Key: "title", Value: entry.PropertyValue{Type: entry.PropertyValueTypeString, StringValue: &textValue}}
	value, err := canonicalPropertyValue(textProperty, "identity", catalogTitleDefinition(t), catalogTestEntryID(), time.Unix(10, 0).UTC(), sourceRevision, entry.PropertyProvenanceFilesystem)
	if err != nil {
		t.Fatal(err)
	}
	if value.PropertyID != catalogTitleDefinition(t).PropertyID || value.Type != entry.PropertyTypeText {
		t.Fatalf("catalog-bound value = %#v", value)
	}

	fallback, err := canonicalPropertyValue(property, "identity", entry.PropertyDefinition{}, catalogTestEntryID(), time.Unix(10, 0).UTC(), sourceRevision, entry.PropertyProvenanceFilesystem)
	if err != nil {
		t.Fatal(err)
	}
	if fallback.Type != entry.PropertyTypeNumber {
		t.Fatalf("fallback value = %#v", fallback)
	}
}

func descriptorContractSelector(t *testing.T, sourceRef entry.SourceRef, nativeType string, cardinality entry.PropertyCardinality) entry.SourcePropertyDescriptor {
	t.Helper()
	return entry.SourcePropertyDescriptor{
		Ref: entry.SourcePropertyRef{
			ProviderID: "fakeexternal", SourceInstanceID: sourceRef.SourceInstanceID,
			ScopeKind: entry.SourceScopeKindWorkspace, ScopeExternalID: "workspace",
			ExternalPropertyID: "kMDItemTitle",
		},
		NativeKey: "title", NativeType: nativeType, NativeCardinality: cardinality,
		Authority: entry.AuthorityKindProvider, SourceReadable: true,
		Lifecycle: entry.PropertyLifecycleActive,
	}
}

func descriptorContractItem(t *testing.T, sourceRef entry.SourceRef, properties []entry.Property) SourceItem {
	t.Helper()
	identity, err := entry.NewEntryIdentity(sourceRef.SourceInstanceID, "doc", entry.IdentityStrengthStable)
	if err != nil {
		t.Fatal(err)
	}
	revision, err := entry.NewRevision(entry.RevisionStrengthProvider, stringPointer("rev-1"))
	if err != nil {
		t.Fatal(err)
	}
	snapshot, err := entry.NewEntrySnapshot(
		"Report.pdf", "document", nil, nil, properties,
		revision,
		entry.Availability{State: entry.AvailabilityStateAvailable},
		entry.Freshness{State: entry.FreshnessStateCurrent},
		entry.OperationState{State: entry.OperationStateIdle},
	)
	if err != nil {
		t.Fatal(err)
	}
	item, err := NewSourceItem("doc", identity, snapshot, SourceLocator{digest: make([]byte, sha256.Size)}, entry.Capabilities{ReadProperties: true})
	if err != nil {
		t.Fatal(err)
	}
	return item
}

func canonicalizeWithDescriptorContract(t *testing.T, sourceRef entry.SourceRef, properties []entry.Property, nativeType string, cardinality entry.PropertyCardinality, definition entry.PropertyDefinition, bound bool) (AdapterEntry, error) {
	t.Helper()
	item := descriptorContractItem(t, sourceRef, properties)
	locatorRef, err := entry.NewLocatorRef("loc:" + base64.RawURLEncoding.EncodeToString(item.Locator.digest))
	if err != nil {
		t.Fatal(err)
	}
	revision, err := entry.NewRevision(entry.RevisionStrengthUnknown, nil)
	if err != nil {
		t.Fatal(err)
	}
	sourceRevision, err := entry.NewSourceRevision(revision)
	if err != nil {
		t.Fatal(err)
	}
	freshness, err := entry.NewFreshness(entry.FreshnessStateCurrent, time.Unix(10, 0).UTC(), sourceRevision, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	selectors := map[string]entry.SourcePropertyDescriptor{}
	transforms := map[string]entry.PropertyBinding{}
	if bound {
		selector := descriptorContractSelector(t, sourceRef, nativeType, cardinality)
		binding := entry.PropertyBinding{
			PropertyID: definition.PropertyID, SourceRef: selector.Ref,
			ReadTransform: "identity", Direction: "read",
			EffectiveReadable: true, ApprovalState: "approved", Lifecycle: entry.PropertyLifecycleActive,
		}
		selectors["common.title"] = selector
		transforms["common.title"] = binding
	}
	return CanonicalizeSourceItemWithLocator(item, locatorRef, []string{"common.title"}, map[string]entry.PropertyDefinition{"common.title": definition}, selectors, transforms, time.Unix(10, 0).UTC(), revision, entry.Availability{State: entry.AvailabilityStateAvailable}, freshness, entry.PropertyProvenanceFilesystem)
}

// VOY-764 P1 복구(review v4 결함 3): 바인딩된 요청 이름은 변환 전에 디스크립터의
// 네이티브 타입·cardinality 계약을 검증하고, 네이티브 값 부재·unset 페이로드도 실패
// 닫기한다. NativeKey만 사용하던 기존 경로는 잘못된 네이티브 페이로드를 canonical
// 변환 뒤에 통과시키고 값 부재로 transform 검증을 우회했다.
func TestCanonicalizeWithLocatorValidatesNativeDescriptorContract(t *testing.T) {
	sourceRef, _ := adapterContractRefs(t)
	textOneDefinition := catalogTitleDefinition(t)
	textManyDefinition, err := entry.NewPropertyDefinition(entry.PropertyDefinition{
		PropertyID:     entry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64e"),
		IdentityScheme: entry.PropertyIdentitySchemeRegistryDerived,
		Namespace:      "system", Key: "common.title", DisplayName: "Title",
		ValueType: entry.PropertyTypeText, Cardinality: entry.PropertyCardinalityMany,
		Provenance: entry.PropertyProvenanceSystem,
	})
	if err != nil {
		t.Fatal(err)
	}
	dateTimeOneDefinition, err := entry.NewPropertyDefinition(entry.PropertyDefinition{
		PropertyID:     entry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64f"),
		IdentityScheme: entry.PropertyIdentitySchemeRegistryDerived,
		Namespace:      "system", Key: "common.title", DisplayName: "Title",
		ValueType: entry.PropertyTypeDateTime, Cardinality: entry.PropertyCardinalityOne,
		Provenance: entry.PropertyProvenanceSystem,
	})
	if err != nil {
		t.Fatal(err)
	}

	titleProperty := mustProperty(t, "title", mustStringValue(t, "Roadmap"))
	listProperty := mustProperty(t, "title", mustStringListValue(t, []string{"a", "b"}))
	timestampProperty := mustProperty(t, "title", mustTimestampValue(t, time.Unix(10, 0).UTC()))
	for _, tc := range []struct {
		name             string
		properties       []entry.Property
		nativeType       string
		cardinality      entry.PropertyCardinality
		definition       entry.PropertyDefinition
		bound            bool
		wantErr          bool
		wantNoProperties bool
	}{
		{name: "string_one_matches", properties: []entry.Property{titleProperty}, nativeType: "string", cardinality: entry.PropertyCardinalityOne, definition: textOneDefinition, bound: true},
		{name: "string_list_many_matches", properties: []entry.Property{listProperty}, nativeType: "string_list", cardinality: entry.PropertyCardinalityMany, definition: textManyDefinition, bound: true},
		{name: "scalar_declared_but_list_payload_rejected", properties: []entry.Property{listProperty}, nativeType: "string", cardinality: entry.PropertyCardinalityOne, definition: textManyDefinition, bound: true, wantErr: true},
		{name: "datetime_definition_with_string_declaration_and_timestamp_rejected", properties: []entry.Property{timestampProperty}, nativeType: "string", cardinality: entry.PropertyCardinalityOne, definition: dateTimeOneDefinition, bound: true, wantErr: true},
		{name: "missing_optional_bound_native_value_stays_optional", nativeType: "string", cardinality: entry.PropertyCardinalityOne, definition: textOneDefinition, bound: true, wantNoProperties: true},
		{name: "unknown_native_type_rejected", properties: []entry.Property{titleProperty}, nativeType: "blob", cardinality: entry.PropertyCardinalityOne, definition: textOneDefinition, bound: true, wantErr: true},
		{name: "unbound_missing_native_value_stays_optional", nativeType: "string", cardinality: entry.PropertyCardinalityOne, definition: textOneDefinition, bound: false, wantNoProperties: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			result, err := canonicalizeWithDescriptorContract(t, sourceRef, tc.properties, tc.nativeType, tc.cardinality, tc.definition, tc.bound)
			if tc.wantErr {
				if !errors.Is(err, ErrAdapterFailure) {
					t.Fatalf("error = %v, want %v", err, ErrAdapterFailure)
				}
				return
			}
			if err != nil {
				t.Fatalf("canonicalize error = %v", err)
			}
			got := len(result.EntrySnapshot.CanonicalProperties)
			if tc.wantNoProperties {
				if got != 0 {
					t.Fatalf("properties = %#v, want none for unbound absent native value", result.EntrySnapshot.CanonicalProperties)
				}
				return
			}
			if got != 1 {
				t.Fatalf("properties = %#v, want exactly one", result.EntrySnapshot.CanonicalProperties)
			}
		})
	}
}

func TestBoundNativeUnsetPayloadRejectedBeforeCanonicalization(t *testing.T) {
	_, err := entry.NewProperty("title", entry.PropertyValue{Type: entry.PropertyValueTypeString})
	if err == nil {
		t.Fatal("unset native payload must be rejected by the source snapshot property boundary")
	}
}

func TestFoundationFilenamePartsMatchesFoundationSemantics(t *testing.T) {
	for _, tc := range []struct {
		name, stem, extension string
		hasExtension          bool
	}{
		{name: "README", stem: "README"},
		{name: ".env", stem: ".env"},
		{name: ".config.json", stem: ".config", extension: "json", hasExtension: true},
		{name: "archive.tar.gz", stem: "archive.tar", extension: "gz", hasExtension: true},
		{name: "name.", stem: "name."},
	} {
		stem, extension, hasExtension := foundationFilenameParts(tc.name)
		if stem != tc.stem || extension != tc.extension || hasExtension != tc.hasExtension {
			t.Fatalf("parts(%q) = (%q, %q, %t)", tc.name, stem, extension, hasExtension)
		}
	}
}

func TestFilenameExtensionTransformOmitsExtensionlessValue(t *testing.T) {
	name := "README"
	property := entry.Property{Key: "name", Value: entry.PropertyValue{Type: entry.PropertyValueTypeString, StringValue: &name}}
	if _, err := canonicalPropertyValue(
		property,
		"filename_extension",
		entry.PropertyDefinition{},
		catalogTestEntryID(),
		time.Time{},
		entry.SourceRevision{},
		entry.PropertyProvenanceFilesystem,
	); !errors.Is(err, errPropertyNotApplicable) {
		t.Fatalf("extensionless transform error = %v", err)
	}
}

func mustStringValue(t *testing.T, value string) entry.PropertyValue {
	t.Helper()
	propertyValue, err := entry.NewStringPropertyValue(value)
	if err != nil {
		t.Fatal(err)
	}
	return propertyValue
}

func mustStringListValue(t *testing.T, values []string) entry.PropertyValue {
	t.Helper()
	propertyValue, err := entry.NewStringListPropertyValue(values)
	if err != nil {
		t.Fatal(err)
	}
	return propertyValue
}

func mustTimestampValue(t *testing.T, value time.Time) entry.PropertyValue {
	t.Helper()
	propertyValue, err := entry.NewTimestampPropertyValue(value)
	if err != nil {
		t.Fatal(err)
	}
	return propertyValue
}

func mustProperty(t *testing.T, key string, value entry.PropertyValue) entry.Property {
	t.Helper()
	property, err := entry.NewProperty(key, value)
	if err != nil {
		t.Fatal(err)
	}
	return property
}
