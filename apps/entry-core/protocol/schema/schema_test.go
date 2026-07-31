package schema

import (
	"bytes"
	"strings"
	"testing"
)

const validRequest = `{"request_id":"request-1","protocol_version":1,"method":"ping","params":{}}`

func TestDecodeRequestStrictMatrix(t *testing.T) {
	t.Parallel()

	invalidUTF8 := append([]byte(`{"request_id":"request-1","protocol_version":1,"method":"`), 0xff)
	invalidUTF8 = append(invalidUTF8, []byte(`","params":{}}`)...)

	tests := []struct {
		name       string
		wire       []byte
		wantCode   ErrorCode
		wantID     string
		wantMethod Method
	}{
		{name: "valid", wire: []byte(validRequest), wantID: "request-1", wantMethod: MethodPing},
		{name: "surrounding whitespace", wire: []byte(" \n\t" + validRequest + "\r "), wantID: "request-1", wantMethod: MethodPing},
		{name: "paired surrogate", wire: []byte(`{"request_id":"\uD83D\uDE80","protocol_version":1,"method":"ping","params":{}}`), wantID: "🚀", wantMethod: MethodPing},
		{name: "unknown field", wire: []byte(`{"request_id":"request-1","protocol_version":1,"method":"ping","params":{},"extra":true}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "duplicate top-level", wire: []byte(`{"request_id":"request-1","protocol_version":1,"method":"ping","method":"health","params":{}}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "missing field", wire: []byte(`{"request_id":"request-1","protocol_version":1,"method":"ping"}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "invalid raw UTF-8", wire: invalidUTF8, wantCode: ErrorInvalidRequest},
		{name: "lone high surrogate", wire: []byte(`{"request_id":"\uD800","protocol_version":1,"method":"ping","params":{}}`), wantCode: ErrorInvalidRequest},
		{name: "lone low surrogate", wire: []byte(`{"request_id":"\uDC00","protocol_version":1,"method":"ping","params":{}}`), wantCode: ErrorInvalidRequest},
		{name: "decimal protocol", wire: []byte(`{"request_id":"request-1","protocol_version":1.0,"method":"ping","params":{}}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "exponent protocol", wire: []byte(`{"request_id":"request-1","protocol_version":1e0,"method":"ping","params":{}}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "string protocol", wire: []byte(`{"request_id":"request-1","protocol_version":"1","method":"ping","params":{}}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "bool protocol", wire: []byte(`{"request_id":"request-1","protocol_version":true,"method":"ping","params":{}}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "null protocol", wire: []byte(`{"request_id":"request-1","protocol_version":null,"method":"ping","params":{}}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "overflow protocol", wire: []byte(`{"request_id":"request-1","protocol_version":9223372036854775808,"method":"ping","params":{}}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "unsupported integer protocol", wire: []byte(`{"request_id":"request-1","protocol_version":2,"method":"ping","params":{}}`), wantCode: ErrorUnsupportedProtocolVersion, wantID: "request-1"},
		{name: "null params", wire: []byte(`{"request_id":"request-1","protocol_version":1,"method":"ping","params":null}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "array params", wire: []byte(`{"request_id":"request-1","protocol_version":1,"method":"ping","params":[]}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "nonempty params", wire: []byte(`{"request_id":"request-1","protocol_version":1,"method":"ping","params":{"x":1}}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "duplicate params", wire: []byte(`{"request_id":"request-1","protocol_version":1,"method":"ping","params":{"x":1,"x":2}}`), wantCode: ErrorInvalidRequest, wantID: "request-1"},
		{name: "second JSON value", wire: []byte(validRequest + `{}`), wantCode: ErrorInvalidRequest},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request, trustworthyID, protocolError := DecodeRequest(test.wire)
			if trustworthyID != test.wantID {
				t.Fatalf("trustworthy ID = %q, want %q", trustworthyID, test.wantID)
			}
			if test.wantCode == "" {
				if protocolError != nil {
					t.Fatalf("unexpected protocol error: %#v", protocolError)
				}
				if request.Method != test.wantMethod || request.ProtocolVersion != ProtocolVersion {
					t.Fatalf("request = %#v", request)
				}
				return
			}
			if protocolError == nil || protocolError.Code != test.wantCode {
				t.Fatalf("error = %#v, want code %q", protocolError, test.wantCode)
			}
		})
	}
}

func TestDecodeRequestSizeBoundary(t *testing.T) {
	t.Parallel()

	padding := MaxWireBytes - len(validRequest)
	atLimit := append([]byte(validRequest), bytes.Repeat([]byte{' '}, padding)...)
	if _, _, protocolError := DecodeRequest(atLimit); protocolError != nil {
		t.Fatalf("65,536-byte request rejected: %#v", protocolError)
	}

	overLimit := append(atLimit, ' ')
	if _, id, protocolError := DecodeRequest(overLimit); protocolError == nil || protocolError.Code != ErrorRequestTooLarge || id != "" {
		t.Fatalf("65,537-byte result = id %q, error %#v", id, protocolError)
	}

	malformedAtLimit := bytes.Repeat([]byte{'{'}, MaxWireBytes)
	if _, _, protocolError := DecodeRequest(malformedAtLimit); protocolError == nil || protocolError.Code != ErrorInvalidRequest {
		t.Fatalf("malformed in-limit error = %#v", protocolError)
	}
}

func TestRequestIDTrustMatrix(t *testing.T) {
	t.Parallel()

	repeat := func(value string) []byte {
		return []byte(`{"request_id":"` + value + `","protocol_version":1,"method":"ping","params":{}}`)
	}

	tests := []struct {
		name     string
		wire     []byte
		wantID   string
		wantCode ErrorCode
	}{
		{name: "one byte", wire: repeat("a"), wantID: "a"},
		{name: "128 bytes", wire: repeat(strings.Repeat("a", 128)), wantID: strings.Repeat("a", 128)},
		{name: "129 bytes", wire: repeat(strings.Repeat("a", 129)), wantCode: ErrorInvalidRequest},
		{name: "empty", wire: repeat(""), wantCode: ErrorInvalidRequest},
		{name: "measure after unescape", wire: repeat(`\u0061`), wantID: "a"},
		{name: "UTF-8 bytes not runes", wire: repeat(strings.Repeat("🚀", 32)), wantID: strings.Repeat("🚀", 32)},
		{name: "UTF-8 over 128 bytes", wire: repeat(strings.Repeat("🚀", 33)), wantCode: ErrorInvalidRequest},
		{name: "preserve normalization", wire: repeat("e\u0301"), wantID: "é"},
		{name: "trust despite other invalid field", wire: []byte(`{"request_id":"keep-me","protocol_version":1.0,"method":"ping","params":{}}`), wantID: "keep-me", wantCode: ErrorInvalidRequest},
		{name: "duplicate ID is untrusted", wire: []byte(`{"request_id":"first","request_id":"second","protocol_version":1,"method":"ping","params":{}}`), wantCode: ErrorInvalidRequest},
		{name: "non-string ID is untrusted", wire: []byte(`{"request_id":1,"protocol_version":1,"method":"ping","params":{}}`), wantCode: ErrorInvalidRequest},
		{name: "truncated object is untrusted", wire: []byte(`{"request_id":"seen","protocol_version":1`), wantCode: ErrorInvalidRequest},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, trustworthyID, protocolError := DecodeRequest(test.wire)
			if trustworthyID != test.wantID {
				t.Fatalf("trustworthy ID = %q, want %q", trustworthyID, test.wantID)
			}
			if test.wantCode == "" {
				if protocolError != nil {
					t.Fatalf("unexpected error: %#v", protocolError)
				}
				return
			}
			if protocolError == nil || protocolError.Code != test.wantCode {
				t.Fatalf("error = %#v, want %q", protocolError, test.wantCode)
			}
		})
	}
}

func TestErrorPrecedence(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		wire []byte
		want ErrorCode
	}{
		{name: "oversized before malformed", wire: bytes.Repeat([]byte{'{'}, MaxWireBytes+1), want: ErrorRequestTooLarge},
		{name: "invalid envelope before unsupported protocol", wire: []byte(`{"request_id":"id","protocol_version":2,"method":"ping"}`), want: ErrorInvalidRequest},
		{name: "unsupported protocol before unknown method", wire: []byte(`{"request_id":"id","protocol_version":2,"method":"future","params":{}}`), want: ErrorUnsupportedProtocolVersion},
		{name: "unknown method after valid envelope", wire: []byte(`{"request_id":"id","protocol_version":1,"method":"future","params":{}}`), want: ErrorUnknownMethod},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, _, protocolError := DecodeRequest(test.wire)
			if protocolError == nil || protocolError.Code != test.want {
				t.Fatalf("error = %#v, want %q", protocolError, test.want)
			}
		})
	}
}

