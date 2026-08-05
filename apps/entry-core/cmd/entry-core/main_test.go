package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"strings"
	"testing"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/transport/unixsocket"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

type clientFunc func(context.Context, string, schema.Request) (schema.Response, error)

func (function clientFunc) Call(ctx context.Context, socketPath string, request schema.Request) (schema.Response, error) {
	return function(ctx, socketPath, request)
}

type errorReader struct {
	err error
}

func (reader errorReader) Read([]byte) (int, error) {
	return 0, reader.err
}

func TestCLICommands(t *testing.T) {
	tests := []struct {
		command string
		result  schema.Result
		stdout  string
	}{
		{command: "ping", result: schema.PingResult{Message: "pong"}, stdout: "{\"message\":\"pong\"}\n"},
		{command: "health", result: schema.HealthResult{Status: "healthy", State: "running"}, stdout: "{\"status\":\"healthy\",\"state\":\"running\"}\n"},
		{command: "version", result: schema.VersionResult{AppVersion: "0.1.0-dev", ProtocolVersion: schema.ProtocolVersion}, stdout: "{\"app_version\":\"0.1.0-dev\",\"protocol_version\":1}\n"},
	}

	for _, test := range tests {
		t.Run(test.command, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			client := clientFunc(func(_ context.Context, socketPath string, request schema.Request) (schema.Response, error) {
				if socketPath != "/tmp/entry-core.sock" {
					t.Fatalf("socket path = %q", socketPath)
				}
				if request.RequestID != "000102030405060708090a0b0c0d0e0f" {
					t.Fatalf("request ID = %q", request.RequestID)
				}
				if request.ProtocolVersion != schema.ProtocolVersion || request.Method != schema.Method(test.command) || request.Params != (schema.EmptyParams{}) {
					t.Fatalf("request = %#v", request)
				}
				return schema.NewSuccessResponse(request.RequestID, test.result), nil
			})

			exitCode := run(context.Background(), []string{"--socket", "/tmp/entry-core.sock", test.command}, bytes.NewReader([]byte{
				0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
				0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
			}), &stdout, &stderr, client)

			if exitCode != 0 || stdout.String() != test.stdout || stderr.Len() != 0 {
				t.Fatalf("run() = exit %d, stdout %q, stderr %q", exitCode, stdout.String(), stderr.String())
			}
		})
	}
}

func TestCLIUsageErrors(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{name: "missing arguments"},
		{name: "missing socket value", args: []string{"--socket"}},
		{name: "empty socket", args: []string{"--socket", "", "ping"}},
		{name: "relative socket", args: []string{"--socket", "entry-core.sock", "ping"}},
		{name: "unknown command", args: []string{"--socket", "/tmp/entry-core.sock", "status"}},
		{name: "unknown flag", args: []string{"--other", "/tmp/entry-core.sock", "ping"}},
		{name: "request ID flag", args: []string{"--socket", "/tmp/entry-core.sock", "--request-id", "ping"}},
		{name: "extra positional", args: []string{"--socket", "/tmp/entry-core.sock", "ping", "extra"}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			clientCalled := false
			client := clientFunc(func(context.Context, string, schema.Request) (schema.Response, error) {
				clientCalled = true
				return schema.Response{}, errors.New("must not be called")
			})

			exitCode := run(context.Background(), test.args, errorReader{err: errors.New("random must not be read")}, &stdout, &stderr, client)

			if exitCode != 2 || stdout.Len() != 0 || stderr.String() != usageMessage || clientCalled {
				t.Fatalf("run() = exit %d, stdout %q, stderr %q, client called %t", exitCode, stdout.String(), stderr.String(), clientCalled)
			}
		})
	}
}

