package runtime

import (
	"context"
	"encoding/json"
	"testing"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// executeFixtureDefinition은 read-back 사상 검증에 쓰는 정의 뷰를 만든다.
func executeFixtureDefinition(idText, valueType, cardinality string) applicationproperty.DefinitionView {
	return applicationproperty.DefinitionView{
		Definition: domainentry.WorkspacePropertyDefinition{
			PropertyID:    domainentry.MustPropertyID(idText),
			Lifecycle:     domainentry.PropertyLifecycleActive,
			ValueType:     domainentry.PropertyType(valueType),
			Cardinality:   domainentry.PropertyCardinality(cardinality),
			DefinitionRev: 1,
		},
	}
}

// TestPropertyExecuteReadBackMatchesApplicationOutputExactly는 execute 정준
// read-back이 애플리케이션 fact를 완전하게 운반함을 증명한다. value 스칼라,
// 순서 있는 many 선택지, 빈 many, null, 내구 unset(→unknown)과 revision 항등
// 사상, 요청 순서 보존을 한 표로 잠근다.
func TestPropertyExecuteReadBackMatchesApplicationOutputExactly(t *testing.T) {
	entryID := testEntryID()
	textID := domainentry.MustPropertyID(testPropertyID)
	selectID := domainentry.MustPropertyID(testPropertyID2)
	optionA := domainentry.MustPropertyOptionID(testOptionID)
	optionB := domainentry.MustPropertyOptionID(testOptionID2)
	emptyTextID := domainentry.MustPropertyID("0198c0a2-7b3f-7555-8f2a-4b6e8d0f1a0b")
	nullID := domainentry.MustPropertyID("0198c0a2-7b3f-7666-8f2a-4b6e8d0f1a1b")
	unsetID := domainentry.MustPropertyID("0198c0a2-7b3f-7777-8f2a-4b6e8d0f1a2b")

	service := newRecordingPropertyService()
	service.listDefinitions = []applicationproperty.DefinitionView{
		executeFixtureDefinition(testPropertyID, "text", "one"),
		executeFixtureDefinition(testPropertyID2, "select", "many"),
		executeFixtureDefinition("0198c0a2-7b3f-7555-8f2a-4b6e8d0f1a0b", "text", "many"),
		executeFixtureDefinition("0198c0a2-7b3f-7666-8f2a-4b6e8d0f1a1b", "text", "one"),
		executeFixtureDefinition("0198c0a2-7b3f-7777-8f2a-4b6e8d0f1a2b", "text", "one"),
	}
	service.facts = []domainentry.EntryPropertyAssignment{
		{EntryID: entryID, PropertyID: textID, State: domainentry.AssignmentStateValue, RecordRevision: 3, ValueContractRevision: 1, Scalar: &domainentry.AssignmentValue{Text: strPtr("hello")}},
		{EntryID: entryID, PropertyID: selectID, State: domainentry.AssignmentStateValue, RecordRevision: 2, ValueContractRevision: 1, Many: []domainentry.OrderedAssignmentValue{{Ordinal: 0, Value: domainentry.AssignmentValue{OptionID: &optionB}}, {Ordinal: 1, Value: domainentry.AssignmentValue{OptionID: &optionA}}}},
		{EntryID: entryID, PropertyID: emptyTextID, State: domainentry.AssignmentStateValue, RecordRevision: 1, ValueContractRevision: 1, Many: []domainentry.OrderedAssignmentValue{}},
		{EntryID: entryID, PropertyID: nullID, State: domainentry.AssignmentStateNull, RecordRevision: 4, ValueContractRevision: 1},
		{EntryID: entryID, PropertyID: unsetID, State: domainentry.AssignmentStateUnset, RecordRevision: 2, ValueContractRevision: 1},
	}
	runtime := newPropertyRuntime(service)
	desired := schema.PropertyDesiredState{State: "value", ValueType: "text", Cardinality: "one", Payload: textPayload(t, "x")}
	response := runtime.Dispatch(context.Background(), executeRequest(changeTarget("/a", 1, desired)))
	if !response.OK {
		t.Fatalf("execute response=%#v", response)
	}
	expected := schema.PropertyChangeExecuteResult{Assignments: []schema.PropertyAssignment{
		{PropertyID: testPropertyID, EntryID: entryID, ValueType: "text", Cardinality: "one", State: "value", Revision: 3, Payload: textPayloadPtr("hello")},
		{PropertyID: testPropertyID2, EntryID: entryID, ValueType: "select", Cardinality: "many", State: "value", Revision: 2, Payload: selectManyPayload(t, []string{testOptionID2, testOptionID})},
		{PropertyID: "0198c0a2-7b3f-7555-8f2a-4b6e8d0f1a0b", EntryID: entryID, ValueType: "text", Cardinality: "many", State: "value", Revision: 1, Payload: textManyPayload(t, []string{})},
		{PropertyID: "0198c0a2-7b3f-7666-8f2a-4b6e8d0f1a1b", EntryID: entryID, ValueType: "text", Cardinality: "one", State: "null", Revision: 4},
		{PropertyID: "0198c0a2-7b3f-7777-8f2a-4b6e8d0f1a2b", EntryID: entryID, ValueType: "text", Cardinality: "one", State: "unknown", Revision: 2},
	}}
	if got := response.Result.(schema.PropertyChangeExecuteResult); len(got.Assignments) != len(expected.Assignments) {
		t.Fatalf("assignments=%+v", got)
	}
	for index, assignment := range response.Result.(schema.PropertyChangeExecuteResult).Assignments {
		if !sameAssignment(assignment, expected.Assignments[index]) {
			t.Fatalf("assignment %d = %+v want %+v", index, assignment, expected.Assignments[index])
		}
	}
	decoded, err := schema.DecodeResponse(schema.EncodeResponse(response), schema.MethodPropertyChangeExecute)
	if err != nil {
		t.Fatalf("round trip: %v", err)
	}
	roundTripped := decoded.Result.(schema.PropertyChangeExecuteResult)
	for index, assignment := range roundTripped.Assignments {
		if !sameAssignment(assignment, expected.Assignments[index]) {
			t.Fatalf("round trip %d = %+v want %+v", index, assignment, expected.Assignments[index])
		}
	}
}

// sameAssignment은 payload 포인터를 값 비교로 바꿔 assignment 전체를 비교한다.
func sameAssignment(left, right schema.PropertyAssignment) bool {
	leftWire, leftErr := json.Marshal(left)
	rightWire, rightErr := json.Marshal(right)
	return leftErr == nil && rightErr == nil && string(leftWire) == string(rightWire)
}

// sameScalar은 포인터 멤버를 값 기준으로 비교한다.
func sameScalar(left, right domainentry.AssignmentValue) bool {
	leftWire, leftErr := json.Marshal(left)
	rightWire, rightErr := json.Marshal(right)
	return leftErr == nil && rightErr == nil && string(leftWire) == string(rightWire)
}

func textPayloadPtr(value string) *schema.PropertyPayload {
	payload, _ := schema.NewPropertyPayload("text", "one", value, nil)
	return &payload
}

func selectManyPayload(t *testing.T, values []string) *schema.PropertyPayload {
	t.Helper()
	payload, ok := schema.NewPropertyPayload("select", "many", nil, values)
	if !ok {
		t.Fatalf("select many payload %v", values)
	}
	return &payload
}

func textManyPayload(t *testing.T, values []string) *schema.PropertyPayload {
	t.Helper()
	payload, ok := schema.NewPropertyPayload("text", "many", nil, values)
	if !ok {
		t.Fatalf("text many payload %v", values)
	}
	return &payload
}

// TestPropertyDesiredStateMappingVariants는 wire 목표 상태 전체와 예상 assignment
// revision 오프셋(wire R ↔ 도메인 R-1, wire 1 = implicit unset@0)을 열거한다.
// not_applicable은 이 슬라이스에서 쓰기 불가이며 unsupported로 명시 거절된다.
func TestPropertyDesiredStateMappingVariants(t *testing.T) {
	tests := []struct {
		name          string
		desired       schema.PropertyDesiredState
		wantState     domainentry.AssignmentState
		wantScalar    *domainentry.AssignmentValue
		wantManyCount int
	}{
		{"value one text", schema.PropertyDesiredState{State: "value", ValueType: "text", Cardinality: "one", Payload: textPayload(t, "hi")}, domainentry.AssignmentStateValue, &domainentry.AssignmentValue{Text: strPtr("hi")}, 0},
		{"value one boolean", schema.PropertyDesiredState{State: "value", ValueType: "boolean", Cardinality: "one", Payload: boolOnePayload(t, true)}, domainentry.AssignmentStateValue, &domainentry.AssignmentValue{Boolean: strBoolPtr(true)}, 0},
		{"value one number", schema.PropertyDesiredState{State: "value", ValueType: "number", Cardinality: "one", Payload: stringOnePayload(t, "number", "1.5")}, domainentry.AssignmentStateValue, &domainentry.AssignmentValue{Decimal: strPtr("1.5")}, 0},
		{"value one date", schema.PropertyDesiredState{State: "value", ValueType: "date", Cardinality: "one", Payload: stringOnePayload(t, "date", "2026-08-26")}, domainentry.AssignmentStateValue, &domainentry.AssignmentValue{Date: strPtr("2026-08-26")}, 0},
		{"value one datetime", schema.PropertyDesiredState{State: "value", ValueType: "datetime", Cardinality: "one", Payload: stringOnePayload(t, "datetime", "2026-08-26T00:00:00Z")}, domainentry.AssignmentStateValue, &domainentry.AssignmentValue{Timestamp: strPtr("2026-08-26T00:00:00Z")}, 0},
		{"value one select", schema.PropertyDesiredState{State: "value", ValueType: "select", Cardinality: "one", Payload: stringOnePayload(t, "select", testOptionID)}, domainentry.AssignmentStateValue, &domainentry.AssignmentValue{OptionID: optionPtr(t, testOptionID)}, 0},
		{"value many text keeps order and empty member", schema.PropertyDesiredState{State: "value", ValueType: "text", Cardinality: "many", Payload: textManyPayload(t, []string{"b", ""})}, domainentry.AssignmentStateValue, nil, 2},
		{"null", schema.PropertyDesiredState{State: "null"}, domainentry.AssignmentStateNull, nil, 0},
		{"unknown clears to unset", schema.PropertyDesiredState{State: "unknown"}, domainentry.AssignmentStateUnset, nil, 0},
	}
	for _, test := range tests {
		service := newRecordingPropertyService()
		service.listDefinitions = []applicationproperty.DefinitionView{executeFixtureDefinition(testPropertyID, "text", "one")}
		service.facts = []domainentry.EntryPropertyAssignment{{
			EntryID: testEntryID(), PropertyID: domainentry.MustPropertyID(testPropertyID),
			State: domainentry.AssignmentStateValue, RecordRevision: 1, ValueContractRevision: 1,
			Scalar: &domainentry.AssignmentValue{Text: strPtr("x")},
		}}
		runtime := newPropertyRuntime(service)
		response := runtime.Dispatch(context.Background(), executeRequest(changeTarget("/a", 7, test.desired)))
		if !response.OK {
			t.Fatalf("%s: response=%#v", test.name, response)
		}
		change := service.lastChanges[0]
		if change.Desired.State != test.wantState {
			t.Fatalf("%s: state=%v want %v", test.name, change.Desired.State, test.wantState)
		}
		if change.ExpectedAssignmentRevision != 6 {
			t.Fatalf("%s: expected revision=%d want 6 (wire 7 - offset 1)", test.name, change.ExpectedAssignmentRevision)
		}
		if test.wantScalar != nil && !sameScalar(*change.Desired.Scalar, *test.wantScalar) {
			t.Fatalf("%s: scalar=%+v want %+v", test.name, *change.Desired.Scalar, *test.wantScalar)
		}
		if test.desired.Payload != nil && test.desired.Cardinality == "many" && len(change.Desired.Many) != test.wantManyCount {
			t.Fatalf("%s: many=%d want %d", test.name, len(change.Desired.Many), test.wantManyCount)
		}
	}

	firstTouch := newRecordingPropertyService()
	firstTouch.listDefinitions = []applicationproperty.DefinitionView{executeFixtureDefinition(testPropertyID, "text", "one")}
	firstTouch.facts = []domainentry.EntryPropertyAssignment{{
		EntryID: testEntryID(), PropertyID: domainentry.MustPropertyID(testPropertyID),
		State: domainentry.AssignmentStateValue, RecordRevision: 1, ValueContractRevision: 1,
		Scalar: &domainentry.AssignmentValue{Text: strPtr("x")},
	}}
	if response := newPropertyRuntime(firstTouch).Dispatch(context.Background(), executeRequest(changeTarget("/a", 1, schema.PropertyDesiredState{State: "null"}))); !response.OK {
		t.Fatalf("first touch response=%#v", response)
	}
	if firstTouch.lastChanges[0].ExpectedAssignmentRevision != 0 {
		t.Fatalf("wire revision 1 must mean implicit unset@0, got %d", firstTouch.lastChanges[0].ExpectedAssignmentRevision)
	}

	notApplicable := newRecordingPropertyService()
	response := newPropertyRuntime(notApplicable).Dispatch(context.Background(), executeRequest(changeTarget("/a", 1, schema.PropertyDesiredState{State: "not_applicable"})))
	if response.Error == nil || response.Error.Code != schema.ErrorUnsupported {
		t.Fatalf("not_applicable must be rejected as unsupported, got %#v", response)
	}
	if notApplicable.calls["execute"] != 0 {
		t.Fatal("rejected desired state must not reach the service")
	}
}

func boolOnePayload(t *testing.T, value bool) *schema.PropertyPayload {
	t.Helper()
	payload, ok := schema.NewPropertyPayload("boolean", "one", value, nil)
	if !ok {
		t.Fatalf("boolean payload")
	}
	return &payload
}

func stringOnePayload(t *testing.T, valueType, value string) *schema.PropertyPayload {
	t.Helper()
	payload, ok := schema.NewPropertyPayload(valueType, "one", value, nil)
	if !ok {
		t.Fatalf("scalar payload %q", value)
	}
	return &payload
}

func optionPtr(t *testing.T, idText string) *domainentry.PropertyOptionID {
	t.Helper()
	id, err := domainentry.ParsePropertyOptionID(idText)
	if err != nil {
		t.Fatalf("option id %s: %v", idText, err)
	}
	return &id
}

func strBoolPtr(value bool) *bool { return &value }
