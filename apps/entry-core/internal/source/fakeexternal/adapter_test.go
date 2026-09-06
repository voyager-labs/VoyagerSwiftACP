package fakeexternal

import (
	"bytes"
	"context"
	"errors"
	"testing"
	"time"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

const expectedFakeSourceID = "src:FyUzZ1Zsw_sZQ2nxAGCPS8bEZ4yihrW2rGmxm_4a0bE"

func TestFakeExternalDeterministicPagination(t *testing.T) {
	title := mustProperty(t, "title", "Roadmap")
	provider := "provider-revision-7"
	fixtures := []Fixture{
		{Key: "zeta-key", RelativePath: "zeta", Name: "Zeta", ResourceType: "document", ProviderRevision: &provider, Capabilities: entry.Capabilities{ReadProperties: true}},
		{Key: "roadmap-key", RelativePath: "roadmap", Name: "Roadmap", ResourceType: "document", Properties: []entry.Property{title}, Capabilities: entry.Capabilities{ReadProperties: true}},
		{Key: "alpha-key", RelativePath: "alpha", Name: "Alpha", ResourceType: "document", Capabilities: entry.Capabilities{ReadProperties: true}},
	}
	adapter := mustAdapter(t, Config{Namespace: "voyager-fixture", Generation: "generation-1", CursorKey: testCursorKey(), Fixtures: fixtures})
	if adapter.SourceIdentity().SourceID != expectedFakeSourceID || adapter.SourceIdentity().IdentityStrength != entry.IdentityStrengthStable {
		t.Fatalf("SourceIdentity() = %#v", adapter.SourceIdentity())
	}

	fixtures[0].Name = "mutated"
	fixtures[1].Properties[0].Key = "mutated"
	first, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-external", "", nil))
	if err != nil {
		t.Fatal(err)
	}
	if got := relativePaths(first.Items); !equalStrings(got, []string{"alpha", "roadmap"}) || first.NextChildCursor == nil {
		t.Fatalf("first result = %#v", first)
	}
	if first.Items[1].Snapshot.Name != "Roadmap" || first.Items[1].Snapshot.Properties[0].Key != "title" {
		t.Fatalf("adapter aliases fixtures: %#v", first.Items[1])
	}
	for _, item := range first.Items {
		if item.Identity.IdentityStrength != entry.IdentityStrengthStable || item.Identity.SourceID != expectedFakeSourceID {
			t.Fatalf("identity = %#v", item.Identity)
		}
		backendLocator := []byte(adapter.namespace + "\x00" + item.Identity.EntryKey)
		if !source.ValidateSourceLocator(item.Locator, adapter.cursorKey, backendLocator) {
			t.Fatal("fake locator did not validate for its fixture key")
		}
	}

	first.Items[1].Snapshot.Name = "caller-mutated"
	first.Items[1].Snapshot.Properties[0].Key = "caller-mutated"
	repeat, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-external", "", nil))
	if err != nil {
		t.Fatal(err)
	}
	if repeat.Items[1].Snapshot.Name != "Roadmap" || repeat.Items[1].Snapshot.Properties[0].Key != "title" {
		t.Fatalf("result aliases adapter state: %#v", repeat.Items[1])
	}

	second, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-external", "", first.NextChildCursor))
	if err != nil || !equalStrings(relativePaths(second.Items), []string{"zeta"}) || second.NextChildCursor != nil {
		t.Fatalf("second result = %#v, error = %v", second, err)
	}
}

func TestFakeExternalNestedListing(t *testing.T) {
	adapter := mustAdapter(t, Config{
		Namespace:  "nested-fixture",
		Generation: "generation-1",
		CursorKey:  testCursorKey(),
		Fixtures: []Fixture{
			{Key: "folder", RelativePath: "folder", Name: "Folder", ResourceType: "folder", Capabilities: entry.Capabilities{ListChildren: true}},
			{Key: "child", RelativePath: "folder/child", Name: "Child", ResourceType: "document"},
		},
	})
	root, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "", nil))
	if err != nil || !equalStrings(relativePaths(root.Items), []string{"folder"}) {
		t.Fatalf("root = %#v, error = %v", root, err)
	}
	child, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "folder", nil))
	if err != nil || !equalStrings(relativePaths(child.Items), []string{"folder/child"}) {
		t.Fatalf("child = %#v, error = %v", child, err)
	}
}

