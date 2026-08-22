package entry

import (
	"context"
	"errors"
	"sort"
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/mount"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

func TestUnifiedListCanonicalizesAdapterProperties(t *testing.T) {
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

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1,
		RequestedProperties: []string{"property.a", "property.z"},
	})
	if err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	assertCanonicalPropertyOrder(t, result.Entries[0].EntrySnapshot.CanonicalProperties)
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

func TestResolveEntryCanonicalizesAdapterProperties(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "external", "item")
	item.EntrySnapshot.CanonicalProperties = unsortedCanonicalProperties(t, item)
	adapter.resolveResult = adapterResolveResultFixture(t, item)
	service := mustUnifiedService(t, registry, bindings)
	path := "/external/item"

	result, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path,
		RequestedProperties: []string{"property.a", "property.z"},
	})
	if err != nil {
		t.Fatalf("ResolveEntry() error = %v", err)
	}
	assertCanonicalPropertyOrder(t, result.EntrySnapshot.CanonicalProperties)
}

func unsortedCanonicalProperties(t *testing.T, item source.AdapterEntry) []domainentry.PropertyValue {
	t.Helper()
	properties := make([]domainentry.PropertyValue, 0, 2)
	for _, propertyID := range []string{"property.a", "property.z"} {
		propertyIDValue, err := domainentry.RegistryPropertyID(propertyID)
		if err != nil {
			t.Fatal(err)
		}
		definition := domainentry.PropertyDefinition{
			PropertyID: propertyIDValue, IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
			Namespace: "test", Key: propertyID,
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
	sort.Slice(properties, func(left, right int) bool {
		return properties[left].PropertyID.String() < properties[right].PropertyID.String()
	})
	for left, right := 0, len(properties)-1; left < right; left, right = left+1, right-1 {
		properties[left], properties[right] = properties[right], properties[left]
	}
	return properties
}

func assertCanonicalPropertyOrder(t *testing.T, properties []domainentry.PropertyValue) {
	t.Helper()
	if len(properties) != 2 {
		t.Fatalf("properties = %#v, want two properties", properties)
	}
	for index := 1; index < len(properties); index++ {
		if properties[index-1].PropertyID.String() >= properties[index].PropertyID.String() {
			t.Fatalf("properties are not canonically sorted: %#v", properties)
		}
	}
}

var catalogTitleID = domainentry.MustPropertyID("0198c0de-f00d-7000-8000-3b9ac9e12345")

func titleCatalogFixture() domainentry.PropertyCatalogSnapshot {
	return domainentry.PropertyCatalogSnapshot{
		Definitions: []domainentry.WorkspacePropertyDefinition{{
			PropertyID: catalogTitleID, Origin: domainentry.PropertyOriginBuiltIn,
			IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
			Namespace:      "system", CanonicalKey: "common.title", DisplayName: "Title",
			ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
			Editable: true, Provenance: domainentry.PropertyProvenanceSystem, Lifecycle: domainentry.PropertyLifecycleActive,
		}},
		Terms: []domainentry.WorkspacePropertyTerm{{PropertyID: catalogTitleID, TermKind: "legacy_alias", Ordinal: 0, TermValue: "title"}},
	}
}

func mustUnifiedServiceWithCatalog(t *testing.T, registry *mount.Registry, bindings []ResourceAdapterBinding, catalog domainentry.PropertyCatalogSnapshot) *UnifiedService {
	t.Helper()
	service, err := NewUnifiedServiceWithCatalog(registry, bindings, catalog, []byte("01234567890123456789012345678901"), func() time.Time { return time.Unix(10, 0).UTC() })
	if err != nil {
		t.Fatal(err)
	}
	return service
}

func catalogTitlePropertyValue(t *testing.T, item source.AdapterEntry) domainentry.PropertyValue {
	t.Helper()
	definition, err := domainentry.NewPropertyDefinition(domainentry.PropertyDefinition{
		PropertyID: catalogTitleID, IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
		Namespace: "system", Key: "common.title", DisplayName: "Title",
		ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
		Editable: true, Provenance: domainentry.PropertyProvenanceSystem, ValidationRules: []domainentry.ValidationRule{},
	})
	if err != nil {
		t.Fatal(err)
	}
	value, err := domainentry.NewPropertyValue(definition, item.EntryRef.EntryID, domainentry.PropertyStateValue,
		domainentry.PropertyProvenanceSystem, item.EntrySnapshot.ObservedAt, item.EntrySnapshot.SourceRevision, false, domainentry.TextPayload("title"))
	if err != nil {
		t.Fatal(err)
	}
	return value
}

// VOY-764 회귀(review 3831189756): 출력 검증은 요청과 같은 카탈로그 해석 결과를 쓴다.
func TestResolveEntryAcceptsAliasResolvedCatalogProperties(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitlePropertyValue(t, item)}
	external.resolveResult = adapterResolveResultFixture(t, item)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings, titleCatalogFixture())
	path := "/external/item"

	result, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{"title"},
	})
	if err != nil {
		t.Fatalf("ResolveEntry() error = %v", err)
	}
	if len(result.EntrySnapshot.CanonicalProperties) != 1 || result.EntrySnapshot.CanonicalProperties[0].PropertyID != catalogTitleID {
		t.Fatalf("canonical properties = %#v, want voyager-issued %s", result.EntrySnapshot.CanonicalProperties, catalogTitleID)
	}
}

