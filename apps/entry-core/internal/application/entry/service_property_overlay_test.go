package entry

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/mount"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

// overlay 테스트 공용 상수. overlayWorkspace는 유효한 UUIDv7 텍스트여야
// ParseWorkspaceID를 통과한다.
const (
	overlayWorkspace = "0198c0de-f00d-7000-8000-3b9ac9e12345"
	overlayTitleKey  = "common.title"
	overlayNoteName  = "note"
)

var (
	overlayTitleID = domainentry.MustPropertyID("5f495fc5-a187-5e64-80ec-a9757f21d64d")
	overlayNoteID  = domainentry.MustPropertyID("0198c0de-f00d-7000-8000-3b9ac9e12345")
)

// spyPropertyOverlayLoader는 LoadOverlay 호출 수와 인자를 기록하는 query-count
// spy다. N+1 없이 배치당 정확히 한 번 호출되는지 증명한다.
type spyPropertyOverlayLoader struct {
	calls        int
	workspaces   []domainentry.WorkspaceContext
	entryIDSets  [][]string
	propertySets [][]domainentry.PropertyID
	rows         map[string][]domainentry.PropertyValue
	err          error
}

func (loader *spyPropertyOverlayLoader) LoadOverlay(_ context.Context, workspace domainentry.WorkspaceContext, entryIDs []string, propertyIDs []domainentry.PropertyID) (map[string][]domainentry.PropertyValue, error) {
	loader.calls++
	loader.workspaces = append(loader.workspaces, workspace)
	loader.entryIDSets = append(loader.entryIDSets, entryIDs)
	loader.propertySets = append(loader.propertySets, propertyIDs)
	if loader.err != nil {
		return nil, loader.err
	}
	return loader.rows, nil
}

func overlayCatalogFixture() domainentry.PropertyCatalogSnapshot {
	return domainentry.PropertyCatalogSnapshot{
		Definitions: []domainentry.WorkspacePropertyDefinition{
			{
				PropertyID: overlayTitleID, Origin: domainentry.PropertyOriginBuiltIn,
				IdentityScheme: domainentry.PropertyIdentitySchemeRegistryDerived,
				Namespace:      "system", CanonicalKey: overlayTitleKey, DisplayName: "Title",
				ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
				Provenance: domainentry.PropertyProvenanceSystem, Lifecycle: domainentry.PropertyLifecycleActive,
			},
			{
				PropertyID: overlayNoteID, Origin: domainentry.PropertyOriginBuiltIn,
				IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
				Namespace:      "system", CanonicalKey: "local.note", DisplayName: "Note",
				ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
				Editable: true, Provenance: domainentry.PropertyProvenanceSystem, Lifecycle: domainentry.PropertyLifecycleActive,
			},
		},
		Terms: []domainentry.WorkspacePropertyTerm{{PropertyID: overlayNoteID, TermKind: "legacy_alias", Ordinal: 0, TermValue: overlayNoteName}},
	}
}

func overlayFixture(t *testing.T, loader PropertyOverlayLoader) (*mount.Registry, []ResourceAdapterBinding, *UnifiedService, map[string]domainentry.PropertyDefinition) {
	t.Helper()
	available, _ := domainentry.NewAvailability(domainentry.AvailabilityStateAvailable)
	identity := mustSourceIdentity(t, externalSourceID, domainentry.IdentityStrengthStable)
	sourceRef, _ := domainentry.NewSourceRef(identity.SourceID, "fakeexternal", "external", available, domainentry.IdentityStrengthStable)
	path, _ := domainentry.NewResolvedVirtualPath("external", "/external", "seed")
	mountRef, _ := domainentry.NewMountRef("external", overlayWorkspace, sourceRef.SourceInstanceID, path, available, domainentry.CachePolicyNone)
	registry := mount.NewMountRegistry()
	if err := registry.Register(mountRef); err != nil {
		t.Fatal(err)
	}
	bindings := []ResourceAdapterBinding{{SourceRef: sourceRef, Adapter: &recordingResourceAdapter{}}}
	var service *UnifiedService
	var err error
	if loader == nil {
		service, err = NewUnifiedServiceWithCatalog(registry, bindings, overlayCatalogFixture(), []byte("01234567890123456789012345678901"), func() time.Time { return time.Unix(10, 0).UTC() })
	} else {
		service, err = NewUnifiedServiceWithCatalog(registry, bindings, overlayCatalogFixture(), []byte("01234567890123456789012345678901"), func() time.Time { return time.Unix(10, 0).UTC() }, WithPropertyOverlayLoader(loader))
	}
	if err != nil {
		t.Fatal(err)
	}
	definitions, err := service.propertyDefinitions(context.Background(), []string{overlayTitleKey, overlayNoteName})
	if err != nil {
		t.Fatal(err)
	}
	return registry, bindings, service, definitions
}

