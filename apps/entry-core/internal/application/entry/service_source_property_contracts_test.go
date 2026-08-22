package entry

import (
	"context"
	"errors"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// ambiguousTitleCatalog는 같은 PropertyID·소스 인스턴스에 실행 가능한 바인딩 둘을
// 만들어 동순위 모호 상황을 재현한다. 두 바인딩은 ExternalPropertyID만 다르고 나머지
// 실행 조건(read 방향, 승인, 활성, 읽기 가능 디스크립터)은 동일하다.
func ambiguousTitleCatalog(t *testing.T, sourceInstanceID string) domainentry.PropertyCatalogSnapshot {
	t.Helper()
	catalog := boundTitleCatalogFixture(sourceInstanceID)
	alt := domainentry.SourcePropertyRef{
		ProviderID: "macos.fakeexternal", SourceInstanceID: sourceInstanceID,
		ScopeKind: domainentry.SourceScopeKindWorkspace, ScopeExternalID: "workspace",
		ExternalPropertyID: "kMDItemTitleAlt",
	}
	catalog.Descriptors = append(catalog.Descriptors, domainentry.SourcePropertyDescriptor{
		Ref: alt, NativeKey: "title", NativeType: "string", NativeCardinality: domainentry.PropertyCardinalityOne,
		Authority: domainentry.AuthorityKindProvider, SourceReadable: true,
		Lifecycle: domainentry.PropertyLifecycleActive,
	})
	catalog.Bindings = append(catalog.Bindings, domainentry.PropertyBinding{
		PropertyID: catalogTitleID, SourceRef: alt, ReadTransform: "identity", Direction: "read",
		EffectiveReadable: true, ApprovalState: "approved", Lifecycle: domainentry.PropertyLifecycleActive,
	})
	return catalog
}

func reverseTitleCatalogPairs(catalog domainentry.PropertyCatalogSnapshot) domainentry.PropertyCatalogSnapshot {
	lastDescriptor, firstDescriptor := catalog.Descriptors[len(catalog.Descriptors)-1], catalog.Descriptors[0]
	catalog.Descriptors[0], catalog.Descriptors[len(catalog.Descriptors)-1] = lastDescriptor, firstDescriptor
	lastBinding, firstBinding := catalog.Bindings[len(catalog.Bindings)-1], catalog.Bindings[0]
	catalog.Bindings[0], catalog.Bindings[len(catalog.Bindings)-1] = lastBinding, firstBinding
	return catalog
}

// VOY-764 P1 복구: 같은 canonical property에 실행 가능한 바인딩이 여럿이면 카탈로그
// 순회 순서와 무관하게 실패 닫기한다. reviewed precedence가 런타임 계약에 없으므로
// 동순위 후복 선택은 모호로 처리한다.
func TestUnifiedListFailsClosedOnSamePrecedenceBindingAmbiguity(t *testing.T) {
	for _, tc := range []struct {
		name    string
		reverse bool
	}{
		{name: "seed_order"}, {name: "reversed_catalog_order", reverse: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			registry, bindings := unifiedFixture(t)
			adapter := bindings[0].Adapter.(*recordingResourceAdapter)
			instanceID := bindings[0].SourceRef.SourceInstanceID
			catalog := ambiguousTitleCatalog(t, instanceID)
			if tc.reverse {
				catalog = reverseTitleCatalogPairs(catalog)
			}
			service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1], catalog)
			path := "/external"

			_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
				WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
			})
			if !errors.Is(err, ErrAmbiguousSourceBinding) {
				t.Fatalf("UnifiedList() error = %v, want %v", err, ErrAmbiguousSourceBinding)
			}
			if adapter.listCalls != 0 || adapter.resolveCalls != 0 {
				t.Fatalf("adapter calls list=%d resolve=%d, want zero", adapter.listCalls, adapter.resolveCalls)
			}
		})
	}
}

func TestResolveEntryFailsClosedOnSamePrecedenceBindingAmbiguity(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
		ambiguousTitleCatalog(t, bindings[0].SourceRef.SourceInstanceID))
	path := "/external/item"

	_, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{"common.title"},
	})
	if !errors.Is(err, ErrAmbiguousSourceBinding) {
		t.Fatalf("ResolveEntry() error = %v, want %v", err, ErrAmbiguousSourceBinding)
	}
	if adapter.resolveCalls != 0 || adapter.listCalls != 0 {
		t.Fatalf("adapter calls resolve=%d list=%d, want zero", adapter.resolveCalls, adapter.listCalls)
	}
}

