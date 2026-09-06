package unixsocket

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

func TestClientRoundTrip(t *testing.T) {
	methods := []struct {
		method schema.Method
		result schema.Result
	}{
		{method: schema.MethodPing, result: schema.PingResult{Message: "pong"}},
		{method: schema.MethodHealth, result: schema.HealthResult{Status: "healthy", State: "running"}},
		{method: schema.MethodVersion, result: schema.VersionResult{AppVersion: "0.1.0-dev"}},
	}

	for _, test := range methods {
		t.Run(string(test.method), func(t *testing.T) {
			socketPath, listener := unixListener(t)
			request := validClientRequest(test.method)
			peerDone := make(chan error, 1)
			go func() {
				connection, err := listener.AcceptUnix()
				if err != nil {
					peerDone <- err
					return
				}
				defer connection.Close()

				wire, err := io.ReadAll(connection)
				if err != nil {
					peerDone <- err
					return
				}
				want := fmt.Sprintf(`{"request_id":"request-1","method":"%s","params":{}}`, test.method)
				if string(wire) != want {
					peerDone <- fmt.Errorf("request = %q, want %q", wire, want)
					return
				}
				decoded, trustworthyID, protocolError := schema.DecodeRequest(wire)
				if protocolError != nil || trustworthyID != request.RequestID || decoded.Method != test.method {
					peerDone <- fmt.Errorf("decoded request = %#v, id = %q, error = %#v", decoded, trustworthyID, protocolError)
					return
				}
				_, err = connection.Write(schema.EncodeResponse(schema.NewSuccessResponse(request.RequestID, test.result)))
				peerDone <- err
			}()

			response, err := NewClient().Call(context.Background(), socketPath, request)
			if err != nil {
				t.Fatalf("Call() error = %v", err)
			}
			if !response.OK || response.RequestID != request.RequestID {
				t.Fatalf("response = %#v", response)
			}
			if err := <-peerDone; err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestClientConditionQueryRequestAwareReconciliation(t *testing.T) {
	propertyID := "00000000-0000-0000-8000-000000000001"
	entryID := "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	operand := schema.PropertyConditionOperand{}
	_ = operand
	conditionPropertyID := "00000000-0000-0000-8000-000000000002"
	params := &schema.PropertyConditionQueryParams{
		Targets: []schema.PropertyTargetSelector{
			{Kind: "local_path", LocalPath: "/a"},
		},
		Combinator: "all",
		Conditions: []schema.PropertyCondition{{
			PropertyID: conditionPropertyID,
			Operator:   "exists",
			Operand:    schema.PropertyConditionOperand{Kind: "none"},
		}},
		ProjectionPropertyIDs: []string{propertyID},
		EvaluationDate:        "2026-09-01",
		PageSize:              1,
	}

	newConditionQueryRequest := func() schema.Request {
		return schema.Request{
			RequestID:                    "request-1",
			Method:                       schema.MethodPropertyConditionQuery,
			PropertyConditionQueryParams: params,
		}
	}
	invalidResult := schema.PropertyConditionQueryResult{
		Items: []schema.PropertyConditionQueryItem{{
			CandidateIndex: 7,
			EntryID:        entryID,
			Projection:     []schema.PropertyAssignment{},
		}},
		UnresolvedCandidateIndices: []int{},
		CatalogVersion:             domainentry.ConditionCatalogVersion,
		HasMore:                    false,
	}
	validResult := schema.PropertyConditionQueryResult{
		Items: []schema.PropertyConditionQueryItem{{
			CandidateIndex: 0,
			EntryID:        entryID,
			Projection:     []schema.PropertyAssignment{},
		}},
		UnresolvedCandidateIndices: []int{},
		CatalogVersion:             domainentry.ConditionCatalogVersion,
		HasMore:                    false,
	}

	t.Run("candidate beyond requested targets rejected", func(t *testing.T) {
		socketPath, listener := unixListener(t)
		peerDone := make(chan error, 1)
		go func() {
			connection, err := listener.AcceptUnix()
			if err != nil {
				peerDone <- err
				return
			}
			defer connection.Close()
			if _, err := io.ReadAll(connection); err != nil {
				peerDone <- err
				return
			}
			_, err = connection.Write(schema.EncodeResponse(
				schema.NewSuccessResponse("request-1", invalidResult),
			))
			peerDone <- err
		}()

		_, err := NewClient().Call(context.Background(), socketPath, newConditionQueryRequest())
		var protocolError *ProtocolError
		if err == nil || !errors.As(err, &protocolError) || protocolError.Reason != "response request mismatch" {
			t.Fatalf("out-of-bounds candidate accepted: %v", err)
		}
		if err := <-peerDone; err != nil {
			t.Fatal(err)
		}
	})

	t.Run("valid page accepted", func(t *testing.T) {
		socketPath, listener := unixListener(t)
		peerDone := make(chan error, 1)
		go func() {
			connection, err := listener.AcceptUnix()
			if err != nil {
				peerDone <- err
				return
			}
			defer connection.Close()
			if _, err := io.ReadAll(connection); err != nil {
				peerDone <- err
				return
			}
			_, err = connection.Write(schema.EncodeResponse(
				schema.NewSuccessResponse("request-1", validResult),
			))
			peerDone <- err
		}()

		response, err := NewClient().Call(context.Background(), socketPath, newConditionQueryRequest())
		if err != nil {
			t.Fatalf("valid page rejected: %v", err)
		}
		if !response.OK {
			t.Fatalf("response = %#v", response)
		}
		if err := <-peerDone; err != nil {
			t.Fatal(err)
		}
	})
}

func TestClientAbsoluteDeadline(t *testing.T) {
	start := time.Now()
	connection := newFakeConn(validResponse("request-1", schema.MethodPing))
	var dialDeadline time.Time
	var network, address string
	client := newClient(func(ctx context.Context, gotNetwork, gotAddress string) (net.Conn, error) {
		network, address = gotNetwork, gotAddress
		var ok bool
		dialDeadline, ok = ctx.Deadline()
		if !ok {
			return nil, errors.New("dial context has no deadline")
		}
		return connection, nil
	}, func() time.Time { return start })

	response, err := client.Call(context.Background(), "/tmp/entry-core-test.sock", validClientRequest(schema.MethodPing))
	if err != nil || !response.OK {
		t.Fatalf("Call() = %#v, %v", response, err)
	}
	wantDeadline := start.Add(2 * time.Second)
	if !dialDeadline.Equal(wantDeadline) {
		t.Fatalf("dial deadline = %v, want %v", dialDeadline, wantDeadline)
	}
	if network != "unix" || address != "/tmp/entry-core-test.sock" {
		t.Fatalf("dial = %q %q", network, address)
	}
	if deadlines := connection.deadlines(); len(deadlines) != 1 || !deadlines[0].Equal(wantDeadline) {
		t.Fatalf("connection deadlines = %v, want one %v", deadlines, wantDeadline)
	}
	if !connection.closeWriteCalled() || !connection.closed() {
		t.Fatalf("CloseWrite = %t, Close = %t", connection.closeWriteCalled(), connection.closed())
	}
}

func TestClientUsesEarlierContextDeadlineForConnection(t *testing.T) {
	start := time.Now()
	contextDeadline := start.Add(time.Second)
	ctx, cancel := context.WithDeadline(context.Background(), contextDeadline)
	defer cancel()

	connection := newFakeConn(validResponse("request-1", schema.MethodPing))
	var dialDeadline time.Time
	client := newClient(func(ctx context.Context, _, _ string) (net.Conn, error) {
		var ok bool
		dialDeadline, ok = ctx.Deadline()
		if !ok {
			return nil, errors.New("dial context has no deadline")
		}
		return connection, nil
	}, func() time.Time { return start })

	response, err := client.Call(ctx, "/tmp/entry-core-test.sock", validClientRequest(schema.MethodPing))
	if err != nil || !response.OK {
		t.Fatalf("Call() = %#v, %v", response, err)
	}
	if !dialDeadline.Equal(contextDeadline) {
		t.Fatalf("dial deadline = %v, want context deadline %v", dialDeadline, contextDeadline)
	}
	if deadlines := connection.deadlines(); len(deadlines) != 1 || !deadlines[0].Equal(contextDeadline) {
		t.Fatalf("connection deadlines = %v, want context deadline %v", deadlines, contextDeadline)
	}
}

func TestClientResponseValidation(t *testing.T) {
	tests := []struct {
		name   string
		method schema.Method
		wire   []byte
		server bool
	}{
		{name: "ping valid", method: schema.MethodPing, wire: validResponse("request-1", schema.MethodPing)},
		{name: "health valid", method: schema.MethodHealth, wire: validResponse("request-1", schema.MethodHealth)},
		{name: "version valid", method: schema.MethodVersion, wire: validResponse("request-1", schema.MethodVersion)},
		{name: "server error", method: schema.MethodPing, wire: []byte(`{"request_id":"request-1","ok":false,"error":{"code":"internal_error","message":"internal error"}}`), server: true},
		{name: "empty error ID", method: schema.MethodPing, wire: []byte(`{"request_id":"","ok":false,"error":{"code":"invalid_request","message":"request is invalid"}}`)},
		{name: "mismatched ID", method: schema.MethodPing, wire: validResponse("other", schema.MethodPing)},
		{name: "legacy protocol field", method: schema.MethodPing, wire: []byte(`{"request_id":"request-1","protocol_version":2,"ok":true,"result":{"message":"pong"}}`)},
		{name: "wrong method result", method: schema.MethodPing, wire: validResponse("request-1", schema.MethodHealth)},
		{name: "invalid error code", method: schema.MethodPing, wire: []byte(`{"request_id":"request-1","ok":false,"error":{"code":"future","message":"future"}}`)},
		{name: "both result and error", method: schema.MethodPing, wire: []byte(`{"request_id":"request-1","ok":true,"result":{"message":"pong"},"error":{"code":"internal_error","message":"internal error"}}`)},
		{name: "neither result nor error", method: schema.MethodPing, wire: []byte(`{"request_id":"request-1","ok":true}`)},
		{name: "unknown field", method: schema.MethodPing, wire: []byte(`{"request_id":"request-1","ok":true,"result":{"message":"pong"},"extra":true}`)},
		{name: "duplicate field", method: schema.MethodPing, wire: []byte(`{"request_id":"request-1","request_id":"request-1","ok":true,"result":{"message":"pong"}}`)},
		{name: "malformed", method: schema.MethodPing, wire: []byte(`{"request_id":`)},
		{name: "multiple JSON values", method: schema.MethodPing, wire: append(validResponse("request-1", schema.MethodPing), []byte(` {}`)...)},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			connection := newFakeConn(test.wire)
			client := fakeClient(connection)
			response, err := client.Call(context.Background(), "/tmp/entry-core-test.sock", validClientRequest(test.method))

			switch {
			case test.server:
				var serverError *ServerError
				if !errors.As(err, &serverError) || serverError.Code != schema.ErrorInternal {
					t.Fatalf("error = %#v, want ServerError", err)
				}
				if response != (schema.Response{}) {
					t.Fatalf("server failure returned partial response: %#v", response)
				}
			case strings.HasSuffix(test.name, "valid"):
				if err != nil || !response.OK {
					t.Fatalf("Call() = %#v, %v", response, err)
				}
			default:
				var protocolError *ProtocolError
				if !errors.As(err, &protocolError) {
					t.Fatalf("error = %#v, want ProtocolError", err)
				}
				if response != (schema.Response{}) {
					t.Fatalf("invalid response returned partial response: %#v", response)
				}
			}
			if !connection.closed() {
				t.Fatal("connection was not closed")
			}
		})
	}
}

func TestClientResponseSizeBoundary(t *testing.T) {
	valid := validResponse("request-1", schema.MethodPing)
	atLimit := append(valid, bytes.Repeat([]byte{' '}, schema.MaxWireBytes-len(valid))...)
	overLimit := append(append([]byte(nil), atLimit...), ' ')

	for _, test := range []struct {
		name    string
		wire    []byte
		wantErr bool
	}{
		{name: "65536 bytes", wire: atLimit},
		{name: "65537 bytes", wire: overLimit, wantErr: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			response, err := fakeClient(newFakeConn(test.wire)).Call(context.Background(), "/tmp/entry-core-test.sock", validClientRequest(schema.MethodPing))
			if test.wantErr {
				var protocolError *ProtocolError
				if !errors.As(err, &protocolError) || response != (schema.Response{}) {
					t.Fatalf("Call() = %#v, %#v", response, err)
				}
				return
			}
			if err != nil || !response.OK {
				t.Fatalf("Call() = %#v, %v", response, err)
			}
		})
	}
}

func TestClientTransportFailuresCloseConnection(t *testing.T) {
	tests := []struct {
		name       string
		connection *fakeConn
	}{
		{name: "write", connection: &fakeConn{writeErr: errors.New("write failed")}},
		{name: "close write", connection: &fakeConn{closeWriteErr: errors.New("close write failed")}},
		{name: "read", connection: &fakeConn{readErr: errors.New("read failed")}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			response, err := fakeClient(test.connection).Call(context.Background(), "/tmp/entry-core-test.sock", validClientRequest(schema.MethodPing))
			var transportError *TransportError
			if !errors.As(err, &transportError) || response != (schema.Response{}) {
				t.Fatalf("Call() = %#v, %#v", response, err)
			}
			if !test.connection.closed() {
				t.Fatal("connection was not closed")
			}
		})
	}
}

