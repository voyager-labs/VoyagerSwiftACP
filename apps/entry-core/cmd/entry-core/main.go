package main

import (
	"context"
	cryptorand "crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/transport/unixsocket"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

const usageMessage = "usage: entry-core --socket <absolute-path> <ping|health|version>\n"

type caller interface {
	Call(context.Context, string, schema.Request) (schema.Response, error)
}

func main() {
	os.Exit(run(context.Background(), os.Args[1:], cryptorand.Reader, os.Stdout, os.Stderr, unixsocket.NewClient()))
}

func run(ctx context.Context, args []string, random io.Reader, stdout, stderr io.Writer, client caller) int {
	socketPath, method, valid := parseArgs(args)
	if !valid {
		writeError(stderr, usageMessage)
		return 2
	}

	requestIDBytes := make([]byte, 16)
	if _, err := io.ReadFull(random, requestIDBytes); err != nil {
		writeError(stderr, "entry-core: request ID generation failure\n")
		return 1
	}

	request := schema.Request{
		RequestID: hex.EncodeToString(requestIDBytes),
		Method:    method,
		Params:    schema.EmptyParams{},
	}
	response, err := client.Call(ctx, socketPath, request)
	if err != nil {
		writeClientError(stderr, err)
		return 1
	}

	result, valid := resultForMethod(method, response.Result)
	if !valid {
		writeError(stderr, "entry-core: protocol failure\n")
		return 1
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		writeError(stderr, "entry-core: output failure\n")
		return 1
	}
	encoded = append(encoded, '\n')
	if written, err := stdout.Write(encoded); err != nil || written != len(encoded) {
		writeError(stderr, "entry-core: output failure\n")
		return 1
	}
	return 0
}

func parseArgs(args []string) (string, schema.Method, bool) {
	if len(args) != 3 || args[0] != "--socket" || args[1] == "" || !filepath.IsAbs(args[1]) {
		return "", "", false
	}

	method := schema.Method(args[2])
	switch method {
	case schema.MethodPing, schema.MethodHealth, schema.MethodVersion:
		return args[1], method, true
	default:
		return "", "", false
	}
}

func resultForMethod(method schema.Method, result schema.Result) (schema.Result, bool) {
	switch method {
	case schema.MethodPing:
		typed, ok := result.(schema.PingResult)
		return typed, ok
	case schema.MethodHealth:
		typed, ok := result.(schema.HealthResult)
		return typed, ok
	case schema.MethodVersion:
		typed, ok := result.(schema.VersionResult)
		return typed, ok
	default:
		return nil, false
	}
}

func writeClientError(stderr io.Writer, err error) {
	var transportError *unixsocket.TransportError
	var protocolError *unixsocket.ProtocolError
	var serverError *unixsocket.ServerError

	switch {
	case errors.As(err, &transportError):
		writeError(stderr, "entry-core: transport failure\n")
	case errors.As(err, &protocolError):
		writeError(stderr, "entry-core: protocol failure\n")
	case errors.As(err, &serverError):
		writeError(stderr, "entry-core: server failure\n")
	default:
		writeError(stderr, "entry-core: request failure\n")
	}
}

func writeError(stderr io.Writer, message string) {
	_, _ = io.WriteString(stderr, message)
}