func TestUnifiedListParentRefFailsClosedOnSamePrecedenceBindingAmbiguity(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "opaque-parent", "folder")
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
		ambiguousTitleCatalog(t, bindings[0].SourceRef.SourceInstanceID))

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{"common.title"},
	})
	if !errors.Is(err, ErrAmbiguousSourceBinding) {
		t.Fatalf("UnifiedList() error = %v, want %v", err, ErrAmbiguousSourceBinding)
	}
	if adapter.resolveCalls != 0 || adapter.listCalls != 0 {
		t.Fatalf("adapter calls resolve=%d list=%d, want zero", adapter.resolveCalls, adapter.listCalls)
	}
}

// nonExecutableTitleCatalog는 단일 바인딩 픽스처에 변이를 적용해 실행 불가능한
// 바인딩 상태를 만든다.
func nonExecutableTitleCatalog(sourceInstanceID string, mutate func(binding *domainentry.PropertyBinding, descriptor *domainentry.SourcePropertyDescriptor)) domainentry.PropertyCatalogSnapshot {
	catalog := boundTitleCatalogFixture(sourceInstanceID)
	mutate(&catalog.Bindings[len(catalog.Bindings)-1], &catalog.Descriptors[len(catalog.Descriptors)-1])
	return catalog
}

func TestSourcePropertyContractsRejectNonExecutableBindings(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func(binding *domainentry.PropertyBinding, descriptor *domainentry.SourcePropertyDescriptor)
	}{
		{"unapproved_binding", func(b *domainentry.PropertyBinding, _ *domainentry.SourcePropertyDescriptor) {
			b.ApprovalState = "pending"
		}},
		{"unreadable_binding", func(b *domainentry.PropertyBinding, _ *domainentry.SourcePropertyDescriptor) {
			b.EffectiveReadable = false
		}},
		{"tombstoned_binding", func(b *domainentry.PropertyBinding, _ *domainentry.SourcePropertyDescriptor) {
			b.Lifecycle = domainentry.PropertyLifecycleTombstoned
		}},
		{"write_direction", func(b *domainentry.PropertyBinding, _ *domainentry.SourcePropertyDescriptor) { b.Direction = "write" }},
		{"unreadable_descriptor", func(_ *domainentry.PropertyBinding, d *domainentry.SourcePropertyDescriptor) {
			d.SourceReadable = false
		}},
		{"tombstoned_descriptor", func(_ *domainentry.PropertyBinding, d *domainentry.SourcePropertyDescriptor) {
			d.Lifecycle = domainentry.PropertyLifecycleTombstoned
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			registry, bindings := unifiedFixture(t)
			adapter := bindings[0].Adapter.(*recordingResourceAdapter)
			service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
				nonExecutableTitleCatalog(bindings[0].SourceRef.SourceInstanceID, tc.mutate))
			path := "/external"

			_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
				WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
			})
			if !errors.Is(err, ErrNoExecutableSourceBinding) {
				t.Fatalf("UnifiedList() error = %v, want %v", err, ErrNoExecutableSourceBinding)
			}
			if adapter.listCalls != 0 || adapter.resolveCalls != 0 {
				t.Fatalf("adapter calls list=%d resolve=%d, want zero", adapter.listCalls, adapter.resolveCalls)
			}
		})
	}
}

func TestSourcePropertyContractsAcceptsBidirectionalReadDirection(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
		nonExecutableTitleCatalog(bindings[0].SourceRef.SourceInstanceID,
			func(b *domainentry.PropertyBinding, _ *domainentry.SourcePropertyDescriptor) {
				b.Direction = "bidirectional"
			}))
	path := "/external"

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
	})
	if errors.Is(err, ErrNoExecutableSourceBinding) {
		t.Fatalf("UnifiedList() error = %v, bidirectional read direction must stay executable", err)
	}
	if adapter.listCalls == 0 {
		t.Fatalf("adapter list calls = 0, want the request to reach the adapter")
	}
}

