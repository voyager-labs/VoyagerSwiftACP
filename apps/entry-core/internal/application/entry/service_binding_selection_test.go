package entry

import (
	"context"
	"errors"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

// VOY-764 바인딩 선택 수리 회귀(선별 통합본): 하나의 canonical key에 여러 활성 바인딩이
// 존재할 때 카탈로그 슬라이스 순서가 아니라 현재 요청 컨텍스트의 스코프 적용 가능성과
// 스코프 구체성 우선순위로 선택해야 한다. 동순위 모호 실패 닫기와 List·Resolve·ParentRef
// 경로 커버리지는 service_source_property_contracts_test.go가 단일 소유한다.

func nativeStringProperty(t *testing.T, key, value string) domainentry.Property {
	t.Helper()
	propertyValue, err := domainentry.NewStringPropertyValue(value)
	if err != nil {
		t.Fatal(err)
	}
	property, err := domainentry.NewProperty(key, propertyValue)
	if err != nil {
		t.Fatal(err)
	}
	return property
}

type titleBindingSpec struct {
	scopeKind     domainentry.SourceScopeKind
	scopeExternal string
	externalID    string
	nativeKey     string
}

var (
	systemTitleBinding    = titleBindingSpec{domainentry.SourceScopeKindSystem, "macos", "sys.title", "system_title"}
	workspaceTitleBinding = titleBindingSpec{domainentry.SourceScopeKindWorkspace, "workspace", "kMDItemTitle", "title"}
)

func catalogWithTitleBindings(sourceInstanceID string, specs []titleBindingSpec) domainentry.PropertyCatalogSnapshot {
	catalog := titleCatalogFixture()
	for _, spec := range specs {
		ref := domainentry.SourcePropertyRef{
			ProviderID: "macos.fakeexternal", SourceInstanceID: sourceInstanceID,
			ScopeKind: spec.scopeKind, ScopeExternalID: spec.scopeExternal,
			ExternalPropertyID: spec.externalID,
		}
		catalog.Descriptors = append(catalog.Descriptors, domainentry.SourcePropertyDescriptor{
			Ref: ref, NativeKey: spec.nativeKey, NativeType: "string",
			NativeCardinality: domainentry.PropertyCardinalityOne,
			Authority:         domainentry.AuthorityKindProvider, SourceReadable: true,
			Lifecycle: domainentry.PropertyLifecycleActive,
		})
		catalog.Bindings = append(catalog.Bindings, domainentry.PropertyBinding{
			PropertyID: catalogTitleID, SourceRef: ref, ReadTransform: "identity", Direction: "read",
			EffectiveReadable: true, ApprovalState: "approved", Lifecycle: domainentry.PropertyLifecycleActive,
		})
	}
	return catalog
}

func multiSourceNativeProperties(t *testing.T) []domainentry.Property {
	return []domainentry.Property{
		nativeStringProperty(t, "title", "Roadmap"),
		nativeStringProperty(t, "system_title", "SystemTitle"),
		nativeStringProperty(t, "display_title", "DisplayTitle"),
	}
}

func assertWorkspaceTitleSelected(t *testing.T, properties []domainentry.PropertyValue) {
	t.Helper()
	assertCanonicalTitleText(t, properties, "Roadmap")
}

func assertCanonicalTitleText(t *testing.T, properties []domainentry.PropertyValue, want string) {
	t.Helper()
	if len(properties) != 1 || properties[0].PropertyID != catalogTitleID ||
		properties[0].Payload.Text == nil || *properties[0].Payload.Text != want {
		t.Fatalf("canonical properties = %#v, want native title %q under %s", properties, want, catalogTitleID)
	}
}

func TestUnifiedListSelectsApplicableBindingRegardlessOfCatalogOrder(t *testing.T) {
	scenarios := []struct {
		name     string
		bindings []titleBindingSpec
	}{
		{"system first", []titleBindingSpec{systemTitleBinding, workspaceTitleBinding}},
		{"workspace first", []titleBindingSpec{workspaceTitleBinding, systemTitleBinding}},
	}
	for _, scenario := range scenarios {
		t.Run(scenario.name, func(t *testing.T) {
			registry, bindings, sourceInstanceID := fakeExternalFixture(t, multiSourceNativeProperties(t))
			service := mustUnifiedServiceWithCatalog(t, registry, bindings, catalogWithTitleBindings(sourceInstanceID, scenario.bindings))
			path := "/external"

			result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
				WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
			})
			if err != nil {
				t.Fatalf("UnifiedList() error = %v", err)
			}
			if len(result.Entries) != 1 {
				t.Fatalf("entries = %#v, want exactly one entry", result.Entries)
			}
			assertWorkspaceTitleSelected(t, result.Entries[0].EntrySnapshot.CanonicalProperties)
		})
	}
}