func overlayPropertyValueFixture(t *testing.T, definition domainentry.PropertyDefinition, entryID string, payload string) domainentry.PropertyValue {
	t.Helper()
	revision, _ := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := domainentry.NewSourceRevision(revision)
	value, err := domainentry.NewPropertyValue(definition, entryID, domainentry.PropertyStateValue, domainentry.PropertyProvenanceUserDefined, time.Unix(1, 0).UTC(), sourceRevision, definition.Editable, domainentry.TextPayload(payload))
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func adapterEntryFixtureWithProperties(t *testing.T, sourceRef domainentry.SourceRef, key, relative string, properties []domainentry.PropertyValue) source.AdapterEntry {
	t.Helper()
	// canonical 스냅샷 계약은 nil property 슬라이스를 거절하므로 빈 슬라이스로 정규화한다.
	if properties == nil {
		properties = []domainentry.PropertyValue{}
	}
	ref, err := domainentry.NewEntryRef(domainentry.DeriveEntryID(sourceRef.SourceInstanceID, "document", key), sourceRef.SourceInstanceID, key, "document", locatorFixture(t), sourceRef.IdentityStrength)
	if err != nil {
		t.Fatal(err)
	}
	revision, _ := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := domainentry.NewSourceRevision(revision)
	observedRevision, _ := domainentry.NewObservedRevision(1)
	observed := time.Unix(1, 0).UTC()
	freshness, _ := domainentry.NewFreshness(domainentry.FreshnessStateCurrent, observed, sourceRevision, nil, nil)
	available, _ := domainentry.NewAvailability(domainentry.AvailabilityStateAvailable)
	snapshot, err := domainentry.NewCanonicalEntrySnapshot(ref, key, nil, properties, sourceRevision, observedRevision, observed, nil, available, freshness)
	if err != nil {
		t.Fatal(err)
	}
	return source.AdapterEntry{RelativePath: relative, EntryRef: ref, EntrySnapshot: snapshot, Capabilities: domainentry.Capabilities{Readable: true}}
}

func overlayListResultFixture(t *testing.T, sourceRef domainentry.SourceRef, count int, properties func(index int, entryID string) []domainentry.PropertyValue) source.AdapterListResult {
	t.Helper()
	items := make([]source.AdapterEntry, 0, count)
	for index := 0; index < count; index++ {
		key := fmt.Sprintf("item-%02d", index)
		base := adapterEntryFixtureWithProperties(t, sourceRef, key, key, nil)
		var entryProperties []domainentry.PropertyValue
		if properties != nil {
			entryProperties = properties(index, base.EntryRef.EntryID)
		}
		items = append(items, adapterEntryFixtureWithProperties(t, sourceRef, key, key, entryProperties))
	}
	revision, _ := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	freshness := items[0].EntrySnapshot.Freshness
	available := items[0].EntrySnapshot.Availability
	return source.AdapterListResult{Items: items, SourceRevision: revision, Availability: available, Freshness: freshness, Warnings: []source.Warning{}}
}

// TestPropertyOverlayMergePreservesSourceFacts는 소스 소유 canonical 값 뒤에 로컬
// overlay 값이 결정적 순서로 합쳐지고 어떤 소스 소유 필드도 덮쓰지 않음을 증명한다.
func TestPropertyOverlayMergePreservesSourceFacts(t *testing.T) {
	loader := &spyPropertyOverlayLoader{}
	_, bindings, service, definitions := overlayFixture(t, loader)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	listResult := overlayListResultFixture(t, bindings[0].SourceRef, 2, func(_ int, entryID string) []domainentry.PropertyValue {
		return []domainentry.PropertyValue{overlayPropertyValueFixture(t, definitions[overlayTitleKey], entryID, "source-title")}
	})
	adapter.listResults = []source.AdapterListResult{listResult}
	// spy는 기록 전용이므로 병합 대상 overlay 행을 테스트가 직접 채운다.
	loader.rows = make(map[string][]domainentry.PropertyValue, len(listResult.Items))
	for _, item := range listResult.Items {
		loader.rows[item.EntryRef.EntryID] = []domainentry.PropertyValue{
			overlayPropertyValueFixture(t, definitions[overlayNoteName], item.EntryRef.EntryID, "local-note"),
		}
	}
	path := "/"
	result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
		WorkspaceID: overlayWorkspace, VirtualPath: &path, PageSize: 2,
		RequestedProperties: []string{overlayTitleKey, overlayNoteName},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Entries) != 2 {
		t.Fatalf("entries = %d", len(result.Entries))
	}
	for index, entry := range result.Entries {
		properties := entry.EntrySnapshot.CanonicalProperties
		if len(properties) != 2 {
			t.Fatalf("entry %d properties = %d, want 2", index, len(properties))
		}
		// 병합 후에도 PropertyID 오름차순이 유지되어야 한다.
		if properties[0].PropertyID != overlayNoteID || properties[1].PropertyID != overlayTitleID {
			t.Fatalf("entry %d order = %s,%s", index, properties[0].PropertyID, properties[1].PropertyID)
		}
		// 소스 소유 사실은 그대로 보존된다.
		title := properties[1]
		if title.State != domainentry.PropertyStateValue || title.Provenance != domainentry.PropertyProvenanceUserDefined ||
			title.Payload.Text == nil || *title.Payload.Text != "source-title" || title.ObservedAt != time.Unix(1, 0).UTC() {
			t.Fatalf("entry %d source fact corrupted: %#v", index, title)
		}
		note := properties[0]
		if note.PropertyID != overlayNoteID || note.Payload.Text == nil || *note.Payload.Text != "local-note" {
			t.Fatalf("entry %d overlay value missing: %#v", index, note)
		}
		// 소스 소유 메타데이터는 병합 전후 동일하다.
		if entry.EntrySnapshot.DisplayName != fmt.Sprintf("item-%02d", index) || entry.EntrySnapshot.Availability.State != domainentry.AvailabilityStateAvailable {
			t.Fatalf("entry %d metadata corrupted: %#v", index, entry.EntrySnapshot)
		}
	}
}

