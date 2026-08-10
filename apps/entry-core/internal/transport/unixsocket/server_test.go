package unixsocket

import (
	"bytes"
	"errors"
	"io"
	"log"
	"net"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	entryruntime "github.com/voyager-labs/voyager-app/apps/entry-core/internal/runtime"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

func TestServerOneShotEOFAndDispatch(t *testing.T) {
	server, path := runningServer(t, nil, testDurations())
	for _, method := range []schema.Method{schema.MethodPing, schema.MethodHealth, schema.MethodVersion} {
		wire := requestWireFor(method, "request-1")
		responseWire := exchange(t, path, wire)
		response, err := schema.DecodeResponse(responseWire, method)
		if err != nil || !response.OK || response.RequestID != "request-1" {
			t.Fatalf("response = %#v, error = %v", response, err)
		}
	}
	shutdownServer(t, server, nil)
}

func TestServerRequestSizeBoundary(t *testing.T) {
	server, path := runningServer(t, nil, testDurations())
	valid := requestWireFor(schema.MethodPing, "request-1")
	atLimit := append(valid, bytes.Repeat([]byte{' '}, schema.MaxWireBytes-len(valid))...)
	response, err := schema.DecodeResponse(exchange(t, path, atLimit), schema.MethodPing)
	if err != nil || !response.OK {
		t.Fatalf("65,536-byte response = %#v, %v", response, err)
	}

	overLimit := append(atLimit, ' ')
	response, err = schema.DecodeResponse(exchange(t, path, overLimit), schema.MethodPing)
	if err != nil || response.OK || response.Error.Code != schema.ErrorRequestTooLarge || response.RequestID != "" {
		t.Fatalf("65,537-byte response = %#v, %v", response, err)
	}
	response, err = schema.DecodeResponse(exchange(t, path, requestWireFor(schema.MethodPing, "request-2")), schema.MethodPing)
	if err != nil || !response.OK {
		t.Fatalf("valid response after oversized = %#v, %v", response, err)
	}
	shutdownServer(t, server, nil)
}

func TestServerMalformedThenValidPing(t *testing.T) {
	var logs bytes.Buffer
	logger := log.New(&logs, "", 0)
	server, path := runningServer(t, logger, testDurations())
	secret := "REQUEST-SECRET-MARKER"
	malformed := []byte(`{"request_id":"raw-id", "params":{"secret":"` + secret)
	response, err := schema.DecodeResponse(exchange(t, path, malformed), schema.MethodPing)
	if err != nil || response.OK || response.Error.Code != schema.ErrorInvalidRequest {
		t.Fatalf("malformed response = %#v, %v", response, err)
	}
	if strings.Contains(logs.String(), secret) || strings.Contains(logs.String(), "params") || strings.Contains(logs.String(), "raw-id") {
		t.Fatalf("logs contain request data: %q", logs.String())
	}

	response, err = schema.DecodeResponse(exchange(t, path, requestWireFor(schema.MethodPing, "request-2")), schema.MethodPing)
	if err != nil || !response.OK {
		t.Fatalf("valid response after malformed = %#v, %v", response, err)
	}
	shutdownServer(t, server, nil)
}

func TestServerEmptyTruncatedAndSecondValue(t *testing.T) {
	server, path := runningServer(t, nil, testDurations())
	for _, wire := range [][]byte{
		nil,
		[]byte(`{"request_id":`),
		append(requestWireFor(schema.MethodPing, "request-1"), []byte(` {}`)...),
	} {
		response, err := schema.DecodeResponse(exchange(t, path, wire), schema.MethodPing)
		if err != nil || response.OK || response.Error.Code != schema.ErrorInvalidRequest {
			t.Fatalf("invalid wire response = %#v, %v", response, err)
		}
	}
	shutdownServer(t, server, nil)
}

func TestServerReadDeadlineIsAbsoluteFromAccept(t *testing.T) {
	durations := testDurations()
	durations.readTimeout = 80 * time.Millisecond
	server, path := runningServer(t, nil, durations)
	connection := dialUnix(t, path)
	defer connection.Close()
	if _, err := connection.Write([]byte(`{"request_id":"slow`)); err != nil {
		t.Fatal(err)
	}
	time.Sleep(120 * time.Millisecond)
	_ = connection.CloseWrite()
	_ = connection.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
	wire, err := io.ReadAll(connection)
	if err != nil && !errors.Is(err, net.ErrClosed) {
		t.Fatal(err)
	}
	if len(wire) != 0 {
		t.Fatalf("read timeout returned protocol response %q", wire)
	}
	shutdownServer(t, server, nil)
}

func TestServerPanicContainment(t *testing.T) {
	server, path := runningServer(t, nil, testDurations())
	server.setHandler(func(net.Conn) { panic("contained") })
	connection := dialUnix(t, path)
	_ = connection.CloseWrite()
	_ = connection.SetReadDeadline(time.Now().Add(time.Second))
	_, _ = io.ReadAll(connection)
	_ = connection.Close()

	server.setHandler(server.handleConnection)
	response, err := schema.DecodeResponse(exchange(t, path, requestWireFor(schema.MethodPing, "request-2")), schema.MethodPing)
	if err != nil || !response.OK {
		t.Fatalf("valid response after panic = %#v, %v", response, err)
	}
	shutdownServer(t, server, nil)
}

func TestServerWriteDeadlineAndPartialFailure(t *testing.T) {
	durations := testDurations()
	runtime := entryruntime.New()
	server := &Server{runtime: runtime, durations: durations}
	connection := &recordingServerConn{
		reader:   bytes.NewReader(requestWireFor(schema.MethodPing, "request-1")),
		writeErr: io.ErrClosedPipe,
	}
	before := time.Now().Add(durations.writeTimeout)
	server.handleConnection(connection)
	after := time.Now().Add(durations.writeTimeout)

	connection.mu.Lock()
	defer connection.mu.Unlock()
	if connection.writeDeadline.Before(before) || connection.writeDeadline.After(after) {
		t.Fatalf("write deadline = %v, want between %v and %v", connection.writeDeadline, before, after)
	}
	if connection.writeCalls != 1 {
		t.Fatalf("Write() calls = %d, want one after partial failure", connection.writeCalls)
	}
	if connection.written == 0 {
		t.Fatal("partial write was not exercised")
	}
}

func TestServerConnectionResetDoesNotWriteResponse(t *testing.T) {
	server := &Server{runtime: entryruntime.New(), durations: testDurations()}
	connection := &recordingServerConn{readErr: syscall.ECONNRESET}
	server.handleConnection(connection)

	connection.mu.Lock()
	defer connection.mu.Unlock()
	if connection.writeCalls != 0 {
		t.Fatalf("Write() calls after reset = %d, want 0", connection.writeCalls)
	}
}

func runningServer(t *testing.T, logger *log.Logger, durations serverDurations) (*Server, string) {
	t.Helper()
	path := filepath.Join(secureTempDir(t), "entry.sock")
	server, err := newServer(path, entryruntime.New(), logger, durations)
	if err != nil {
		t.Fatal(err)
	}
	go func() { _ = server.Serve() }()
	t.Cleanup(func() {
		if server.runtime.State() != entryruntime.StateStopping {
			_ = server.Shutdown(nil)
		}
	})
	return server, path
}

func startServer(t *testing.T, path string, durations serverDurations) *Server {
	t.Helper()
	server, err := newServer(path, entryruntime.New(), nil, durations)
	if err != nil {
		t.Fatal(err)
	}
	go func() { _ = server.Serve() }()
	return server
}

func shutdownServer(t *testing.T, server *Server, force <-chan struct{}) {
	t.Helper()
	if err := server.Shutdown(force); err != nil {
		t.Fatalf("Shutdown() error = %v", err)
	}
}

func requestWireFor(method schema.Method, requestID string) []byte {
	return []byte(`{"request_id":"` + requestID + `","method":"` + string(method) + `","params":{}}`)
}

func exchange(t *testing.T, path string, wire []byte) []byte {
	t.Helper()
	connection := dialUnix(t, path)
	if len(wire) > 0 {
		if _, err := connection.Write(wire); err != nil {
			t.Fatal(err)
		}
	}
	if err := connection.CloseWrite(); err != nil {
		t.Fatal(err)
	}
	response, err := io.ReadAll(connection)
	if err != nil {
		t.Fatal(err)
	}
	if err := connection.Close(); err != nil {
		t.Fatal(err)
	}
	return response
}

func dialUnix(t *testing.T, path string) *net.UnixConn {
	t.Helper()
	connection, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	return connection
}

type recordingServerConn struct {
	mu            sync.Mutex
	reader        *bytes.Reader
	readErr       error
	writeErr      error
	writeDeadline time.Time
	writeCalls    int
	written       int
}

func (connection *recordingServerConn) Read(buffer []byte) (int, error) {
	if connection.readErr != nil {
		return 0, connection.readErr
	}
	return connection.reader.Read(buffer)
}

func (connection *recordingServerConn) Write(buffer []byte) (int, error) {
	connection.mu.Lock()
	defer connection.mu.Unlock()
	connection.writeCalls++
	written := len(buffer) / 2
	connection.written += written
	return written, connection.writeErr
}

func (connection *recordingServerConn) Close() error                    { return nil }
func (connection *recordingServerConn) LocalAddr() net.Addr             { return fakeAddr("local") }
func (connection *recordingServerConn) RemoteAddr() net.Addr            { return fakeAddr("remote") }
func (connection *recordingServerConn) SetDeadline(time.Time) error     { return nil }
func (connection *recordingServerConn) SetReadDeadline(time.Time) error { return nil }
func (connection *recordingServerConn) SetWriteDeadline(deadline time.Time) error {
	connection.mu.Lock()
	defer connection.mu.Unlock()
	connection.writeDeadline = deadline
	return nil
}
