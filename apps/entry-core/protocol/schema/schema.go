package schema

import (
	"encoding/json"
	"errors"
	"strconv"
	"unicode/utf8"
)

const MaxWireBytes = 65_536

type Method string

const (
	MethodPing         Method = "ping"
	MethodHealth       Method = "health"
	MethodVersion      Method = "version"
	MethodEntryList    Method = "entry.list"
	MethodEntryResolve Method = "entry.resolve"
)

type ErrorCode string

const (
	ErrorRequestTooLarge   ErrorCode = "request_too_large"
	ErrorInvalidRequest    ErrorCode = "invalid_request"
	ErrorUnknownMethod     ErrorCode = "unknown_method"
	ErrorInvalidPath       ErrorCode = "invalid_path"
	ErrorMountNotFound     ErrorCode = "mount_not_found"
	ErrorSourceNotFound    ErrorCode = "source_not_found"
	ErrorInvalidSelector   ErrorCode = "invalid_selector"
	ErrorContextMismatch   ErrorCode = "context_mismatch"
	ErrorScopeTooLarge     ErrorCode = "scope_too_large"
	ErrorInvalidPageToken  ErrorCode = "invalid_page_token"
	ErrorPermissionDenied  ErrorCode = "permission_denied"
	ErrorSourceUnavailable ErrorCode = "source_unavailable"
	ErrorSourceDeleted     ErrorCode = "source_deleted"
	ErrorEntryNotFound     ErrorCode = "entry_not_found"
	ErrorUnsupported       ErrorCode = "unsupported"
	ErrorConflict          ErrorCode = "conflict"
	ErrorAdapterFailure    ErrorCode = "adapter_failure"
	ErrorInternal          ErrorCode = "internal_error"
)

type EmptyParams struct{}

type Request struct {
	RequestID                       string
	Method                          Method
	Params                          EmptyParams
	EntryListParams                 *EntryListParams
	EntryResolveParams              *EntryResolveParams
	PropertyDefinitionListParams    *PropertyDefinitionListParams
	PropertyDefinitionCreateParams  *PropertyDefinitionCreateParams
	PropertyDefinitionUpdateParams  *PropertyDefinitionUpdateParams
	PropertyDefinitionDisableParams *PropertyDefinitionDisableParams
	PropertyOptionCreateParams      *PropertyOptionCreateParams
	PropertyOptionUpdateParams      *PropertyOptionUpdateParams
	PropertyOptionReorderParams     *PropertyOptionReorderParams
	PropertyOptionDisableParams     *PropertyOptionDisableParams
	PropertyAssignmentListParams    *PropertyAssignmentListParams
	PropertyChangePrepareParams     *PropertyChangePrepareParams
	PropertyChangeExecuteParams     *PropertyChangeExecuteParams
	PropertyConditionQueryParams    *PropertyConditionQueryParams
}

type ProtocolError struct {
	Code    ErrorCode `json:"code"`
	Message string    `json:"message"`
}