// TestPropertyOverlayResolveEntryMerge는 resolve 경로에서도 같은 batched 병합이
// 적용됨을 증명한다.
func TestPropertyOverlayResolveEntryMerge(t *testing.T) {
	loader := &spyPropertyOverlayLoader{}
	_, bindings, service, definitions := overlayFixture(t, loader)
	adapter := bindings[0].Adapter.(*recordingResourceAdapter)
	item := adapterEntryFixtureWithProperties(t, bindings[0].SourceRef, "stable-object", "item", nil)
	item = adapterEntryFixtureWithProperties(t, bindings[0].SourceRef, "stable-object", "item", []domainentry.PropertyValue{
		overlayPropertyValueFixture(t, definitions[overlayTitleKey], item.EntryRef.EntryID, "source-title"),
	})
	adapter.resolveResult = adapterResolveResultFixture(t, item)
	loader.rows = map[string][]domainentry.PropertyValue{
		item.EntryRef.EntryID: {overlayPropertyValueFixture(t, definitions[overlayNoteName], item.EntryRef.EntryID, "local-note")},
	}
	path := "/external/item"
	result, err := service.ResolveEntry(context.Background(), ResolveRequest{
		WorkspaceID: overlayWorkspace, VirtualPath: &path,
		RequestedProperties: []string{overlayTitleKey, overlayNoteName},
	})
	if err != nil {
		t.Fatal(err)
	}
	properties := result.EntrySnapshot.CanonicalProperties
	if len(properties) != 2 || properties[0].PropertyID != overlayNoteID || properties[1].PropertyID != overlayTitleID {
		t.Fatalf("resolved properties = %#v", properties)
	}
	if *properties[0].Payload.Text != "local-note" || *properties[1].Payload.Text != "source-title" {
		t.Fatalf("resolved values = %#v", properties)
	}
	if loader.calls != 1 {
		t.Fatalf("resolve loader calls = %d, want 1", loader.calls)
	}
}

