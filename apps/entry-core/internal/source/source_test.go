package source

import (
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
	if _, err := canonicalPropertyValue(property, catalogTitleDefinition(t), catalogTestEntryID(), time.Unix(10, 0).UTC(), sourceRevision, entry.PropertyProvenanceFilesystem); !errors.Is(err, ErrAdapterFailure) {
		t.Fatalf("int64 payload against text catalog error = %v", err)
	}

	textValue := "Roadmap"
	textProperty := entry.Property{Key: "title", Value: entry.PropertyValue{Type: entry.PropertyValueTypeString, StringValue: &textValue}}
	value, err := canonicalPropertyValue(textProperty, catalogTitleDefinition(t), catalogTestEntryID(), time.Unix(10, 0).UTC(), sourceRevision, entry.PropertyProvenanceFilesystem)
	if err != nil {
		t.Fatal(err)
	}
	if value.PropertyID != catalogTitleDefinition(t).PropertyID || value.Type != entry.PropertyTypeText {
		t.Fatalf("catalog-bound value = %#v", value)
	}

	fallback, err := canonicalPropertyValue(property, entry.PropertyDefinition{}, catalogTestEntryID(), time.Unix(10, 0).UTC(), sourceRevision, entry.PropertyProvenanceFilesystem)
	if err != nil {
		t.Fatal(err)
	}
	if fallback.Type != entry.PropertyTypeNumber {
		t.Fatalf("fallback value = %#v", fallback)
	}
}
