package runtime

import (
	"context"
	"errors"
	"testing"
	"time"

	applicationentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/entry"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

type recordingEntryService struct {
	lists         int
	resolves      int
	listErr       error
	listResult    applicationentry.UnifiedListResult
	resolveErr    error
	resolveResult applicationentry.ResolveResult
}

func (service *recordingEntryService) UnifiedList(context.Context, applicationentry.UnifiedListRequest) (applicationentry.UnifiedListResult, error) {
	service.lists++
	return service.listResult, service.listErr
}
func (service *recordingEntryService) ResolveEntry(context.Context, applicationentry.ResolveRequest) (applicationentry.ResolveResult, error) {
	service.resolves++
	return service.resolveResult, service.resolveErr
}

func TestEntryListResolveDispatch(t *testing.T) {
	t.Parallel()
	resolved := entryResolveResultFixture(t)
	service := &recordingEntryService{resolveResult: resolved, listResult: unifiedListResultFixture(resolved)}
	runtime := NewWithEntryService("workspace", service)
	list := schema.Request{RequestID: "list", Method: schema.MethodEntryList, EntryListParams: &schema.EntryListParams{VirtualPath: "/", PageSize: 1, RequestedProperties: []string{}}}
	listResponse := runtime.Dispatch(context.Background(), list)
	if !listResponse.OK || service.lists != 1 {
		t.Fatalf("list response=%#v calls=%d", listResponse, service.lists)
	}
	resolve := schema.Request{RequestID: "resolve", Method: schema.MethodEntryResolve, EntryResolveParams: &schema.EntryResolveParams{VirtualPath: stringPtr("/a"), RequestedProperties: []string{}}}
	response := runtime.Dispatch(context.Background(), resolve)
	if service.resolves != 1 || !response.OK || response.Error != nil {
		t.Fatalf("resolve response=%#v calls=%d", response, service.resolves)
	}
	encoded := schema.EncodeResponse(response)
	if _, err := schema.DecodeResponse(encoded, schema.MethodEntryResolve); err != nil {
		t.Fatalf("resolve round trip: %v wire=%s", err, encoded)
	}
}

func TestEntryListResolveDispatchCanonicalErrors(t *testing.T) {
	t.Parallel()
	tests := []struct {
		err  error
		code schema.ErrorCode
	}{
		{applicationentry.ErrInvalidSelector, schema.ErrorInvalidSelector},
		{applicationentry.ErrContextMismatch, schema.ErrorContextMismatch},
		{applicationentry.ErrScopeTooLarge, schema.ErrorScopeTooLarge},
		{applicationentry.ErrInvalidPageToken, schema.ErrorInvalidPageToken},
		{applicationentry.ErrPermissionDenied, schema.ErrorPermissionDenied},
		{applicationentry.ErrApplicationSourceUnavailable, schema.ErrorSourceUnavailable},
		{applicationentry.ErrApplicationSourceDeleted, schema.ErrorSourceDeleted},
		{applicationentry.ErrEntryNotFound, schema.ErrorEntryNotFound},
		{applicationentry.ErrApplicationAdapterFailure, schema.ErrorAdapterFailure},
		{ambiguousPropertySelectorError{}, schema.ErrorInvalidRequest},
		{unregisteredPropertyIDError{}, schema.ErrorInvalidRequest},
		{errors.New("secret backend detail"), schema.ErrorInternal},
	}
	for _, test := range tests {
		service := &recordingEntryService{listErr: test.err}
		runtime := NewWithEntryService("workspace", service)
		request := schema.Request{RequestID: "id", Method: schema.MethodEntryList, EntryListParams: &schema.EntryListParams{VirtualPath: "/", PageSize: 1, RequestedProperties: []string{}}}
		response := runtime.Dispatch(context.Background(), request)
		if response.Error == nil || response.Error.Code != test.code {
			t.Fatalf("err=%v response=%#v", test.err, response)
		}
	}
}

func stringPtr(value string) *string { return &value }

func entryResolveResultFixture(t *testing.T) applicationentry.ResolveResult {
	t.Helper()
	sourceID := "src:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	locator, _ := domainentry.NewLocatorRef("loc:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
	ref, err := domainentry.NewEntryRef(domainentry.DeriveEntryID(sourceID, "file", "object"), sourceID, "object", "file", locator, domainentry.IdentityStrengthLocator)
	if err != nil {
		t.Fatal(err)
	}
	revision, _ := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := domainentry.NewSourceRevision(revision)
	observedRevision, _ := domainentry.NewObservedRevision(1)
	observedAt := time.Unix(1, 0).UTC()
	freshness, _ := domainentry.NewFreshness(domainentry.FreshnessStateCurrent, observedAt, sourceRevision, nil, nil)
	availability, _ := domainentry.NewAvailability(domainentry.AvailabilityStateAvailable)
	snapshot, err := domainentry.NewCanonicalEntrySnapshot(ref, "object", nil, []domainentry.PropertyValue{}, sourceRevision, observedRevision, observedAt, nil, availability, freshness)
	if err != nil {
		t.Fatal(err)
	}
	path, _ := domainentry.NewResolvedVirtualPath("mount", "/object", "1")
	capabilities := domainentry.Capabilities{Readable: true}
	access, err := domainentry.NewCanonicalAccessContext(sourceID, "mount", path, nil, capabilities)
	if err != nil {
		t.Fatal(err)
	}
	return applicationentry.ResolveResult{EntryRef: ref, EntrySnapshot: snapshot, AccessContext: access, Capabilities: capabilities, Availability: availability, Freshness: freshness, SourceRevision: revision}
}

func unifiedListResultFixture(resolved applicationentry.ResolveResult) applicationentry.UnifiedListResult {
	return applicationentry.UnifiedListResult{
		Entries:           []applicationentry.CanonicalEntry{{EntryRef: resolved.EntryRef, EntrySnapshot: resolved.EntrySnapshot, AccessContext: resolved.AccessContext}},
		ObservedAt:        resolved.EntrySnapshot.ObservedAt,
		RevisionSummaries: []applicationentry.RevisionSummary{{SourceInstanceID: resolved.EntryRef.SourceInstanceID, MountID: resolved.AccessContext.MountID, SourceRevision: resolved.SourceRevision, ObservedRevision: resolved.EntrySnapshot.ObservedRevision}},
		Availabilities:    []applicationentry.SourceAvailability{{SourceInstanceID: resolved.EntryRef.SourceInstanceID, MountID: resolved.AccessContext.MountID, State: resolved.Availability.State}},
		Freshness:         []applicationentry.SourceFreshness{{SourceInstanceID: resolved.EntryRef.SourceInstanceID, MountID: resolved.AccessContext.MountID, State: resolved.Freshness.State, ObservedAt: resolved.Freshness.ObservedAt, SourceRevision: resolved.SourceRevision}},
		Warnings:          []applicationentry.ScopeWarning{},
	}
}

type pageSizeTooSmallError struct{}

func (pageSizeTooSmallError) Error() string { return "page_size_too_small" }
func (pageSizeTooSmallError) Unwrap() error { return applicationentry.ErrInvalidRequest }

// ambiguousPropertySelectorError와 unregisteredPropertyIDError는 애플리케이션
// 계층이 반환하는 감싸진 선택자 오류의 wire 형태를 재현한다.
type ambiguousPropertySelectorError struct{}

func (ambiguousPropertySelectorError) Error() string { return "ambiguous_property_selector" }
func (ambiguousPropertySelectorError) Unwrap() error {
	return applicationentry.ErrAmbiguousPropertySelector
}

type unregisteredPropertyIDError struct{}

func (unregisteredPropertyIDError) Error() string { return "unregistered_property_selector" }
func (unregisteredPropertyIDError) Unwrap() error { return applicationentry.ErrUnregisteredPropertyID }

func TestEntryPageSizeTooSmallStableMessage(t *testing.T) {
	service := &recordingEntryService{listErr: pageSizeTooSmallError{}}
	runtime := NewWithEntryService("workspace", service)
	request := schema.Request{RequestID: "id", Method: schema.MethodEntryList, EntryListParams: &schema.EntryListParams{VirtualPath: "/", PageSize: 1, RequestedProperties: []string{}}}
	response := runtime.Dispatch(context.Background(), request)
	if response.Error == nil || response.Error.Code != schema.ErrorInvalidRequest || response.Error.Message != "page_size_too_small" {
		t.Fatalf("response=%#v", response)
	}
	if got := string(schema.EncodeResponse(response)); got != `{"request_id":"id","ok":false,"error":{"code":"invalid_request","message":"page_size_too_small"}}` {
		t.Fatalf("wire=%s", got)
	}
}

func TestEntryRejectsServicePageOverflow(t *testing.T) {
	resolved := entryResolveResultFixture(t)
	result := unifiedListResultFixture(resolved)
	result.Entries = append(result.Entries, result.Entries[0])
	service := &recordingEntryService{listResult: result}
	runtime := NewWithEntryService("workspace", service)
	request := schema.Request{RequestID: "id", Method: schema.MethodEntryList, EntryListParams: &schema.EntryListParams{VirtualPath: "/", PageSize: 1, RequestedProperties: []string{}}}
	response := runtime.Dispatch(context.Background(), request)
	if response.Error == nil || response.Error.Code != schema.ErrorInternal {
		t.Fatalf("response=%#v", response)
	}
}