func TestCursorMountScope(t *testing.T) {
	fixtures := []Fixture{
		{Key: "a", RelativePath: "a", Name: "A", ResourceType: "document"},
		{Key: "b", RelativePath: "b", Name: "B", ResourceType: "document"},
		{Key: "c", RelativePath: "c", Name: "C", ResourceType: "document"},
	}
	key := testCursorKey()
	adapter := mustAdapter(t, Config{Namespace: "scope-one", Generation: "generation-1", CursorKey: key, Fixtures: fixtures})
	first, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-a", "", nil))
	if err != nil || first.NextChildCursor == nil {
		t.Fatalf("first result = %#v, error = %v", first, err)
	}
	assertInvalidCursor(t, adapter, mustRequest(t, adapter.SourceIdentity(), "mount-b", "", first.NextChildCursor))
	assertInvalidCursor(t, adapter, mustRequest(t, adapter.SourceIdentity(), "mount-a", "folder", first.NextChildCursor))

	otherSource := mustAdapter(t, Config{Namespace: "scope-two", Generation: "generation-1", CursorKey: key, Fixtures: fixtures})
	assertInvalidCursor(t, otherSource, mustRequest(t, otherSource.SourceIdentity(), "mount-a", "", first.NextChildCursor))

	nextGeneration := mustAdapter(t, Config{Namespace: "scope-one", Generation: "generation-2", CursorKey: key, Fixtures: fixtures})
	assertInvalidCursor(t, nextGeneration, mustRequest(t, nextGeneration.SourceIdentity(), "mount-a", "", first.NextChildCursor))

	tampered := *first.NextChildCursor
	if tampered[0] == 'A' {
		tampered = "B" + tampered[1:]
	} else {
		tampered = "A" + tampered[1:]
	}
	assertInvalidCursor(t, adapter, mustRequest(t, adapter.SourceIdentity(), "mount-a", "", &tampered))
}

func TestRevisionFallback(t *testing.T) {
	title := mustProperty(t, "title", "Roadmap")
	fixture := Fixture{
		Key:          "fixture-note-1",
		RelativePath: "roadmap",
		Name:         "Roadmap",
		ResourceType: "document",
		Properties:   []entry.Property{title},
	}
	adapter := mustAdapter(t, Config{Namespace: "voyager-fixture", Generation: "generation-1", CursorKey: testCursorKey(), Fixtures: []Fixture{fixture}})
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "", nil))
	if err != nil {
		t.Fatal(err)
	}
	const wantMetadata = "meta:LhhYfU_MqHbrkd7T8Y3yjEsOG3eKCa3ynrsb57-srko"
	revision := result.Items[0].Snapshot.Revision
	if revision.Strength != entry.RevisionStrengthMetadata || revision.Token == nil || *revision.Token != wantMetadata {
		t.Fatalf("metadata revision = %#v", revision)
	}

	provider := "provider-revision"
	fixture.ProviderRevision = &provider
	providerRevision, err := revisionFor("voyager-fixture", fixture)
	if err != nil || providerRevision.Strength != entry.RevisionStrengthProvider || providerRevision.Token == nil || *providerRevision.Token != provider {
		t.Fatalf("provider revision = %#v, error = %v", providerRevision, err)
	}
	unknown, err := revisionForMetadata(nil, nil)
	if err != nil || unknown.Strength != entry.RevisionStrengthUnknown || unknown.Token != nil {
		t.Fatalf("unknown revision = %#v, error = %v", unknown, err)
	}

	timestamp := time.Date(2026, time.August, 2, 12, 34, 56, 123456789, time.UTC)
	size := int64(7)
	allProperties := []entry.Property{
		mustTypedProperty(t, "z_string", func() (entry.PropertyValue, error) { return entry.NewStringPropertyValue("value") }),
		mustTypedProperty(t, "a_int", func() (entry.PropertyValue, error) { return entry.NewInt64PropertyValue(-7) }),
		mustTypedProperty(t, "m_bool", func() (entry.PropertyValue, error) { return entry.NewBoolPropertyValue(true) }),
		mustTypedProperty(t, "b_timestamp", func() (entry.PropertyValue, error) { return entry.NewTimestampPropertyValue(timestamp) }),
		mustTypedProperty(t, "c_list", func() (entry.PropertyValue, error) {
			return entry.NewStringListPropertyValue([]string{"one", "one", ""})
		}),
	}
	allTags, err := revisionFor("all-properties", Fixture{
		Key:          "item-1",
		RelativePath: "all",
		Name:         "All",
		ResourceType: "document",
		SizeBytes:    &size,
		ModifiedAt:   &timestamp,
		Properties:   allProperties,
	})
	if err != nil {
		t.Fatal(err)
	}
	const wantAllTags = "meta:IoiTrsWkCxu1nPK1jJtX8qI3qjOhbUIUCFn4rtGpv6A"
	if allTags.Strength != entry.RevisionStrengthMetadata || allTags.Token == nil || *allTags.Token != wantAllTags {
		t.Fatalf("all-tag metadata revision = %#v", allTags)
	}
}

