package runtime

import (
	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// changeTargetsFromWire는 wire 변경 대상을 application 명령으로 번역한다.
// wire expected_assignment_revision은 도메인 revision과 1:1이다 — 0은 implicit
// unset@0 첫 쓰기, 이후 변경은 read-back revision을 그대로 CAS 토큰으로
// 전달한다(definition CAS와 대칭). not_applicable 목표 상태는 이 슬라이스에서
// 쓰기 불가이며 unsupported로 명시 거절한다(unknown/not_applicable은 resolved
// projection 전용 상태이나 unknown은 값 지움(clear) 의미로 unset에 대응한다).
func changeTargetsFromWire(wire []schema.PropertyChangeTarget) ([]applicationproperty.ChangeTarget, schema.ErrorCode) {
	changes := make([]applicationproperty.ChangeTarget, len(wire))
	for index, target := range wire {
		desired, code := desiredFromWire(target.Desired)
		if code != "" {
			return nil, code
		}
		propertyID, err := domainentry.ParsePropertyID(target.PropertyID)
		if err != nil {
			return nil, schema.ErrorInvalidRequest
		}
		changes[index] = applicationproperty.ChangeTarget{
			LocalPath:                  target.Target.LocalPath,
			EntryID:                    target.EntryID,
			PropertyID:                 propertyID,
			ExpectedDefinitionRevision: int(target.ExpectedDefinitionRevision),
			ExpectedAssignmentRevision: uint64(target.ExpectedAssignmentRevision),
			Desired:                    desired,
		}
	}
	return changes, ""
}

// desiredFromWire는 wire 목표 상태를 도메인 DesiredAssignment로 사상한다.
func desiredFromWire(desired schema.PropertyDesiredState) (applicationproperty.DesiredAssignment, schema.ErrorCode) {
	switch desired.State {
	case "null":
		return applicationproperty.DesiredAssignment{State: domainentry.AssignmentStateNull}, ""
	case "unknown":
		return applicationproperty.DesiredAssignment{State: domainentry.AssignmentStateUnset}, ""
	case "not_applicable":
		return applicationproperty.DesiredAssignment{}, schema.ErrorUnsupported
	case "value":
		if desired.Payload == nil {
			return applicationproperty.DesiredAssignment{}, schema.ErrorInvalidRequest
		}
		if desired.Cardinality == "one" {
			scalar, ok := scalarFromWire(desired.ValueType, desired.Payload.One())
			if !ok {
				return applicationproperty.DesiredAssignment{}, schema.ErrorInvalidRequest
			}
			return applicationproperty.DesiredAssignment{State: domainentry.AssignmentStateValue, Scalar: &scalar}, ""
		}
		values, ok := manyFromWire(desired.ValueType, desired.Payload.Many())
		if !ok {
			return applicationproperty.DesiredAssignment{}, schema.ErrorInvalidRequest
		}
		return applicationproperty.DesiredAssignment{State: domainentry.AssignmentStateValue, Many: values}, ""
	default:
		return applicationproperty.DesiredAssignment{}, schema.ErrorInvalidRequest
	}
}

// scalarFromWire는 디코딩된 스칼라 멤버를 typed AssignmentValue로 옮긴다.
func scalarFromWire(valueType string, member any) (domainentry.AssignmentValue, bool) {
	switch value := member.(type) {
	case string:
		mapped, ok := assignmentStringMember(valueType, value)
		return mapped, ok
	case bool:
		if valueType != "boolean" {
			return domainentry.AssignmentValue{}, false
		}
		return domainentry.AssignmentValue{Boolean: &value}, true
	default:
		return domainentry.AssignmentValue{}, false
	}
}

// assignmentStringMember는 문자열 스칼라를 유형별 멤버로 분배한다.
func assignmentStringMember(valueType, value string) (domainentry.AssignmentValue, bool) {
	switch valueType {
	case "text":
		return domainentry.AssignmentValue{Text: &value}, true
	case "number":
		return domainentry.AssignmentValue{Decimal: &value}, true
	case "date":
		return domainentry.AssignmentValue{Date: &value}, true
	case "datetime":
		return domainentry.AssignmentValue{Timestamp: &value}, true
	case "select":
		optionID, err := domainentry.ParsePropertyOptionID(value)
		if err != nil {
			return domainentry.AssignmentValue{}, false
		}
		return domainentry.AssignmentValue{OptionID: &optionID}, true
	default:
		return domainentry.AssignmentValue{}, false
	}
}

// manyFromWire는 디코딩된 many 멤버 배열을 순서 보존하여 옮긴다.
func manyFromWire(valueType string, members any) ([]domainentry.AssignmentValue, bool) {
	switch items := members.(type) {
	case []string:
		values := make([]domainentry.AssignmentValue, len(items))
		for index, item := range items {
			mapped, ok := assignmentStringMember(valueType, item)
			if !ok {
				return nil, false
			}
			values[index] = mapped
		}
		return values, true
	case []bool:
		if valueType != "boolean" {
			return nil, false
		}
		values := make([]domainentry.AssignmentValue, len(items))
		for index, item := range items {
			copied := item
			values[index] = domainentry.AssignmentValue{Boolean: &copied}
		}
		return values, true
	default:
		return nil, false
	}
}

// prepareResultFromApplication은 제안을 wire 결과로 사상한다. wire 계약은
// requires_confirmation을 항상 true로 요구하므로(todo-3 동결) application의
// 세분화 신호는 표현되지 않는다. Before가 nil이면 implicit unset이다.
func prepareResultFromApplication(proposal applicationproperty.Proposal, definitions map[domainentry.PropertyID]applicationproperty.DefinitionView, requested []schema.PropertyChangeTarget) (schema.PropertyChangePrepareResult, schema.ErrorCode) {
	changes := make([]schema.PropertyPreparedChange, len(proposal.Changes))
	for index, prepared := range proposal.Changes {
		view, ok := definitions[prepared.PropertyID]
		if !ok {
			return schema.PropertyChangePrepareResult{}, schema.ErrorInternal
		}
		var before *schema.PropertyAssignment
		if prepared.Before != nil {
			mapped, code := assignmentFactToWire(*prepared.Before, definitions)
			if code != "" {
				return schema.PropertyChangePrepareResult{}, code
			}
			before = &mapped
		}
		after, code := assignmentFactToDesired(prepared.After, view)
		if code != "" {
			return schema.PropertyChangePrepareResult{}, code
		}
		if index >= len(requested) {
			return schema.PropertyChangePrepareResult{}, schema.ErrorInternal
		}
		changes[index] = schema.PropertyPreparedChange{Target: requested[index].Target, PropertyID: prepared.PropertyID.String(), EntryID: prepared.EntryID, Before: before, After: after}
	}
	result := schema.PropertyChangePrepareResult{Changes: changes, RequiresConfirmation: true}
	if result.Validate() != nil {
		return schema.PropertyChangePrepareResult{}, schema.ErrorInternal
	}
	return result, ""
}
