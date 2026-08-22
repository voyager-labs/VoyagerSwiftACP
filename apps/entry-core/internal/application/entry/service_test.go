package entry

import (
	"context"
	"errors"
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/mount"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source/fakeexternal"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source/localfs"
)

var _ ResourceAdapter = (*localfs.ResourceAdapter)(nil)
var _ ResourceAdapter = (*fakeexternal.ResourceAdapter)(nil)

const (
	localSourceID    = "src:8kHitBFXUPx-VG4Qf_M3LXM1kDu4jXaGZ1JTw9cUiyY"
	externalSourceID = "src:m-KQdBGV6oTOo0uNavbxU6UH9heJBwQTseDcv_utLsE"
)

func mustSourceIdentity(t *testing.T, sourceID string, strength domainentry.IdentityStrength) domainentry.SourceIdentity {
	t.Helper()
	identity, err := domainentry.NewSourceIdentity(sourceID, strength)
	if err != nil {
		t.Fatal(err)
	}
	return identity
}

func TestEntryResolver(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	service := mustUnifiedService(t, registry, bindings)
	var _ EntryResolver = service
	ref, err := service.SourceObjectToEntryRef(bindings[0].SourceRef, source.SourceObjectIdentity{ObjectKey: "stable", ResourceType: "document", LocatorRef: locatorFixture(t), IdentityStrength: domainentry.IdentityStrengthStable})
	if err != nil {
		t.Fatal(err)
	}
	selector, err := service.EntryRefToSourceObject(ref)
	if err != nil || selector.SourceInstanceID != ref.SourceInstanceID || selector.SourceObjectKey != "stable" {
		t.Fatalf("selector = %#v, %v", selector, err)
	}
}

func TestUnifiedMultiSourceList(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	local := bindings[1].Adapter.(*recordingResourceAdapter)
	localCursor := "local-next"
	external.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[0].SourceRef, "external-item", "item", nil)}
	local.listResults = []source.AdapterListResult{
		adapterListResultFixture(t, bindings[1].SourceRef, "local-item", "item", &localCursor),
		adapterListResultFixture(t, bindings[1].SourceRef, "local-last", "last", nil),
	}
	if err := external.listResults[0].Validate(1); err != nil {
		t.Fatalf("external fixture invalid: %v", err)
	}
	if err := local.listResults[0].Validate(1); err != nil {
		t.Fatalf("local fixture invalid: %v", err)
	}
	service := mustUnifiedService(t, registry, bindings)
	path := "/"
	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2, RequestedProperties: []string{"title"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Entries) != 2 || result.Entries[0].EntryRef.SourceInstanceID != bindings[0].SourceRef.SourceInstanceID || result.Entries[1].EntryRef.SourceInstanceID != bindings[1].SourceRef.SourceInstanceID {
		t.Fatalf("entries = %#v", result.Entries)
	}
	if external.listCalls != 1 || local.listCalls != 1 || external.listRequests[0].PageQuota != 1 || local.listRequests[0].PageQuota != 1 {
		t.Fatalf("calls external=%d local=%d requests=%#v %#v", external.listCalls, local.listCalls, external.listRequests, local.listRequests)
	}
	if len(local.listRequests[0].RequestedProperties) != 1 || local.listRequests[0].RequestedProperties[0] != "title" {
		t.Fatalf("requested properties = %#v", local.listRequests[0].RequestedProperties)
	}
	if !result.HasMore || result.NextPageToken == nil || len(result.RevisionSummaries) != 2 || len(result.Availabilities) != 2 || len(result.Freshness) != 2 {
		t.Fatalf("result summaries = %#v", result)
	}
	continued, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2,
		PageToken: result.NextPageToken, RequestedProperties: []string{"title"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if external.listCalls != 1 || local.listCalls != 2 || len(continued.Entries) != 1 || continued.HasMore || continued.NextPageToken != nil {
		t.Fatalf("continuation = %#v calls external=%d local=%d", continued, external.listCalls, local.listCalls)
	}
}