func TestClientTotalTimeout(t *testing.T) {
	socketPath, listener := unixListener(t)
	accepted := make(chan *net.UnixConn, 1)
	peerDone := make(chan struct{})
	go func() {
		connection, err := listener.AcceptUnix()
		if err != nil {
			close(peerDone)
			return
		}
		accepted <- connection
		_, _ = io.ReadAll(connection)
		<-peerDone
		_ = connection.Close()
	}()

	started := time.Now()
	response, err := NewClient().Call(context.Background(), socketPath, validClientRequest(schema.MethodPing))
	elapsed := time.Since(started)
	var transportError *TransportError
	if !errors.As(err, &transportError) || response != (schema.Response{}) {
		t.Fatalf("Call() = %#v, %#v", response, err)
	}
	if elapsed < 1500*time.Millisecond || elapsed > 3*time.Second {
		t.Fatalf("elapsed = %v, want one approximately 2s total deadline", elapsed)
	}
	select {
	case connection := <-accepted:
		_ = connection
	default:
		t.Fatal("peer did not accept connection")
	}
	close(peerDone)
}

func TestClientCancellationAfterDialInterruptsRead(t *testing.T) {
	socketPath, listener := unixListener(t)
	requestRead := make(chan struct{})
	releasePeer := make(chan struct{})
	var releaseOnce sync.Once
	release := func() { releaseOnce.Do(func() { close(releasePeer) }) }
	defer release()

	peerDone := make(chan error, 1)
	go func() {
		connection, err := listener.AcceptUnix()
		if err != nil {
			peerDone <- err
			return
		}
		defer connection.Close()
		if _, err := io.ReadAll(connection); err != nil {
			peerDone <- err
			return
		}
		close(requestRead)
		<-releasePeer
		peerDone <- nil
	}()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	type callResult struct {
		response schema.Response
		err      error
	}
	callDone := make(chan callResult, 1)
	go func() {
		response, err := NewClient().Call(ctx, socketPath, validClientRequest(schema.MethodPing))
		callDone <- callResult{response: response, err: err}
	}()

	<-requestRead
	started := time.Now()
	cancel()
	select {
	case result := <-callDone:
		if result.response != (schema.Response{}) || !errors.Is(result.err, context.Canceled) {
			t.Fatalf("Call() = %#v, %#v, want context cancellation", result.response, result.err)
		}
		var transportError *TransportError
		if !errors.As(result.err, &transportError) || transportError.Phase != "read" {
			t.Fatalf("Call() error = %#v, want read TransportError", result.err)
		}
		if elapsed := time.Since(started); elapsed > 300*time.Millisecond {
			t.Fatalf("canceled Call() took %v", elapsed)
		}
	case <-time.After(300 * time.Millisecond):
		release()
		result := <-callDone
		t.Fatalf("Call() ignored cancellation: response = %#v, error = %#v", result.response, result.err)
	}

	release()
	if err := <-peerDone; err != nil {
		t.Fatal(err)
	}
}