// VOY-764 ordinal 수리 회귀: 같은 스코프 계층(여기서는 system)에 여러 system key
// 바인딩이 있으면 모호로 거부하지 않고 검토된 binding_ordinal이 낮은 것을 선택한다.
// ordinal이 같고 서로 다른 소스 ref면 여전히 동순위 모호로 실패 닫기한다.
func TestUnifiedListSelectsLowestOrdinalWithinSameScope(t *testing.T) {
	scenarios := []struct {
		name      string
		firstKey  string
		firstOrd  int
		secondKey string
		secondOrd int
		wantText  string
	}{
		{"lower ordinal listed first", "system_title", 0, "display_title", 1, "SystemTitle"},
		{"lower ordinal listed last", "display_title", 1, "system_title", 0, "SystemTitle"},
	}
	for _, scenario := range scenarios {
		t.Run(scenario.name, func(t *testing.T) {
			registry, bindings, sourceInstanceID := fakeExternalFixture(t, multiSourceNativeProperties(t))
			catalog := titleCatalogFixture()
			for _, spec := range []struct {
				key string
				ord int
			}{{scenario.firstKey, scenario.firstOrd}, {scenario.secondKey, scenario.secondOrd}} {
				ref := domainentry.SourcePropertyRef{
					ProviderID: "macos.fakeexternal", SourceInstanceID: sourceInstanceID,
					ScopeKind: domainentry.SourceScopeKindSystem, ScopeExternalID: "macos",
					ExternalPropertyID: spec.key,
				}
				catalog.Descriptors = append(catalog.Descriptors, domainentry.SourcePropertyDescriptor{
					Ref: ref, NativeKey: spec.key, NativeType: "string",
					NativeCardinality: domainentry.PropertyCardinalityOne,
					Authority:         domainentry.AuthorityKindProvider, SourceReadable: true,
					Lifecycle: domainentry.PropertyLifecycleActive,
				})
				catalog.Bindings = append(catalog.Bindings, domainentry.PropertyBinding{
					PropertyID: catalogTitleID, SourceRef: ref, BindingOrdinal: spec.ord,
					ReadTransform: "identity", Direction: "read",
					EffectiveReadable: true, ApprovalState: "approved", Lifecycle: domainentry.PropertyLifecycleActive,
				})
			}
			service := mustUnifiedServiceWithCatalog(t, registry, bindings, catalog)
			path := "/external"

			result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
				WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
			})
			if err != nil {
				t.Fatalf("UnifiedList() error = %v", err)
			}
			if len(result.Entries) != 1 {
				t.Fatalf("entries = %#v, want exactly one entry", result.Entries)
			}
			assertCanonicalTitleText(t, result.Entries[0].EntrySnapshot.CanonicalProperties, scenario.wantText)
		})
	}
}

func TestUnifiedListRejectsSameScopeEqualOrdinalAmbiguity(t *testing.T) {
	registry, bindings, sourceInstanceID := fakeExternalFixture(t, multiSourceNativeProperties(t))
	catalog := titleCatalogFixture()
	for _, nativeKey := range []string{"system_title", "display_title"} {
		ref := domainentry.SourcePropertyRef{
			ProviderID: "macos.fakeexternal", SourceInstanceID: sourceInstanceID,
			ScopeKind: domainentry.SourceScopeKindSystem, ScopeExternalID: "macos",
			ExternalPropertyID: nativeKey,
		}
		catalog.Descriptors = append(catalog.Descriptors, domainentry.SourcePropertyDescriptor{
			Ref: ref, NativeKey: nativeKey, NativeType: "string",
			NativeCardinality: domainentry.PropertyCardinalityOne,
			Authority:         domainentry.AuthorityKindProvider, SourceReadable: true,
			Lifecycle: domainentry.PropertyLifecycleActive,
		})
		catalog.Bindings = append(catalog.Bindings, domainentry.PropertyBinding{
			PropertyID: catalogTitleID, SourceRef: ref, BindingOrdinal: 0,
			ReadTransform: "identity", Direction: "read",
			EffectiveReadable: true, ApprovalState: "approved", Lifecycle: domainentry.PropertyLifecycleActive,
		})
	}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings, catalog)
	path := "/external"

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
	})
	if !errors.Is(err, ErrAmbiguousSourceBinding) {
		t.Fatalf("UnifiedList() error = %v, want ErrAmbiguousSourceBinding", err)
	}
}