// VOY-764 P1 복구: 같은 canonical property가 서로 다른 소스 인스턴스에 바인딩되어
// 있으면 현재 요청 인스턴스의 바인딩만 적용 후보다. 카탈로그 순서를 뒤집어도 선택이
// 동일해야 한다.
func TestSourcePropertyContractsSelectCurrentInstanceAmongMultipleBindings(t *testing.T) {
	foreignIdentity := mustSourceIdentity(t, localSourceID, domainentry.IdentityStrengthLocator)
	for _, tc := range []struct {
		name    string
		reverse bool
	}{
		{name: "seed_order"}, {name: "reversed_catalog_order", reverse: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			registry, bindings, sourceInstanceID := fakeExternalFixture(t, []domainentry.Property{nativeTitleProperty(t)})
			catalog := boundTitleCatalogFixture(sourceInstanceID)
			foreign := domainentry.SourcePropertyRef{
				ProviderID: "macos.fakeexternal", SourceInstanceID: foreignIdentity.SourceID,
				ScopeKind: domainentry.SourceScopeKindWorkspace, ScopeExternalID: "workspace",
				ExternalPropertyID: "kMDItemTitle",
			}
			catalog.Descriptors = append(catalog.Descriptors, domainentry.SourcePropertyDescriptor{
				Ref: foreign, NativeKey: "foreign-title", NativeType: "string", NativeCardinality: domainentry.PropertyCardinalityOne,
				Authority: domainentry.AuthorityKindProvider, SourceReadable: true,
				Lifecycle: domainentry.PropertyLifecycleActive,
			})
			catalog.Bindings = append(catalog.Bindings, domainentry.PropertyBinding{
				PropertyID: catalogTitleID, SourceRef: foreign, ReadTransform: "identity", Direction: "read",
				EffectiveReadable: true, ApprovalState: "approved", Lifecycle: domainentry.PropertyLifecycleActive,
			})
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
			if len(result.Entries) != 1 || len(result.Entries[0].EntrySnapshot.CanonicalProperties) != 1 ||
				result.Entries[0].EntrySnapshot.CanonicalProperties[0].Payload.Text == nil ||
				*result.Entries[0].EntrySnapshot.CanonicalProperties[0].Payload.Text != "Roadmap" {
				t.Fatalf("entries = %#v, want current-instance native title value", result.Entries)
			}
		})
	}
}

// bindingWithoutDescriptorCatalog는 활성 바인딩만 남기고 디스크립터를 카탈로그에서
// 제외한다. 바인딩은 적용 가능하지만 실행 조건 검증에 필요한 디스크립터가 없다.
func bindingWithoutDescriptorCatalog(sourceInstanceID string) domainentry.PropertyCatalogSnapshot {
	catalog := boundTitleCatalogFixture(sourceInstanceID)
	catalog.Descriptors = nil
	return catalog
}

// VOY-764 P1 복구(review v4 결함 2): 디스크립터가 없는 적용 가능 바인딩을 후보 보존
// 전에 버리면 unbound raw-key fallback으로 잘못 통과한다. 적용 가능 바인딩을 먼저
// 보존하고 디스크립터 부재를 실행 불가능으로 판정해 List·Resolve·ParentRef 세 경로가
// 모두 어댑터 호출 전에 같은 실패 닫기 오류를 내야 한다.
func TestUnifiedListFailsClosedWhenApplicableBindingLacksDescriptor(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
		bindingWithoutDescriptorCatalog(bindings[0].SourceRef.SourceInstanceID))
	path := "/external"

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
	})
	if !errors.Is(err, ErrNoExecutableSourceBinding) {
		t.Fatalf("UnifiedList() error = %v, want %v", err, ErrNoExecutableSourceBinding)
	}
	if adapter.listCalls != 0 || adapter.resolveCalls != 0 {
		t.Fatalf("adapter calls list=%d resolve=%d, want zero", adapter.listCalls, adapter.resolveCalls)
	}
}