func TestAvailabilityPropagation(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	local := bindings[1].Adapter.(*recordingResourceAdapter)
	external.listResults = []source.AdapterListResult{adapterFailureListResultFixture(t, domainentry.AvailabilityStatePermissionDenied)}
	if err := external.listResults[0].Validate(1); err != nil {
		t.Fatalf("failure fixture invalid: %v", err)
	}
	local.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[1].SourceRef, "local", "item", nil)}
	service := mustUnifiedService(t, registry, bindings)
	path := "/"
	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2, RequestedProperties: []string{}})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Entries) != 1 || result.Availabilities[0].State != domainentry.AvailabilityStatePermissionDenied || len(result.Warnings) == 0 {
		t.Fatalf("partial result = %#v", result)
	}

	local.listResults = []source.AdapterListResult{adapterFailureListResultFixture(t, domainentry.AvailabilityStateOffline)}
	external.listResults = []source.AdapterListResult{adapterFailureListResultFixture(t, domainentry.AvailabilityStatePermissionDenied)}
	local.listCalls = 0
	external.listCalls = 0
	service = mustUnifiedService(t, registry, bindings)
	_, err = service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2, RequestedProperties: []string{}})
	if !errors.Is(err, ErrPermissionDenied) {
		t.Fatalf("all-fail error = %v", err)
	}
}

func TestResolveEntry(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "stable-object", "folder/item")
	external.resolveResult = adapterResolveResultFixture(t, item)
	if err := external.resolveResult.Validate(); err != nil {
		t.Fatalf("resolve fixture invalid: %v", err)
	}
	mountRef, err := registry.MountByID("workspace", "external")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := source.NewAdapterResolveRequest(bindings[0].SourceRef, mountRef, &item.EntryRef, nil, []string{}); err != nil {
		t.Fatalf("resolve request invalid: %v source=%v mount=%v ref=%v ids=%q/%q/%q", err, bindings[0].SourceRef.Validate(), mountRef.Validate(), item.EntryRef.Validate(), bindings[0].SourceRef.SourceInstanceID, mountRef.SourceInstanceID, item.EntryRef.SourceInstanceID)
	}
	service := mustUnifiedService(t, registry, bindings)

	mountID := "external"
	byRef, err := service.ResolveEntry(context.Background(), ResolveRequest{WorkspaceID: "workspace", EntryRef: &item.EntryRef, MountID: &mountID, RequestedProperties: []string{}})
	if err != nil {
		t.Fatal(err)
	}
	path := "/external/folder/item"
	byPath, err := service.ResolveEntry(context.Background(), ResolveRequest{WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{}})
	if err != nil {
		t.Fatal(err)
	}
	if byRef.EntryRef.EntryID != byPath.EntryRef.EntryID || byRef.AccessContext.MountID != "external" || byPath.AccessContext.VirtualPath.String() != path {
		t.Fatalf("resolve results = %#v %#v", byRef, byPath)
	}
	if external.resolveCalls != 2 || external.resolveRequests[0].EntryRef == nil || external.resolveRequests[1].RelativePath == nil {
		t.Fatalf("resolve requests = %#v", external.resolveRequests)
	}
}

func TestRequestedProperties(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	adapter.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[0].SourceRef, "external", "item", nil)}
	if err := adapter.listResults[0].Validate(1); err != nil {
		t.Fatalf("fixture invalid: %v", err)
	}
	service := mustUnifiedService(t, registry, bindings)
	path := "/external"
	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"title"}})
	if err != nil {
		t.Fatal(err)
	}
	if len(adapter.listRequests) != 1 || len(adapter.listRequests[0].RequestedProperties) != 1 || adapter.listRequests[0].RequestedProperties[0] != "title" {
		t.Fatalf("request = %#v", adapter.listRequests)
	}
}

func TestResolveEntryRejectsInvalidRequestedProperties(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	service := mustUnifiedService(t, registry, bindings)
	path := "/external"

	for name, properties := range map[string][]string{
		"duplicate": {"title", "title"},
		"unsorted":  {"title", "name"},
	} {
		t.Run(name, func(t *testing.T) {
			_, err := service.ResolveEntry(context.Background(), ResolveRequest{
				WorkspaceID:         "workspace",
				VirtualPath:         &path,
				RequestedProperties: properties,
			})
			if !errors.Is(err, ErrInvalidRequest) || err.Error() != "invalid_request" {
				t.Fatalf("error = %v", err)
			}
		})
	}
}

type recordingResourceAdapter struct {
	listResults     []source.AdapterListResult
	resolveResult   source.AdapterResolveResult
	listCalls       int
	resolveCalls    int
	listRequests    []source.AdapterListRequest
	resolveRequests []source.AdapterResolveRequest
	listError       error
}