func TestFakeExternalRejectsDuplicateFixture(t *testing.T) {
	_, err := New(Config{
		Namespace:  "duplicates",
		Generation: "generation-1",
		CursorKey:  testCursorKey(),
		Fixtures: []Fixture{
			{Key: "one", RelativePath: "same", Name: "One", ResourceType: "document"},
			{Key: "two", RelativePath: "same", Name: "Two", ResourceType: "document"},
		},
	})
	if !errors.Is(err, source.ErrInvalidConfig) {
		t.Fatalf("New() error = %v, want %v", err, source.ErrInvalidConfig)
	}
}

func mustAdapter(t *testing.T, config Config) *Adapter {
	t.Helper()
	adapter, err := New(config)
	if err != nil {
		t.Fatal(err)
	}
	return adapter
}

func mustRequest(t *testing.T, identity entry.SourceIdentity, mountID, relativePath string, cursor *string) listRequest {
	t.Helper()
	request, err := newListRequest(identity, mountID, relativePath, cursor)
	if err != nil {
		t.Fatal(err)
	}
	return request
}

func mustTypedProperty(t *testing.T, key string, makeValue func() (entry.PropertyValue, error)) entry.Property {
	t.Helper()
	value, err := makeValue()
	if err != nil {
		t.Fatal(err)
	}
	property, err := entry.NewProperty(key, value)
	if err != nil {
		t.Fatal(err)
	}
	return property
}

func mustProperty(t *testing.T, key, value string) entry.Property {
	t.Helper()
	propertyValue, err := entry.NewStringPropertyValue(value)
	if err != nil {
		t.Fatal(err)
	}
	property, err := entry.NewProperty(key, propertyValue)
	if err != nil {
		t.Fatal(err)
	}
	return property
}

func assertInvalidCursor(t *testing.T, adapter *Adapter, request listRequest) {
	t.Helper()
	if _, err := adapter.List(context.Background(), request); !errors.Is(err, source.ErrInvalidCursor) {
		t.Fatalf("List() error = %v, want %v", err, source.ErrInvalidCursor)
	}
}

func testCursorKey() []byte { return bytes.Repeat([]byte{0x24}, 32) }

func relativePaths(items []source.SourceItem) []string {
	paths := make([]string, len(items))
	for index, item := range items {
		paths[index] = item.RelativePath
	}
	return paths
}

func equalStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

func TestProviderAvailability(t *testing.T) {
	tests := []struct {
		name      string
		state     entry.AvailabilityState
		fixtures  []Fixture
		wantError error
	}{
		{name: "available nonempty", state: entry.AvailabilityStateAvailable, fixtures: []Fixture{providerFixture("provider-1", "item", "revision-1")}},
		{name: "available empty", state: entry.AvailabilityStateAvailable},
		{name: "stale cached snapshot", state: entry.AvailabilityStateStale, fixtures: []Fixture{providerFixture("provider-1", "item", "revision-1")}},
		{name: "offline no snapshot", state: entry.AvailabilityStateOffline, wantError: source.ErrSourceUnavailable},
		{name: "permission denied", state: entry.AvailabilityStatePermissionDenied, wantError: source.ErrPermissionDenied},
		{name: "source deleted", state: entry.AvailabilityStateSourceDeleted, wantError: source.ErrSourceDeleted},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			adapter := mustAdapter(t, providerConfig(test.state, test.fixtures))
			result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "", nil))
			if !errors.Is(err, test.wantError) {
				t.Fatalf("List() error = %v, want %v", err, test.wantError)
			}
			if result.Availability.State != test.state {
				t.Fatalf("availability = %#v", result.Availability)
			}
			if test.wantError != nil {
				if len(result.Items) != 0 || result.NextChildCursor != nil || result.SourceError == nil {
					t.Fatalf("failed outcome masquerades as success: %#v", result)
				}
			} else if result.SourceError != nil {
				t.Fatalf("success source error = %#v", result.SourceError)
			}
		})
	}
}

