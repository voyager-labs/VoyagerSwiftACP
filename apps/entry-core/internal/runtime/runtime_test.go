package runtime

import (
	"sync"
	"sync/atomic"
	"testing"

	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

func TestRuntimeStateTransitions(t *testing.T) {
	runtime := New()
	if got := runtime.State(); got != StateRunning {
		t.Fatalf("initial state = %q, want %q", got, StateRunning)
	}

	const transitions = 64
	var changed atomic.Int64
	var waitGroup sync.WaitGroup
	waitGroup.Add(transitions)
	for range transitions {
		go func() {
			defer waitGroup.Done()
			if runtime.BeginStopping() {
				changed.Add(1)
			}
		}()
	}
	waitGroup.Wait()

	if got := changed.Load(); got != 1 {
		t.Fatalf("successful transitions = %d, want 1", got)
	}
	if got := runtime.State(); got != StateStopping {
		t.Fatalf("final state = %q, want %q", got, StateStopping)
	}
	if runtime.BeginStopping() {
		t.Fatal("repeated stopping transition reported a state change")
	}
}

func TestDispatchResults(t *testing.T) {
	runtime := New()
	tests := []struct {
		name   string
		method schema.Method
		want   schema.Result
	}{
		{name: "ping", method: schema.MethodPing, want: schema.PingResult{Message: "pong"}},
		{name: "health", method: schema.MethodHealth, want: schema.HealthResult{Status: "healthy", State: "running"}},
		{name: "version", method: schema.MethodVersion, want: schema.VersionResult{AppVersion: "0.1.0-dev", ProtocolVersion: schema.ProtocolVersion}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			result, protocolError := runtime.Dispatch(request(test.method))
			if protocolError != nil {
				t.Fatalf("unexpected protocol error: %#v", protocolError)
			}
			if result != test.want {
				t.Fatalf("result = %#v, want %#v", result, test.want)
			}
		})
	}
}

func TestDispatchWhileStopping(t *testing.T) {
	runtime := New()
	runtime.BeginStopping()

	for _, method := range []schema.Method{schema.MethodPing, schema.MethodHealth, schema.MethodVersion} {
		t.Run(string(method), func(t *testing.T) {
			result, protocolError := runtime.Dispatch(request(method))
			if result != nil {
				t.Fatalf("result = %#v, want nil", result)
			}
			if protocolError == nil || protocolError.Code != schema.ErrorInternal {
				t.Fatalf("error = %#v, want %q", protocolError, schema.ErrorInternal)
			}
			if protocolError.Message != "internal error" {
				t.Fatalf("error message = %q, want canonical internal error", protocolError.Message)
			}
			if got := runtime.State(); got != StateStopping {
				t.Fatalf("state = %q, want %q", got, StateStopping)
			}
		})
	}
}

func TestAppVersionInjection(t *testing.T) {
	runtime := newWithAppVersion("9.8.7-test")
	result, protocolError := runtime.Dispatch(request(schema.MethodVersion))
	if protocolError != nil {
		t.Fatalf("unexpected protocol error: %#v", protocolError)
	}
	want := schema.VersionResult{AppVersion: "9.8.7-test", ProtocolVersion: schema.ProtocolVersion}
	if result != want {
		t.Fatalf("result = %#v, want %#v", result, want)
	}
}

func TestDispatchUnexpectedMethod(t *testing.T) {
	runtime := New()
	result, protocolError := runtime.Dispatch(request(schema.Method("future")))
	if result != nil {
		t.Fatalf("result = %#v, want nil", result)
	}
	if protocolError == nil || protocolError.Code != schema.ErrorInternal || protocolError.Message != "internal error" {
		t.Fatalf("error = %#v, want canonical internal error", protocolError)
	}
}

func request(method schema.Method) schema.Request {
	return schema.Request{
		RequestID:       "request-1",
		ProtocolVersion: schema.ProtocolVersion,
		Method:          method,
		Params:          schema.EmptyParams{},
	}
}