// VOY-764 회귀(review 3831189763): canonical key는 alias와 같은 카탈로그 정의와 타입·cardinality 계약을 공유한다.
func TestResolveEntryCanonicalKeySharesAliasCatalogDefinition(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitlePropertyValue(t, item)}
	external.resolveResult = adapterResolveResultFixture(t, item)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings, titleCatalogFixture())
	path := "/external/item"

	result, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{"common.title"},
	})
	if err != nil {
		t.Fatalf("ResolveEntry() error = %v", err)
	}
	if external.resolveCalls != 1 {
		t.Fatalf("resolve calls = %d", external.resolveCalls)
	}
	definition, ok := external.resolveRequests[0].PropertyDefinitions["common.title"]
	if !ok || definition.PropertyID != catalogTitleID || definition.IdentityScheme != domainentry.PropertyIdentitySchemeVoyagerIssued ||
		definition.ValueType != domainentry.PropertyTypeText || definition.Cardinality != domainentry.PropertyCardinalityOne {
		t.Fatalf("adapter definitions = %#v, want shared catalog definition %s", external.resolveRequests[0].PropertyDefinitions, catalogTitleID)
	}
	if len(result.EntrySnapshot.CanonicalProperties) != 1 || result.EntrySnapshot.CanonicalProperties[0].PropertyID != catalogTitleID {
		t.Fatalf("canonical properties = %#v", result.EntrySnapshot.CanonicalProperties)
	}
}

// VOY-764 회귀: UnifiedList 형제 경로도 동일한 단일 해석 결과로 검증한다.
func TestUnifiedListAcceptsAliasResolvedCatalogProperties(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitlePropertyValue(t, item)}
	adapter.listResults = []source.AdapterListResult{{
		Items:          []source.AdapterEntry{item},
		SourceRevision: item.EntrySnapshot.SourceRevision.Revision,
		Availability:   item.EntrySnapshot.Availability,
		Freshness:      item.EntrySnapshot.Freshness,
		Warnings:       []source.Warning{},
	}}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], titleCatalogFixture())
	path := "/external"

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"title"},
	})
	if err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if len(result.Entries) != 1 || len(result.Entries[0].EntrySnapshot.CanonicalProperties) != 1 ||
		result.Entries[0].EntrySnapshot.CanonicalProperties[0].PropertyID != catalogTitleID {
		t.Fatalf("entries = %#v", result.Entries)
	}
}