// TestPropertyOverlaySingleBatchedCallScales는 Entry 수가 늘어나도 loader 호출이
// 정확히 한 번임을 spy로 증명한다(N+1 부재).
func TestPropertyOverlaySingleBatchedCallScales(t *testing.T) {
	for _, count := range []int{1, 50} {
		t.Run(fmt.Sprintf("entries_%d", count), func(t *testing.T) {
			loader := &spyPropertyOverlayLoader{}
			_, bindings, service, _ := overlayFixture(t, loader)
			adapter := bindings[0].Adapter.(*recordingResourceAdapter)
			adapter.listResults = []source.AdapterListResult{overlayListResultFixture(t, bindings[0].SourceRef, count, nil)}
			path := "/"
			result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
				WorkspaceID: overlayWorkspace, VirtualPath: &path, PageSize: 64,
				RequestedProperties: []string{overlayTitleKey, overlayNoteName},
			})
			if err != nil {
				t.Fatal(err)
			}
			if len(result.Entries) != count {
				t.Fatalf("entries = %d, want %d", len(result.Entries), count)
			}
			if loader.calls != 1 {
				t.Fatalf("loader calls = %d, want exactly 1 for %d entries", loader.calls, count)
			}
			if len(loader.entryIDSets[0]) != count {
				t.Fatalf("batched entry ids = %d, want %d", len(loader.entryIDSets[0]), count)
			}
			if loader.workspaces[0].ID.String() != overlayWorkspace {
				t.Fatalf("workspace = %s, want %s", loader.workspaces[0].ID.String(), overlayWorkspace)
			}
			if len(loader.propertySets[0]) != 2 {
				t.Fatalf("property ids = %#v, want 2 resolved ids", loader.propertySets[0])
			}
			// 결과 순서대로 EntryID가 수집되었는지 확인한다.
			for index, entryID := range loader.entryIDSets[0] {
				if entryID != result.Entries[index].EntryRef.EntryID {
					t.Fatalf("entry id %d = %s, want %s", index, entryID, result.Entries[index].EntryRef.EntryID)
				}
			}
		})
	}
}

// TestPropertyOverlayNoopPreservesExistingBehavior는 loader 미주입, 빈 요청,
// 비(非)UUIDv7 워크스페이스가 모두 no-op임을 증명한다.
func TestPropertyOverlayNoopPreservesExistingBehavior(t *testing.T) {
	t.Run("no_loader_configured", func(t *testing.T) {
		_, bindings, service, _ := overlayFixture(t, nil)
		adapter := bindings[0].Adapter.(*recordingResourceAdapter)
		adapter.listResults = []source.AdapterListResult{overlayListResultFixture(t, bindings[0].SourceRef, 1, nil)}
		path := "/"
		result, err := service.UnifiedList(context.Background(), UnifiedListRequest{
			WorkspaceID: overlayWorkspace, VirtualPath: &path, PageSize: 1,
			RequestedProperties: []string{overlayTitleKey, overlayNoteName},
		})
		if err != nil {
			t.Fatal(err)
		}
		if len(result.Entries[0].EntrySnapshot.CanonicalProperties) != 0 {
			t.Fatalf("properties = %#v, want untouched empty", result.Entries[0].EntrySnapshot.CanonicalProperties)
		}
	})
	t.Run("empty_request", func(t *testing.T) {
		loader := &spyPropertyOverlayLoader{}
		_, bindings, service, _ := overlayFixture(t, loader)
		adapter := bindings[0].Adapter.(*recordingResourceAdapter)
		adapter.listResults = []source.AdapterListResult{overlayListResultFixture(t, bindings[0].SourceRef, 1, nil)}
		path := "/"
		if _, err := service.UnifiedList(context.Background(), UnifiedListRequest{
			WorkspaceID: overlayWorkspace, VirtualPath: &path, PageSize: 1, RequestedProperties: []string{},
		}); err != nil {
			t.Fatal(err)
		}
		if loader.calls != 0 {
			t.Fatalf("loader calls = %d, want 0", loader.calls)
		}
	})
	t.Run("non_uuid_workspace", func(t *testing.T) {
		loader := &spyPropertyOverlayLoader{}
		registry, bindings, service, _ := overlayFixture(t, loader)
		// 요청 워크스페이스 텍스트에 귀속된 마운트가 있어야 list 자체가 성공하고,
		// overlay가 no-op으로 건너뛰어지는지를 분리해 관찰할 수 있다.
		available, _ := domainentry.NewAvailability(domainentry.AvailabilityStateAvailable)
		mountPath, _ := domainentry.NewResolvedVirtualPath("external-plain", "/external-plain", "seed")
		mountRef, err := domainentry.NewMountRef("external-plain", "workspace", bindings[0].SourceRef.SourceInstanceID, mountPath, available, domainentry.CachePolicyNone)
		if err != nil {
			t.Fatal(err)
		}
		if err := registry.Register(mountRef); err != nil {
			t.Fatal(err)
		}
		adapter := bindings[0].Adapter.(*recordingResourceAdapter)
		adapter.listResults = []source.AdapterListResult{overlayListResultFixture(t, bindings[0].SourceRef, 1, nil)}
		path := "/"
		if _, err := service.UnifiedList(context.Background(), UnifiedListRequest{
			WorkspaceID: "workspace", VirtualPath: &path, PageSize: 1,
			RequestedProperties: []string{overlayTitleKey, overlayNoteName},
		}); err != nil {
			t.Fatal(err)
		}
		if loader.calls != 0 {
			t.Fatalf("loader calls = %d, want 0", loader.calls)
		}
	})
	t.Run("duplicate_loader_injection_rejected", func(t *testing.T) {
		_, bindings, _, _ := overlayFixture(t, nil)
		_, err := NewUnifiedServiceWithCatalog(mount.NewMountRegistry(), bindings, overlayCatalogFixture(), []byte("01234567890123456789012345678901"), func() time.Time { return time.Unix(10, 0).UTC() },
			WithPropertyOverlayLoader(&spyPropertyOverlayLoader{}), WithPropertyOverlayLoader(&spyPropertyOverlayLoader{}))
		if !errors.Is(err, ErrInvalidService) {
			t.Fatalf("duplicate injection error = %v", err)
		}
	})
}

