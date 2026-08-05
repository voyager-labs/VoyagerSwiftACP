package schema

import (
	"encoding/json"
	"errors"
	"strconv"
	"unicode/utf8"
)

const (
	MaxWireBytes          = 65_536
	ProtocolVersion int64 = 1
)

type Method string

const (
	MethodPing    Method = "ping"
	MethodHealth  Method = "health"
	MethodVersion Method = "version"
)

type ErrorCode string

const (
	ErrorRequestTooLarge            ErrorCode = "request_too_large"
	ErrorInvalidRequest             ErrorCode = "invalid_request"
	ErrorUnsupportedProtocolVersion ErrorCode = "unsupported_protocol_version"
	ErrorUnknownMethod              ErrorCode = "unknown_method"
	ErrorInternal                   ErrorCode = "internal_error"
)

type EmptyParams struct{}

type Request struct {
	RequestID       string
	ProtocolVersion int64
	Method          Method
	Params          EmptyParams
}

type ProtocolError struct {
	Code    ErrorCode `json:"code"`
	Message string    `json:"message"`
}

func DecodeRequest(wire []byte) (Request, string, *ProtocolError) {
	if len(wire) > MaxWireBytes {
		return Request{}, "", newProtocolError(ErrorRequestTooLarge)
	}

	root, err := parseJSON(wire)
	if err != nil || root.kind != jsonObject {
		return Request{}, "", newProtocolError(ErrorInvalidRequest)
	}
	trustworthyID := extractTrustworthyID(root)
	fields, validEnvelope := objectFields(root, "request_id", "protocol_version", "method", "params")
	if !validEnvelope || !validRequestID(fields["request_id"]) || fields["method"].kind != jsonString || !validEmptyParams(fields["params"]) {
		return Request{}, trustworthyID, newProtocolError(ErrorInvalidRequest)
	}

	version, versionIsInteger := lexicalInteger(fields["protocol_version"])
	if !versionIsInteger {
		return Request{}, trustworthyID, newProtocolError(ErrorInvalidRequest)
	}
	if version != ProtocolVersion {
		return Request{}, trustworthyID, newProtocolError(ErrorUnsupportedProtocolVersion)
	}

	method := Method(fields["method"].text)
	if !method.valid() {
		return Request{}, trustworthyID, newProtocolError(ErrorUnknownMethod)
	}

	return Request{
		RequestID:       trustworthyID,
		ProtocolVersion: version,
		Method:          method,
		Params:          EmptyParams{},
	}, trustworthyID, nil
}

func (method Method) valid() bool {
	switch method {
	case MethodPing, MethodHealth, MethodVersion:
		return true
	default:
		return false
	}
}

func extractTrustworthyID(root jsonValue) string {
	values := root.memberValues("request_id")
	if len(values) != 1 || !validRequestID(values[0]) {
		return ""
	}
	return values[0].text
}

func validRequestID(value jsonValue) bool {
	if value.kind != jsonString || !utf8.ValidString(value.text) {
		return false
	}
	length := len([]byte(value.text))
	return length >= 1 && length <= 128
}

func validResponseID(value jsonValue) bool {
	return value.kind == jsonString && utf8.ValidString(value.text) && len([]byte(value.text)) <= 128
}

func validEmptyParams(value jsonValue) bool {
	return value.kind == jsonObject && len(value.members) == 0
}

func lexicalInteger(value jsonValue) (int64, bool) {
	if value.kind != jsonNumber || value.text == "" {
		return 0, false
	}
	for index, character := range value.text {
		if index == 0 && character == '-' {
			continue
		}
		if character < '0' || character > '9' {
			return 0, false
		}
	}
	parsed, err := strconv.ParseInt(value.text, 10, 64)
	return parsed, err == nil
}

func newProtocolError(code ErrorCode) *ProtocolError {
	return &ProtocolError{Code: code, Message: errorMessage(code)}
}