func (adapter *recordingResourceAdapter) List(_ context.Context, request source.AdapterListRequest) (source.AdapterListResult, error) {
	adapter.listRequests = append(adapter.listRequests, request)
	index := adapter.listCalls
	adapter.listCalls++
	if adapter.listError != nil {
		return source.AdapterListResult{}, adapter.listError
	}
	if index >= len(adapter.listResults) {
		return source.AdapterListResult{}, source.ErrAdapterFailure
	}
	return adapter.listResults[index], nil
}

func (adapter *recordingResourceAdapter) Resolve(_ context.Context, request source.AdapterResolveRequest) (source.AdapterResolveResult, error) {
	adapter.resolveCalls++
	adapter.resolveRequests = append(adapter.resolveRequests, request)
	return adapter.resolveResult, nil
}

// mutatingResourceAdapter는 악의적 어댑터가 요청 맵을 변조하고 임의 결과를 반환하는
// 시나리오를 재현한다. 서비스 소유 정의 맵이 어댑터 변조로 오염되지 않음을 검증한다.
type mutatingResourceAdapter struct {
	listResults     []source.AdapterListResult
	resolveResult   source.AdapterResolveResult
	onList          func(request source.AdapterListRequest)
	onResolve       func(request source.AdapterResolveRequest)
	listRequests    []source.AdapterListRequest
	resolveRequests []source.AdapterResolveRequest
}

func (adapter *mutatingResourceAdapter) List(_ context.Context, request source.AdapterListRequest) (source.AdapterListResult, error) {
	if adapter.onList != nil {
		adapter.onList(request)
	}
	adapter.listRequests = append(adapter.listRequests, request)
	index := len(adapter.listRequests) - 1
	if index >= len(adapter.listResults) {
		return source.AdapterListResult{}, source.ErrAdapterFailure
	}
	return adapter.listResults[index], nil
}

func (adapter *mutatingResourceAdapter) Resolve(_ context.Context, request source.AdapterResolveRequest) (source.AdapterResolveResult, error) {
	if adapter.onResolve != nil {
		adapter.onResolve(request)
	}
	adapter.resolveRequests = append(adapter.resolveRequests, request)
	return adapter.resolveResult, nil
}

func unifiedFixture(t *testing.T) (*mount.Registry, []ResourceAdapterBinding) {
	t.Helper()
	available, _ := domainentry.NewAvailability(domainentry.AvailabilityStateAvailable)
	externalIdentity := mustSourceIdentity(t, externalSourceID, domainentry.IdentityStrengthStable)
	localIdentity := mustSourceIdentity(t, localSourceID, domainentry.IdentityStrengthLocator)
	externalRef, _ := domainentry.NewSourceRef(externalIdentity.SourceID, "fakeexternal", "external", available, domainentry.IdentityStrengthStable)
	localRef, _ := domainentry.NewSourceRef(localIdentity.SourceID, "localfs", "local", available, domainentry.IdentityStrengthLocator)
	registry := mount.NewMountRegistry()
	for _, candidate := range []struct {
		id, point string
		ref       domainentry.SourceRef
	}{{"external", "/external", externalRef}, {"local", "/local", localRef}} {
		path, _ := domainentry.NewResolvedVirtualPath(candidate.id, candidate.point, "seed")
		mountRef, _ := domainentry.NewMountRef(candidate.id, "workspace", candidate.ref.SourceInstanceID, path, available, domainentry.CachePolicyNone)
		if err := registry.Register(mountRef); err != nil {
			t.Fatal(err)
		}
	}
	return registry, []ResourceAdapterBinding{{SourceRef: externalRef, Adapter: &recordingResourceAdapter{}}, {SourceRef: localRef, Adapter: &recordingResourceAdapter{}}}
}

func mustUnifiedService(t *testing.T, registry *mount.Registry, bindings []ResourceAdapterBinding) *UnifiedService {
	t.Helper()
	service, err := NewUnifiedService(registry, bindings, []byte("01234567890123456789012345678901"), func() time.Time { return time.Unix(10, 0).UTC() })
	if err != nil {
		t.Fatal(err)
	}
	return service
}

