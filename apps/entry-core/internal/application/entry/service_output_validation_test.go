package entry

import (
	"context"
	"errors"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

func TestUnifiedListRejectsUnsortedAdapterProperties(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "external", "item")
	item.EntrySnapshot.CanonicalProperties = unsortedCanonicalProperties(t, item)
	adapter.listResults = []source.AdapterListResult{{
		Items:          []source.AdapterEntry{item},
		SourceRevision: item.EntrySnapshot.SourceRevision.Revision,
		Availability:   item.EntrySnapshot.Availability,
		Freshness:      item.EntrySnapshot.Freshness,
		Warnings:       []source.Warning{},
	}}
	service := mustUnifiedService(t, registry, bindings)
	path := "/external"

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1,
		RequestedProperties: []string{"property.a", "property.z"},
	})
	if !errors.Is(err, ErrApplicationAdapterFailure) {
		t.Fatalf("UnifiedList() error = %v, want %v", err, ErrApplicationAdapterFailure)
	}
}

func TestUnifiedListRejectsDuplicateAdapterRelativePath(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "external", "item")
	result := adapterListResultFixture(t, bindings[0].SourceRef, "external", "item", nil)
	result.Items = append(result.Items, item)
	adapter.listResults = []source.AdapterListResult{result}
	service := mustUnifiedService(t, registry, bindings)
	path := "/external"

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2,
		RequestedProperties: []string{},
	})
	if !errors.Is(err, ErrApplicationAdapterFailure) {
		t.Fatalf("UnifiedList() error = %v, want %v", err, ErrApplicationAdapterFailure)
	}
}

func TestResolveEntryRejectsUnsortedAdapterProperties(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "external", "item")
	item.EntrySnapshot.CanonicalProperties = unsortedCanonicalProperties(t, item)
	adapter.resolveResult = adapterResolveResultFixture(t, item)
	service := mustUnifiedService(t, registry, bindings)
	path := "/external/item"

	_, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path,
		RequestedProperties: []string{"property.a", "property.z"},
	})
	if !errors.Is(err, ErrApplicationAdapterFailure) {
		t.Fatalf("ResolveEntry() error = %v, want %v", err, ErrApplicationAdapterFailure)
	}
}

func unsortedCanonicalProperties(t *testing.T, item source.AdapterEntry) []domainentry.PropertyValue {
	t.Helper()
	properties := make([]domainentry.PropertyValue, 0, 2)
	for _, propertyID := range []string{"property.z", "property.a"} {
		definition := domainentry.PropertyDefinition{
			PropertyID: propertyID, Namespace: "test", Key: propertyID,
			DisplayName: propertyID, ValueType: domainentry.PropertyTypeText,
			Cardinality: domainentry.PropertyCardinalityOne, Editable: true,
			Provenance: domainentry.PropertyProvenanceSystem, ValidationRules: []domainentry.ValidationRule{},
		}
		value, err := domainentry.NewPropertyValue(
			definition, item.EntryRef.EntryID, domainentry.PropertyStateValue,
			domainentry.PropertyProvenanceSystem, item.EntrySnapshot.ObservedAt,
			item.EntrySnapshot.SourceRevision, false, domainentry.TextPayload(propertyID),
		)
		if err != nil {
			t.Fatal(err)
		}
		properties = append(properties, value)
	}
	return properties
}
