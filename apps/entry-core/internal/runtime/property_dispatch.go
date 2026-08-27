package runtime

import (
	"context"
	"encoding/hex"
	"strings"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// PropertyService는 Property 유스케이스의 application 경계다. runtime은 저장소에
// 접근하지 않고 이 좁은 인터페이스를 통해서만 정의·선택지·할당 명령을 수행한다.
type PropertyService interface {
	ListDefinitions(ctx context.Context, workspace domainentry.WorkspaceContext) ([]applicationproperty.DefinitionView, error)
	ListDefinitionsPage(ctx context.Context, workspace domainentry.WorkspaceContext, activeOnly bool, idFilter []domainentry.PropertyID, after *domainentry.PropertyID, limit int) ([]applicationproperty.DefinitionView, *domainentry.PropertyID, bool, error)
	CreateDefinition(ctx context.Context, workspace domainentry.WorkspaceContext, input applicationproperty.CreateDefinitionInput) (applicationproperty.DefinitionView, error)
	UpdateDefinitionMetadata(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, expectedRevision int, requestID string, displayName string) (applicationproperty.DefinitionView, error)
	DisableDefinition(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, expectedRevision int, requestID string) (applicationproperty.DefinitionView, error)
	CreateOption(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, expectedRevision int, requestID string, label string) (applicationproperty.DefinitionView, error)
	RenameOption(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, optionID domainentry.PropertyOptionID, expectedRevision int, requestID string, label string) (applicationproperty.DefinitionView, error)
	ReorderOptions(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, expectedRevision int, requestID string, orderedIDs []domainentry.PropertyOptionID) (applicationproperty.DefinitionView, error)
	DisableOption(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, optionID domainentry.PropertyOptionID, expectedRevision int, requestID string) (applicationproperty.DefinitionView, error)
	Prepare(ctx context.Context, workspace domainentry.WorkspaceContext, changes []applicationproperty.ChangeTarget) (applicationproperty.Proposal, error)
	Execute(ctx context.Context, workspace domainentry.WorkspaceContext, requestID string, changes []applicationproperty.ChangeTarget) ([]domainentry.EntryPropertyAssignment, error)
	ListAssignments(ctx context.Context, workspace domainentry.WorkspaceContext, localPath string, propertyIDs []domainentry.PropertyID) ([]domainentry.EntryPropertyAssignment, error)
}

// NewWithPropertyService는 Property 전용 테스트·조합 생성자다. 워크스페이스
// 식별이 typed UUIDv7로 파싱되지 않으면 실패 닫기로 서비스를 떼어 게이트가
// 거절한다.
func NewWithPropertyService(workspaceID string, service PropertyService) *Runtime {
	return NewWithServices(workspaceID, nil, service)
}

// NewWithServices는 daemon 조합용 생성자다. 각 서비스는 독립적으로 검증되며
// 구성되지 않은 서비스의 메서드는 메서드 게이트에서 unknown_method로 거절된다.
func NewWithServices(workspaceID string, entryService EntryService, propertyService PropertyService) *Runtime {
	if nilInterface(entryService) || workspaceID == "" {
		entryService = nil
	}
	if nilInterface(propertyService) {
		propertyService = nil
	} else if _, err := parseWorkspaceText(workspaceID); err != nil {
		propertyService = nil
	}
	return newWithAppVersionAndServices(AppVersion, workspaceID, entryService, propertyService)
}

// parseWorkspaceText는 하이픈 UUID 텍스트를 typed WorkspaceID로 파싱한다.
func parseWorkspaceText(text string) (domainentry.WorkspaceID, error) {
	raw, err := hex.DecodeString(strings.ReplaceAll(text, "-", ""))
	if err != nil {
		return domainentry.WorkspaceID{}, err
	}
	return domainentry.ParseWorkspaceID(raw)
}

// propertyParamsMissing은 Property 메서드별 필수 파라미터 결손을 검사한다.
// 각 케이스는 열거형 전체를 다루며 default는 실패 닫기다.
func propertyParamsMissing(request schema.Request) bool {
	switch request.Method {
	case schema.MethodPropertyDefinitionList:
		return request.PropertyDefinitionListParams == nil
	case schema.MethodPropertyDefinitionCreate:
		return request.PropertyDefinitionCreateParams == nil
	case schema.MethodPropertyDefinitionUpdate:
		return request.PropertyDefinitionUpdateParams == nil
	case schema.MethodPropertyDefinitionDisable:
		return request.PropertyDefinitionDisableParams == nil
	case schema.MethodPropertyOptionCreate:
		return request.PropertyOptionCreateParams == nil
	case schema.MethodPropertyOptionUpdate:
		return request.PropertyOptionUpdateParams == nil
	case schema.MethodPropertyOptionReorder:
		return request.PropertyOptionReorderParams == nil
	case schema.MethodPropertyOptionDisable:
		return request.PropertyOptionDisableParams == nil
	case schema.MethodPropertyAssignmentList:
		return request.PropertyAssignmentListParams == nil
	case schema.MethodPropertyChangePrepare:
		return request.PropertyChangePrepareParams == nil
	case schema.MethodPropertyChangeExecute:
		return request.PropertyChangeExecuteParams == nil
	default:
		return false
	}
}

// propertyDispatchGuard는 공통 실패 닫기 전제를 검사하고 주입된 워크스페이스
// 컨텍스트를 돌려준다.
func propertyDispatchGuard(ctx context.Context, workspaceID string, service PropertyService) (domainentry.WorkspaceContext, bool) {
	if ctx == nil || service == nil || workspaceID == "" {
		return domainentry.WorkspaceContext{}, false
	}
	workspace, err := parseWorkspaceText(workspaceID)
	if err != nil {
		return domainentry.WorkspaceContext{}, false
	}
	return domainentry.WorkspaceContext{ID: workspace}, true
}

func dispatchPropertyAssignmentList(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.PropertyAssignmentListParams
	propertyIDs, err := parsePropertyIDs(params.RequestedPropertyIDs)
	if err != nil {
		return dispatchError(request, schema.ErrorInvalidRequest)
	}
	facts, err := service.ListAssignments(ctx, workspace, params.Target.LocalPath, propertyIDs)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	definitions, err := loadDefinitionIndex(ctx, workspace, service)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	assignments, nextToken, hasMore := pageAssignmentFacts(facts, definitions, params)
	result := schema.PropertyAssignmentListResult{Assignments: assignments, NextPageToken: nextToken, HasMore: hasMore}
	return dispatchPropertySuccess(request, result)
}

func dispatchPropertyChangePrepare(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	changes, code := changeTargetsFromWire(request.PropertyChangePrepareParams.Changes)
	if code != "" {
		return dispatchError(request, code)
	}
	proposal, err := service.Prepare(ctx, workspace, changes)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	definitions, err := loadDefinitionIndex(ctx, workspace, service)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	result, code := prepareResultFromApplication(proposal, definitions, request.PropertyChangePrepareParams.Changes)
	if code != "" {
		return dispatchError(request, code)
	}
	return dispatchPropertySuccess(request, result)
}

func dispatchPropertyChangeExecute(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	changes, code := changeTargetsFromWire(request.PropertyChangeExecuteParams.Changes)
	if code != "" {
		return dispatchError(request, code)
	}
	facts, err := service.Execute(ctx, workspace, request.RequestID, changes)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	definitions, err := loadDefinitionIndex(ctx, workspace, service)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	assignments := make([]schema.PropertyAssignment, len(facts))
	for index, fact := range facts {
		mapped, mapCode := assignmentFactToWire(fact, definitions)
		if mapCode != "" {
			return dispatchError(request, mapCode)
		}
		assignments[index] = mapped
	}
	result := schema.PropertyChangeExecuteResult{Assignments: assignments}
	return dispatchPropertySuccess(request, result)
}

// dispatchPropertySuccess는 socket write 전에 응답 봉투 적합성을 강제한다.
// 초과 결과는 내부 폴백 대신 안정 코드 response_too_large로 거절된다.
func dispatchPropertySuccess(request schema.Request, result schema.Result) schema.Response {
	if _, fits := schema.EncodedSuccessBytes(request.RequestID, result); !fits {
		return dispatchError(request, schema.ErrorResponseTooLarge)
	}
	return dispatchSuccess(request, result)
}

func definitionViewResponse(request schema.Request, view applicationproperty.DefinitionView) schema.Response {
	definition, code := applicationproperty.DefinitionViewToWire(view)
	if code != "" {
		return dispatchError(request, code)
	}
	return dispatchPropertySuccess(request, schema.PropertyDefinitionResult{Definition: definition})
}

// parseOptionCommandIDs는 option update/disable 명령의 소유 정의와 선택지
// 식별자를 함께 파싱한다.
func parseOptionCommandIDs(propertyText, optionText string) (struct {
	propertyID domainentry.PropertyID
	optionID   domainentry.PropertyOptionID
}, schema.ErrorCode) {
	var ids struct {
		propertyID domainentry.PropertyID
		optionID   domainentry.PropertyOptionID
	}
	propertyID, err := domainentry.ParsePropertyID(propertyText)
	if err != nil {
		return ids, schema.ErrorInvalidRequest
	}
	optionID, err := domainentry.ParsePropertyOptionID(optionText)
	if err != nil {
		return ids, schema.ErrorInvalidRequest
	}
	ids.propertyID = propertyID
	ids.optionID = optionID
	return ids, ""
}

func parsePropertyIDs(texts []string) ([]domainentry.PropertyID, error) {
	ids := make([]domainentry.PropertyID, len(texts))
	for index, text := range texts {
		id, err := domainentry.ParsePropertyID(text)
		if err != nil {
			return nil, err
		}
		ids[index] = id
	}
	return ids, nil
}

// loadDefinitionIndex는 read-back 사상에 필요한 정의 계약(value_type,
// cardinality)을 한 번의 batched 목록 읽기로 모은다. 정의 유형과 카디널리티는
// 불변(ErrImmutableDefinitionField)이므로 커밋 뒤 재조회도 안전하다.
func loadDefinitionIndex(ctx context.Context, workspace domainentry.WorkspaceContext, service PropertyService) (map[domainentry.PropertyID]applicationproperty.DefinitionView, error) {
	views, err := service.ListDefinitions(ctx, workspace)
	if err != nil {
		return nil, err
	}
	index := make(map[domainentry.PropertyID]applicationproperty.DefinitionView, len(views))
	for _, view := range views {
		index[view.Definition.PropertyID] = view
	}
	return index, nil
}