func TestDecodeResponseStrictMatrix(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		wire    string
		method  Method
		wantErr bool
	}{
		{name: "ping success", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"message":"pong"}}`, method: MethodPing},
		{name: "health success", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"status":"healthy","state":"running"}}`, method: MethodHealth},
		{name: "version success", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"app_version":"0.1.0-dev","protocol_version":1}}`, method: MethodVersion},
		{name: "error", wire: `{"request_id":"","protocol_version":1,"ok":false,"error":{"code":"invalid_request","message":"request is invalid"}}`, method: MethodPing},
		{name: "duplicate response field", wire: `{"request_id":"id","protocol_version":1,"ok":true,"ok":true,"result":{"message":"pong"}}`, method: MethodPing, wantErr: true},
		{name: "unknown response field", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"message":"pong"},"extra":true}`, method: MethodPing, wantErr: true},
		{name: "missing response field", wire: `{"request_id":"id","protocol_version":1,"ok":true}`, method: MethodPing, wantErr: true},
		{name: "failure without error", wire: `{"request_id":"","protocol_version":1,"ok":false}`, method: MethodPing, wantErr: true},
		{name: "duplicate result field", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"message":"pong","message":"pong"}}`, method: MethodPing, wantErr: true},
		{name: "duplicate error field", wire: `{"request_id":"","protocol_version":1,"ok":false,"error":{"code":"invalid_request","code":"invalid_request","message":"request is invalid"}}`, method: MethodPing, wantErr: true},
		{name: "success with error", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"message":"pong"},"error":{"code":"internal_error","message":"internal error"}}`, method: MethodPing, wantErr: true},
		{name: "failure with result", wire: `{"request_id":"id","protocol_version":1,"ok":false,"result":{"message":"pong"},"error":{"code":"internal_error","message":"internal error"}}`, method: MethodPing, wantErr: true},
		{name: "wrong result shape", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"message":"nope"}}`, method: MethodPing, wantErr: true},
		{name: "unknown result field", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"message":"pong","extra":true}}`, method: MethodPing, wantErr: true},
		{name: "wrong health status", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"status":"degraded","state":"running"}}`, method: MethodHealth, wantErr: true},
		{name: "noninteger version result protocol", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"app_version":"0.1.0-dev","protocol_version":1.0}}`, method: MethodVersion, wantErr: true},
		{name: "invalid error code", wire: `{"request_id":"","protocol_version":1,"ok":false,"error":{"code":"future_error","message":"future error"}}`, method: MethodPing, wantErr: true},
		{name: "unsupported response protocol", wire: `{"request_id":"id","protocol_version":2,"ok":true,"result":{"message":"pong"}}`, method: MethodPing, wantErr: true},
		{name: "empty success ID", wire: `{"request_id":"","protocol_version":1,"ok":true,"result":{"message":"pong"}}`, method: MethodPing, wantErr: true},
		{name: "129-byte response ID", wire: `{"request_id":"` + strings.Repeat("x", 129) + `","protocol_version":1,"ok":true,"result":{"message":"pong"}}`, method: MethodPing, wantErr: true},
		{name: "noninteger response protocol", wire: `{"request_id":"id","protocol_version":1.0,"ok":true,"result":{"message":"pong"}}`, method: MethodPing, wantErr: true},
		{name: "second response value", wire: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"message":"pong"}} {}`, method: MethodPing, wantErr: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			response, err := DecodeResponse([]byte(test.wire), test.method)
			if (err != nil) != test.wantErr {
				t.Fatalf("response = %#v, error = %v", response, err)
			}
		})
	}

	responseWire := []byte(`{"request_id":"id","protocol_version":1,"ok":true,"result":{"message":"pong"}}`)
	atLimit := append(responseWire, bytes.Repeat([]byte{' '}, MaxWireBytes-len(responseWire))...)
	if _, err := DecodeResponse(atLimit, MethodPing); err != nil {
		t.Fatalf("65,536-byte response rejected: %v", err)
	}
	if _, err := DecodeResponse(append(atLimit, ' '), MethodPing); err == nil {
		t.Fatal("65,537-byte response accepted")
	}
}

type unencodableResult struct {
	Value func()
}

func (unencodableResult) isResult() {}

func TestEncodeResponseContract(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		response Response
		want     string
	}{
		{name: "ping", response: NewSuccessResponse("id", PingResult{Message: "pong"}), want: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"message":"pong"}}`},
		{name: "health", response: NewSuccessResponse("id", HealthResult{Status: "healthy", State: "running"}), want: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"status":"healthy","state":"running"}}`},
		{name: "version", response: NewSuccessResponse("id", VersionResult{AppVersion: "0.1.0-dev", ProtocolVersion: 1}), want: `{"request_id":"id","protocol_version":1,"ok":true,"result":{"app_version":"0.1.0-dev","protocol_version":1}}`},
		{name: "failure", response: NewErrorResponse("", ErrorInvalidRequest), want: `{"request_id":"","protocol_version":1,"ok":false,"error":{"code":"invalid_request","message":"request is invalid"}}`},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			encoded := EncodeResponse(test.response)
			if string(encoded) != test.want {
				t.Fatalf("encoded = %s, want %s", encoded, test.want)
			}
			if len(encoded) > MaxWireBytes {
				t.Fatalf("encoded response is %d bytes", len(encoded))
			}
		})
	}

	overflow := NewSuccessResponse("trusted", VersionResult{AppVersion: strings.Repeat("x", MaxWireBytes), ProtocolVersion: ProtocolVersion})
	assertInternalFallback(t, EncodeResponse(overflow), "trusted")

	unexpected := Response{RequestID: "trusted", ProtocolVersion: ProtocolVersion, OK: true, Result: unencodableResult{Value: func() {}}}
	assertInternalFallback(t, EncodeResponse(unexpected), "trusted")

	untrustworthy := Response{RequestID: strings.Repeat("x", 129), ProtocolVersion: ProtocolVersion, OK: true, Result: unencodableResult{Value: func() {}}}
	assertInternalFallback(t, EncodeResponse(untrustworthy), "")

	emptySuccessID := NewSuccessResponse("", PingResult{Message: "pong"})
	assertInternalFallback(t, EncodeResponse(emptySuccessID), "")

	invalidAppVersion := NewSuccessResponse("trusted", VersionResult{AppVersion: string([]byte{0xff}), ProtocolVersion: ProtocolVersion})
	assertInternalFallback(t, EncodeResponse(invalidAppVersion), "trusted")

	customMessage := NewErrorResponse("trusted", ErrorInternal)
	customMessage.Error.Message = "raw internal detail"
	encoded := EncodeResponse(customMessage)
	if bytes.Contains(encoded, []byte("raw internal detail")) || !bytes.Contains(encoded, []byte(`"message":"internal error"`)) {
		t.Fatalf("error message was not canonicalized: %s", encoded)
	}
}

func assertInternalFallback(t *testing.T, encoded []byte, wantID string) {
	t.Helper()
	if len(encoded) > MaxWireBytes {
		t.Fatalf("fallback is %d bytes", len(encoded))
	}
	response, err := DecodeResponse(encoded, MethodPing)
	if err != nil {
		t.Fatalf("fallback decode: %v; wire=%s", err, encoded)
	}
	if response.OK || response.RequestID != wantID || response.Error == nil || response.Error.Code != ErrorInternal {
		t.Fatalf("fallback response = %#v", response)
	}
}