// TestPropertyOverlayFailsClosed는 loader 오류와 중복·불일치·충돌 행이 요청 전체를
// 실패 닫기함을 증명한다. 소스 필드는 부분 노출되지 않는다.
func TestPropertyOverlayFailsClosed(t *testing.T) {
	tests := map[string]struct {
		rows   func(entryIDs []string, definitions map[string]domainentry.PropertyDefinition) map[string][]domainentry.PropertyValue
		loader func(entryIDs []string) (map[string][]domainentry.PropertyValue, error)
	}{
		"loader_error": {
			loader: func([]string) (map[string][]domainentry.PropertyValue, error) {
				return nil, errors.New("db down")
			},
		},
		"duplicate_row": {
			rows: func(entryIDs []string, definitions map[string]domainentry.PropertyDefinition) map[string][]domainentry.PropertyValue {
				first := overlayPropertyValueFixture(t, definitions[overlayNoteName], entryIDs[0], "one")
				second := overlayPropertyValueFixture(t, definitions[overlayNoteName], entryIDs[0], "two")
				return map[string][]domainentry.PropertyValue{entryIDs[0]: {first, second}}
			},
		},
		"mismatched_entry_id": {
			rows: func(entryIDs []string, definitions map[string]domainentry.PropertyDefinition) map[string][]domainentry.PropertyValue {
				row := overlayPropertyValueFixture(t, definitions[overlayNoteName], entryIDs[0], "note")
				row.EntryID = "entry-other"
				return map[string][]domainentry.PropertyValue{entryIDs[0]: {row}}
			},
		},
		"unrequested_property": {
			rows: func(entryIDs []string, definitions map[string]domainentry.PropertyDefinition) map[string][]domainentry.PropertyValue {
				row := overlayPropertyValueFixture(t, definitions[overlayTitleKey], entryIDs[0], "title")
				return map[string][]domainentry.PropertyValue{entryIDs[0]: {row}}
			},
		},
		"foreign_entry_key": {
			rows: func(entryIDs []string, definitions map[string]domainentry.PropertyDefinition) map[string][]domainentry.PropertyValue {
				row := overlayPropertyValueFixture(t, definitions[overlayNoteName], entryIDs[0], "note")
				row.EntryID = "entry-foreign"
				return map[string][]domainentry.PropertyValue{"entry-foreign": {row}}
			},
		},
	}
	for name, test := range tests {
		test := test
		t.Run(name, func(t *testing.T) {
			loader := &spyPropertyOverlayLoader{}
			requestOnlyNote := name == "unrequested_property"
			requested := []string{overlayTitleKey, overlayNoteName}
			_, bindings, service, definitions := overlayFixture(t, loader)
			if requestOnlyNote {
				requested = []string{overlayNoteName}
			}
			adapter := bindings[0].Adapter.(*recordingResourceAdapter)
			listResult := overlayListResultFixture(t, bindings[0].SourceRef, 1, nil)
			adapter.listResults = []source.AdapterListResult{listResult}
			if test.loader != nil {
				loader.rows, loader.err = test.loader(nil)
			} else {
				loader.rows = test.rows([]string{listResult.Items[0].EntryRef.EntryID}, definitions)
			}
			path := "/"
			_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
				WorkspaceID: overlayWorkspace, VirtualPath: &path, PageSize: 1, RequestedProperties: requested,
			})
			if !errors.Is(err, ErrPropertyOverlayFailed) || err.Error() != "property_overlay_failed" {
				t.Fatalf("%s error = %v, want property_overlay_failed", name, err)
			}
		})
	}
	t.Run("conflicting_source_owned_property", func(t *testing.T) {
		loader := &spyPropertyOverlayLoader{}
		_, bindings, service, definitions := overlayFixture(t, loader)
		adapter := bindings[0].Adapter.(*recordingResourceAdapter)
		listResult := overlayListResultFixture(t, bindings[0].SourceRef, 1, func(_ int, entryID string) []domainentry.PropertyValue {
			return []domainentry.PropertyValue{overlayPropertyValueFixture(t, definitions[overlayNoteName], entryID, "source-note")}
		})
		adapter.listResults = []source.AdapterListResult{listResult}
		loader.rows = map[string][]domainentry.PropertyValue{
			listResult.Items[0].EntryRef.EntryID: {
				overlayPropertyValueFixture(t, definitions[overlayNoteName], listResult.Items[0].EntryRef.EntryID, "local-note"),
			},
		}
		path := "/"
		_, err := service.UnifiedList(context.Background(), UnifiedListRequest{
			WorkspaceID: overlayWorkspace, VirtualPath: &path, PageSize: 1,
			RequestedProperties: []string{overlayTitleKey, overlayNoteName},
		})
		if !errors.Is(err, ErrPropertyOverlayFailed) {
			t.Fatalf("conflict error = %v, want property_overlay_failed", err)
		}
	})
}