func TestResolveEntryStillRejectsOutOfRequestProperties(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	outOfRequest, err := domainentry.RegistryPropertyID("unbound.prop")
	if err != nil {
		t.Fatal(err)
	}
	definition, err := domainentry.NewPropertyDefinition(domainentry.PropertyDefinition{
		PropertyID: outOfRequest, IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
		Namespace: "test", Key: "unbound.prop", DisplayName: "Unbound",
		ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
		Provenance: domainentry.PropertyProvenanceSystem, ValidationRules: []domainentry.ValidationRule{},
	})
	if err != nil {
		t.Fatal(err)
	}
	unboundValue, err := domainentry.NewPropertyValue(definition, item.EntryRef.EntryID, domainentry.PropertyStateValue,
		domainentry.PropertyProvenanceSystem, item.EntrySnapshot.ObservedAt, item.EntrySnapshot.SourceRevision, false, domainentry.TextPayload("unbound"))
	if err != nil {
		t.Fatal(err)
	}
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitlePropertyValue(t, item), unboundValue}
	external.resolveResult = adapterResolveResultFixture(t, item)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings, titleCatalogFixture())
	path := "/external/item"

	_, err = service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{"title"},
	})
	if !errors.Is(err, ErrApplicationAdapterFailure) {
		t.Fatalf("ResolveEntry() error = %v, want %v", err, ErrApplicationAdapterFailure)
	}
}

// VOY-764 회귀(후속 P1): ParentRef 사전 resolve도 본 요청과 같은 카탈로그 정의를 받는다.
func TestUnifiedListParentRefPreliminaryResolveUsesAliasCatalogDefinition(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "opaque-parent", "folder")
	external.resolveResult = adapterResolveResultFixture(t, parent)
	external.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[0].SourceRef, "child", "folder/child", nil)}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], titleCatalogFixture())

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{"title"},
	})
	if err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if external.resolveCalls != 1 || len(result.Entries) != 1 {
		t.Fatalf("calls = %d entries = %#v", external.resolveCalls, result.Entries)
	}
	definition, ok := external.resolveRequests[0].PropertyDefinitions["title"]
	if !ok || definition.PropertyID != catalogTitleID || definition.ValueType != domainentry.PropertyTypeText ||
		definition.Cardinality != domainentry.PropertyCardinalityOne {
		t.Fatalf("preliminary resolve definitions = %#v, want shared voyager-issued definition %s",
			external.resolveRequests[0].PropertyDefinitions, catalogTitleID)
	}
}

// VOY-764 회귀(후속 P1): canonical key 요청도 ParentRef 사전 resolve에 동일 정의를 보낸다.
func TestUnifiedListParentRefPreliminaryResolveUsesCanonicalKeyDefinition(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "opaque-parent", "folder")
	external.resolveResult = adapterResolveResultFixture(t, parent)
	external.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[0].SourceRef, "child", "folder/child", nil)}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], titleCatalogFixture())

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{"common.title"},
	})
	if err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if external.resolveCalls != 1 || len(result.Entries) != 1 {
		t.Fatalf("calls = %d entries = %#v", external.resolveCalls, result.Entries)
	}
	definition, ok := external.resolveRequests[0].PropertyDefinitions["common.title"]
	if !ok || definition.PropertyID != catalogTitleID || definition.IdentityScheme != domainentry.PropertyIdentitySchemeVoyagerIssued ||
		definition.ValueType != domainentry.PropertyTypeText || definition.Cardinality != domainentry.PropertyCardinalityOne {
		t.Fatalf("preliminary resolve definitions = %#v, want shared canonical-key definition %s",
			external.resolveRequests[0].PropertyDefinitions, catalogTitleID)
	}
}