func TestResolveEntrySelectsApplicableBindingLikeUnifiedList(t *testing.T) {
	registry, bindings, sourceInstanceID := fakeExternalFixture(t, multiSourceNativeProperties(t))
	service := mustUnifiedServiceWithCatalog(t, registry, bindings, catalogWithTitleBindings(sourceInstanceID, []titleBindingSpec{systemTitleBinding, workspaceTitleBinding}))
	path := "/external/doc"

	result, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{"common.title"},
	})
	if err != nil {
		t.Fatalf("ResolveEntry() error = %v", err)
	}
	assertWorkspaceTitleSelected(t, result.EntrySnapshot.CanonicalProperties)
}

func TestParentRefPathUsesSameApplicableBindingAsMainList(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	recorder := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "child", "folder/child")
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "opaque-parent", "folder")
	recorder.resolveResult = adapterResolveResultFixture(t, parent)
	recorder.listResults = []source.AdapterListResult{{
		Items:          []source.AdapterEntry{item},
		SourceRevision: item.EntrySnapshot.SourceRevision.Revision,
		Availability:   item.EntrySnapshot.Availability,
		Freshness:      item.EntrySnapshot.Freshness,
		Warnings:       []source.Warning{},
	}}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], catalogWithTitleBindings(bindings[0].SourceRef.SourceInstanceID, []titleBindingSpec{systemTitleBinding, workspaceTitleBinding}))

	if _, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{"common.title"},
	}); err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if len(recorder.resolveRequests) == 0 || len(recorder.listRequests) == 0 {
		t.Fatalf("adapter calls resolve=%d list=%d, want both paths exercised", len(recorder.resolveRequests), len(recorder.listRequests))
	}
	if got := recorder.resolveRequests[0].SourceSelectors["common.title"].NativeKey; got != "title" {
		t.Fatalf("parent resolve selector native key = %q, want title (workspace-scoped)", got)
	}
	if got := recorder.listRequests[0].SourceSelectors["common.title"].NativeKey; got != "title" {
		t.Fatalf("main list selector native key = %q, want title (workspace-scoped)", got)
	}
}

// VOY-764 P1 복구(review v4 결함 1): 바인딩 후보 수집이 요청 스코프 정체를 무시하면
// 다른 워크스페이스·저장소 스코프 바인딩이 적용 후보로 들어와 잘못된 네이티브 키가
// 선택되거나 동순위 모호로 오판된다. repository > workspace > system 우선순위 판정보다
// 먼저 현재 요청의 워크스페이스/마운트 정체로 적용 가능성을 걸러야 한다.
var (
	foreignWorkspaceTitleBinding  = titleBindingSpec{domainentry.SourceScopeKindWorkspace, "other-workspace", "kMDItemTitle", "display_title"}
	currentRepositoryTitleBinding = titleBindingSpec{domainentry.SourceScopeKindRepository, "external", "repo.title", "display_title"}
	foreignRepositoryTitleBinding = titleBindingSpec{domainentry.SourceScopeKindRepository, "other-repository", "repo.title", "display_title"}
)

func TestUnifiedListIgnoresBindingsScopedToOtherWorkspace(t *testing.T) {
	for _, tc := range []struct {
		name    string
		reverse bool
	}{
		{name: "seed_order"}, {name: "reversed_catalog_order", reverse: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			registry, bindings, sourceInstanceID := fakeExternalFixture(t, multiSourceNativeProperties(t))
			catalog := catalogWithTitleBindings(sourceInstanceID, []titleBindingSpec{foreignWorkspaceTitleBinding, workspaceTitleBinding})
			if tc.reverse {
				catalog = reverseTitleCatalogPairs(catalog)
			}
			service := mustUnifiedServiceWithCatalog(t, registry, bindings, catalog)
			path := "/external"

			result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
				WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
			})
			if err != nil {
				t.Fatalf("UnifiedList() error = %v", err)
			}
			if len(result.Entries) != 1 {
				t.Fatalf("entries = %#v, want exactly one entry", result.Entries)
			}
			assertCanonicalTitleText(t, result.Entries[0].EntrySnapshot.CanonicalProperties, "Roadmap")
		})
	}
}