func TestCLITransportErrors(t *testing.T) {
	secret := "secret-request-id-and-payload"
	tests := []struct {
		name       string
		err        error
		wantStderr string
	}{
		{name: "transport dial", err: &unixsocket.TransportError{Phase: "dial", Err: errors.New(secret)}, wantStderr: "entry-core: transport failure\n"},
		{name: "transport timeout", err: &unixsocket.TransportError{Phase: "read", Err: context.DeadlineExceeded}, wantStderr: "entry-core: transport failure\n"},
		{name: "request ID mismatch", err: &unixsocket.ProtocolError{Reason: "response request ID mismatch", Err: errors.New(secret)}, wantStderr: "entry-core: protocol failure\n"},
		{name: "protocol mismatch", err: &unixsocket.ProtocolError{Reason: "response schema", Err: errors.New(secret)}, wantStderr: "entry-core: protocol failure\n"},
		{name: "malformed response", err: &unixsocket.ProtocolError{Reason: "response schema", Err: errors.New(secret)}, wantStderr: "entry-core: protocol failure\n"},
		{name: "oversized response", err: &unixsocket.ProtocolError{Reason: "response exceeds 65,536 bytes", Err: errors.New(secret)}, wantStderr: "entry-core: protocol failure\n"},
		{name: "server", err: &unixsocket.ServerError{Code: schema.ErrorInternal, Message: secret}, wantStderr: "entry-core: server failure\n"},
		{name: "unexpected", err: errors.New(secret), wantStderr: "entry-core: request failure\n"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			client := clientFunc(func(context.Context, string, schema.Request) (schema.Response, error) {
				return schema.Response{}, test.err
			})

			exitCode := run(context.Background(), []string{"--socket", "/tmp/entry-core.sock", "ping"}, bytes.NewReader(make([]byte, 16)), &stdout, &stderr, client)

			if exitCode != 1 || stdout.Len() != 0 || stderr.String() != test.wantStderr {
				t.Fatalf("run() = exit %d, stdout %q, stderr %q", exitCode, stdout.String(), stderr.String())
			}
			if strings.Contains(stderr.String(), secret) || strings.Contains(stderr.String(), strings.Repeat("0", 32)) {
				t.Fatalf("stderr leaked request data: %q", stderr.String())
			}
		})
	}
}

func TestCLIRequestID(t *testing.T) {
	t.Run("fresh ID for every call", func(t *testing.T) {
		var requestIDs []string
		client := clientFunc(func(_ context.Context, _ string, request schema.Request) (schema.Response, error) {
			requestIDs = append(requestIDs, request.RequestID)
			return schema.NewSuccessResponse(request.RequestID, schema.PingResult{Message: "pong"}), nil
		})
		random := bytes.NewReader(append(make([]byte, 16), bytes.Repeat([]byte{0xff}, 16)...))

		for range 2 {
			var stdout, stderr bytes.Buffer
			if exitCode := run(context.Background(), []string{"--socket", "/tmp/entry-core.sock", "ping"}, random, &stdout, &stderr, client); exitCode != 0 {
				t.Fatalf("run() exit = %d, stderr %q", exitCode, stderr.String())
			}
		}
		if len(requestIDs) != 2 || requestIDs[0] == requestIDs[1] || requestIDs[0] != strings.Repeat("0", 32) || requestIDs[1] != strings.Repeat("f", 32) {
			t.Fatalf("request IDs = %q", requestIDs)
		}
	})

	t.Run("lowercase hexadecimal", func(t *testing.T) {
		var stdout, stderr bytes.Buffer
		var requestID string
		client := clientFunc(func(_ context.Context, _ string, request schema.Request) (schema.Response, error) {
			requestID = request.RequestID
			return schema.NewSuccessResponse(request.RequestID, schema.PingResult{Message: "pong"}), nil
		})

		exitCode := run(context.Background(), []string{"--socket", "/tmp/entry-core.sock", "ping"}, bytes.NewReader(bytes.Repeat([]byte{0xab}, 16)), &stdout, &stderr, client)
		if exitCode != 0 || requestID != strings.Repeat("ab", 16) || len(requestID) != 32 {
			t.Fatalf("run() = exit %d, request ID %q", exitCode, requestID)
		}
	})

	for _, test := range []struct {
		name   string
		random io.Reader
	}{
		{name: "short source", random: bytes.NewReader(make([]byte, 15))},
		{name: "erroring source", random: errorReader{err: errors.New("random-secret")}},
	} {
		t.Run(test.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			clientCalled := false
			client := clientFunc(func(context.Context, string, schema.Request) (schema.Response, error) {
				clientCalled = true
				return schema.Response{}, nil
			})

			exitCode := run(context.Background(), []string{"--socket", "/tmp/entry-core.sock", "ping"}, test.random, &stdout, &stderr, client)
			if exitCode != 1 || stdout.Len() != 0 || stderr.String() != "entry-core: request ID generation failure\n" || clientCalled {
				t.Fatalf("run() = exit %d, stdout %q, stderr %q, client called %t", exitCode, stdout.String(), stderr.String(), clientCalled)
			}
		})
	}
}