func TestPropertyDefinitionsResolveCatalogTerms(t *testing.T) {
	titleID := domainentry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64d")
	service := &UnifiedService{catalog: domainentry.PropertyCatalogSnapshot{
		Definitions: []domainentry.WorkspacePropertyDefinition{{
			PropertyID: titleID, IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
			Namespace: "system", CanonicalKey: "common.title", DisplayName: "Title",
			ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
			Provenance: domainentry.PropertyProvenanceSystem,
		}},
		Terms: []domainentry.WorkspacePropertyTerm{{PropertyID: titleID, TermKind: "legacy_alias", TermValue: "title"}},
	}}
	definitions, err := service.propertyDefinitions([]string{"title"})
	if err != nil {
		t.Fatal(err)
	}
	definition, ok := definitions["title"]
	if !ok || definition.PropertyID != titleID || definition.Key != "common.title" || definition.Namespace != "system" {
		t.Fatalf("title definition = %#v", definition)
	}
}

// VOY-764 회귀: canonical key와 alias는 하나의 resolver를 공유하고 같은 카탈로그
// 정의(PropertyID·ValueType·Cardinality)를 반환해야 한다.
func TestPropertyDefinitionsResolveCanonicalKeySameAsAlias(t *testing.T) {
	titleID := domainentry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64d")
	service := &UnifiedService{catalog: domainentry.PropertyCatalogSnapshot{
		Definitions: []domainentry.WorkspacePropertyDefinition{{
			PropertyID: titleID, IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
			Namespace: "system", CanonicalKey: "common.title", DisplayName: "Title",
			ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
			Provenance: domainentry.PropertyProvenanceSystem,
		}},
		Terms: []domainentry.WorkspacePropertyTerm{{PropertyID: titleID, TermKind: "legacy_alias", TermValue: "title"}},
	}}
	aliasDefinitions, err := service.propertyDefinitions([]string{"title"})
	if err != nil {
		t.Fatal(err)
	}
	canonicalDefinitions, err := service.propertyDefinitions([]string{"common.title"})
	if err != nil {
		t.Fatal(err)
	}
	alias, aliasOK := aliasDefinitions["title"]
	canonical, canonicalOK := canonicalDefinitions["common.title"]
	if !aliasOK || !canonicalOK {
		t.Fatalf("resolution missing: alias=%v canonical=%v", aliasOK, canonicalOK)
	}
	if alias.PropertyID != titleID || canonical.PropertyID != titleID {
		t.Fatalf("alias id = %s, canonical id = %s, want %s", alias.PropertyID, canonical.PropertyID, titleID)
	}
	if alias.ValueType != domainentry.PropertyTypeText || canonical.ValueType != domainentry.PropertyTypeText ||
		alias.Cardinality != domainentry.PropertyCardinalityOne || canonical.Cardinality != domainentry.PropertyCardinalityOne ||
		canonical.Key != "common.title" {
		t.Fatalf("alias = %#v, canonical = %#v, want shared catalog contract", alias, canonical)
	}
}

func TestNormalizeRequestedPropertiesDeduplicatesSemanticSelectors(t *testing.T) {
	titleID := domainentry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64d")
	service := &UnifiedService{catalog: domainentry.PropertyCatalogSnapshot{
		Definitions: []domainentry.WorkspacePropertyDefinition{{
			PropertyID: titleID, IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
			Namespace: "system", CanonicalKey: "common.title", DisplayName: "Title",
			ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
			Provenance: domainentry.PropertyProvenanceSystem,
		}},
		Terms: []domainentry.WorkspacePropertyTerm{{PropertyID: titleID, TermKind: "legacy_alias", TermValue: "title"}},
	}}
	normalized, err := service.normalizeRequestedProperties([]string{"common.title", "title"})
	if err != nil {
		t.Fatal(err)
	}
	if len(normalized) != 1 || normalized[0] != "common.title" {
		t.Fatalf("normalized selectors = %#v, want [common.title]", normalized)
	}
}

// VOY-764 회귀: UUIDv7 PropertyID term은 registry 재해싱 없이 resolve된다.
func TestPropertyDefinitionsResolveVoyagerIssuedTerm(t *testing.T) {
	v7ID := domainentry.MustPropertyID("0198c0de-f00d-7000-8000-3b9ac9e12345")
	service := &UnifiedService{catalog: domainentry.PropertyCatalogSnapshot{
		Definitions: []domainentry.WorkspacePropertyDefinition{{
			PropertyID: v7ID, IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
			Namespace: "system", CanonicalKey: "common.title", DisplayName: "Title",
			ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
			Provenance: domainentry.PropertyProvenanceSystem,
		}},
		Terms: []domainentry.WorkspacePropertyTerm{{PropertyID: v7ID, TermKind: "legacy_alias", TermValue: "title"}},
	}}
	definitions, err := service.propertyDefinitions([]string{"title"})
	if err != nil {
		t.Fatal(err)
	}
	definition, ok := definitions["title"]
	if !ok || definition.PropertyID != v7ID || definition.IdentityScheme != domainentry.PropertyIdentitySchemeVoyagerIssued {
		t.Fatalf("title definition = %#v, want voyager-issued %s", definition, v7ID)
	}
}