func errorMessage(code ErrorCode) string {
	switch code {
	case ErrorRequestTooLarge:
		return "request is too large"
	case ErrorInvalidRequest:
		return "request is invalid"
	case ErrorUnsupportedProtocolVersion:
		return "protocol version is unsupported"
	case ErrorUnknownMethod:
		return "method is unknown"
	default:
		return "internal error"
	}
}

type Result interface {
	isResult()
}

type PingResult struct {
	Message string `json:"message"`
}

func (PingResult) isResult() {}

type HealthResult struct {
	Status string `json:"status"`
	State  string `json:"state"`
}

func (HealthResult) isResult() {}

type VersionResult struct {
	AppVersion      string `json:"app_version"`
	ProtocolVersion int64  `json:"protocol_version"`
}

func (VersionResult) isResult() {}

type Response struct {
	RequestID       string
	ProtocolVersion int64
	OK              bool
	Result          Result
	Error           *ProtocolError
}

func NewSuccessResponse(requestID string, result Result) Response {
	return Response{
		RequestID:       requestID,
		ProtocolVersion: ProtocolVersion,
		OK:              true,
		Result:          result,
	}
}

func NewErrorResponse(requestID string, code ErrorCode) Response {
	return Response{
		RequestID:       requestID,
		ProtocolVersion: ProtocolVersion,
		Error:           newProtocolError(code),
	}
}

type successWire struct {
	RequestID       string `json:"request_id"`
	ProtocolVersion int64  `json:"protocol_version"`
	OK              bool   `json:"ok"`
	Result          Result `json:"result"`
}

type errorWire struct {
	RequestID       string         `json:"request_id"`
	ProtocolVersion int64          `json:"protocol_version"`
	OK              bool           `json:"ok"`
	Error           *ProtocolError `json:"error"`
}

func EncodeResponse(response Response) []byte {
	var (
		encoded []byte
		err     error
	)
	if response.ProtocolVersion != ProtocolVersion || !validEchoID(response.RequestID) {
		return encodeInternalFallback(response.RequestID)
	}
	if response.OK {
		if response.RequestID == "" || response.Error != nil || !validResult(response.Result) {
			return encodeInternalFallback(response.RequestID)
		}
		encoded, err = json.Marshal(successWire{
			RequestID:       response.RequestID,
			ProtocolVersion: ProtocolVersion,
			OK:              true,
			Result:          response.Result,
		})
	} else {
		if response.Result != nil || !validProtocolError(response.Error) {
			return encodeInternalFallback(response.RequestID)
		}
		encoded, err = json.Marshal(errorWire{
			RequestID:       response.RequestID,
			ProtocolVersion: ProtocolVersion,
			OK:              false,
			Error:           newProtocolError(response.Error.Code),
		})
	}
	if err != nil || len(encoded) > MaxWireBytes {
		return encodeInternalFallback(response.RequestID)
	}
	return encoded
}

func validEchoID(requestID string) bool {
	return utf8.ValidString(requestID) && len([]byte(requestID)) <= 128
}

func validResult(result Result) bool {
	switch typed := result.(type) {
	case PingResult:
		return typed.Message == "pong"
	case HealthResult:
		return typed.Status == "healthy" && typed.State == "running"
	case VersionResult:
		return typed.AppVersion != "" && utf8.ValidString(typed.AppVersion) && typed.ProtocolVersion == ProtocolVersion
	default:
		return false
	}
}

func validProtocolError(protocolError *ProtocolError) bool {
	if protocolError == nil || protocolError.Message == "" || !utf8.ValidString(protocolError.Message) {
		return false
	}
	switch protocolError.Code {
	case ErrorRequestTooLarge, ErrorInvalidRequest, ErrorUnsupportedProtocolVersion, ErrorUnknownMethod, ErrorInternal:
		return true
	default:
		return false
	}
}

func encodeInternalFallback(requestID string) []byte {
	if !validEchoID(requestID) {
		requestID = ""
	}
	encoded, err := json.Marshal(errorWire{
		RequestID:       requestID,
		ProtocolVersion: ProtocolVersion,
		OK:              false,
		Error:           newProtocolError(ErrorInternal),
	})
	if err != nil || len(encoded) > MaxWireBytes {
		return []byte(`{"request_id":"","protocol_version":1,"ok":false,"error":{"code":"internal_error","message":"internal error"}}`)
	}
	return encoded
}