func TestResolveEntryFailsClosedWhenApplicableBindingLacksDescriptor(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
		bindingWithoutDescriptorCatalog(bindings[0].SourceRef.SourceInstanceID))
	path := "/external/item"

	_, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{"common.title"},
	})
	if !errors.Is(err, ErrNoExecutableSourceBinding) {
		t.Fatalf("ResolveEntry() error = %v, want %v", err, ErrNoExecutableSourceBinding)
	}
	if adapter.resolveCalls != 0 || adapter.listCalls != 0 {
		t.Fatalf("adapter calls resolve=%d list=%d, want zero", adapter.resolveCalls, adapter.listCalls)
	}
}

func TestUnifiedListParentRefFailsClosedWhenApplicableBindingLacksDescriptor(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "opaque-parent", "folder")
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
		bindingWithoutDescriptorCatalog(bindings[0].SourceRef.SourceInstanceID))

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{"common.title"},
	})
	if !errors.Is(err, ErrNoExecutableSourceBinding) {
		t.Fatalf("UnifiedList() error = %v, want %v", err, ErrNoExecutableSourceBinding)
	}
	if adapter.resolveCalls != 0 || adapter.listCalls != 0 {
		t.Fatalf("adapter calls resolve=%d list=%d, want zero", adapter.resolveCalls, adapter.listCalls)
	}
}

// VOY-764 P1 복구(review v4 결함 2): 지원하지 않는 read transform은 실행 가능 후보가
// 아니다. 실행 가능으로 취급하면 어댑터 변환 단계에서 늦게 실패해 경로마다 다른 오류
// 계약을 만든다.
func TestUnifiedListRejectsUnsupportedReadTransform(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
		nonExecutableTitleCatalog(bindings[0].SourceRef.SourceInstanceID,
			func(b *domainentry.PropertyBinding, _ *domainentry.SourcePropertyDescriptor) {
				b.ReadTransform = "reverse_string"
			}))
	path := "/external"

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1, RequestedProperties: []string{"common.title"},
	})
	if !errors.Is(err, ErrNoExecutableSourceBinding) {
		t.Fatalf("UnifiedList() error = %v, want %v", err, ErrNoExecutableSourceBinding)
	}
	if adapter.listCalls != 0 || adapter.resolveCalls != 0 {
		t.Fatalf("adapter calls list=%d resolve=%d, want zero", adapter.listCalls, adapter.resolveCalls)
	}
}

func TestResolveEntryRejectsUnsupportedReadTransform(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
		nonExecutableTitleCatalog(bindings[0].SourceRef.SourceInstanceID,
			func(b *domainentry.PropertyBinding, _ *domainentry.SourcePropertyDescriptor) {
				b.ReadTransform = "reverse_string"
			}))
	path := "/external/item"

	_, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: "workspace", VirtualPath: &path, RequestedProperties: []string{"common.title"},
	})
	if !errors.Is(err, ErrNoExecutableSourceBinding) {
		t.Fatalf("ResolveEntry() error = %v, want %v", err, ErrNoExecutableSourceBinding)
	}
	if adapter.resolveCalls != 0 || adapter.listCalls != 0 {
		t.Fatalf("adapter calls resolve=%d list=%d, want zero", adapter.resolveCalls, adapter.listCalls)
	}
}

func TestUnifiedListParentRefRejectsUnsupportedReadTransform(t *testing.T) {
	registry, bindings := unifiedFixture(t)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	parent := adapterEntryFixture(t, bindings[0].SourceRef, "opaque-parent", "folder")
	service := mustUnifiedServiceWithCatalog(t, registry, bindings[:1],
		nonExecutableTitleCatalog(bindings[0].SourceRef.SourceInstanceID,
			func(b *domainentry.PropertyBinding, _ *domainentry.SourcePropertyDescriptor) {
				b.ReadTransform = "reverse_string"
			}))

	_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: "workspace", ParentRef: &parent.EntryRef, PageSize: 1, RequestedProperties: []string{"common.title"},
	})
	if !errors.Is(err, ErrNoExecutableSourceBinding) {
		t.Fatalf("UnifiedList() error = %v, want %v", err, ErrNoExecutableSourceBinding)
	}
	if adapter.resolveCalls != 0 || adapter.listCalls != 0 {
		t.Fatalf("adapter calls resolve=%d list=%d, want zero", adapter.resolveCalls, adapter.listCalls)
	}
}