// VOY-764 회귀(후속 P1): 같은 별칭이 서로 다른 PropertyID에 걸리면 첫 매칭 대신 실패 닫기한다.
func TestPropertyDefinitionsRejectsAmbiguousAlias(t *testing.T) {
	firstID := domainentry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64d")
	secondID := domainentry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64e")
	service := &UnifiedService{catalog: domainentry.PropertyCatalogSnapshot{
		Definitions: []domainentry.WorkspacePropertyDefinition{
			{
				PropertyID: firstID, IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
				Namespace: "system", CanonicalKey: "common.title", DisplayName: "Title",
				ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
				Provenance: domainentry.PropertyProvenanceSystem,
			},
			{
				PropertyID: secondID, IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
				Namespace: "system", CanonicalKey: "common.body", DisplayName: "Body",
				ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
				Provenance: domainentry.PropertyProvenanceSystem,
			},
		},
		Terms: []domainentry.WorkspacePropertyTerm{
			{PropertyID: firstID, TermKind: "legacy_alias", TermValue: "shared"},
			{PropertyID: secondID, TermKind: "legacy_alias", TermValue: "shared"},
		},
	}}
	definitions, err := service.propertyDefinitions([]string{"shared"})
	if !errors.Is(err, ErrAmbiguousPropertySelector) {
		t.Fatalf("propertyDefinitions() error = %v, want %v", err, ErrAmbiguousPropertySelector)
	}
	if definitions != nil {
		t.Fatalf("definitions = %#v, want nil on ambiguity", definitions)
	}
}

// VOY-764 회귀(후속 P1): canonical key가 여러 정의에 걸리는 잘못된 스냅샷도 실패 닫기한다.
func TestPropertyDefinitionsRejectsAmbiguousCanonicalKey(t *testing.T) {
	firstID := domainentry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64d")
	secondID := domainentry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64e")
	service := &UnifiedService{catalog: domainentry.PropertyCatalogSnapshot{
		Definitions: []domainentry.WorkspacePropertyDefinition{
			{
				PropertyID: firstID, IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
				Namespace: "system", CanonicalKey: "common.dup", DisplayName: "First",
				ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
				Provenance: domainentry.PropertyProvenanceSystem,
			},
			{
				PropertyID: secondID, IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
				Namespace: "system", CanonicalKey: "common.dup", DisplayName: "Second",
				ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
				Provenance: domainentry.PropertyProvenanceSystem,
			},
		},
	}}
	definitions, err := service.propertyDefinitions([]string{"common.dup"})
	if !errors.Is(err, ErrAmbiguousPropertySelector) {
		t.Fatalf("propertyDefinitions() error = %v, want %v", err, ErrAmbiguousPropertySelector)
	}
	if definitions != nil {
		t.Fatalf("definitions = %#v, want nil on ambiguity", definitions)
	}
}

func adapterListResultFixture(t *testing.T, sourceRef domainentry.SourceRef, key, relative string, cursor *string) source.AdapterListResult {
	t.Helper()
	item := adapterEntryFixture(t, sourceRef, key, relative)
	revision := item.EntrySnapshot.SourceRevision.Revision
	return source.AdapterListResult{Items: []source.AdapterEntry{item}, NextChildCursor: cursor, SourceRevision: revision, Availability: item.EntrySnapshot.Availability, Freshness: item.EntrySnapshot.Freshness, Warnings: []source.Warning{}}
}

func adapterFailureListResultFixture(t *testing.T, state domainentry.AvailabilityState) source.AdapterListResult {
	t.Helper()
	revision, _ := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := domainentry.NewSourceRevision(revision)
	freshness, _ := domainentry.NewFreshness(domainentry.FreshnessStateUnknown, time.Unix(1, 0).UTC(), sourceRevision, nil, nil)
	availability, _ := domainentry.NewAvailability(state)
	code := source.SourceErrorCodeSourceUnavailable
	if state == domainentry.AvailabilityStatePermissionDenied {
		code = source.SourceErrorCodePermissionDenied
	}
	sourceError, _ := source.NewSourceError(code)
	return source.AdapterListResult{Items: []source.AdapterEntry{}, SourceRevision: revision, Availability: availability, Freshness: freshness, SourceError: sourceError, Warnings: []source.Warning{}}
}

