package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	applicationentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/entry"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/mount"
	entryruntime "github.com/voyager-labs/voyager-app/apps/entry-core/internal/runtime"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source/fakeexternal"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source/localfs"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

const integrationWorkspaceID = "workspace"

type sourceExpectation struct {
	mountID           string
	virtualPrefix     string
	requestLabel      string
	entryResourceType string
	wantProperties    bool
}

type unifiedComposition struct {
	runtime *entryruntime.Runtime
	sources map[string]sourceExpectation
}

type listPage struct {
	wire   []byte
	result schema.EntryListResult
}

func TestEntryContractUnifiedListResolve(t *testing.T) {
	composition := newUnifiedComposition(t)
	first := dispatchList(t, composition.runtime, "mixed-list-1", "/", 2, nil, []string{"title"})
	assertMixedPage(t, composition, first, true)
	assertNoProviderDTOLeakage(t, first.wire)

	second := dispatchList(t, composition.runtime, "mixed-list-2", "/", 2, first.result.NextPageToken, []string{"title"})
	assertMixedPage(t, composition, second, false)
	assertNoProviderDTOLeakage(t, second.wire)

	entriesBySource := assertCompleteContinuation(t, composition, first, second)
	for sourceID, listed := range entriesBySource {
		expectation := composition.sources[sourceID]
		resolved, wire := dispatchResolve(t, composition.runtime, "resolve-"+expectation.requestLabel, listed.EntryRef, expectation.mountID, []string{"title"})
		assertResolvedEntry(t, listed, resolved, expectation)
		assertNoProviderDTOLeakage(t, wire)
	}

	assertRepresentativeSourceOutcomes(t)
	assertCurrentProtocolThroughInjectedRuntime(t, composition.runtime)
}