// VOY-764 회귀(후속 P1): 요청 문자열이 카탈로그 PropertyID 텍스트와 정확히 같으면
// 같은 정의(ID·scheme·타입·cardinality)를 어댑터 요청과 출력 검증에 그대로 쓴다.
func TestResolveEntryAcceptsExactPropertyIDRequest(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitlePropertyValue(t, item)}
	external.resolveResult = adapterResolveResultFixture(t, item)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings, titleCatalogFixture())
	path := "/external/item"
	exactID := catalogTitleID.String()

	result, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{exactID},
	})
	if err != nil {
		t.Fatalf("ResolveEntry() error = %v", err)
	}
	if external.resolveCalls != 1 {
		t.Fatalf("resolve calls = %d", external.resolveCalls)
	}
	definition, ok := external.resolveRequests[0].PropertyDefinitions[exactID]
	if !ok || definition.PropertyID != catalogTitleID || definition.IdentityScheme != domainentry.PropertyIdentitySchemeVoyagerIssued ||
		definition.ValueType != domainentry.PropertyTypeText || definition.Cardinality != domainentry.PropertyCardinalityOne {
		t.Fatalf("adapter definitions = %#v, want exact catalog definition %s", external.resolveRequests[0].PropertyDefinitions, catalogTitleID)
	}
	if len(result.EntrySnapshot.CanonicalProperties) != 1 || result.EntrySnapshot.CanonicalProperties[0].PropertyID != catalogTitleID {
		t.Fatalf("canonical properties = %#v", result.EntrySnapshot.CanonicalProperties)
	}
}

// VOY-764 회귀(후속 P1): UnifiedList 본 요청도 정확한 PropertyID 텍스트로 같은 정의를 보낸다.
func TestUnifiedListAcceptsExactPropertyIDRequest(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitlePropertyValue(t, item)}
	adapter.listResults = []source.AdapterListResult{{
		Items:          []source.AdapterEntry{item},
		SourceRevision: item.EntrySnapshot.SourceRevision.Revision,
		Availability:   item.EntrySnapshot.Availability,
		Freshness:      item.EntrySnapshot.Freshness,
		Warnings:       []source.Warning{},
	}}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], titleCatalogFixture())
	path := "/external"
	exactID := catalogTitleID.String()

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{exactID},
	})
	if err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if len(result.Entries) != 1 || len(result.Entries[0].EntrySnapshot.CanonicalProperties) != 1 ||
		result.Entries[0].EntrySnapshot.CanonicalProperties[0].PropertyID != catalogTitleID {
		t.Fatalf("entries = %#v", result.Entries)
	}
	definition, ok := adapter.listRequests[0].PropertyDefinitions[exactID]
	if !ok || definition.PropertyID != catalogTitleID || definition.IdentityScheme != domainentry.PropertyIdentitySchemeVoyagerIssued ||
		definition.ValueType != domainentry.PropertyTypeText || definition.Cardinality != domainentry.PropertyCardinalityOne {
		t.Fatalf("list definitions = %#v, want exact voyager-issued definition %s",
			adapter.listRequests[0].PropertyDefinitions, catalogTitleID)
	}
}

// VOY-764 회귀(후속 P1): 정확한 PropertyID 텍스트 요청도 ParentRef 사전 resolve에 동일 정의를 보낸다.
func TestUnifiedListParentRefPreliminaryResolveUsesExactPropertyIDDefinition(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "opaque-parent", "folder")
	external.resolveResult = adapterResolveResultFixture(t, parent)
	external.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[0].SourceRef, "child", "folder/child", nil)}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], titleCatalogFixture())
	exactID := catalogTitleID.String()

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{exactID},
	})
	if err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if external.resolveCalls != 1 || len(result.Entries) != 1 {
		t.Fatalf("calls = %d entries = %#v", external.resolveCalls, result.Entries)
	}
	definition, ok := external.resolveRequests[0].PropertyDefinitions[exactID]
	if !ok || definition.PropertyID != catalogTitleID || definition.IdentityScheme != domainentry.PropertyIdentitySchemeVoyagerIssued ||
		definition.ValueType != domainentry.PropertyTypeText || definition.Cardinality != domainentry.PropertyCardinalityOne {
		t.Fatalf("preliminary resolve definitions = %#v, want exact voyager-issued definition %s",
			external.resolveRequests[0].PropertyDefinitions, catalogTitleID)
	}
}