var ErrInvalidResponse = errors.New("invalid protocol response")

func DecodeResponse(wire []byte, method Method) (Response, error) {
	if len(wire) > MaxWireBytes || !method.valid() {
		return Response{}, ErrInvalidResponse
	}
	root, err := parseJSON(wire)
	if err != nil {
		return Response{}, ErrInvalidResponse
	}
	baseFields, ok := responseBaseFields(root)
	if !ok {
		return Response{}, ErrInvalidResponse
	}
	version, integer := lexicalInteger(baseFields["protocol_version"])
	if !integer || version != ProtocolVersion || !validResponseID(baseFields["request_id"]) || baseFields["ok"].kind != jsonBool {
		return Response{}, ErrInvalidResponse
	}

	requestID := baseFields["request_id"].text
	if baseFields["ok"].boolean {
		if requestID == "" {
			return Response{}, ErrInvalidResponse
		}
		fields, success := objectFields(root, "request_id", "protocol_version", "ok", "result")
		if !success {
			return Response{}, ErrInvalidResponse
		}
		result, resultErr := decodeResult(fields["result"], method)
		if resultErr != nil {
			return Response{}, ErrInvalidResponse
		}
		return NewSuccessResponse(requestID, result), nil
	}

	fields, failure := objectFields(root, "request_id", "protocol_version", "ok", "error")
	if !failure {
		return Response{}, ErrInvalidResponse
	}
	protocolError, errorOK := decodeProtocolError(fields["error"])
	if !errorOK {
		return Response{}, ErrInvalidResponse
	}
	return Response{
		RequestID:       requestID,
		ProtocolVersion: ProtocolVersion,
		OK:              false,
		Error:           protocolError,
	}, nil
}

func responseBaseFields(root jsonValue) (map[string]jsonValue, bool) {
	if root.kind != jsonObject || root.hasDuplicateObjectKey() {
		return nil, false
	}
	fields := make(map[string]jsonValue, len(root.members))
	for _, member := range root.members {
		fields[member.name] = member.value
	}
	for _, required := range []string{"request_id", "protocol_version", "ok"} {
		if _, exists := fields[required]; !exists {
			return nil, false
		}
	}
	return fields, true
}

func decodeResult(value jsonValue, method Method) (Result, error) {
	switch method {
	case MethodPing:
		fields, ok := objectFields(value, "message")
		if !ok || fields["message"].kind != jsonString || fields["message"].text != "pong" {
			return nil, ErrInvalidResponse
		}
		return PingResult{Message: "pong"}, nil
	case MethodHealth:
		fields, ok := objectFields(value, "status", "state")
		if !ok || fields["status"].kind != jsonString || fields["state"].kind != jsonString || fields["status"].text != "healthy" || fields["state"].text != "running" {
			return nil, ErrInvalidResponse
		}
		return HealthResult{Status: "healthy", State: "running"}, nil
	case MethodVersion:
		fields, ok := objectFields(value, "app_version", "protocol_version")
		if !ok || fields["app_version"].kind != jsonString || fields["app_version"].text == "" {
			return nil, ErrInvalidResponse
		}
		version, integer := lexicalInteger(fields["protocol_version"])
		if !integer || version != ProtocolVersion {
			return nil, ErrInvalidResponse
		}
		return VersionResult{AppVersion: fields["app_version"].text, ProtocolVersion: version}, nil
	default:
		return nil, ErrInvalidResponse
	}
}

func decodeProtocolError(value jsonValue) (*ProtocolError, bool) {
	fields, ok := objectFields(value, "code", "message")
	if !ok || fields["code"].kind != jsonString || fields["message"].kind != jsonString || fields["message"].text == "" {
		return nil, false
	}
	protocolError := &ProtocolError{Code: ErrorCode(fields["code"].text), Message: fields["message"].text}
	return protocolError, validProtocolError(protocolError)
}