func newUnifiedComposition(t *testing.T) unifiedComposition {
	t.Helper()
	localRoot := t.TempDir()
	for _, name := range []string{"alpha.txt", "beta.txt"} {
		if err := os.WriteFile(filepath.Join(localRoot, name), []byte(name), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	localAdapter, err := localfs.New(localfs.Config{Root: localRoot, Generation: "integration-local", CursorKey: bytes.Repeat([]byte{0x31}, 32)})
	if err != nil {
		t.Fatal(err)
	}
	modifiedAt := time.Date(2026, 8, 2, 3, 0, 0, 123456789, time.UTC)
	externalAdapter, err := fakeexternal.New(fakeexternal.Config{
		Namespace:  "voyager-integration",
		Generation: "integration-external",
		CursorKey:  bytes.Repeat([]byte{0x57}, 32),
		ObservedAt: time.Date(2026, 8, 3, 4, 0, 0, 0, time.UTC),
		Fixtures: []fakeexternal.Fixture{
			fakeFixture(t, "external-alpha", "alpha", "External Alpha", modifiedAt),
			fakeFixture(t, "external-beta", "beta", "External Beta", modifiedAt),
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	registry := mount.NewMountRegistry()
	available := mustAvailability(t, domainentry.AvailabilityStateAvailable)
	localSource := mustSourceRef(t, localAdapter.SourceIdentity().SourceID, "localfs", "local", available, localAdapter.SourceIdentity().IdentityStrength)
	externalSource := mustSourceRef(t, externalAdapter.SourceIdentity().SourceID, "fakeexternal", "external", available, externalAdapter.SourceIdentity().IdentityStrength)
	localMount := mustMountRef(t, "mount-local", localSource.SourceInstanceID, "/local")
	externalMount := mustMountRef(t, "mount-external", externalSource.SourceInstanceID, "/external")
	for _, ref := range []domainentry.MountRef{localMount, externalMount} {
		if err := registry.Register(ref); err != nil {
			t.Fatal(err)
		}
	}
	service, err := applicationentry.NewUnifiedService(registry, []applicationentry.ResourceAdapterBinding{
		{SourceRef: localSource, Adapter: localfs.NewResourceAdapter(localAdapter)},
		{SourceRef: externalSource, Adapter: fakeexternal.NewResourceAdapter(externalAdapter)},
	}, bytes.Repeat([]byte{0x42}, 32), func() time.Time { return time.Date(2026, 8, 3, 5, 0, 0, 0, time.UTC) })
	if err != nil {
		t.Fatal(err)
	}
	return unifiedComposition{
		runtime: entryruntime.NewWithEntryService(integrationWorkspaceID, service),
		sources: map[string]sourceExpectation{
			localSource.SourceInstanceID:    {mountID: localMount.MountID, virtualPrefix: "/local", requestLabel: "local", entryResourceType: "file", wantProperties: false},
			externalSource.SourceInstanceID: {mountID: externalMount.MountID, virtualPrefix: "/external", requestLabel: "external", entryResourceType: "document", wantProperties: true},
		},
	}
}

func fakeFixture(t *testing.T, key, relativePath, name string, modifiedAt time.Time) fakeexternal.Fixture {
	t.Helper()
	value, err := domainentry.NewStringPropertyValue(name)
	if err != nil {
		t.Fatal(err)
	}
	property, err := domainentry.NewProperty("title", value)
	if err != nil {
		t.Fatal(err)
	}
	size := int64(len(name))
	providerRevision := "provider-" + key
	return fakeexternal.Fixture{
		Key: key, RelativePath: relativePath, Name: name, ResourceType: "document", SizeBytes: &size,
		ModifiedAt: &modifiedAt, Properties: []domainentry.Property{property}, ProviderRevision: &providerRevision,
		Capabilities: domainentry.Capabilities{ReadProperties: true},
	}
}

func dispatchList(t *testing.T, runtime *entryruntime.Runtime, requestID, virtualPath string, pageSize int, token *string, properties []string) listPage {
	t.Helper()
	params := map[string]any{"virtual_path": virtualPath, "page_size": pageSize, "requested_properties": properties}
	if token != nil {
		params["page_token"] = *token
	}
	wire := rawRequest(t, requestID, schema.MethodEntryList, params)
	request, trustworthyID, protocolError := schema.DecodeRequest(wire)
	if protocolError != nil || trustworthyID != requestID {
		t.Fatalf("DecodeRequest() = %#v, %q, %#v; wire=%s", request, trustworthyID, protocolError, wire)
	}
	encoded := schema.EncodeResponse(runtime.Dispatch(context.Background(), request))
	decoded, err := schema.DecodeResponse(encoded, schema.MethodEntryList)
	if err != nil {
		t.Fatalf("DecodeResponse(): %v; wire=%s", err, encoded)
	}
	result, ok := decoded.Result.(schema.EntryListResult)
	if !ok || !decoded.OK || decoded.RequestID != requestID {
		t.Fatalf("decoded response = %#v error=%#v wire=%s", decoded, decoded.Error, encoded)
	}
	if err := result.Validate(); err != nil {
		t.Fatalf("result Validate(): %v", err)
	}
	if result.HasMore != (result.NextPageToken != nil) {
		t.Fatalf("has_more=%t token=%#v", result.HasMore, result.NextPageToken)
	}
	return listPage{wire: encoded, result: result}
}

func dispatchResolve(t *testing.T, runtime *entryruntime.Runtime, requestID string, ref schema.EntryRef, mountID string, properties []string) (schema.EntryResolveResult, []byte) {
	t.Helper()
	params := map[string]any{"entry_ref": ref, "mount_id": mountID, "requested_properties": properties}
	wire := rawRequest(t, requestID, schema.MethodEntryResolve, params)
	request, trustworthyID, protocolError := schema.DecodeRequest(wire)
	if protocolError != nil || trustworthyID != requestID {
		t.Fatalf("DecodeRequest() = %#v, %q, %#v; wire=%s", request, trustworthyID, protocolError, wire)
	}
	encoded := schema.EncodeResponse(runtime.Dispatch(context.Background(), request))
	decoded, err := schema.DecodeResponse(encoded, schema.MethodEntryResolve)
	if err != nil {
		t.Fatalf("DecodeResponse(): %v; wire=%s", err, encoded)
	}
	result, ok := decoded.Result.(schema.EntryResolveResult)
	if !ok || !decoded.OK || decoded.RequestID != requestID || result.Validate() != nil {
		t.Fatalf("decoded resolve = %#v error=%#v wire=%s", decoded, decoded.Error, encoded)
	}
	return result, encoded
}

func rawRequest(t *testing.T, requestID string, method schema.Method, params map[string]any) []byte {
	t.Helper()
	wire, err := json.Marshal(map[string]any{"request_id": requestID, "method": method, "params": params})
	if err != nil {
		t.Fatal(err)
	}
	return wire
}

func assertMixedPage(t *testing.T, composition unifiedComposition, page listPage, wantToken bool) {
	t.Helper()
	if len(page.result.Entries) != 2 || (page.result.NextPageToken != nil) != wantToken || page.result.HasMore != wantToken {
		t.Fatalf("page entries=%d has_more=%t token=%#v", len(page.result.Entries), page.result.HasMore, page.result.NextPageToken)
	}
	if wantToken && *page.result.NextPageToken == "" {
		t.Fatal("composite page token is empty")
	}
	seenSources := map[string]bool{}
	for _, entry := range page.result.Entries {
		expectation, exists := composition.sources[entry.EntryRef.SourceInstanceID]
		if !exists {
			t.Fatalf("unexpected source: %#v", entry.EntryRef)
		}
		seenSources[entry.EntryRef.SourceInstanceID] = true
		if entry.EntryRef != entry.EntrySnapshot.EntryRef || entry.AccessContext.SourceInstanceID != entry.EntryRef.SourceInstanceID || entry.AccessContext.MountID != expectation.mountID || !strings.HasPrefix(entry.AccessContext.VirtualPath, expectation.virtualPrefix+"/") {
			t.Fatalf("inconsistent canonical entry: %#v", entry)
		}
		if !entry.AccessContext.Capabilities.Readable || entry.EntrySnapshot.Availability.State != "available" || entry.EntrySnapshot.Freshness.State != "current" || entry.EntryRef.ResourceType != expectation.entryResourceType {
			t.Fatalf("entry state/type/capabilities: %#v", entry)
		}
		if expectation.wantProperties {
			titleID, idErr := domainentry.RegistryPropertyID("title")
			if idErr != nil {
				t.Fatal(idErr)
			}
			if len(entry.EntrySnapshot.Properties) != 1 || entry.EntrySnapshot.Properties[0].PropertyID != titleID.String() {
				t.Fatalf("external properties=%#v", entry.EntrySnapshot.Properties)
			}
		} else if len(entry.EntrySnapshot.Properties) != 0 {
			t.Fatalf("local properties=%#v", entry.EntrySnapshot.Properties)
		}
	}
	if len(page.result.SourceRevision) != 2 || len(page.result.Availability) != 2 || len(page.result.Freshness) != 2 {
		t.Fatalf("summary cardinality: %#v", page.result)
	}
	for _, summary := range page.result.SourceRevision {
		expectation, exists := composition.sources[summary.SourceInstanceID]
		if !exists || summary.MountID != expectation.mountID {
			t.Fatalf("unexpected summary=%#v", summary)
		}
	}
	if len(seenSources) != len(composition.sources) {
		t.Fatalf("page sources=%v, want local+external", seenSources)
	}
}

func assertCompleteContinuation(t *testing.T, composition unifiedComposition, pages ...listPage) map[string]schema.Entry {
	t.Helper()
	seenIDs := map[string]struct{}{}
	counts := map[string]int{}
	representatives := map[string]schema.Entry{}
	for _, page := range pages {
		for _, entry := range page.result.Entries {
			if _, duplicate := seenIDs[entry.EntryRef.EntryID]; duplicate {
				t.Fatalf("duplicate entry across continuation: %s", entry.EntryRef.EntryID)
			}
			seenIDs[entry.EntryRef.EntryID] = struct{}{}
			counts[entry.EntryRef.SourceInstanceID]++
			if _, exists := representatives[entry.EntryRef.SourceInstanceID]; !exists {
				representatives[entry.EntryRef.SourceInstanceID] = entry
			}
		}
	}
	if len(seenIDs) != 4 || len(representatives) != len(composition.sources) {
		t.Fatalf("continuation entries=%d representatives=%d", len(seenIDs), len(representatives))
	}
	for sourceID := range composition.sources {
		if counts[sourceID] != 2 {
			t.Fatalf("source %s count=%d, want 2", sourceID, counts[sourceID])
		}
	}
	return representatives
}

func assertResolvedEntry(t *testing.T, listed schema.Entry, resolved schema.EntryResolveResult, expectation sourceExpectation) {
	t.Helper()
	if resolved.EntryRef != listed.EntryRef || resolved.EntrySnapshot.EntryRef != resolved.EntryRef || resolved.AccessContext.SourceInstanceID != resolved.EntryRef.SourceInstanceID || resolved.AccessContext.MountID != expectation.mountID || resolved.AccessContext.VirtualPath != listed.AccessContext.VirtualPath {
		t.Fatalf("resolve identity/context mismatch: listed=%#v resolved=%#v", listed, resolved)
	}
	if resolved.EntrySnapshot.DisplayName != listed.EntrySnapshot.DisplayName || resolved.Capabilities != resolved.AccessContext.Capabilities || resolved.Availability != resolved.EntrySnapshot.Availability || !reflect.DeepEqual(resolved.Freshness, resolved.EntrySnapshot.Freshness) || !reflect.DeepEqual(resolved.SourceRevision, resolved.EntrySnapshot.SourceRevision) {
		t.Fatalf("resolve snapshot/state mismatch: listed=%#v resolved=%#v", listed, resolved)
	}
	if resolved.Availability.State != "available" || resolved.Freshness.State != "current" || !resolved.Capabilities.Readable {
		t.Fatalf("resolve state/capabilities: %#v", resolved)
	}
}

func assertRepresentativeSourceOutcomes(t *testing.T) {
	t.Helper()
	observedAt := time.Date(2026, 8, 3, 6, 0, 0, 0, time.UTC)
	modifiedAt := observedAt.Add(-time.Hour)
	tests := []struct {
		name          string
		mountPoint    string
		config        fakeexternal.Config
		wantEntries   int
		wantState     string
		wantFreshness string
		wantWarning   string
	}{
		{
			name: "success empty", mountPoint: "/empty", wantEntries: 0, wantState: "available", wantFreshness: "current",
			config: fakeexternal.Config{Namespace: "integration-empty", Generation: "empty-v1", CursorKey: bytes.Repeat([]byte{0x61}, 32), ObservedAt: observedAt, Fixtures: []fakeexternal.Fixture{}},
		},
		{
			name: "cached offline", mountPoint: "/cached", wantEntries: 1, wantState: "stale", wantFreshness: "stale", wantWarning: "source_offline",
			config: fakeexternal.Config{Namespace: "integration-cached", Generation: "cached-v1", CursorKey: bytes.Repeat([]byte{0x62}, 32), Availability: domainentry.AvailabilityStateOffline, ObservedAt: observedAt, LastSyncAt: timePointer(observedAt.Add(-time.Minute)), CachedSnapshot: true, Fixtures: []fakeexternal.Fixture{fakeFixture(t, "cached", "cached", "Cached", modifiedAt)}},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			runtime := newFakeOnlyRuntime(t, test.mountPoint, test.config)
			page := dispatchList(t, runtime, "outcome-"+test.name, test.mountPoint, 1, nil, []string{"title"})
			if len(page.result.Entries) != test.wantEntries || page.result.HasMore || page.result.NextPageToken != nil || len(page.result.Availability) != 1 || page.result.Availability[0].State != test.wantState || page.result.Availability[0].Error != nil || len(page.result.Freshness) != 1 || page.result.Freshness[0].State != test.wantFreshness {
				t.Fatalf("outcome result=%#v", page.result)
			}
			if test.wantWarning == "" {
				if len(page.result.Warnings) != 0 {
					t.Fatalf("unexpected warnings=%#v", page.result.Warnings)
				}
			} else if len(page.result.Warnings) != 1 || page.result.Warnings[0].Code != test.wantWarning {
				t.Fatalf("warnings=%#v, want %s", page.result.Warnings, test.wantWarning)
			}
			if test.wantEntries == 1 {
				entry := page.result.Entries[0]
				if entry.EntrySnapshot.Availability.State != test.wantState || entry.EntrySnapshot.Freshness.State != test.wantFreshness {
					t.Fatalf("cached entry state=%#v", entry.EntrySnapshot)
				}
			}
		})
	}
	for _, failure := range []struct {
		name  string
		state domainentry.AvailabilityState
		code  schema.ErrorCode
	}{
		{name: "auth required", state: domainentry.AvailabilityStatePermissionDenied, code: schema.ErrorPermissionDenied},
		{name: "provider unavailable", state: domainentry.AvailabilityStateOffline, code: schema.ErrorSourceUnavailable},
	} {
		t.Run(failure.name, func(t *testing.T) {
			runtime := newFakeOnlyRuntime(t, "/failure", fakeexternal.Config{Namespace: "integration-" + strings.ReplaceAll(failure.name, " ", "-"), Generation: "failure-v1", CursorKey: bytes.Repeat([]byte{0x63}, 32), Availability: failure.state, ObservedAt: observedAt, Fixtures: []fakeexternal.Fixture{}})
			wire := []byte(`{"request_id":"failure","method":"entry.list","params":{"virtual_path":"/failure","page_size":1,"requested_properties":[]}}`)
			request, _, protocolError := schema.DecodeRequest(wire)
			if protocolError != nil {
				t.Fatal(protocolError)
			}
			encoded := schema.EncodeResponse(runtime.Dispatch(context.Background(), request))
			response, err := schema.DecodeResponse(encoded, schema.MethodEntryList)
			if err != nil || response.Error == nil || response.Error.Code != failure.code {
				t.Fatalf("response=%#v err=%v wire=%s", response, err, encoded)
			}
			assertNoProviderDTOLeakage(t, encoded)
		})
	}
}

func newFakeOnlyRuntime(t *testing.T, mountPoint string, config fakeexternal.Config) *entryruntime.Runtime {
	t.Helper()
	adapter, err := fakeexternal.New(config)
	if err != nil {
		t.Fatal(err)
	}
	availabilityState := domainentry.AvailabilityStateAvailable
	if config.CachedSnapshot {
		availabilityState = domainentry.AvailabilityStateStale
	}
	sourceAvailability := mustAvailability(t, availabilityState)
	sourceRef := mustSourceRef(t, adapter.SourceIdentity().SourceID, "fakeexternal", config.Namespace, sourceAvailability, adapter.SourceIdentity().IdentityStrength)
	mountRef := mustMountRef(t, "mount-"+strings.TrimPrefix(mountPoint, "/"), sourceRef.SourceInstanceID, mountPoint)
	registry := mount.NewMountRegistry()
	if err := registry.Register(mountRef); err != nil {
		t.Fatal(err)
	}
	service, err := applicationentry.NewUnifiedService(registry, []applicationentry.ResourceAdapterBinding{{SourceRef: sourceRef, Adapter: fakeexternal.NewResourceAdapter(adapter)}}, bytes.Repeat([]byte{0x43}, 32), func() time.Time { return time.Date(2026, 8, 3, 7, 0, 0, 0, time.UTC) })
	if err != nil {
		t.Fatal(err)
	}
	return entryruntime.NewWithEntryService(integrationWorkspaceID, service)
}

func mustAvailability(t *testing.T, state domainentry.AvailabilityState) domainentry.Availability {
	t.Helper()
	value, err := domainentry.NewAvailability(state)
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func mustSourceRef(t *testing.T, sourceID, providerType, accountKey string, availability domainentry.Availability, strength domainentry.IdentityStrength) domainentry.SourceRef {
	t.Helper()
	value, err := domainentry.NewSourceRef(sourceID, providerType, accountKey, availability, strength)
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func mustMountRef(t *testing.T, mountID, sourceID, mountPoint string) domainentry.MountRef {
	t.Helper()
	path, err := domainentry.NewResolvedVirtualPath(mountID, mountPoint, "integration-entry")
	if err != nil {
		t.Fatal(err)
	}
	value, err := domainentry.NewMountRef(mountID, integrationWorkspaceID, sourceID, path, mustAvailability(t, domainentry.AvailabilityStateAvailable), domainentry.CachePolicyNone)
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func assertNoProviderDTOLeakage(t *testing.T, wire []byte) {
	t.Helper()
	var value any
	if err := json.Unmarshal(wire, &value); err != nil {
		t.Fatal(err)
	}
	forbidden := map[string]struct{}{"provider_type": {}, "provider_revision": {}, "next_child_cursor": {}, "child_cursor": {}, "relative_path": {}, "backend_locator": {}, "raw_provider": {}, "credential_ref": {}, "authorization": {}, "access_token": {}, "refresh_token": {}, "api_key": {}}
	var visit func(any)
	visit = func(candidate any) {
		switch typed := candidate.(type) {
		case map[string]any:
			for key, nested := range typed {
				if _, exists := forbidden[key]; exists {
					t.Fatalf("provider DTO field %q leaked in wire=%s", key, wire)
				}
				visit(nested)
			}
		case []any:
			for _, nested := range typed {
				visit(nested)
			}
		}
	}
	visit(value)
	lower := strings.ToLower(string(wire))
	for _, literal := range []string{"fake-credential-reference", "bearer ", "authorization:"} {
		if strings.Contains(lower, literal) {
			t.Fatalf("credential material leaked in wire")
		}
	}
}

func assertCurrentProtocolThroughInjectedRuntime(t *testing.T, runtime *entryruntime.Runtime) {
	t.Helper()
	wire := []byte(`{"request_id":"current","method":"ping","params":{}}`)
	request, trustworthyID, protocolError := schema.DecodeRequest(wire)
	if protocolError != nil || trustworthyID != "current" {
		t.Fatalf("DecodeRequest() = %#v, %q, %#v", request, trustworthyID, protocolError)
	}
	encoded := schema.EncodeResponse(runtime.Dispatch(context.Background(), request))
	response, err := schema.DecodeResponse(encoded, schema.MethodPing)
	if err != nil || !response.OK || response.Result != (schema.PingResult{Message: "pong"}) {
		t.Fatalf("current response = %#v, error = %v, wire=%s", response, err, encoded)
	}
}

func timePointer(value time.Time) *time.Time { return &value }