// VOY-764 회귀(후속 P1): 같은 별칭이 여러 PropertyID에 걸리면 어댑터 요청 없이
// 확립된 애플리케이션 오류 계약으로 실패 닫기한다.
func TestUnifiedListRejectsAmbiguousAliasWithoutAdapterCall(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	secondID := domainentry.MustPropertyID("0198c0de-f00d-7000-8000-3b9ac9e12346")
	catalog := titleCatalogFixture()
	catalog.Definitions = append(catalog.Definitions, domainentry.WorkspacePropertyDefinition{
		PropertyID: secondID, Origin: domainentry.PropertyOriginBuiltIn,
		IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
		Namespace:      "system", CanonicalKey: "common.subtitle", DisplayName: "Subtitle",
		ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
		Editable: true, Provenance: domainentry.PropertyProvenanceSystem, Lifecycle: domainentry.PropertyLifecycleActive,
	})
	catalog.Terms = append(catalog.Terms, domainentry.WorkspacePropertyTerm{PropertyID: secondID, TermKind: "legacy_alias", Ordinal: 0, TermValue: "title"})
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], catalog)
	path := "/external"

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"title"},
	})
	if !errors.Is(err, ErrAmbiguousPropertySelector) {
		t.Fatalf("UnifiedList() error = %v, want %v", err, ErrAmbiguousPropertySelector)
	}
	if adapter.listCalls != 0 || adapter.resolveCalls != 0 {
		t.Fatalf("adapter calls list=%d resolve=%d, want zero", adapter.listCalls, adapter.resolveCalls)
	}
}

// VOY-764 회귀(후속 P1-1): 카탈로그에 없는 유효한 PropertyID 텍스트 요청은 registry
// 재해싱하지 않고 어댑터 호출 전에 실패 닫기한다.
func TestUnifiedListFailsClosedForUnregisteredExactPropertyID(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitlePropertyValue(t, item)}
	adapter.listResults = []source.AdapterListResult{{
		Items:          []source.AdapterEntry{item},
		SourceRevision: item.EntrySnapshot.SourceRevision.Revision,
		Availability:   item.EntrySnapshot.Availability,
		Freshness:      item.EntrySnapshot.Freshness,
		Warnings:       []source.Warning{},
	}}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], titleCatalogFixture())
	path := "/external"
	unregisteredID := domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12345").String()

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{unregisteredID},
	})
	if !errors.Is(err, ErrUnregisteredPropertyID) {
		t.Fatalf("UnifiedList() error = %v, want %v", err, ErrUnregisteredPropertyID)
	}
	if adapter.listCalls != 0 || adapter.resolveCalls != 0 {
		t.Fatalf("adapter calls list=%d resolve=%d, want zero", adapter.listCalls, adapter.resolveCalls)
	}
}

func TestResolveEntryFailsClosedForUnregisteredExactPropertyID(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitlePropertyValue(t, item)}
	external.resolveResult = adapterResolveResultFixture(t, item)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings, titleCatalogFixture())
	path := "/external/item"
	unregisteredID := domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12345").String()

	_, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{unregisteredID},
	})
	if !errors.Is(err, ErrUnregisteredPropertyID) {
		t.Fatalf("ResolveEntry() error = %v, want %v", err, ErrUnregisteredPropertyID)
	}
	if external.resolveCalls != 0 || external.listCalls != 0 {
		t.Fatalf("adapter calls resolve=%d list=%d, want zero", external.resolveCalls, external.listCalls)
	}
}

