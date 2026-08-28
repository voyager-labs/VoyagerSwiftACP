package runtime

// Property 메서드 게이트 등록과 메서드별 성공 경로·명령 번역 테스트다.

import (
	"context"
	"testing"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

func TestPropertyDispatchMethodGate(t *testing.T) {
	view := testDefinitionView(testPropertyID, true)
	for _, method := range propertyMethods {
		if !runtimeMethodAllowed(false, true, method) {
			t.Fatalf("%s must be allowed with property service", method)
		}
		if runtimeMethodAllowed(false, false, method) || runtimeMethodAllowed(true, false, method) {
			t.Fatalf("%s must be rejected without property service", method)
		}
	}
	if !runtimeMethodAllowed(false, false, schema.MethodPing) || !runtimeMethodAllowed(false, false, schema.MethodHealth) || !runtimeMethodAllowed(false, false, schema.MethodVersion) {
		t.Fatal("lifecycle methods must stay always allowed")
	}
	if runtimeMethodAllowed(false, true, schema.MethodEntryList) || runtimeMethodAllowed(true, true, schema.MethodEntryResolve) == false {
		t.Fatal("entry methods must keep depending on the entry service only")
	}

	requests := map[schema.Method]schema.Request{
		schema.MethodPropertyDefinitionList:    {RequestID: "id", Method: schema.MethodPropertyDefinitionList, PropertyDefinitionListParams: &schema.PropertyDefinitionListParams{PageSize: 1, RequestedPropertyIDs: []string{}}},
		schema.MethodPropertyDefinitionCreate:  {RequestID: "id", Method: schema.MethodPropertyDefinitionCreate, PropertyDefinitionCreateParams: &schema.PropertyDefinitionCreateParams{Key: "k", Name: "n", ValueType: "text", Cardinality: "one"}},
		schema.MethodPropertyDefinitionUpdate:  {RequestID: "id", Method: schema.MethodPropertyDefinitionUpdate, PropertyDefinitionUpdateParams: &schema.PropertyDefinitionUpdateParams{PropertyID: testPropertyID, ExpectedDefinitionRevision: 1, Name: "n"}},
		schema.MethodPropertyDefinitionDisable: {RequestID: "id", Method: schema.MethodPropertyDefinitionDisable, PropertyDefinitionDisableParams: &schema.PropertyDefinitionDisableParams{PropertyID: testPropertyID, ExpectedDefinitionRevision: 1}},
		schema.MethodPropertyOptionCreate:      {RequestID: "id", Method: schema.MethodPropertyOptionCreate, PropertyOptionCreateParams: &schema.PropertyOptionCreateParams{PropertyID: testPropertyID, ExpectedDefinitionRevision: 1, Label: "L"}},
		schema.MethodPropertyOptionUpdate:      {RequestID: "id", Method: schema.MethodPropertyOptionUpdate, PropertyOptionUpdateParams: &schema.PropertyOptionUpdateParams{PropertyID: testPropertyID, OptionID: testOptionID, ExpectedDefinitionRevision: 1, Label: "L"}},
		schema.MethodPropertyOptionReorder:     {RequestID: "id", Method: schema.MethodPropertyOptionReorder, PropertyOptionReorderParams: &schema.PropertyOptionReorderParams{PropertyID: testPropertyID, ExpectedDefinitionRevision: 1, OptionIDs: []string{testOptionID}}},
		schema.MethodPropertyOptionDisable:     {RequestID: "id", Method: schema.MethodPropertyOptionDisable, PropertyOptionDisableParams: &schema.PropertyOptionDisableParams{PropertyID: testPropertyID, OptionID: testOptionID, ExpectedDefinitionRevision: 1}},
		schema.MethodPropertyAssignmentList:    {RequestID: "id", Method: schema.MethodPropertyAssignmentList, PropertyAssignmentListParams: &schema.PropertyAssignmentListParams{PageSize: 1, RequestedPropertyIDs: []string{}, Target: localPathTarget("/a")}},
		schema.MethodPropertyChangePrepare:     prepareRequest(changeTarget("/a", 1, schema.PropertyDesiredState{State: "null"})),
		schema.MethodPropertyChangeExecute:     executeRequest(changeTarget("/a", 1, schema.PropertyDesiredState{State: "null"})),
	}
	for _, method := range propertyMethods {
		gateService := newRecordingPropertyService()
		gateService.view = view
		gateService.listDefinitions = []applicationproperty.DefinitionView{view}
		if method == schema.MethodPropertyChangePrepare {
			gateService.proposal = applicationproperty.Proposal{Changes: []applicationproperty.PreparedChange{{
				EntryID:    testEntryID(),
				PropertyID: domainentry.MustPropertyID(testPropertyID),
				After:      domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateNull, RecordRevision: 1, ValueContractRevision: 1},
			}}, Definitions: proposalDefinitions(t, testPropertyID, view)}
		}
		if method == schema.MethodPropertyChangeExecute {
			gateService.facts = []domainentry.EntryPropertyAssignment{{
				EntryID: testEntryID(), PropertyID: domainentry.MustPropertyID(testPropertyID),
				State: domainentry.AssignmentStateNull, RecordRevision: 1, ValueContractRevision: 1,
			}}
		}
		response := New().Dispatch(context.Background(), requests[method])
		if response.Error == nil || response.Error.Code != schema.ErrorUnknownMethod {
			t.Fatalf("%s without service must be unknown_method, got %#v", method, response)
		}
		response = newPropertyRuntime(gateService).Dispatch(context.Background(), requests[method])
		if !response.OK {
			t.Fatalf("%s with service and valid params must reach the service, got %#v", method, response)
		}
		nilParams := requests[method]
		nilParams.RequestID = "id2"
		switch method {
		case schema.MethodPropertyDefinitionList:
			nilParams.PropertyDefinitionListParams = nil
		case schema.MethodPropertyDefinitionCreate:
			nilParams.PropertyDefinitionCreateParams = nil
		case schema.MethodPropertyDefinitionUpdate:
			nilParams.PropertyDefinitionUpdateParams = nil
		case schema.MethodPropertyDefinitionDisable:
			nilParams.PropertyDefinitionDisableParams = nil
		case schema.MethodPropertyOptionCreate:
			nilParams.PropertyOptionCreateParams = nil
		case schema.MethodPropertyOptionUpdate:
			nilParams.PropertyOptionUpdateParams = nil
		case schema.MethodPropertyOptionReorder:
			nilParams.PropertyOptionReorderParams = nil
		case schema.MethodPropertyOptionDisable:
			nilParams.PropertyOptionDisableParams = nil
		case schema.MethodPropertyAssignmentList:
			nilParams.PropertyAssignmentListParams = nil
		case schema.MethodPropertyChangePrepare:
			nilParams.PropertyChangePrepareParams = nil
		case schema.MethodPropertyChangeExecute:
			nilParams.PropertyChangeExecuteParams = nil
		default:
			t.Fatalf("unenumerated method %s", method)
		}
		response = newPropertyRuntime(newRecordingPropertyService()).Dispatch(context.Background(), nilParams)
		if response.Error == nil || response.Error.Code != schema.ErrorInvalidRequest {
			t.Fatalf("%s with nil params must be invalid_request, got %#v", method, response)
		}
	}
}

