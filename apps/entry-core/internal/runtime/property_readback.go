package runtime

// durable fact → wire 결과(read-back·prepare after) 사상이다. unset은 unknown에,
// 빈 many는 빈 배열에 대응하고 revision은 항등 사상된다.

import (
	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// assignmentFactToWire는 durable fact를 wire assignment로 사상한다. 도메인
// unset(null 아님)은 wire unknown에 대응하고 빈 many는 빈 배열로 보존된다.
// revision은 항등 사상이다.
func assignmentFactToWire(fact domainentry.EntryPropertyAssignment, definitions map[domainentry.PropertyID]applicationproperty.DefinitionView) (schema.PropertyAssignment, schema.ErrorCode) {
	view, ok := definitions[fact.PropertyID]
	if !ok {
		return schema.PropertyAssignment{}, schema.ErrorInternal
	}
	state, ok := wireAssignmentState(fact.State)
	if !ok {
		return schema.PropertyAssignment{}, schema.ErrorInternal
	}
	assignment := schema.PropertyAssignment{
		PropertyID:  fact.PropertyID.String(),
		EntryID:     fact.EntryID,
		ValueType:   string(view.Definition.ValueType),
		Cardinality: string(view.Definition.Cardinality),
		State:       state,
		Revision:    int64(fact.RecordRevision),
	}
	if fact.State == domainentry.AssignmentStateValue {
		payload, ok := payloadFromFact(fact, view)
		if !ok {
			return schema.PropertyAssignment{}, schema.ErrorInternal
		}
		assignment.Payload = &payload
	}
	if assignment.Validate() != nil {
		return schema.PropertyAssignment{}, schema.ErrorInternal
	}
	return assignment, ""
}

// assignmentFactToDesired은 fact를 wire 목표 상태로 되돌린다(prepare after).
func assignmentFactToDesired(fact domainentry.EntryPropertyAssignment, view applicationproperty.DefinitionView) (schema.PropertyDesiredState, schema.ErrorCode) {
	state, ok := wireAssignmentState(fact.State)
	if !ok {
		return schema.PropertyDesiredState{}, schema.ErrorInternal
	}
	desired := schema.PropertyDesiredState{State: state}
	if fact.State == domainentry.AssignmentStateValue {
		payload, ok := payloadFromFact(fact, view)
		if !ok {
			return schema.PropertyDesiredState{}, schema.ErrorInternal
		}
		desired.ValueType = string(view.Definition.ValueType)
		desired.Cardinality = string(view.Definition.Cardinality)
		desired.Payload = &payload
	}
	if desired.Validate() != nil {
		return schema.PropertyDesiredState{}, schema.ErrorInternal
	}
	return desired, ""
}

// wireAssignmentState는 도메인 상태를 wire 상태로 사상한다. implicit unset@0은
// read-back에 나타나지 않지만(미존재 행 제외 계약) 나타나면 실패 닫기한다.
func wireAssignmentState(state domainentry.AssignmentState) (string, bool) {
	switch state {
	case domainentry.AssignmentStateValue:
		return "value", true
	case domainentry.AssignmentStateNull:
		return "null", true
	case domainentry.AssignmentStateUnset:
		return "unknown", true
	default:
		return "", false
	}
}

// payloadFromFact은 value 상태 fact의 스칼라·many 멤버를 wire payload로 옮긴다.
func payloadFromFact(fact domainentry.EntryPropertyAssignment, view applicationproperty.DefinitionView) (schema.PropertyPayload, bool) {
	valueType := string(view.Definition.ValueType)
	cardinality := string(view.Definition.Cardinality)
	if cardinality == "one" {
		if fact.Scalar == nil {
			return schema.PropertyPayload{}, false
		}
		member, ok := wireScalarMember(*fact.Scalar, valueType)
		if !ok {
			return schema.PropertyPayload{}, false
		}
		return schema.NewPropertyPayload(valueType, cardinality, member, nil)
	}
	items := make([]any, 0, len(fact.Many))
	for _, member := range fact.Many {
		item, ok := wireScalarMember(member.Value, valueType)
		if !ok {
			return schema.PropertyPayload{}, false
		}
		items = append(items, item)
	}
	return schema.NewPropertyPayload(valueType, cardinality, nil, wireManySlice(items))
}

// wireScalarMember는 typed 멤버 하나를 JSON 원시 값과 유형 검증 쌍으로 바꾼다.
func wireScalarMember(value domainentry.AssignmentValue, valueType string) (any, bool) {
	switch {
	case value.Boolean != nil:
		return *value.Boolean, valueType == "boolean"
	case value.Decimal != nil:
		return *value.Decimal, valueType == "number"
	case value.Date != nil:
		return *value.Date, valueType == "date"
	case value.Timestamp != nil:
		return *value.Timestamp, valueType == "datetime"
	case value.Text != nil:
		return *value.Text, valueType == "text"
	case value.OptionID != nil:
		return value.OptionID.String(), valueType == "select"
	default:
		return nil, false
	}
}

// wireManySlice는 유형별 many 배열을 NewPropertyPayload 기대 형태로 정규화한다.
func wireManySlice(items []any) any {
	if len(items) > 0 {
		if _, isBool := items[0].(bool); isBool {
			values := make([]bool, len(items))
			for index, item := range items {
				values[index] = item.(bool)
			}
			return values
		}
	}
	values := make([]string, len(items))
	for index, item := range items {
		text, _ := item.(string)
		values[index] = text
	}
	return values
}
