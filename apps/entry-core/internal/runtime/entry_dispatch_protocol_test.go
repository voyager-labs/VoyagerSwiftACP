package runtime

import (
	"context"
	"testing"

	applicationentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

func TestCoreMethodDispatch(t *testing.T) {
	runtime := New()
	response := runtime.Dispatch(context.Background(), schema.Request{RequestID: "current", Method: schema.MethodPing, Params: schema.EmptyParams{}})
	if !response.OK || response.Result != (schema.PingResult{Message: "pong"}) {
		t.Fatalf("response=%#v", response)
	}
}

func TestProductionMethodGate(t *testing.T) {
	runtime := New()
	tests := []struct {
		request schema.Request
		code    schema.ErrorCode
	}{
		{request: schema.Request{RequestID: "id", Method: schema.Method("future")}, code: schema.ErrorUnknownMethod},
		{request: schema.Request{RequestID: "id", Method: schema.MethodEntryList}, code: schema.ErrorUnknownMethod},
		{request: schema.Request{RequestID: "id", Method: schema.MethodEntryResolve}, code: schema.ErrorUnknownMethod},
	}
	for _, test := range tests {
		response := runtime.Dispatch(context.Background(), test.request)
		if response.Error == nil || response.Error.Code != test.code {
			t.Fatalf("request=%#v response=%#v want=%q", test.request, response, test.code)
		}
	}
}

type blockingEntryService struct {
	started chan struct{}
	release chan struct{}
	result  applicationentry.UnifiedListResult
}

func (service *blockingEntryService) UnifiedList(context.Context, applicationentry.UnifiedListRequest) (applicationentry.UnifiedListResult, error) {
	close(service.started)
	<-service.release
	return service.result, nil
}
func (service *blockingEntryService) ResolveEntry(context.Context, applicationentry.ResolveRequest) (applicationentry.ResolveResult, error) {
	return applicationentry.ResolveResult{}, nil
}

func TestEntryListDispatchReleasesLifecycleLock(t *testing.T) {
	resolved := entryResolveResultFixture(t)
	service := &blockingEntryService{started: make(chan struct{}), release: make(chan struct{}), result: unifiedListResultFixture(resolved)}
	runtime := NewWithEntryService("workspace", service)
	done := make(chan struct{})
	go func() {
		runtime.Dispatch(context.Background(), schema.Request{RequestID: "id", Method: schema.MethodEntryList, EntryListParams: &schema.EntryListParams{VirtualPath: "/", PageSize: 1, RequestedProperties: []string{}}})
		close(done)
	}()
	<-service.started
	if !runtime.BeginStopping() {
		t.Fatal("lifecycle lock held during service I/O")
	}
	close(service.release)
	<-done
}