func TestSuccessEmpty(t *testing.T) {
	adapter := mustAdapter(t, providerConfig(entry.AvailabilityStateAvailable, nil))
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "", nil))
	if err != nil || result.Items == nil || len(result.Items) != 0 || result.Availability.State != entry.AvailabilityStateAvailable || result.Freshness.State != entry.FreshnessStateCurrent {
		t.Fatalf("success empty = %#v, %v", result, err)
	}
}

func TestStale(t *testing.T) {
	emptyConfig := providerConfig(entry.AvailabilityStateStale, nil)
	emptyConfig.CachedSnapshot = true
	emptyAdapter := mustAdapter(t, emptyConfig)
	emptyResult, err := emptyAdapter.List(context.Background(), mustRequest(t, emptyAdapter.SourceIdentity(), "mount", "", nil))
	if err != nil || emptyResult.Items == nil || len(emptyResult.Items) != 0 || emptyResult.Freshness.State != entry.FreshnessStateStale || len(emptyResult.Warnings) != 1 {
		t.Fatalf("known stale empty = %#v, %v", emptyResult, err)
	}

	if _, err := New(providerConfig(entry.AvailabilityStateStale, nil)); !errors.Is(err, source.ErrInvalidConfig) {
		t.Fatalf("stale without snapshot error = %v", err)
	}
	offlineCached := providerConfig(entry.AvailabilityStateOffline, nil)
	offlineCached.CachedSnapshot = true
	offlineAdapter := mustAdapter(t, offlineCached)
	offlineResult, err := offlineAdapter.List(context.Background(), mustRequest(t, offlineAdapter.SourceIdentity(), "mount", "", nil))
	if err != nil || offlineResult.Availability.State != entry.AvailabilityStateStale || offlineResult.Freshness.State != entry.FreshnessStateStale || len(offlineResult.Warnings) != 1 || offlineResult.Warnings[0].Code != source.WarningCodeSourceOffline {
		t.Fatalf("offline cached snapshot = %#v, %v", offlineResult, err)
	}

	lastSync := providerObservedAt().Add(-time.Hour)
	config := providerConfig(entry.AvailabilityStateStale, []Fixture{providerFixture("provider-1", "cached", "revision-1")})
	config.LastSyncAt = &lastSync
	adapter := mustAdapter(t, config)
	lastSync = lastSync.Add(-time.Hour)
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "", nil))
	if err != nil || len(result.Items) != 1 || result.Availability.State != entry.AvailabilityStateStale || result.Freshness.State != entry.FreshnessStateStale {
		t.Fatalf("stale = %#v, %v", result, err)
	}
	if result.Items[0].Snapshot.Availability.State != entry.AvailabilityStateStale || result.Items[0].Snapshot.Freshness.State != entry.FreshnessStateStale {
		t.Fatalf("stale item states = %#v", result.Items[0].Snapshot)
	}
	if len(result.Warnings) != 1 || result.Warnings[0].Code != source.WarningCodeStaleSnapshot || result.Freshness.LastSyncAt == nil || result.Freshness.LastSyncAt.Equal(lastSync) {
		t.Fatalf("stale metadata = %#v", result)
	}
	*result.Freshness.LastSyncAt = result.Freshness.LastSyncAt.Add(-time.Hour)
	repeat, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "", nil))
	if err != nil || repeat.Freshness.LastSyncAt == nil || repeat.Freshness.LastSyncAt.Equal(*result.Freshness.LastSyncAt) {
		t.Fatalf("result metadata aliases adapter state: %#v, %v", repeat, err)
	}
}