// live 정의 공급자가 주입되면 시작 시점 snapshot에 없는 정의도 requested
// property 검증을 통과하고, 비활성(tombstoned) 정의도 여전히 존재로 인정된다.
// snapshot 고정은 실행 중 생성 정의를 unregistered_property_selector로
// 거절하고 재시작 시 active-only 로더가 read-back을 깨뜨린다.
func TestLiveDefinitionsServeRequestedPropertyResolution(t *testing.T) {
	nextID := overlayNoteID
	nextID[15] ^= 0x01
	tombID := overlayNoteID
	tombID[15] ^= 0x02
	extra := domainentry.WorkspacePropertyDefinition{
		PropertyID: nextID, Origin: domainentry.PropertyOriginUserDefined,
		IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
		Namespace:      "user", CanonicalKey: "user.created", DisplayName: "Created",
		ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
		Editable: true, Provenance: domainentry.PropertyProvenanceUserDefined, Lifecycle: domainentry.PropertyLifecycleActive,
	}
	tombstoned := domainentry.WorkspacePropertyDefinition{
		PropertyID: tombID, Origin: domainentry.PropertyOriginUserDefined,
		IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
		Namespace:      "user", CanonicalKey: "user.removed", DisplayName: "Removed",
		ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne,
		Editable: true, Provenance: domainentry.PropertyProvenanceUserDefined, Lifecycle: domainentry.PropertyLifecycleTombstoned,
	}
	provider := func(_ context.Context) ([]domainentry.WorkspacePropertyDefinition, error) {
		return append(overlayCatalogFixture().Definitions, extra, tombstoned), nil
	}
	_, _, service, _ := overlayFixture(t, nil)
	service.liveDefinitions = provider

	resolved, err := service.propertyDefinitions(context.Background(), []string{"user.created"})
	if err != nil {
		t.Fatalf("created definition rejected: %v", err)
	}
	if _, ok := resolved["user.created"]; !ok {
		t.Fatal("created definition missing from resolution")
	}

	resolved, err = service.propertyDefinitions(context.Background(), []string{"user.removed"})
	if err != nil {
		t.Fatalf("tombstoned definition rejected: %v", err)
	}
	if _, ok := resolved["user.removed"]; !ok {
		t.Fatal("tombstoned definition missing from resolution")
	}

	unknown := overlayNoteID
	unknown[15] ^= 0xff
	if _, err := service.propertyDefinitions(context.Background(), []string{unknown.String()}); err == nil {
		t.Fatal("unknown property id must stay rejected")
	}
}