// VOY-764 회귀(후속 P1-4): 카탈로그 바인딩 값은 해석된 정의의 타입·cardinality까지 검증한다.
func catalogTitleNumberManyPropertyValue(t *testing.T, item source.AdapterEntry) domainentry.PropertyValue {
	t.Helper()
	forgedDefinition, err := domainentry.NewPropertyDefinition(domainentry.PropertyDefinition{
		PropertyID: catalogTitleID, IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
		Namespace: "system", Key: "common.title", DisplayName: "Title",
		ValueType: domainentry.PropertyTypeNumber, Cardinality: domainentry.PropertyCardinalityMany,
		Editable: true, Provenance: domainentry.PropertyProvenanceSystem, ValidationRules: []domainentry.ValidationRule{},
	})
	if err != nil {
		t.Fatal(err)
	}
	value, err := domainentry.NewPropertyValue(forgedDefinition, item.EntryRef.EntryID, domainentry.PropertyStateValue,
		domainentry.PropertyProvenanceSystem, item.EntrySnapshot.ObservedAt, item.EntrySnapshot.SourceRevision, false,
		domainentry.NumberManyPayload([]string{"1", "2"}))
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func assertCatalogTypeCardinalityRejected(t *testing.T, err error) {
	t.Helper()
	if !errors.Is(err, ErrApplicationAdapterFailure) {
		t.Fatalf("error = %v, want %v", err, ErrApplicationAdapterFailure)
	}
}

func TestUnifiedListRejectsCatalogTypeCardinalityMismatch(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitleNumberManyPropertyValue(t, item)}
	adapter.listResults = []source.AdapterListResult{{
		Items:          []source.AdapterEntry{item},
		SourceRevision: item.EntrySnapshot.SourceRevision.Revision,
		Availability:   item.EntrySnapshot.Availability,
		Freshness:      item.EntrySnapshot.Freshness,
		Warnings:       []source.Warning{},
	}}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], titleCatalogFixture())
	path := "/external"

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"title"},
	})
	assertCatalogTypeCardinalityRejected(t, err)
}

func TestResolveEntryRejectsCatalogTypeCardinalityMismatch(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitleNumberManyPropertyValue(t, item)}
	external.resolveResult = adapterResolveResultFixture(t, item)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings, titleCatalogFixture())
	path := "/external/item"

	_, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{"title"},
	})
	assertCatalogTypeCardinalityRejected(t, err)
}

// VOY-764 회귀(후속 P1-3): 악의적 어댑터가 요청 정의 맵을 변조해 위조 ID를 반환해도
// 권위 맵 기반 출력 검증이 거부한다.
func TestResolveEntryRejectsAdapterMutatedRequestDefinitions(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	forgedID := domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12346")
	forgedDefinition, err := domainentry.NewPropertyDefinition(domainentry.PropertyDefinition{
		PropertyID: forgedID, IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
		Namespace: "system", Key: "common.title", DisplayName: "Forged",
		ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
		Editable: true, Provenance: domainentry.PropertyProvenanceSystem, ValidationRules: []domainentry.ValidationRule{},
	})
	if err != nil {
		t.Fatal(err)
	}
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	forgedValue, err := domainentry.NewPropertyValue(forgedDefinition, item.EntryRef.EntryID, domainentry.PropertyStateValue,
		domainentry.PropertyProvenanceSystem, item.EntrySnapshot.ObservedAt, item.EntrySnapshot.SourceRevision, false,
		domainentry.TextPayload("forged"))
	if err != nil {
		t.Fatal(err)
	}
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{forgedValue}
	malicious := &mutatingResourceAdapter{
		resolveResult: adapterResolveResultFixture(t, item),
		onResolve: func(request source.AdapterResolveRequest) {
			request.PropertyDefinitions["title"] = forgedDefinition
		},
	}
	bindings[0].Adapter = malicious
	service := mustUnifiedServiceWithCatalog(t, registry, bindings, titleCatalogFixture())
	path := "/external/item"

	_, err = service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{"title"},
	})
	assertCatalogTypeCardinalityRejected(t, err)
}