func TestOffline(t *testing.T) {
	assertFailedProviderState(t, entry.AvailabilityStateOffline, source.ErrSourceUnavailable, source.SourceErrorCodeSourceUnavailable)
}

func TestPermissionDenied(t *testing.T) {
	assertFailedProviderState(t, entry.AvailabilityStatePermissionDenied, source.ErrPermissionDenied, source.SourceErrorCodePermissionDenied)
}

func TestSourceDeleted(t *testing.T) {
	assertFailedProviderState(t, entry.AvailabilityStateSourceDeleted, source.ErrSourceDeleted, source.SourceErrorCodeSourceDeleted)
}

func TestProviderUpdateIdentity(t *testing.T) {
	beforeAdapter := mustAdapter(t, providerConfig(entry.AvailabilityStateAvailable, []Fixture{providerFixture("provider-1", "item", "revision-1")}))
	afterAdapter := mustAdapter(t, providerConfig(entry.AvailabilityStateAvailable, []Fixture{providerFixture("provider-1", "item", "revision-2")}))
	before := onlyProviderItem(t, beforeAdapter)
	after := onlyProviderItem(t, afterAdapter)
	if before.Identity != after.Identity {
		t.Fatalf("update changed identity: %#v %#v", before.Identity, after.Identity)
	}
	if before.Snapshot.Revision.Token == nil || after.Snapshot.Revision.Token == nil || *before.Snapshot.Revision.Token == *after.Snapshot.Revision.Token {
		t.Fatalf("update revisions = %#v %#v", before.Snapshot.Revision, after.Snapshot.Revision)
	}
}

func TestDeleteRecreateIdentity(t *testing.T) {
	beforeAdapter := mustAdapter(t, providerConfig(entry.AvailabilityStateAvailable, []Fixture{providerFixture("provider-old", "item", "revision-1")}))
	afterAdapter := mustAdapter(t, providerConfig(entry.AvailabilityStateAvailable, []Fixture{providerFixture("provider-new", "item", "revision-1")}))
	before := onlyProviderItem(t, beforeAdapter)
	after := onlyProviderItem(t, afterAdapter)
	if before.Identity.EntryKey == after.Identity.EntryKey || before.Identity.SourceID != after.Identity.SourceID {
		t.Fatalf("recreated identities = %#v %#v", before.Identity, after.Identity)
	}
}

func providerConfig(state entry.AvailabilityState, fixtures []Fixture) Config {
	return Config{
		Namespace: "provider-outcomes", Generation: "generation-1", CursorKey: testCursorKey(),
		Fixtures: fixtures, Availability: state, ObservedAt: providerObservedAt(),
	}
}

func providerFixture(key, relativePath, revision string) Fixture {
	return Fixture{Key: key, RelativePath: relativePath, Name: "Item", ResourceType: "document", ProviderRevision: &revision, Capabilities: entry.Capabilities{ReadProperties: true}}
}

func providerObservedAt() time.Time {
	return time.Date(2026, time.August, 3, 3, 0, 0, 0, time.UTC)
}

func onlyProviderItem(t *testing.T, adapter *Adapter) source.SourceItem {
	t.Helper()
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "", nil))
	if err != nil || len(result.Items) != 1 {
		t.Fatalf("List() = %#v, %v", result, err)
	}
	return result.Items[0]
}

func assertFailedProviderState(t *testing.T, state entry.AvailabilityState, wantError error, wantCode source.SourceErrorCode) {
	t.Helper()
	adapter := mustAdapter(t, providerConfig(state, nil))
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "", nil))
	if !errors.Is(err, wantError) || result.SourceError == nil || result.SourceError.Code != wantCode || len(result.Items) != 0 || result.NextChildCursor != nil {
		t.Fatalf("failed state %q = %#v, %v", state, result, err)
	}
}