func adapterResolveResultFixture(t *testing.T, item source.AdapterEntry) source.AdapterResolveResult {
	t.Helper()
	return source.AdapterResolveResult{Item: &item, SourceRevision: item.EntrySnapshot.SourceRevision.Revision, Availability: item.EntrySnapshot.Availability, Freshness: item.EntrySnapshot.Freshness, Warnings: []source.Warning{}}
}

func adapterEntryFixture(t *testing.T, sourceRef domainentry.SourceRef, key, relative string) source.AdapterEntry {
	t.Helper()
	locator := locatorFixture(t)
	ref, err := domainentry.NewEntryRef(domainentry.DeriveEntryID(sourceRef.SourceInstanceID, "document", key), sourceRef.SourceInstanceID, key, "document", locator, sourceRef.IdentityStrength)
	if err != nil {
		t.Fatal(err)
	}
	revision, _ := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := domainentry.NewSourceRevision(revision)
	observedRevision, _ := domainentry.NewObservedRevision(1)
	observed := time.Unix(1, 0).UTC()
	freshness, _ := domainentry.NewFreshness(domainentry.FreshnessStateCurrent, observed, sourceRevision, nil, nil)
	available, _ := domainentry.NewAvailability(domainentry.AvailabilityStateAvailable)
	snapshot, err := domainentry.NewCanonicalEntrySnapshot(ref, key, nil, []domainentry.PropertyValue{}, sourceRevision, observedRevision, observed, nil, available, freshness)
	if err != nil {
		t.Fatal(err)
	}
	return source.AdapterEntry{RelativePath: relative, EntryRef: ref, EntrySnapshot: snapshot, Capabilities: domainentry.Capabilities{Readable: true}}
}

func locatorFixture(t *testing.T) domainentry.LocatorRef {
	t.Helper()
	locator, err := domainentry.NewLocatorRef("loc:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
	if err != nil {
		t.Fatal(err)
	}
	return locator
}

func TestUnifiedMultiSourceListPageSizePrecondition(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	service := mustUnifiedService(t, registry, bindings)
	path := "/"
	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{}})
	if !errors.Is(err, ErrInvalidRequest) || err.Error() != "page_size_too_small" {
		t.Fatalf("small page error = %v", err)
	}
	for _, binding := range bindings {
		adapter := binding.Adapter.(*recordingResourceAdapter)
		if adapter.listCalls != 0 || adapter.resolveCalls != 0 {
			t.Fatalf("adapter called before page-size rejection: %#v", adapter)
		}
	}
}

func TestUnifiedMultiSourceListParentRef(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "opaque-parent", "folder")
	external.resolveResult = adapterResolveResultFixture(t, parent)
	external.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[0].SourceRef, "child", "folder/child", nil)}
	service := mustUnifiedService(t, registry, bindings)
	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{}})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Entries) != 1 || external.resolveCalls != 1 || external.listCalls != 1 || external.listRequests[0].RelativePath != "folder" {
		t.Fatalf("parent result = %#v resolve=%#v list=%#v", result, external.resolveRequests, external.listRequests)
	}
}

func TestAvailabilityPropagationTypedAdapterErrors(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	bindings[0].Adapter.(*recordingResourceAdapter).listError = source.ErrPermissionDenied
	bindings[1].Adapter.(*recordingResourceAdapter).listError = source.ErrSourceDeleted
	service := mustUnifiedService(t, registry, bindings)
	path := "/"
	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2, RequestedProperties: []string{}})
	if !errors.Is(err, ErrPermissionDenied) {
		t.Fatalf("typed all-fail error = %v", err)
	}
}

func TestUnifiedListPreservesEntryNotFoundFromAdapter(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	external.listError = source.ErrEntryNotFound
	service := mustUnifiedService(t, registry, bindings[:1])
	path := "/external/missing"

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{},
	})
	if !errors.Is(err, ErrEntryNotFound) || err.Error() != "entry_not_found" {
		t.Fatalf("UnifiedList() error = %v, want entry_not_found", err)
	}
}