// VOY-764 회귀(후속 P1-3): ParentRef 사전 resolve의 어댑터 변조는 본 List 요청과
// 권위 검증 맵으로 누수되지 않는다.
func TestUnifiedListParentRefMutationDoesNotLeakIntoMainList(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "child", "folder/child")
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{catalogTitlePropertyValue(t, item)}
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "opaque-parent", "folder")
	unit := "characters"
	malicious := &mutatingResourceAdapter{
		listResults: []source.AdapterListResult{{
			Items:          []source.AdapterEntry{item},
			SourceRevision: item.EntrySnapshot.SourceRevision.Revision,
			Availability:   item.EntrySnapshot.Availability,
			Freshness:      item.EntrySnapshot.Freshness,
			Warnings:       []source.Warning{},
		}},
		resolveResult: func() source.AdapterResolveResult {
			result := adapterResolveResultFixture(t, parent)
			result.Item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{}
			return result
		}(),
		onResolve: func(request source.AdapterResolveRequest) {
			definition, ok := request.PropertyDefinitions["title"]
			if !ok {
				return
			}
			corrupted := definition
			corrupted.ValueType = domainentry.PropertyTypeNumber
			corrupted.Cardinality = domainentry.PropertyCardinalityMany
			corrupted.Unit = &unit
			request.PropertyDefinitions["title"] = corrupted
		},
	}
	bindings[0].Adapter = malicious
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], titleCatalogFixture())

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{"title"},
	})
	if err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if len(result.Entries) != 1 || len(result.Entries[0].EntrySnapshot.CanonicalProperties) != 1 ||
		result.Entries[0].EntrySnapshot.CanonicalProperties[0].PropertyID != catalogTitleID {
		t.Fatalf("entries = %#v", result.Entries)
	}
	definition := malicious.listRequests[0].PropertyDefinitions["title"]
	if definition.PropertyID != catalogTitleID || definition.ValueType != domainentry.PropertyTypeText ||
		definition.Cardinality != domainentry.PropertyCardinalityOne || definition.Unit != nil {
		t.Fatalf("main list definition mutated by parent resolve: %#v", definition)
	}
}

// VOY-764 회귀: 카탈로그에 없는 진짜 미바인딩 term만 registry 파생 fallback을 유지한다.
func TestUnifiedListKeepsRegistryFallbackForUnboundTerms(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	unboundID, err := domainentry.RegistryPropertyID("unbound.prop")
	if err != nil {
		t.Fatal(err)
	}
	definition, err := domainentry.NewPropertyDefinition(domainentry.PropertyDefinition{
		PropertyID: unboundID, IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
		Namespace: "test", Key: "unbound.prop", DisplayName: "Unbound",
		ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
		Provenance: domainentry.PropertyProvenanceSystem, ValidationRules: []domainentry.ValidationRule{},
	})
	if err != nil {
		t.Fatal(err)
	}
	unboundValue, err := domainentry.NewPropertyValue(definition, item.EntryRef.EntryID, domainentry.PropertyStateValue,
		domainentry.PropertyProvenanceSystem, item.EntrySnapshot.ObservedAt, item.EntrySnapshot.SourceRevision, false, domainentry.TextPayload("unbound"))
	if err != nil {
		t.Fatal(err)
	}
	item.EntrySnapshot.CanonicalProperties = []domainentry.PropertyValue{unboundValue}
	adapter.listResults = []source.AdapterListResult{{
		Items:          []source.AdapterEntry{item},
		SourceRevision: item.EntrySnapshot.SourceRevision.Revision,
		Availability:   item.EntrySnapshot.Availability,
		Freshness:      item.EntrySnapshot.Freshness,
		Warnings:       []source.Warning{},
	}}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], titleCatalogFixture())
	path := "/external"

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"unbound.prop"},
	})
	if err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if len(result.Entries) != 1 || len(result.Entries[0].EntrySnapshot.CanonicalProperties) != 1 ||
		result.Entries[0].EntrySnapshot.CanonicalProperties[0].PropertyID != unboundID {
		t.Fatalf("entries = %#v", result.Entries)
	}
}