func TestRequestedPropertiesResourceAdapter(t *testing.T) {
	delegate := mustAdapter(t, Config{
		Namespace: "requested", Generation: "generation-1", CursorKey: testCursorKey(),
		Fixtures: []Fixture{{Key: "item", RelativePath: "item", Name: "Item", ResourceType: "document", Properties: []entry.Property{mustProperty(t, "other", "hidden"), mustProperty(t, "title", "Visible")}}},
	})
	adapter := NewResourceAdapter(delegate)
	sourceRef, mountRef := canonicalRefs(t, delegate.SourceIdentity(), "fakeexternal", "requested", "mount", "/external")
	request, err := source.NewAdapterListRequest(sourceRef, mountRef, "", 1, nil, []string{"title"})
	if err != nil {
		t.Fatal(err)
	}
	result, err := adapter.List(context.Background(), request)
	titleID, idErr := entry.RegistryPropertyID("title")
	if idErr != nil {
		t.Fatal(idErr)
	}
	if err != nil || len(result.Items) != 1 || len(result.Items[0].EntrySnapshot.CanonicalProperties) != 1 || result.Items[0].EntrySnapshot.CanonicalProperties[0].PropertyID != titleID {
		t.Fatalf("List() = %#v, %v", result, err)
	}
	ref := result.Items[0].EntryRef
	resolveRequest, err := source.NewAdapterResolveRequest(sourceRef, mountRef, &ref, nil, []string{"title"})
	if err != nil {
		t.Fatal(err)
	}
	resolved, err := adapter.Resolve(context.Background(), resolveRequest)
	if err != nil || resolved.Item == nil || resolved.Item.EntryRef.EntryID != ref.EntryID || len(resolved.Item.EntrySnapshot.CanonicalProperties) != 1 {
		t.Fatalf("Resolve() = %#v, %v", resolved, err)
	}
}

func canonicalRefs(t *testing.T, identity entry.SourceIdentity, providerType, account, mountID, point string) (entry.SourceRef, entry.MountRef) {
	t.Helper()
	available, _ := entry.NewAvailability(entry.AvailabilityStateAvailable)
	sourceRef, err := entry.NewSourceRef(identity.SourceID, providerType, account, available, identity.IdentityStrength)
	if err != nil {
		t.Fatal(err)
	}
	path, _ := entry.NewResolvedVirtualPath(mountID, point, "seed")
	mountRef, err := entry.NewMountRef(mountID, "workspace", identity.SourceID, path, available, entry.CachePolicyNone)
	if err != nil {
		t.Fatal(err)
	}
	return sourceRef, mountRef
}

func TestAvailabilityPropagationResourceAdapter(t *testing.T) {
	config := providerConfig(entry.AvailabilityStateReadOnly, []Fixture{providerFixture("provider-1", "item", "revision-1")})
	delegate := mustAdapter(t, config)
	adapter := NewResourceAdapter(delegate)
	sourceRef, mountRef := canonicalRefs(t, delegate.SourceIdentity(), "fakeexternal", "provider-outcomes", "mount", "/external")
	request, err := source.NewAdapterListRequest(sourceRef, mountRef, "", 1, nil, []string{})
	if err != nil {
		t.Fatal(err)
	}
	result, err := adapter.List(context.Background(), request)
	if err != nil || result.Availability.State != entry.AvailabilityStateReadOnly || len(result.Items) != 1 {
		t.Fatalf("read-only result = %#v, %v", result, err)
	}
	capabilities := result.Items[0].Capabilities
	if capabilities.Writable || capabilities.Movable || capabilities.Copyable || capabilities.Deletable || capabilities.Commentable {
		t.Fatalf("read-only capabilities = %#v", capabilities)
	}
}

func TestLegacyLocatorCompatibilityWithLongKey(t *testing.T) {
	key := bytes.Repeat([]byte{0x35}, 48)
	adapter := mustAdapter(t, Config{Namespace: "legacy-long-key", Generation: "generation-1", CursorKey: key, Fixtures: []Fixture{{Key: "item", RelativePath: "item", Name: "Item", ResourceType: "document"}}})
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "", nil))
	if err != nil || len(result.Items) != 1 {
		t.Fatalf("List() = %#v, %v", result, err)
	}
	backend := []byte(adapter.namespace + "\x00item")
	if !source.ValidateSourceLocator(result.Items[0].Locator, key, backend) {
		t.Fatal("legacy locator no longer validates")
	}
}

type recordingConnectionResolver struct {
	delegate source.ConnectionResolver
	calls    int
}