func TestClientRequiresAbsoluteSocketPath(t *testing.T) {
	response, err := NewClient().Call(context.Background(), "relative.sock", validClientRequest(schema.MethodPing))
	var transportError *TransportError
	if !errors.As(err, &transportError) || response != (schema.Response{}) {
		t.Fatalf("Call() = %#v, %#v", response, err)
	}
}

func validClientRequest(method schema.Method) schema.Request {
	return schema.Request{RequestID: "request-1", Method: method, Params: schema.EmptyParams{}}
}

func validResponse(requestID string, method schema.Method) []byte {
	var result schema.Result
	switch method {
	case schema.MethodPing:
		result = schema.PingResult{Message: "pong"}
	case schema.MethodHealth:
		result = schema.HealthResult{Status: "healthy", State: "running"}
	case schema.MethodVersion:
		result = schema.VersionResult{AppVersion: "0.1.0-dev"}
	default:
		panic("unsupported test method")
	}
	return schema.EncodeResponse(schema.NewSuccessResponse(requestID, result))
}

func unixListener(t *testing.T) (string, *net.UnixListener) {
	t.Helper()
	directory, err := os.MkdirTemp("", "ec-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	socketPath := filepath.Join(directory, "socket")
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: socketPath, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	return socketPath, listener
}

func fakeClient(connection net.Conn) *Client {
	return newClient(func(context.Context, string, string) (net.Conn, error) {
		return connection, nil
	}, time.Now)
}

type fakeConn struct {
	mu            sync.Mutex
	reader        *bytes.Reader
	writeErr      error
	closeWriteErr error
	readErr       error
	closedValue   bool
	closeWrite    bool
	setDeadlines  []time.Time
}

func newFakeConn(response []byte) *fakeConn {
	return &fakeConn{reader: bytes.NewReader(response)}
}

func (connection *fakeConn) Read(buffer []byte) (int, error) {
	if connection.readErr != nil {
		return 0, connection.readErr
	}
	if connection.reader == nil {
		return 0, io.EOF
	}
	return connection.reader.Read(buffer)
}

func (connection *fakeConn) Write(buffer []byte) (int, error) {
	if connection.writeErr != nil {
		return 0, connection.writeErr
	}
	return len(buffer), nil
}

func (connection *fakeConn) Close() error {
	connection.mu.Lock()
	defer connection.mu.Unlock()
	connection.closedValue = true
	return nil
}

func (connection *fakeConn) CloseWrite() error {
	connection.mu.Lock()
	defer connection.mu.Unlock()
	connection.closeWrite = true
	return connection.closeWriteErr
}

func (connection *fakeConn) LocalAddr() net.Addr  { return fakeAddr("local") }
func (connection *fakeConn) RemoteAddr() net.Addr { return fakeAddr("remote") }
func (connection *fakeConn) SetReadDeadline(time.Time) error {
	return errors.New("unexpected read deadline")
}
func (connection *fakeConn) SetWriteDeadline(time.Time) error {
	return errors.New("unexpected write deadline")
}
func (connection *fakeConn) SetDeadline(deadline time.Time) error {
	connection.mu.Lock()
	defer connection.mu.Unlock()
	connection.setDeadlines = append(connection.setDeadlines, deadline)
	return nil
}

func (connection *fakeConn) deadlines() []time.Time {
	connection.mu.Lock()
	defer connection.mu.Unlock()
	return append([]time.Time(nil), connection.setDeadlines...)
}

func (connection *fakeConn) closed() bool {
	connection.mu.Lock()
	defer connection.mu.Unlock()
	return connection.closedValue
}

func (connection *fakeConn) closeWriteCalled() bool {
	connection.mu.Lock()
	defer connection.mu.Unlock()
	return connection.closeWrite
}

type fakeAddr string

func (address fakeAddr) Network() string { return "unix" }
func (address fakeAddr) String() string  { return string(address) }
