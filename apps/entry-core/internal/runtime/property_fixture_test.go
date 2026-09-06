package runtime

// Property dispatch 테스트 공용 fixture다. recording 서비스와 요청 빌더만
// 소유하며 개별 시나리오는 각 테스트 파일이 소유한다.

import (
	"context"
	"sort"
	"strings"
	"testing"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

const (
	testWorkspaceText = "0198abcd-7b3f-7c3e-9f2a-4b6e8d0f1a2b"
	testPropertyID    = "0198c0a2-7b3f-7111-8f2a-4b6e8d0f1a2b"
	testPropertyID2   = "0198c0a2-7b3f-7444-8f2a-4b6e8d0f1a2e"
	testOptionID      = "0198c0a2-7b3f-7222-8f2a-4b6e8d0f1a2c"
	testOptionID2     = "0198c0a2-7b3f-7333-8f2a-4b6e8d0f1a2d"
)

var propertyMethods = []schema.Method{
	schema.MethodPropertyDefinitionList,
	schema.MethodPropertyDefinitionCreate,
	schema.MethodPropertyDefinitionUpdate,
	schema.MethodPropertyDefinitionDisable,
	schema.MethodPropertyOptionCreate,
	schema.MethodPropertyOptionUpdate,
	schema.MethodPropertyOptionReorder,
	schema.MethodPropertyOptionDisable,
	schema.MethodPropertyAssignmentList,
	schema.MethodPropertyChangePrepare,
	schema.MethodPropertyChangeExecute,
}

// recordingPropertyService는 모든 PropertyService 메서드를 기록하고 고정 결과를
// 반환하는 페이크다. 호출별 계수와 마지막 인자를 노출해 명령 번역을 단언한다.

func newRecordingPropertyService() *recordingPropertyService {
	return &recordingPropertyService{calls: map[string]int{}}
}

func (service *recordingPropertyService) record(name string, workspace domainentry.WorkspaceContext) {
	service.calls[name]++
	service.lastWorkspace = workspace
}

func (service *recordingPropertyService) ListDefinitionsPage(ctx context.Context, workspace domainentry.WorkspaceContext, activeOnly bool, idFilter []domainentry.PropertyID, after *domainentry.PropertyID, limit int) ([]applicationproperty.DefinitionView, *domainentry.PropertyID, bool, error) {
	views, err := service.ListDefinitions(ctx, workspace)
	if err != nil {
		return nil, nil, false, err
	}
	filtered := make([]applicationproperty.DefinitionView, 0, len(views))
	for _, view := range views {
		if activeOnly && !view.IsActive() {
			continue
		}
		wanted := len(idFilter) == 0
		for _, id := range idFilter {
			if view.Definition.PropertyID == id {
				wanted = true
				break
			}
		}
		if !wanted {
			continue
		}
		if after != nil && !(view.Definition.PropertyID.String() > after.String()) {
			continue
		}
		filtered = append(filtered, view)
	}
	sort.Slice(filtered, func(i, j int) bool {
		return filtered[i].Definition.PropertyID.String() < filtered[j].Definition.PropertyID.String()
	})
	hasMore := len(filtered) > limit
	if hasMore {
		filtered = filtered[:limit]
	}
	var next *domainentry.PropertyID
	if len(filtered) > 0 {
		id := filtered[len(filtered)-1].Definition.PropertyID
		next = &id
	}
	return filtered, next, hasMore, nil
}

func (service *recordingPropertyService) ListDefinitions(ctx context.Context, workspace domainentry.WorkspaceContext) ([]applicationproperty.DefinitionView, error) {
	service.record("list_definitions", workspace)
	return service.listDefinitions, service.serviceErr
}

func (service *recordingPropertyService) CreateDefinition(ctx context.Context, workspace domainentry.WorkspaceContext, input applicationproperty.CreateDefinitionInput) (applicationproperty.DefinitionView, error) {
	service.record("create_definition", workspace)
	service.lastCreateInput = input
	return service.view, service.serviceErr
}

func (service *recordingPropertyService) UpdateDefinitionMetadata(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, expectedRevision int, requestID string, displayName string) (applicationproperty.DefinitionView, error) {
	service.record("update_definition", workspace)
	service.lastExpectedRev = expectedRevision
	service.lastLabel = displayName
	return service.view, service.serviceErr
}

func (service *recordingPropertyService) DisableDefinition(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, expectedRevision int, requestID string) (applicationproperty.DefinitionView, error) {
	service.record("disable_definition", workspace)
	service.lastExpectedRev = expectedRevision
	return service.view, service.serviceErr
}

func (service *recordingPropertyService) CreateOption(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, expectedRevision int, requestID string, label string) (applicationproperty.DefinitionView, error) {
	service.record("create_option", workspace)
	service.lastExpectedRev = expectedRevision
	service.lastLabel = label
	return service.view, service.serviceErr
}

func (service *recordingPropertyService) RenameOption(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, optionID domainentry.PropertyOptionID, expectedRevision int, requestID string, label string) (applicationproperty.DefinitionView, error) {
	service.record("rename_option", workspace)
	service.lastExpectedRev = expectedRevision
	service.lastLabel = label
	return service.view, service.serviceErr
}

func (service *recordingPropertyService) ReorderOptions(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, expectedRevision int, requestID string, orderedIDs []domainentry.PropertyOptionID) (applicationproperty.DefinitionView, error) {
	service.record("reorder_options", workspace)
	service.lastExpectedRev = expectedRevision
	service.lastOptionIDs = orderedIDs
	return service.view, service.serviceErr
}

func (service *recordingPropertyService) DisableOption(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID, optionID domainentry.PropertyOptionID, expectedRevision int, requestID string) (applicationproperty.DefinitionView, error) {
	service.record("disable_option", workspace)
	service.lastExpectedRev = expectedRevision
	return service.view, service.serviceErr
}

func (service *recordingPropertyService) Prepare(ctx context.Context, workspace domainentry.WorkspaceContext, changes []applicationproperty.ChangeTarget) (applicationproperty.Proposal, error) {
	service.record("prepare", workspace)
	service.lastChanges = changes
	return service.proposal, service.serviceErr
}

func (service *recordingPropertyService) Execute(ctx context.Context, workspace domainentry.WorkspaceContext, requestID string, changes []applicationproperty.ChangeTarget) (applicationproperty.ExecuteResult, error) {
	service.record("execute", workspace)
	service.lastRequestID = requestID
	service.lastChanges = changes
	definitions := make(map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition, len(service.listDefinitions))
	for _, view := range service.listDefinitions {
		definitions[view.Definition.PropertyID] = view.Definition
	}
	return applicationproperty.ExecuteResult{Facts: service.facts, Definitions: definitions}, service.serviceErr
}

func (service *recordingPropertyService) ListAssignmentsPage(ctx context.Context, workspace domainentry.WorkspaceContext, localPath string, requestedIDs []domainentry.PropertyID, after *domainentry.PropertyID, limit int) ([]domainentry.EntryPropertyAssignment, map[domainentry.PropertyID]applicationproperty.DefinitionView, *domainentry.PropertyID, bool, error) {
	service.record("list_assignments", workspace)
	service.lastLocalPath = localPath
	service.lastPropertyIDs = requestedIDs
	facts := make([]domainentry.EntryPropertyAssignment, 0, len(service.facts))
	for _, fact := range service.facts {
		wanted := len(requestedIDs) == 0
		for _, id := range requestedIDs {
			if fact.PropertyID == id {
				wanted = true
				break
			}
		}
		if !wanted {
			continue
		}
		if after != nil && !(fact.PropertyID.String() > after.String()) {
			continue
		}
		facts = append(facts, fact)
	}
	sort.Slice(facts, func(i, j int) bool {
		return facts[i].PropertyID.String() < facts[j].PropertyID.String()
	})
	hasMore := len(facts) > limit
	if hasMore {
		facts = facts[:limit]
	}
	var next *domainentry.PropertyID
	if len(facts) > 0 {
		id := facts[len(facts)-1].PropertyID
		next = &id
	}
	views := make(map[domainentry.PropertyID]applicationproperty.DefinitionView, len(service.listDefinitions))
	for _, view := range service.listDefinitions {
		views[view.Definition.PropertyID] = view
	}
	return facts, views, next, hasMore, service.serviceErr
}

func newPropertyRuntime(service *recordingPropertyService) *Runtime {
	return NewWithPropertyService(testWorkspaceText, service)
}

func testDefinitionView(idText string, active bool) applicationproperty.DefinitionView {
	lifecycle := domainentry.PropertyLifecycleTombstoned
	if active {
		lifecycle = domainentry.PropertyLifecycleActive
	}
	return applicationproperty.DefinitionView{
		Definition: domainentry.WorkspacePropertyDefinition{
			PropertyID:    domainentry.MustPropertyID(idText),
			CanonicalKey:  "key_" + strings.ReplaceAll(idText[len(idText)-6:], "-", "_"),
			DisplayName:   "display name",
			Lifecycle:     lifecycle,
			ValueType:     domainentry.PropertyTypeText,
			Cardinality:   domainentry.PropertyCardinalityOne,
			Origin:        domainentry.PropertyOriginUserDefined,
			DefinitionRev: 1,
		},
	}
}

func testEntryID() string {
	return domainentry.DeriveEntryID("src:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "file", "object")
}

func localPathTarget(path string) schema.PropertyTargetSelector {
	return schema.PropertyTargetSelector{Kind: "local_path", LocalPath: path}
}

func changeTarget(path string, assignmentRevision int64, desired schema.PropertyDesiredState) schema.PropertyChangeTarget {
	return schema.PropertyChangeTarget{
		Target:                     localPathTarget(path),
		EntryID:                    testEntryID(),
		PropertyID:                 testPropertyID,
		ExpectedDefinitionRevision: 1,
		ExpectedAssignmentRevision: assignmentRevision,
		Desired:                    desired,
	}
}

func prepareRequest(changes ...schema.PropertyChangeTarget) schema.Request {
	return schema.Request{RequestID: "id", Method: schema.MethodPropertyChangePrepare, PropertyChangePrepareParams: &schema.PropertyChangePrepareParams{Changes: changes}}
}

func executeRequest(changes ...schema.PropertyChangeTarget) schema.Request {
	return schema.Request{RequestID: "id", Method: schema.MethodPropertyChangeExecute, PropertyChangeExecuteParams: &schema.PropertyChangeExecuteParams{Changes: changes}}
}

func strPtr(value string) *string { return &value }

func textPayload(t *testing.T, value string) *schema.PropertyPayload {
	t.Helper()
	payload, ok := schema.NewPropertyPayload("text", "one", value, nil)
	if !ok {
		t.Fatalf("payload %q", value)
	}
	return &payload
}