func (resolver *recordingConnectionResolver) Resolve(ctx context.Context, sourceID, provider string) (source.ConnectionResolution, error) {
	resolver.calls++
	return resolver.delegate.Resolve(ctx, sourceID, provider)
}

type recordingProviderClient struct {
	delegate fixtureProviderClient
	lists    int
	resolves int
}

func (client *recordingProviderClient) List(ctx context.Context, session source.AccessSession, adapter *Adapter, request listRequest, limit int) (listResult, error) {
	client.lists++
	return client.delegate.List(ctx, session, adapter, request, limit)
}
func (client *recordingProviderClient) Resolve(ctx context.Context, session source.AccessSession, adapter *Adapter, request source.AdapterResolveRequest) (*Fixture, error) {
	client.resolves++
	return client.delegate.Resolve(ctx, session, adapter, request)
}

func TestConnectedAccessSessionClientBoundary(t *testing.T) {
	providerRevision := "provider-revision-connected"
	delegate := mustAdapter(t, Config{Namespace: "connected-boundary", Generation: "generation-1", CursorKey: testCursorKey(), Fixtures: []Fixture{{Key: "item", RelativePath: "item", Name: "Item", ResourceType: "document", ProviderRevision: &providerRevision}}, ObservedAt: providerObservedAt()})
	resolver := connectedResolverForTest(t, delegate, source.ConnectionResolutionConnected)
	recordingResolver := &recordingConnectionResolver{delegate: resolver}
	client := &recordingProviderClient{}
	adapter, err := newResourceAdapterWithConnection(delegate, recordingResolver, client)
	if err != nil {
		t.Fatal(err)
	}
	sourceRef, mountRef := canonicalRefs(t, delegate.SourceIdentity(), "fakeexternal", "connected-boundary", "mount", "/external")
	listRequest, _ := source.NewAdapterListRequest(sourceRef, mountRef, "", 1, nil, []string{})
	listed, err := adapter.List(context.Background(), listRequest)
	if err != nil || recordingResolver.calls != 1 || client.lists != 1 || len(listed.Items) != 1 || listed.SourceRevision.Strength != entry.RevisionStrengthUnknown || listed.Items[0].EntrySnapshot.SourceRevision.Revision.Token == nil || *listed.Items[0].EntrySnapshot.SourceRevision.Revision.Token != providerRevision {
		t.Fatalf("list=%#v err=%v resolver=%d client=%d", listed, err, recordingResolver.calls, client.lists)
	}
	ref := listed.Items[0].EntryRef
	resolveRequest, _ := source.NewAdapterResolveRequest(sourceRef, mountRef, &ref, nil, []string{})
	resolved, err := adapter.Resolve(context.Background(), resolveRequest)
	if err != nil || recordingResolver.calls != 2 || client.resolves != 1 || resolved.Item == nil || resolved.SourceRevision.Token == nil || *resolved.SourceRevision.Token != providerRevision {
		t.Fatalf("resolve=%#v err=%v resolver=%d client=%d", resolved, err, recordingResolver.calls, client.resolves)
	}
}

func TestAuthRequired(t *testing.T) {
	assertConnectionResolutionMapping(t, source.ConnectionResolutionAuthRequired, entry.AvailabilityStatePermissionDenied, source.SourceErrorCodePermissionDenied)
}
func TestAuthExpired(t *testing.T) {
	assertConnectionResolutionMapping(t, source.ConnectionResolutionAuthExpired, entry.AvailabilityStatePermissionDenied, source.SourceErrorCodePermissionDenied)
}
func TestAuthRevoked(t *testing.T) {
	assertConnectionResolutionMapping(t, source.ConnectionResolutionAuthRevoked, entry.AvailabilityStatePermissionDenied, source.SourceErrorCodePermissionDenied)
}
func TestProviderUnavailable(t *testing.T) {
	assertConnectionResolutionMapping(t, source.ConnectionResolutionProviderUnavailable, entry.AvailabilityStateOffline, source.SourceErrorCodeSourceUnavailable)
}