func (method Method) valid() bool {
	switch method {
	case MethodPing, MethodHealth, MethodVersion, MethodEntryList, MethodEntryResolve:
		return true
	default:
		return propertyMethodValid(method)
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
	case ErrorUnknownMethod:
		return "method is unknown"
	case ErrorInvalidPath:
		return "path is invalid"
	case ErrorMountNotFound:
		return "mount was not found"
	case ErrorSourceNotFound:
		return "source was not found"
	case ErrorInvalidPageToken:
		return "page token is invalid"
	case ErrorInvalidSelector:
		return "selector is invalid"
	case ErrorContextMismatch:
		return "context does not match"
	case ErrorScopeTooLarge:
		return "scope is too large"
	case ErrorPermissionDenied:
		return "permission was denied"
	case ErrorSourceUnavailable:
		return "source is unavailable"
	case ErrorSourceDeleted:
		return "source was deleted"
	case ErrorEntryNotFound:
		return "entry was not found"
	case ErrorUnsupported:
		return "operation is unsupported"
	case ErrorConflict:
		return "request conflicts with current state"
	case ErrorAdapterFailure:
		return "adapter failed"
	case ErrorPropertyNotFound:
		return "property was not found"
	case ErrorResponseTooLarge:
		return "response is too large"
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
	AppVersion string `json:"app_version"`
}

func (VersionResult) isResult() {}

type Response struct {
	RequestID string
	OK        bool
	Result    Result
	Error     *ProtocolError
}

func NewSuccessResponse(requestID string, result Result) Response {
	return Response{
		RequestID: requestID,
		OK:        true,
		Result:    result,
	}
}

func NewErrorResponse(requestID string, code ErrorCode) Response {
	return Response{
		RequestID: requestID,
		Error:     newProtocolError(code),
	}
}

func NewPageSizeTooSmallResponse(requestID string) Response {
	return Response{RequestID: requestID, Error: &ProtocolError{Code: ErrorInvalidRequest, Message: "page_size_too_small"}}
}

type successWire struct {
	RequestID string `json:"request_id"`
	OK        bool   `json:"ok"`
	Result    Result `json:"result"`
}

type errorWire struct {
	RequestID string         `json:"request_id"`
	OK        bool           `json:"ok"`
	Error     *ProtocolError `json:"error"`
}

func EncodeResponse(response Response) []byte {
	if !validEchoID(response.RequestID) {
		return encodeInternalFallback(response.RequestID)
	}
	var (
		encoded []byte
		err     error
	)
	if response.OK {
		if response.OK && !successFitsWire(response.RequestID, response.Result) {
			return encodeInternalFallback(response.RequestID)
		}
		if response.RequestID == "" || response.Error != nil || !validResult(response.Result) {
			return encodeInternalFallback(response.RequestID)
		}
		encoded, err = json.Marshal(successWire{
			RequestID: response.RequestID,
			OK:        true,
			Result:    response.Result,
		})
	} else {
		if response.Result != nil || !validProtocolError(response.Error) {
			return encodeInternalFallback(response.RequestID)
		}
		errorValue := &ProtocolError{Code: response.Error.Code, Message: response.Error.Message}
		if response.Error.Message != "page_size_too_small" {
			errorValue = newProtocolError(response.Error.Code)
		}
		encoded, err = json.Marshal(errorWire{
			RequestID: response.RequestID,
			OK:        false,
			Error:     errorValue,
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
		return typed.AppVersion != "" && utf8.ValidString(typed.AppVersion)
	case EntryListResult:
		return typed.Validate() == nil
	case EntryResolveResult:
		return typed.Validate() == nil
	case PropertyDefinitionListResult:
		return typed.Validate() == nil
	case PropertyDefinitionResult:
		return typed.Validate() == nil
	case PropertyAssignmentListResult:
		return typed.Validate() == nil
	case PropertyChangePrepareResult:
		return typed.Validate() == nil
	case PropertyChangeExecuteResult:
		return typed.Validate() == nil
	case PropertyConditionQueryResult:
		return typed.Validate() == nil
	default:
		return false
	}
}

func validProtocolError(protocolError *ProtocolError) bool {
	if protocolError == nil || protocolError.Message == "" || !utf8.ValidString(protocolError.Message) {
		return false
	}
	if protocolError.Code == ErrorInvalidRequest && protocolError.Message == "page_size_too_small" {
		return true
	}
	if protocolError.Message != errorMessage(protocolError.Code) {
		return false
	}
	switch protocolError.Code {
	case ErrorRequestTooLarge, ErrorInvalidRequest, ErrorUnknownMethod, ErrorInternal, ErrorInvalidPath, ErrorMountNotFound, ErrorSourceNotFound, ErrorInvalidSelector, ErrorContextMismatch, ErrorScopeTooLarge, ErrorInvalidPageToken, ErrorPermissionDenied, ErrorSourceUnavailable, ErrorSourceDeleted, ErrorEntryNotFound, ErrorUnsupported, ErrorConflict, ErrorAdapterFailure, ErrorPropertyNotFound, ErrorResponseTooLarge:
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
		RequestID: requestID,
		OK:        false,
		Error:     newProtocolError(ErrorInternal),
	})
	if err != nil || len(encoded) > MaxWireBytes {
		return []byte(`{"request_id":"","ok":false,"error":{"code":"internal_error","message":"internal error"}}`)
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
	if !validResponseID(baseFields["request_id"]) || baseFields["ok"].kind != jsonBool {
		return Response{}, ErrInvalidResponse
	}

	requestID := baseFields["request_id"].text
	if baseFields["ok"].boolean {
		if requestID == "" {
			return Response{}, ErrInvalidResponse
		}
		fields, success := objectFields(root, "request_id", "ok", "result")
		if !success {
			return Response{}, ErrInvalidResponse
		}
		result, resultErr := decodeResult(fields["result"], method)
		if resultErr != nil {
			return Response{}, ErrInvalidResponse
		}
		return NewSuccessResponse(requestID, result), nil
	}

	fields, failure := objectFields(root, "request_id", "ok", "error")
	if !failure {
		return Response{}, ErrInvalidResponse
	}
	protocolError, errorOK := decodeProtocolError(fields["error"])
	if !errorOK {
		return Response{}, ErrInvalidResponse
	}
	return Response{
		RequestID: requestID,
		OK:        false,
		Error:     protocolError,
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
	for _, required := range []string{"request_id", "ok"} {
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
		fields, ok := objectFields(value, "app_version")
		if !ok || fields["app_version"].kind != jsonString || fields["app_version"].text == "" {
			return nil, ErrInvalidResponse
		}
		return VersionResult{AppVersion: fields["app_version"].text}, nil
	case MethodEntryList:
		result, ok := decodeEntryListResult(value)
		if !ok {
			return nil, ErrInvalidResponse
		}
		return result, nil
	case MethodEntryResolve:
		result, ok := decodeEntryResolveResult(value)
		if !ok {
			return nil, ErrInvalidResponse
		}
		return result, nil
	case MethodPropertyDefinitionList:
		result, ok := decodePropertyDefinitionListResult(value)
		if !ok {
			return nil, ErrInvalidResponse
		}
		return result, nil
	case MethodPropertyDefinitionCreate, MethodPropertyDefinitionUpdate, MethodPropertyDefinitionDisable,
		MethodPropertyOptionCreate, MethodPropertyOptionUpdate, MethodPropertyOptionReorder, MethodPropertyOptionDisable:
		result, ok := decodePropertyDefinitionResult(value)
		if !ok {
			return nil, ErrInvalidResponse
		}
		return result, nil
	case MethodPropertyAssignmentList:
		result, ok := decodePropertyAssignmentListResult(value)
		if !ok {
			return nil, ErrInvalidResponse
		}
		return result, nil
	case MethodPropertyChangePrepare:
		result, ok := decodePropertyChangePrepareResult(value)
		if !ok {
			return nil, ErrInvalidResponse
		}
		return result, nil
	case MethodPropertyChangeExecute:
		result, ok := decodePropertyChangeExecuteResult(value)
		if !ok {
			return nil, ErrInvalidResponse
		}
		return result, nil
	case MethodPropertyConditionQuery:
		result, ok := decodePropertyConditionQueryResult(value)
		if !ok {
			return nil, ErrInvalidResponse
		}
		return result, nil
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