func TestUnifiedListKeepsEntryNotFoundAsPartialFailure(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	local := bindings[1].Adapter.(*recordingResourceAdapter)
	external.listError = source.ErrEntryNotFound
	local.listResults = []source.AdapterListResult{
		adapterListResultFixture(t, bindings[1].SourceRef, "local", "item", nil),
	}
	service := mustUnifiedService(t, registry, bindings)
	path := "/"

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2, RequestedProperties: []string{},
	})
	if err != nil {
		t.Fatal(err)
	}
	partial := false
	for _, warning := range result.Warnings {
		partial = partial || warning.Code == source.WarningCodePartialResult
	}
	if len(result.Entries) != 1 || !partial {
		t.Fatalf("UnifiedList() result = %#v, want one entry and partial_result warning", result)
	}
}

func TestUnifiedListContinuationPreservesEntryNotFoundFailure(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	local := bindings[1].Adapter.(*recordingResourceAdapter)
	localCursor := "local-next"
	external.listError = source.ErrEntryNotFound
	local.listResults = []source.AdapterListResult{
		adapterListResultFixture(t, bindings[1].SourceRef, "local", "item", &localCursor),
	}
	service := mustUnifiedService(t, registry, bindings)
	path := "/"

	first, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2, RequestedProperties: []string{},
	})
	if err != nil || first.NextPageToken == nil {
		t.Fatalf("first page = %#v, error = %v", first, err)
	}

	_, err = service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2,
		PageToken: first.NextPageToken, RequestedProperties: []string{},
	})
	if !errors.Is(err, ErrEntryNotFound) || err.Error() != "entry_not_found" {
		t.Fatalf("continued UnifiedList() error = %v, want entry_not_found", err)
	}
}

func TestResolveEntryRejectsCrossSourceResult(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	foreign := adapterEntryFixture(t, bindings[1].SourceRef, "foreign", "item")
	external.resolveResult = adapterResolveResultFixture(t, foreign)
	service := mustUnifiedService(t, registry, bindings)
	path := "/external/item"
	_, err := service.ResolveEntry(context.Background(), ResolveRequest{WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{}})
	if !errors.Is(err, ErrContextMismatch) {
		t.Fatalf("cross-source resolve error = %v", err)
	}
}

func TestUnifiedMultiSourceListRejectsParentSelectorMismatch(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	service := mustUnifiedService(t, registry, bindings)
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "parent", "parent")
	mountID := "local"
	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", MountID: &mountID, ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{}})
	if !errors.Is(err, ErrInvalidSelector) {
		t.Fatalf("selector mismatch error = %v", err)
	}
	if bindings[0].Adapter.(*recordingResourceAdapter).listCalls != 0 || bindings[1].Adapter.(*recordingResourceAdapter).listCalls != 0 {
		t.Fatal("adapter called for selector mismatch")
	}
}

func TestResolveEntryRejectsDifferentRelativePath(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	external.resolveResult = adapterResolveResultFixture(t, adapterEntryFixture(t, bindings[0].SourceRef, "different", "different"))
	service := mustUnifiedService(t, registry, bindings)
	path := "/external/requested"
	_, err := service.ResolveEntry(context.Background(), ResolveRequest{WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{}})
	if !errors.Is(err, ErrContextMismatch) {
		t.Fatalf("different relative path error = %v", err)
	}
}

func TestEntryResolverRejectsDifferentEntryProjection(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	requested := adapterEntryFixture(t, bindings[0].SourceRef, "requested", "requested")
	external.resolveResult = adapterResolveResultFixture(t, adapterEntryFixture(t, bindings[0].SourceRef, "different", "different"))
	service := mustUnifiedService(t, registry, bindings)
	_, err := service.EntryRefToVirtualPaths(requested.EntryRef)
	if !errors.Is(err, ErrContextMismatch) {
		t.Fatalf("different projection error = %v", err)
	}
}

func TestCompositeCursorRejectsInvalidChildCursor(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	local := bindings[1].Adapter.(*recordingResourceAdapter)
	child := "child"
	external.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[0].SourceRef, "external", "item", nil)}
	local.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[1].SourceRef, "local", "item", &child)}
	service := mustUnifiedService(t, registry, bindings)
	path := "/"
	first, err := service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2, RequestedProperties: []string{}})
	if err != nil || first.NextPageToken == nil {
		t.Fatalf("first = %#v, %v", first, err)
	}
	local.listError = source.ErrInvalidCursor
	_, err = service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", VirtualPath: &path, PageSize: 2, PageToken: first.NextPageToken, RequestedProperties: []string{}})
	if !errors.Is(err, ErrInvalidPageToken) {
		t.Fatalf("invalid child cursor error = %v", err)
	}
}

