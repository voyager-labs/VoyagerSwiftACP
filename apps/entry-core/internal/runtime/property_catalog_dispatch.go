package runtime

// Property 정의·선택지 명령의 dispatch 어댑터다. 각 함수는 디코딩된 wire DTO를
// application 명령으로 번역하고 결과를 wire로 되돌린다.

import (
	"context"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

func dispatchPropertyDefinitionList(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.PropertyDefinitionListParams
	views, err := service.ListDefinitions(ctx, workspace)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	definitions, nextToken, hasMore := pageDefinitionViews(views, params)
	result := schema.PropertyDefinitionListResult{Definitions: definitions, NextPageToken: nextToken, HasMore: hasMore}
	return dispatchPropertySuccess(request, result)
}

func dispatchPropertyDefinitionCreate(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.PropertyDefinitionCreateParams
	input := applicationproperty.CreateDefinitionInput{
		Key:          params.Key,
		DisplayName:  params.Name,
		ValueType:    domainentry.PropertyType(params.ValueType),
		Cardinality:  domainentry.PropertyCardinality(params.Cardinality),
		OptionLabels: append([]string{}, params.OptionLabels...),
		RequestID:    request.RequestID,
	}
	view, err := service.CreateDefinition(ctx, workspace, input)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	return definitionViewResponse(request, view)
}

func dispatchPropertyDefinitionUpdate(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.PropertyDefinitionUpdateParams
	propertyID, err := domainentry.ParsePropertyID(params.PropertyID)
	if err != nil {
		return dispatchError(request, schema.ErrorInvalidRequest)
	}
	view, err := service.UpdateDefinitionMetadata(ctx, workspace, propertyID, int(params.ExpectedDefinitionRevision), request.RequestID, params.Name)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	return definitionViewResponse(request, view)
}

func dispatchPropertyDefinitionDisable(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.PropertyDefinitionDisableParams
	propertyID, err := domainentry.ParsePropertyID(params.PropertyID)
	if err != nil {
		return dispatchError(request, schema.ErrorInvalidRequest)
	}
	view, err := service.DisableDefinition(ctx, workspace, propertyID, int(params.ExpectedDefinitionRevision), request.RequestID)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	return definitionViewResponse(request, view)
}

func dispatchPropertyOptionCreate(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.PropertyOptionCreateParams
	propertyID, err := domainentry.ParsePropertyID(params.PropertyID)
	if err != nil {
		return dispatchError(request, schema.ErrorInvalidRequest)
	}
	view, err := service.CreateOption(ctx, workspace, propertyID, int(params.ExpectedDefinitionRevision), request.RequestID, params.Label)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	return definitionViewResponse(request, view)
}

func dispatchPropertyOptionUpdate(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.PropertyOptionUpdateParams
	ids, code := parseOptionCommandIDs(params.PropertyID, params.OptionID)
	if code != "" {
		return dispatchError(request, code)
	}
	view, err := service.RenameOption(ctx, workspace, ids.propertyID, ids.optionID, int(params.ExpectedDefinitionRevision), request.RequestID, params.Label)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	return definitionViewResponse(request, view)
}

func dispatchPropertyOptionReorder(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.PropertyOptionReorderParams
	propertyID, err := domainentry.ParsePropertyID(params.PropertyID)
	if err != nil {
		return dispatchError(request, schema.ErrorInvalidRequest)
	}
	orderedIDs := make([]domainentry.PropertyOptionID, len(params.OptionIDs))
	for index, text := range params.OptionIDs {
		optionID, parseErr := domainentry.ParsePropertyOptionID(text)
		if parseErr != nil {
			return dispatchError(request, schema.ErrorInvalidRequest)
		}
		orderedIDs[index] = optionID
	}
	view, err := service.ReorderOptions(ctx, workspace, propertyID, int(params.ExpectedDefinitionRevision), request.RequestID, orderedIDs)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	return definitionViewResponse(request, view)
}

func dispatchPropertyOptionDisable(ctx context.Context, request schema.Request, workspaceID string, service PropertyService) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, service)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.PropertyOptionDisableParams
	ids, code := parseOptionCommandIDs(params.PropertyID, params.OptionID)
	if code != "" {
		return dispatchError(request, code)
	}
	view, err := service.DisableOption(ctx, workspace, ids.propertyID, ids.optionID, int(params.ExpectedDefinitionRevision), request.RequestID)
	if err != nil {
		return dispatchError(request, protocolCodeForPropertyError(err))
	}
	return definitionViewResponse(request, view)
}
