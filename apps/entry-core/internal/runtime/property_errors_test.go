package runtime

// Property 오류 사상 테스트다. 모든 센티널의 안정 코드 사상, 고정 메시지 바이트,
// 봉투 초과 거절을 소유한다.

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/mount"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

func TestPropertyDispatchCanonicalErrorBytes(t *testing.T) {
	tests := []struct {
		err  error
		wire string
	}{
		{applicationproperty.ErrStaleAssignmentRevision, `{"request_id":"id","ok":false,"error":{"code":"conflict","message":"request conflicts with current state"}}`},
		{applicationproperty.ErrScopeTooLarge, `{"request_id":"id","ok":false,"error":{"code":"scope_too_large","message":"scope is too large"}}`},
		{applicationproperty.ErrDefinitionNotEditable, `{"request_id":"id","ok":false,"error":{"code":"unsupported","message":"operation is unsupported"}}`},
		{errors.New("secret"), `{"request_id":"id","ok":false,"error":{"code":"internal_error","message":"internal error"}}`},
	}
	for _, test := range tests {
		service := newRecordingPropertyService()
		service.serviceErr = test.err
		response := newPropertyRuntime(service).Dispatch(context.Background(), prepareRequest(changeTarget("/a", 1, schema.PropertyDesiredState{State: "null"})))
		if got := string(schema.EncodeResponse(response)); got != test.wire {
			t.Fatalf("err=%v wire=%s", test.err, got)
		}
	}
}

// TestPropertyDispatchResponseTooLarge는 봉투 초과 성공 결과가 socket write 전에
// response_too_large로 거절됨을 증명한다.

func TestPropertyDispatchResponseTooLarge(t *testing.T) {
	options := make([]domainentry.PropertyOption, 256)
	for index := range options {
		options[index] = domainentry.PropertyOption{
			OptionID:   domainentry.MustPropertyOptionID(fmt.Sprintf("0198c0a2-7b3f-7%03x-8f2a-4b6e8d0f1a2c", index)),
			PropertyID: domainentry.MustPropertyID(testPropertyID),
			Label:      strings.Repeat("a", 256),
			Ordinal:    index,
			Active:     true,
		}
	}
	service := newRecordingPropertyService()
	service.listDefinitions = []applicationproperty.DefinitionView{{
		Definition: domainentry.WorkspacePropertyDefinition{
			PropertyID: domainentry.MustPropertyID(testPropertyID), Lifecycle: domainentry.PropertyLifecycleActive,
			Origin: domainentry.PropertyOriginBuiltIn, IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
			Namespace: "system", CanonicalKey: "local.large", DisplayName: "Large",
			ValueType: domainentry.PropertyTypeSelect, Cardinality: domainentry.PropertyCardinalityOne,
			Provenance: domainentry.PropertyProvenanceSystem, DefinitionRev: 1,
		},
		Options: options,
	}}
	runtime := newPropertyRuntime(service)
	request := schema.Request{RequestID: "id", Method: schema.MethodPropertyDefinitionList, PropertyDefinitionListParams: &schema.PropertyDefinitionListParams{PageSize: 8, RequestedPropertyIDs: []string{}}}
	response := runtime.Dispatch(context.Background(), request)
	if response.Error == nil || response.Error.Code != schema.ErrorResponseTooLarge {
		t.Fatalf("response=%v", response.Error)
	}
}

// 테스트 전용 UUIDv7 형태 식별자들이다. 세 번째 그룹 첫 니블 7, 네 번째 그룹
// 첫 바이트 상위 비트 10(RFC 9562 variant)을 만족한다.

type recordingPropertyService struct {
	calls           map[string]int
	lastWorkspace   domainentry.WorkspaceContext
	listDefinitions []applicationproperty.DefinitionView
	view            applicationproperty.DefinitionView
	serviceErr      error
	proposal        applicationproperty.Proposal
	facts           []domainentry.EntryPropertyAssignment

	lastCreateInput applicationproperty.CreateDefinitionInput
	lastChanges     []applicationproperty.ChangeTarget
	lastRequestID   string
	lastPropertyIDs []domainentry.PropertyID
	lastLocalPath   string
	lastOptionIDs   []domainentry.PropertyOptionID
	lastLabel       string
	lastExpectedRev int
}