type snapshotCountingRegistry struct {
	*mount.Registry
	snapshots int
}

func (registry *snapshotCountingRegistry) Snapshot() mount.MountRegistrySnapshot {
	registry.snapshots++
	return registry.Registry.Snapshot()
}

type unmountingResourceAdapter struct {
	delegate *recordingResourceAdapter
	registry *mount.Registry
	mountID  string
}

func (adapter *unmountingResourceAdapter) List(ctx context.Context, request source.AdapterListRequest) (source.AdapterListResult, error) {
	result, err := adapter.delegate.List(ctx, request)
	_ = adapter.registry.Unmount(adapter.mountID)
	return result, err
}
func (adapter *unmountingResourceAdapter) Resolve(ctx context.Context, request source.AdapterResolveRequest) (source.AdapterResolveResult, error) {
	result, err := adapter.delegate.Resolve(ctx, request)
	_ = adapter.registry.Unmount(adapter.mountID)
	return result, err
}

func TestListUsesSingleSnapshot(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	base := bindings[0].Adapter.(*recordingResourceAdapter)
	base.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[0].SourceRef, "item", "item", nil)}
	bindings = bindings[:1]
	bindings[0].Adapter = &unmountingResourceAdapter{delegate: base, registry: registry, mountID: "external"}
	counting := &snapshotCountingRegistry{Registry: registry}
	service, err := NewUnifiedService(counting, bindings, []byte("01234567890123456789012345678901"), func() time.Time { return time.Unix(10, 0).UTC() })
	if err != nil {
		t.Fatal(err)
	}
	path := "/external"
	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{}})
	if err != nil || counting.snapshots != 1 || len(result.Entries) != 1 || result.Entries[0].AccessContext.VirtualPath.String() != "/external/item" {
		t.Fatalf("result=%#v err=%v snapshots=%d", result, err, counting.snapshots)
	}
}

func TestResolveUsesSingleSnapshot(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	base := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	base.resolveResult = adapterResolveResultFixture(t, item)
	bindings = bindings[:1]
	bindings[0].Adapter = &unmountingResourceAdapter{delegate: base, registry: registry, mountID: "external"}
	counting := &snapshotCountingRegistry{Registry: registry}
	service, err := NewUnifiedService(counting, bindings, []byte("01234567890123456789012345678901"), func() time.Time { return time.Unix(10, 0).UTC() })
	if err != nil {
		t.Fatal(err)
	}
	service.observed.Store(item.EntrySnapshot.ObservedRevision.Sequence)
	path := "/external/item"
	result, err := service.ResolveEntry(context.Background(), ResolveRequest{WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{}})
	if err != nil || counting.snapshots != 1 || result.AccessContext.VirtualPath.String() != path || result.EntrySnapshot.ObservedRevision.Sequence <= item.EntrySnapshot.ObservedRevision.Sequence {
		t.Fatalf("result=%#v err=%v snapshots=%d", result, err, counting.snapshots)
	}
}

func TestObservedRevisionSequencerListAndResolve(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	external := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "item", "item")
	external.listResults = []source.AdapterListResult{adapterListResultFixture(t, bindings[0].SourceRef, "item", "item", nil)}
	external.resolveResult = adapterResolveResultFixture(t, item)
	service := mustUnifiedService(t, registry, bindings[:1])
	path := "/external"
	listed, err := service.UnifiedList(context.Background(), UnifiedListRequest{WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{}})
	if err != nil {
		t.Fatal(err)
	}
	resolvePath := "/external/item"
	resolved, err := service.ResolveEntry(context.Background(), ResolveRequest{WorkspaceID: "workspace", VirtualPath: &resolvePath, RequestedProperties: []string{}})
	if err != nil {
		t.Fatal(err)
	}
	if len(listed.RevisionSummaries) != 1 || listed.RevisionSummaries[0].ObservedRevision.Sequence == 0 || resolved.EntrySnapshot.ObservedRevision.Sequence <= listed.RevisionSummaries[0].ObservedRevision.Sequence {
		t.Fatalf("list=%#v resolve=%#v", listed.RevisionSummaries, resolved.EntrySnapshot.ObservedRevision)
	}
}
