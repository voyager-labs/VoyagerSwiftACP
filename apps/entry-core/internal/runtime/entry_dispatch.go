package runtime

import (
	"context"
	"errors"
	"reflect"

	applicationentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/mount"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

type EntryService interface {
	UnifiedList(context.Context, applicationentry.UnifiedListRequest) (applicationentry.UnifiedListResult, error)
	ResolveEntry(context.Context, applicationentry.ResolveRequest) (applicationentry.ResolveResult, error)
}

func NewWithEntryService(workspaceID string, service EntryService) *Runtime {
	if nilInterface(service) || workspaceID == "" {
		service = nil
	}
	return newWithAppVersionAndServices(AppVersion, workspaceID, service, nil)
}

func (runtime *Runtime) Dispatch(ctx context.Context, request schema.Request) schema.Response {
	runtime.mu.RLock()
	state, appVersion := runtime.state, runtime.appVersion
	entryService, propertyService := runtime.entryService, runtime.propertyService
	workspaceID := runtime.workspaceID
	queryTokenKey := runtime.propertyQueryTokenKey
	runtime.mu.RUnlock()
	if state != StateRunning {
		return dispatchError(request, schema.ErrorInternal)
	}
	if !runtimeMethodAllowed(entryService != nil, propertyService != nil, request.Method) {
		return dispatchError(request, schema.ErrorUnknownMethod)
	}
	if request.Method == schema.MethodEntryList && request.EntryListParams == nil {
		return dispatchError(request, schema.ErrorInvalidRequest)
	}
	if request.Method == schema.MethodEntryResolve && request.EntryResolveParams == nil {
		return dispatchError(request, schema.ErrorInvalidRequest)
	}
	if propertyParamsMissing(request) {
		return dispatchError(request, schema.ErrorInvalidRequest)
	}

	switch request.Method {
	case schema.MethodPing:
		return dispatchSuccess(request, schema.PingResult{Message: "pong"})
	case schema.MethodHealth:
		return dispatchSuccess(request, schema.HealthResult{Status: "healthy", State: string(StateRunning)})
	case schema.MethodVersion:
		return dispatchSuccess(request, schema.VersionResult{AppVersion: appVersion})
	case schema.MethodEntryList:
		if entryService == nil {
			return dispatchError(request, schema.ErrorInternal)
		}
		return dispatchUnifiedList(ctx, request, workspaceID, entryService)
	case schema.MethodEntryResolve:
		return dispatchResolve(ctx, request, workspaceID, entryService)
	case schema.MethodPropertyDefinitionList:
		return dispatchPropertyDefinitionList(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyDefinitionCreate:
		return dispatchPropertyDefinitionCreate(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyDefinitionUpdate:
		return dispatchPropertyDefinitionUpdate(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyDefinitionDisable:
		return dispatchPropertyDefinitionDisable(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyOptionCreate:
		return dispatchPropertyOptionCreate(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyOptionUpdate:
		return dispatchPropertyOptionUpdate(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyOptionReorder:
		return dispatchPropertyOptionReorder(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyOptionDisable:
		return dispatchPropertyOptionDisable(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyAssignmentList:
		return dispatchPropertyAssignmentList(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyChangePrepare:
		return dispatchPropertyChangePrepare(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyChangeExecute:
		return dispatchPropertyChangeExecute(ctx, request, workspaceID, propertyService)
	case schema.MethodPropertyConditionQuery:
		return dispatchPropertyConditionQuery(ctx, request, workspaceID, propertyService, queryTokenKey)
	default:
		return dispatchError(request, schema.ErrorUnknownMethod)
	}
}

func dispatchUnifiedList(ctx context.Context, request schema.Request, workspaceID string, service EntryService) schema.Response {
	if ctx == nil || service == nil || workspaceID == "" {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.EntryListParams
	applicationRequest := applicationentry.UnifiedListRequest{WorkspaceID: workspaceID, MountID: cloneString(params.MountID), SourceInstanceID: cloneString(params.SourceInstanceID), PageSize: params.PageSize, PageToken: cloneString(params.PageToken), RequestedProperties: append([]string{}, params.RequestedProperties...)}
	if params.VirtualPath != "" {
		applicationRequest.VirtualPath = stringPointer(params.VirtualPath)
	}
	if params.ParentRef != nil {
		ref, err := params.ParentRef.Domain()
		if err != nil {
			return dispatchError(request, schema.ErrorInvalidRequest)
		}
		applicationRequest.ParentRef = &ref
	}
	result, err := service.UnifiedList(ctx, applicationRequest)
	if err != nil {
		if errors.Is(err, applicationentry.ErrInvalidRequest) && err.Error() == "page_size_too_small" {
			return schema.NewPageSizeTooSmallResponse(request.RequestID)
		}
		return dispatchError(request, protocolCodeForEntryError(err))
	}
	if len(result.Entries) > params.PageSize {
		return dispatchError(request, schema.ErrorInternal)
	}
	wire, err := schema.EntryListResultFromApplication(result)
	if err != nil {
		return dispatchError(request, schema.ErrorInternal)
	}
	return dispatchSuccess(request, wire)
}

func dispatchResolve(ctx context.Context, request schema.Request, workspaceID string, service EntryService) schema.Response {
	if ctx == nil || service == nil || workspaceID == "" {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.EntryResolveParams
	applicationRequest := applicationentry.ResolveRequest{WorkspaceID: workspaceID, VirtualPath: cloneString(params.VirtualPath), MountID: cloneString(params.MountID), RequestedProperties: append([]string{}, params.RequestedProperties...)}
	if params.EntryRef != nil {
		ref, err := params.EntryRef.Domain()
		if err != nil {
			return dispatchError(request, schema.ErrorInvalidSelector)
		}
		applicationRequest.EntryRef = &ref
	}
	result, err := service.ResolveEntry(ctx, applicationRequest)
	if err != nil {
		return dispatchError(request, protocolCodeForEntryError(err))
	}
	wire, err := schema.EntryResolveResultFromApplication(result)
	if err != nil {
		return dispatchError(request, schema.ErrorInternal)
	}
	return dispatchSuccess(request, wire)
}

func nilInterface(value any) bool {
	if value == nil {
		return true
	}
	ref := reflect.ValueOf(value)
	switch ref.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return ref.IsNil()
	}
	return false
}

func runtimeMethodAllowed(hasEntryService bool, hasPropertyService bool, method schema.Method) bool {
	switch method {
	case schema.MethodPing, schema.MethodHealth, schema.MethodVersion:
		return true
	case schema.MethodEntryList, schema.MethodEntryResolve:
		return hasEntryService
	case schema.MethodPropertyDefinitionList, schema.MethodPropertyDefinitionCreate, schema.MethodPropertyDefinitionUpdate, schema.MethodPropertyDefinitionDisable,
		schema.MethodPropertyOptionCreate, schema.MethodPropertyOptionUpdate, schema.MethodPropertyOptionReorder, schema.MethodPropertyOptionDisable,
		schema.MethodPropertyAssignmentList, schema.MethodPropertyChangePrepare, schema.MethodPropertyChangeExecute, schema.MethodPropertyConditionQuery:
		return hasPropertyService
	default:
		return false
	}
}

func protocolCodeForEntryError(err error) schema.ErrorCode {
	switch {
	case errors.Is(err, applicationentry.ErrInvalidSelector):
		return schema.ErrorInvalidSelector
	case errors.Is(err, applicationentry.ErrContextMismatch):
		return schema.ErrorContextMismatch
	case errors.Is(err, applicationentry.ErrScopeTooLarge):
		return schema.ErrorScopeTooLarge
	case errors.Is(err, applicationentry.ErrInvalidPageToken), errors.Is(err, source.ErrInvalidCursor):
		return schema.ErrorInvalidPageToken
	case errors.Is(err, applicationentry.ErrPermissionDenied), errors.Is(err, source.ErrPermissionDenied):
		return schema.ErrorPermissionDenied
	case errors.Is(err, applicationentry.ErrApplicationSourceUnavailable), errors.Is(err, source.ErrSourceUnavailable):
		return schema.ErrorSourceUnavailable
	case errors.Is(err, applicationentry.ErrApplicationSourceDeleted), errors.Is(err, source.ErrSourceDeleted):
		return schema.ErrorSourceDeleted
	case errors.Is(err, applicationentry.ErrEntryNotFound), errors.Is(err, source.ErrEntryNotFound):
		return schema.ErrorEntryNotFound
	case errors.Is(err, mount.ErrInvalidPath):
		return schema.ErrorInvalidPath
	case errors.Is(err, mount.ErrMountNotFound):
		return schema.ErrorMountNotFound
	case errors.Is(err, applicationentry.ErrSourceNotFound):
		return schema.ErrorSourceNotFound
	case errors.Is(err, applicationentry.ErrAmbiguousPropertySelector), errors.Is(err, applicationentry.ErrUnregisteredPropertyID):
		return schema.ErrorInvalidRequest
	case errors.Is(err, applicationentry.ErrInvalidRequest):
		return schema.ErrorInvalidRequest
	case errors.Is(err, applicationentry.ErrApplicationAdapterFailure), errors.Is(err, source.ErrAdapterFailure):
		return schema.ErrorAdapterFailure
	default:
		return schema.ErrorInternal
	}
}
func dispatchSuccess(request schema.Request, result schema.Result) schema.Response {
	return schema.NewSuccessResponse(request.RequestID, result)
}
func dispatchError(request schema.Request, code schema.ErrorCode) schema.Response {
	return schema.NewErrorResponse(request.RequestID, code)
}
func stringPointer(value string) *string { return &value }
func cloneString(value *string) *string {
	if value == nil {
		return nil
	}
	return stringPointer(*value)
}