func TestPropertyDispatchErrorMappingTable(t *testing.T) {
	prepare := func(err error) (schema.Request, func(*recordingPropertyService)) {
		return prepareRequest(changeTarget("/a", 1, schema.PropertyDesiredState{State: "null"})), func(service *recordingPropertyService) { service.serviceErr = err }
	}
	create := func(err error) (schema.Request, func(*recordingPropertyService)) {
		return schema.Request{RequestID: "id", Method: schema.MethodPropertyDefinitionCreate, PropertyDefinitionCreateParams: &schema.PropertyDefinitionCreateParams{Key: "k", Name: "n", ValueType: "text", Cardinality: "one"}}, func(service *recordingPropertyService) { service.serviceErr = err }
	}
	rename := func(err error) (schema.Request, func(*recordingPropertyService)) {
		return schema.Request{RequestID: "id", Method: schema.MethodPropertyOptionUpdate, PropertyOptionUpdateParams: &schema.PropertyOptionUpdateParams{PropertyID: testPropertyID, OptionID: testOptionID, ExpectedDefinitionRevision: 1, Label: "M"}}, func(service *recordingPropertyService) { service.serviceErr = err }
	}
	reorder := func(err error) (schema.Request, func(*recordingPropertyService)) {
		return schema.Request{RequestID: "id", Method: schema.MethodPropertyOptionReorder, PropertyOptionReorderParams: &schema.PropertyOptionReorderParams{PropertyID: testPropertyID, ExpectedDefinitionRevision: 1, OptionIDs: []string{testOptionID}}}, func(service *recordingPropertyService) { service.serviceErr = err }
	}
	list := func(err error) (schema.Request, func(*recordingPropertyService)) {
		return schema.Request{RequestID: "id", Method: schema.MethodPropertyAssignmentList, PropertyAssignmentListParams: &schema.PropertyAssignmentListParams{PageSize: 1, RequestedPropertyIDs: []string{}, Target: localPathTarget("/a")}}, func(service *recordingPropertyService) { service.serviceErr = err }
	}
	definitions := func(err error) (schema.Request, func(*recordingPropertyService)) {
		return schema.Request{RequestID: "id", Method: schema.MethodPropertyDefinitionList, PropertyDefinitionListParams: &schema.PropertyDefinitionListParams{PageSize: 1, RequestedPropertyIDs: []string{}}}, func(service *recordingPropertyService) { service.serviceErr = err }
	}

	tests := []struct {
		name string
		err  error
		code schema.ErrorCode
	}{
		{"stale definition revision", applicationproperty.ErrStaleDefinitionRevision, schema.ErrorConflict},
		{"stale assignment revision", applicationproperty.ErrStaleAssignmentRevision, schema.ErrorConflict},
		{"duplicate definition key", applicationproperty.ErrDuplicateDefinitionKey, schema.ErrorConflict},
		{"definition inactive", applicationproperty.ErrDefinitionInactive, schema.ErrorConflict},
		{"option inactive", applicationproperty.ErrOptionInactive, schema.ErrorConflict},
		{"duplicate option id", applicationproperty.ErrDuplicateOptionID, schema.ErrorConflict},
		{"inactive option in value", domainentry.ErrAssignmentInactiveOption, schema.ErrorConflict},
		{"scope too large", applicationproperty.ErrScopeTooLarge, schema.ErrorScopeTooLarge},
		{"definition not found", applicationproperty.ErrDefinitionNotFound, schema.ErrorPropertyNotFound},
		{"option not found", applicationproperty.ErrOptionNotFound, schema.ErrorPropertyNotFound},
		{"definition not editable", applicationproperty.ErrDefinitionNotEditable, schema.ErrorUnsupported},
		{"definition not selectable", applicationproperty.ErrDefinitionNotSelectable, schema.ErrorUnsupported},
		{"invalid change request", applicationproperty.ErrInvalidChangeRequest, schema.ErrorInvalidRequest},
		{"duplicate change target", applicationproperty.ErrDuplicateChangeTarget, schema.ErrorInvalidRequest},
		{"invalid option owner", applicationproperty.ErrInvalidOptionOwner, schema.ErrorInvalidRequest},
		{"invalid option order", applicationproperty.ErrInvalidOptionOrder, schema.ErrorInvalidRequest},
		{"immutable definition field", applicationproperty.ErrImmutableDefinitionField, schema.ErrorInvalidRequest},
		{"value type mismatch", domainentry.ErrAssignmentValueTypeMismatch, schema.ErrorInvalidRequest},
		{"cardinality mismatch", domainentry.ErrAssignmentCardinalityMismatch, schema.ErrorInvalidRequest},
		{"null not allowed", domainentry.ErrAssignmentNullNotAllowed, schema.ErrorInvalidRequest},
		{"empty scalar", domainentry.ErrAssignmentEmptyScalar, schema.ErrorInvalidRequest},
		{"invalid path", mount.ErrInvalidPath, schema.ErrorInvalidPath},
		{"path escape", source.ErrPathEscape, schema.ErrorInvalidPath},
		{"entry not found", source.ErrEntryNotFound, schema.ErrorEntryNotFound},
		{"permission denied", source.ErrPermissionDenied, schema.ErrorPermissionDenied},
		{"source unavailable", source.ErrSourceUnavailable, schema.ErrorSourceUnavailable},
		{"adapter failure", source.ErrAdapterFailure, schema.ErrorAdapterFailure},
		{"workspace required", applicationproperty.ErrWorkspaceRequired, schema.ErrorInternal},
		{"invalid catalog service", applicationproperty.ErrInvalidCatalogService, schema.ErrorInternal},
		{"invalid change service", applicationproperty.ErrInvalidChangeService, schema.ErrorInternal},
		{"invalid resolved target", applicationproperty.ErrInvalidResolvedTarget, schema.ErrorInternal},
		{"read back incomplete", applicationproperty.ErrCanonicalReadBackIncomplete, schema.ErrorInternal},
		{"unknown raw error", errors.New("raw backend secret detail"), schema.ErrorInternal},
	}
	builders := []func(error) (schema.Request, func(*recordingPropertyService)){prepare, create, rename, reorder, list, definitions}
	for _, test := range tests {
		for _, build := range builders {
			request, inject := build(test.err)
			service := newRecordingPropertyService()
			inject(service)
			response := newPropertyRuntime(service).Dispatch(context.Background(), request)
			if response.Error == nil || response.Error.Code != test.code {
				t.Fatalf("%s: err=%v response=%#v", test.name, test.err, response)
			}
			if response.Error.Message != schema.NewErrorResponse("probe", test.code).Error.Message {
				t.Fatalf("%s: leaked message %q", test.name, response.Error.Message)
			}
		}
	}
}

// TestPropertyDispatchCanonicalErrorBytes는 대표 오류의 정확한 wire 바이트를 잠가
// 원문 유출 없는 고정 메시지를 증명한다.