// TestPropertyDispatchHappyPathsPerMethod은 메서드별 성공 경로와 애플리케이션 명령
// 번역을 단언한다. 각 행은 디코딩된 파라미터가 서비스 인자로 정확히 옮겨졌음을
// 확인하고 응답이 wire 왕복에 생존함을 증명한다.

func TestPropertyDispatchHappyPathsPerMethod(t *testing.T) {
	view := testDefinitionView(testPropertyID, true)

	t.Run("catalog commands", func(t *testing.T) {
		service := newRecordingPropertyService()
		service.view = view
		runtime := newPropertyRuntime(service)

		create := schema.Request{RequestID: "r1", Method: schema.MethodPropertyDefinitionCreate, PropertyDefinitionCreateParams: &schema.PropertyDefinitionCreateParams{Key: "key", Name: "name", ValueType: "text", Cardinality: "one"}}
		if response := runtime.Dispatch(context.Background(), create); !response.OK {
			t.Fatalf("create response=%#v", response)
		}
		if service.lastCreateInput.Key != "key" || service.lastCreateInput.DisplayName != "name" ||
			service.lastCreateInput.ValueType != domainentry.PropertyTypeText || service.lastCreateInput.Cardinality != domainentry.PropertyCardinalityOne || len(service.lastCreateInput.OptionLabels) != 0 {
			t.Fatalf("create input=%+v", service.lastCreateInput)
		}

		update := schema.Request{RequestID: "r2", Method: schema.MethodPropertyDefinitionUpdate, PropertyDefinitionUpdateParams: &schema.PropertyDefinitionUpdateParams{PropertyID: testPropertyID, ExpectedDefinitionRevision: 3, Name: "renamed"}}
		if response := runtime.Dispatch(context.Background(), update); !response.OK {
			t.Fatalf("update response=%#v", response)
		}
		if service.lastExpectedRev != 3 || service.lastLabel != "renamed" {
			t.Fatalf("update capture rev=%d name=%s", service.lastExpectedRev, service.lastLabel)
		}

		disable := schema.Request{RequestID: "r3", Method: schema.MethodPropertyDefinitionDisable, PropertyDefinitionDisableParams: &schema.PropertyDefinitionDisableParams{PropertyID: testPropertyID, ExpectedDefinitionRevision: 2}}
		if response := runtime.Dispatch(context.Background(), disable); !response.OK {
			t.Fatalf("disable response=%#v", response)
		}
		if service.lastExpectedRev != 2 {
			t.Fatalf("disable capture rev=%d", service.lastExpectedRev)
		}

		optionCreate := schema.Request{RequestID: "r4", Method: schema.MethodPropertyOptionCreate, PropertyOptionCreateParams: &schema.PropertyOptionCreateParams{PropertyID: testPropertyID, ExpectedDefinitionRevision: 1, Label: "L"}}
		if response := runtime.Dispatch(context.Background(), optionCreate); !response.OK {
			t.Fatalf("option create response=%#v", response)
		}
		if service.lastExpectedRev != 1 || service.lastLabel != "L" {
			t.Fatalf("option create capture rev=%d label=%s", service.lastExpectedRev, service.lastLabel)
		}

		optionUpdate := schema.Request{RequestID: "r5", Method: schema.MethodPropertyOptionUpdate, PropertyOptionUpdateParams: &schema.PropertyOptionUpdateParams{PropertyID: testPropertyID, OptionID: testOptionID, ExpectedDefinitionRevision: 4, Label: "M"}}
		if response := runtime.Dispatch(context.Background(), optionUpdate); !response.OK {
			t.Fatalf("option update response=%#v", response)
		}
		if service.lastExpectedRev != 4 || service.lastLabel != "M" {
			t.Fatalf("option update capture rev=%d label=%s", service.lastExpectedRev, service.lastLabel)
		}

		reorder := schema.Request{RequestID: "r6", Method: schema.MethodPropertyOptionReorder, PropertyOptionReorderParams: &schema.PropertyOptionReorderParams{PropertyID: testPropertyID, ExpectedDefinitionRevision: 5, OptionIDs: []string{testOptionID2, testOptionID}}}
		if response := runtime.Dispatch(context.Background(), reorder); !response.OK {
			t.Fatalf("option reorder response=%#v", response)
		}
		if len(service.lastOptionIDs) != 2 || service.lastOptionIDs[0].String() != testOptionID2 || service.lastOptionIDs[1].String() != testOptionID {
			t.Fatalf("option reorder capture=%v", service.lastOptionIDs)
		}

		optionDisable := schema.Request{RequestID: "r7", Method: schema.MethodPropertyOptionDisable, PropertyOptionDisableParams: &schema.PropertyOptionDisableParams{PropertyID: testPropertyID, OptionID: testOptionID, ExpectedDefinitionRevision: 6}}
		if response := runtime.Dispatch(context.Background(), optionDisable); !response.OK {
			t.Fatalf("option disable response=%#v", response)
		}
		if service.lastExpectedRev != 6 {
			t.Fatalf("option disable capture rev=%d", service.lastExpectedRev)
		}
		if service.lastWorkspace.ID == (domainentry.WorkspaceID{}) {
			t.Fatal("workspace context must be injected by dispatch")
		}
	})

	t.Run("definition list round trip", func(t *testing.T) {
		service := newRecordingPropertyService()
		disabled := testDefinitionView(testPropertyID2, false)
		service.listDefinitions = []applicationproperty.DefinitionView{view, disabled}
		runtime := newPropertyRuntime(service)
		request := schema.Request{RequestID: "r8", Method: schema.MethodPropertyDefinitionList, PropertyDefinitionListParams: &schema.PropertyDefinitionListParams{PageSize: 8, RequestedPropertyIDs: []string{}, IncludeDisabled: true}}
		response := runtime.Dispatch(context.Background(), request)
		if !response.OK {
			t.Fatalf("list response=%#v", response)
		}
		decoded, err := schema.DecodeResponse(schema.EncodeResponse(response), schema.MethodPropertyDefinitionList)
		if err != nil {
			t.Fatalf("round trip: %v", err)
		}
		result := decoded.Result.(schema.PropertyDefinitionListResult)
		if len(result.Definitions) != 2 || result.Definitions[0].PropertyID != testPropertyID || result.Definitions[1].State != "disabled" {
			t.Fatalf("definitions=%+v", result.Definitions)
		}
	})

	t.Run("assignment list maps facts", func(t *testing.T) {
		service := newRecordingPropertyService()
		propertyID := domainentry.MustPropertyID(testPropertyID)
		service.listDefinitions = []applicationproperty.DefinitionView{view}
		service.facts = []domainentry.EntryPropertyAssignment{{
			WorkspaceID: service.lastWorkspace.ID, EntryID: testEntryID(), PropertyID: propertyID,
			State: domainentry.AssignmentStateValue, RecordRevision: 2, ValueContractRevision: 1,
			Scalar: &domainentry.AssignmentValue{Text: strPtr("hello")},
		}}
		runtime := newPropertyRuntime(service)
		request := schema.Request{RequestID: "r9", Method: schema.MethodPropertyAssignmentList, PropertyAssignmentListParams: &schema.PropertyAssignmentListParams{PageSize: 8, RequestedPropertyIDs: []string{testPropertyID}, Target: localPathTarget("/docs/a.txt")}}
		response := runtime.Dispatch(context.Background(), request)
		if !response.OK {
			t.Fatalf("assignment list response=%#v", response)
		}
		if service.lastLocalPath != "/docs/a.txt" || len(service.lastPropertyIDs) != 1 || service.lastPropertyIDs[0].String() != testPropertyID {
			t.Fatalf("assignment list capture path=%s ids=%v", service.lastLocalPath, service.lastPropertyIDs)
		}
		decoded, err := schema.DecodeResponse(schema.EncodeResponse(response), schema.MethodPropertyAssignmentList)
		if err != nil {
			t.Fatalf("round trip: %v", err)
		}
		result := decoded.Result.(schema.PropertyAssignmentListResult)
		if len(result.Assignments) != 1 || result.Assignments[0].State != "value" || result.Assignments[0].Revision != 2 {
			t.Fatalf("assignments=%+v", result.Assignments)
		}
	})

	t.Run("prepare echoes proposal with contract confirmation", func(t *testing.T) {
		service := newRecordingPropertyService()
		service.listDefinitions = []applicationproperty.DefinitionView{view}
		propertyID := domainentry.MustPropertyID(testPropertyID)
		before := domainentry.EntryPropertyAssignment{EntryID: testEntryID(), PropertyID: propertyID, State: domainentry.AssignmentStateValue, RecordRevision: 1, ValueContractRevision: 1, Scalar: &domainentry.AssignmentValue{Text: strPtr("old")}}
		after := before
		after.RecordRevision = 2
		after.Scalar = &domainentry.AssignmentValue{Text: strPtr("new")}
		service.proposal = applicationproperty.Proposal{Changes: []applicationproperty.PreparedChange{{EntryID: testEntryID(), PropertyID: propertyID, Before: &before, After: after}}, RequiresConfirmation: false, Definitions: proposalDefinitions(t, testPropertyID, view)}
		runtime := newPropertyRuntime(service)
		desired := schema.PropertyDesiredState{State: "value", ValueType: "text", Cardinality: "one", Payload: textPayload(t, "new")}
		response := runtime.Dispatch(context.Background(), prepareRequest(changeTarget("/a", 2, desired)))
		if !response.OK {
			t.Fatalf("prepare response=%#v", response)
		}
		if len(service.lastChanges) != 1 || service.lastChanges[0].ExpectedAssignmentRevision != 2 {
			t.Fatalf("prepare capture=%+v", service.lastChanges)
		}
		decoded, err := schema.DecodeResponse(schema.EncodeResponse(response), schema.MethodPropertyChangePrepare)
		if err != nil {
			t.Fatalf("round trip: %v", err)
		}
		result := decoded.Result.(schema.PropertyChangePrepareResult)
		if !result.RequiresConfirmation || len(result.Changes) != 1 || result.Changes[0].Before == nil || result.Changes[0].After.State != "value" {
			t.Fatalf("prepared=%+v", result)
		}
	})
}

// proposalDefinitions은 prepare 응답 매핑이 사용할 요청 정의 뷰를 만든다.
func proposalDefinitions(t *testing.T, idText string, view applicationproperty.DefinitionView) map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition {
	t.Helper()
	if view.Definition.PropertyID == (domainentry.PropertyID{}) {
		view.Definition.PropertyID = domainentry.MustPropertyID(idText)
	}
	return map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition{
		view.Definition.PropertyID: view.Definition,
	}
}