func assertConnectionResolutionMapping(t *testing.T, state source.ConnectionResolutionState, availability entry.AvailabilityState, code source.SourceErrorCode) {
	t.Helper()
	delegate := mustAdapter(t, Config{Namespace: "connection-state-" + string(state), Generation: "generation-1", CursorKey: testCursorKey(), ObservedAt: providerObservedAt()})
	resolver := &recordingConnectionResolver{delegate: connectedResolverForTest(t, delegate, state)}
	client := &recordingProviderClient{}
	adapter, err := newResourceAdapterWithConnection(delegate, resolver, client)
	if err != nil {
		t.Fatal(err)
	}
	sourceRef, mountRef := canonicalRefs(t, delegate.SourceIdentity(), "fakeexternal", "connection", "mount", "/external")
	request, _ := source.NewAdapterListRequest(sourceRef, mountRef, "", 1, nil, []string{})
	result, err := adapter.List(context.Background(), request)
	if err != nil || resolver.calls != 1 || client.lists != 0 || len(result.Items) != 0 || result.NextChildCursor != nil || result.Availability.State != availability || result.SourceError == nil || result.SourceError.Code != code {
		t.Fatalf("state=%s result=%#v err=%v resolver=%d client=%d", state, result, err, resolver.calls, client.lists)
	}
}

func connectedResolverForTest(t *testing.T, adapter *Adapter, state source.ConnectionResolutionState) source.ConnectionResolver {
	t.Helper()
	credential, err := source.NewCredentialRef("fake-reference")
	if err != nil {
		t.Fatal(err)
	}
	connection, err := source.NewSourceConnection("connection", "fakeexternal", adapter.SourceIdentity().SourceID, source.AuthMethodOAuth2, source.ConnectionStatusConnected, &credential, []string{}, adapter.observedAt, nil)
	if err != nil {
		t.Fatal(err)
	}
	resolver, err := source.NewFakeConnectionResolver(connection, state, adapter.observedAt.Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	return resolver
}

func TestConnectionResolverTypedNilSafety(t *testing.T) {
	delegate := mustAdapter(t, Config{Namespace: "typed-nil-connection", Generation: "generation-1", CursorKey: testCursorKey(), ObservedAt: providerObservedAt()})
	var resolver *source.FakeConnectionResolver
	if _, err := newResourceAdapterWithConnection(delegate, resolver, fixtureProviderClient{}); !errors.Is(err, source.ErrInvalidConfig) {
		t.Fatalf("typed nil resolver error = %v", err)
	}
	var client *recordingProviderClient
	connected := connectedResolverForTest(t, delegate, source.ConnectionResolutionConnected)
	if _, err := newResourceAdapterWithConnection(delegate, connected, client); !errors.Is(err, source.ErrInvalidConfig) {
		t.Fatalf("typed nil client error = %v", err)
	}
}

func TestProviderRevisionPreservedPerEntry(t *testing.T) {
	firstRevision, secondRevision := "provider-a", "provider-b"
	delegate := mustAdapter(t, Config{Namespace: "per-entry-revision", Generation: "generation-1", CursorKey: testCursorKey(), Fixtures: []Fixture{
		{Key: "a", RelativePath: "a", Name: "A", ResourceType: "document", ProviderRevision: &firstRevision},
		{Key: "b", RelativePath: "b", Name: "B", ResourceType: "document", ProviderRevision: &secondRevision},
	}, ObservedAt: providerObservedAt()})
	adapter := NewResourceAdapter(delegate)
	sourceRef, mountRef := canonicalRefs(t, delegate.SourceIdentity(), "fakeexternal", "revision", "mount", "/external")
	request, _ := source.NewAdapterListRequest(sourceRef, mountRef, "", 2, nil, []string{})
	result, err := adapter.List(context.Background(), request)
	if err != nil || len(result.Items) != 2 {
		t.Fatalf("result=%#v err=%v", result, err)
	}
	for index, want := range []string{firstRevision, secondRevision} {
		got := result.Items[index].EntrySnapshot.SourceRevision.Revision.Token
		if got == nil || *got != want || result.Items[index].EntrySnapshot.Freshness.SourceRevision.Revision.Token == nil || *result.Items[index].EntrySnapshot.Freshness.SourceRevision.Revision.Token != want {
			t.Fatalf("entry %d revision=%#v", index, result.Items[index].EntrySnapshot)
		}
	}
	if result.SourceRevision.Strength != entry.RevisionStrengthUnknown {
		t.Fatalf("scope revision=%#v", result.SourceRevision)
	}
}
