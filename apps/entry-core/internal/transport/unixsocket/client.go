package unixsocket

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"path/filepath"
	"time"

	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

const clientTimeout = 2 * time.Second

type TransportError struct {
	Phase string
	Err   error
}

func (transportError *TransportError) Error() string {
	return fmt.Sprintf("unix socket %s failed: %v", transportError.Phase, transportError.Err)
}

func (transportError *TransportError) Unwrap() error {
	return transportError.Err
}

func newTransportError(ctx context.Context, phase string, err error) *TransportError {
	if ctxErr := ctx.Err(); ctxErr != nil {
		err = ctxErr
	}
	return &TransportError{Phase: phase, Err: err}
}

type ProtocolError struct {
	Reason string
	Err    error
}

func (protocolError *ProtocolError) Error() string {
	if protocolError.Err == nil {
		return "invalid protocol response: " + protocolError.Reason
	}
	return fmt.Sprintf("invalid protocol response: %s: %v", protocolError.Reason, protocolError.Err)
}

func (protocolError *ProtocolError) Unwrap() error {
	return protocolError.Err
}

type ServerError struct {
	Code    schema.ErrorCode
	Message string
}

func (serverError *ServerError) Error() string {
	return fmt.Sprintf("server error %s: %s", serverError.Code, serverError.Message)
}

type dialFunc func(context.Context, string, string) (net.Conn, error)

type Client struct {
	dial dialFunc
	now  func() time.Time
}

func NewClient() *Client {
	dialer := &net.Dialer{}
	return newClient(dialer.DialContext, time.Now)
}

func newClient(dial dialFunc, now func() time.Time) *Client {
	return &Client{dial: dial, now: now}
}

type requestWire struct {
	RequestID string             `json:"request_id"`
	Method    schema.Method      `json:"method"`
	Params    schema.EmptyParams `json:"params"`
}

func (client *Client) Call(ctx context.Context, socketPath string, request schema.Request) (schema.Response, error) {
	if !filepath.IsAbs(socketPath) {
		return schema.Response{}, &TransportError{Phase: "dial", Err: errors.New("socket path must be absolute")}
	}

	wire, err := json.Marshal(requestWire{
		RequestID: request.RequestID,
		Method:    request.Method,
		Params:    request.Params,
	})
	if err != nil {
		return schema.Response{}, &ProtocolError{Reason: "request encoding", Err: err}
	}
	decodedRequest, _, requestError := schema.DecodeRequest(wire)
	if requestError != nil || decodedRequest != request {
		return schema.Response{}, &ProtocolError{Reason: "invalid request"}
	}

	timeoutDeadline := client.now().Add(clientTimeout)
	dialContext, cancel := context.WithDeadline(ctx, timeoutDeadline)
	defer cancel()
	deadline, _ := dialContext.Deadline()
	connection, err := client.dial(dialContext, "unix", socketPath)
	if err != nil {
		return schema.Response{}, newTransportError(dialContext, "dial", err)
	}
	defer connection.Close()
	stopCancellation := context.AfterFunc(dialContext, func() { _ = connection.Close() })
	defer stopCancellation()

	if err := connection.SetDeadline(deadline); err != nil {
		return schema.Response{}, newTransportError(dialContext, "deadline", err)
	}
	if _, err := io.Copy(connection, bytes.NewReader(wire)); err != nil {
		return schema.Response{}, newTransportError(dialContext, "write", err)
	}
	unixWriter, ok := connection.(interface{ CloseWrite() error })
	if !ok {
		return schema.Response{}, &TransportError{Phase: "close write", Err: errors.New("connection does not support Unix half-close")}
	}
	if err := unixWriter.CloseWrite(); err != nil {
		return schema.Response{}, newTransportError(dialContext, "close write", err)
	}

	responseWire, err := io.ReadAll(io.LimitReader(connection, schema.MaxWireBytes+1))
	if err != nil {
		return schema.Response{}, newTransportError(dialContext, "read", err)
	}
	if len(responseWire) > schema.MaxWireBytes {
		return schema.Response{}, &ProtocolError{Reason: "response exceeds 65,536 bytes"}
	}
	response, err := schema.DecodeResponse(responseWire, request.Method)
	if err != nil {
		return schema.Response{}, &ProtocolError{Reason: "response schema", Err: err}
	}
	if response.RequestID == "" || response.RequestID != request.RequestID {
		return schema.Response{}, &ProtocolError{Reason: "response request ID mismatch"}
	}
	if ctxErr := dialContext.Err(); ctxErr != nil {
		return schema.Response{}, &TransportError{Phase: "validation", Err: ctxErr}
	}
	if !client.now().Before(deadline) {
		return schema.Response{}, &TransportError{Phase: "validation", Err: context.DeadlineExceeded}
	}
	if !response.OK {
		return schema.Response{}, &ServerError{Code: response.Error.Code, Message: response.Error.Message}
	}
	return response, nil
}