func TestResolveEntryIgnoresBindingsScopedToOtherWorkspace(t *testing.T) {
	registry, bindings, sourceInstanceID := fakeExternalFixture(t, multiSourceNativeProperties(t))
	service := mustUnifiedServiceWithCatalog(t, registry, bindings,
		catalogWithTitleBindings(sourceInstanceID, []titleBindingSpec{foreignWorkspaceTitleBinding, workspaceTitleBinding}))
	path := "/external/doc"

	result, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{"common.title"},
	})
	if err != nil {
		t.Fatalf("ResolveEntry() error = %v", err)
	}
	assertCanonicalTitleText(t, result.EntrySnapshot.CanonicalProperties, "Roadmap")
}

func TestParentRefPathIgnoresBindingsScopedToOtherWorkspace(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	recorder := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixture(t, bindings[0].SourceRef, "child", "folder/child")
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "opaque-parent", "folder")
	recorder.resolveResult = adapterResolveResultFixture(t, parent)
	recorder.listResults = []source.AdapterListResult{{
		Items:          []source.AdapterEntry{item},
		SourceRevision: item.EntrySnapshot.SourceRevision.Revision,
		Availability:   item.EntrySnapshot.Availability,
		Freshness:      item.EntrySnapshot.Freshness,
		Warnings:       []source.Warning{},
	}}
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
		catalogWithTitleBindings(bindings[0].SourceRef.SourceInstanceID, []titleBindingSpec{foreignWorkspaceTitleBinding, workspaceTitleBinding}))

	if _, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{"common.title"},
	}); err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if len(recorder.resolveRequests) == 0 || len(recorder.listRequests) == 0 {
		t.Fatalf("adapter calls resolve=%d list=%d, want both paths exercised", len(recorder.resolveRequests), len(recorder.listRequests))
	}
	if got := recorder.resolveRequests[0].SourceSelectors["common.title"].NativeKey; got != "title" {
		t.Fatalf("parent resolve selector native key = %q, want title (current workspace)", got)
	}
	if got := recorder.listRequests[0].SourceSelectors["common.title"].NativeKey; got != "title" {
		t.Fatalf("main list selector native key = %q, want title (current workspace)", got)
	}
}

func TestUnifiedListIgnoresRepositoryBindingsOfOtherRepository(t *testing.T) {
	registry, bindings, sourceInstanceID := fakeExternalFixture(t, multiSourceNativeProperties(t))
	service := mustUnifiedServiceWithCatalog(t, registry, bindings,
		catalogWithTitleBindings(sourceInstanceID, []titleBindingSpec{systemTitleBinding, foreignRepositoryTitleBinding}))
	path := "/external"

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
	})
	if err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if len(result.Entries) != 1 {
		t.Fatalf("entries = %#v, want exactly one entry", result.Entries)
	}
	assertCanonicalTitleText(t, result.Entries[0].EntrySnapshot.CanonicalProperties, "SystemTitle")
}

// 제어 실험: 현재 마운트에 적용되는 repository 바인딩은 system보다 우선한다.
func TestUnifiedListPrefersCurrentRepositoryBindingOverSystem(t *testing.T) {
	registry, bindings, sourceInstanceID := fakeExternalFixture(t, multiSourceNativeProperties(t))
	service := mustUnifiedServiceWithCatalog(t, registry, bindings,
		catalogWithTitleBindings(sourceInstanceID, []titleBindingSpec{systemTitleBinding, currentRepositoryTitleBinding}))
	path := "/external"

	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
	})
	if err != nil {
		t.Fatalf("UnifiedList() error = %v", err)
	}
	if len(result.Entries) != 1 {
		t.Fatalf("entries = %#v, want exactly one entry", result.Entries)
	}
	assertCanonicalTitleText(t, result.Entries[0].EntrySnapshot.CanonicalProperties, "DisplayTitle")
}
