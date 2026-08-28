package property

import (
	"encoding/json"
	"unicode/utf8"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	schema "github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// executeSuccessEnvelope와 executeAssignmentWire는 protocol successWire와
// PropertyChangeExecuteResult·PropertyAssignment의 정준 JSON 모양을 그대로
// 반영한다. schema.PropertyPayload는 패키지 비공개 필드라 외부에서 구성할 수
// 없으므로, execute의 commit 전 응답 예산 검사는 이 반영 구조체로 인코딩한다.
// 모양 동기화는 payload가 nil인 행에 대해 protocol EncodedSuccessBytes와의
// 바이트 parity 테스트로 잠긴다(TestEncodedExecuteResponseBytesMatchProtocolEnvelope).
type executeSuccessEnvelope struct {
	RequestID string                `json:"request_id"`
	OK        bool                  `json:"ok"`
	Result    executeResultEnvelope `json:"result"`
}

type executeResultEnvelope struct {
	Assignments []executeAssignmentWire `json:"assignments"`
}

type executeAssignmentWire struct {
	PropertyID  string `json:"property_id"`
	EntryID     string `json:"entry_id"`
	ValueType   string `json:"value_type"`
	Cardinality string `json:"cardinality"`
	State       string `json:"state"`
	Revision    int64  `json:"revision"`
	Value       any    `json:"value,omitempty"`
}

// encodedExecuteResponseBytes는 read-back 행의 성공 응답 인코딩 바이트 수를
// 계산하고 봉투 적합 여부를 보고한다. protocol EncodedSuccessBytes와 같은
// 65,536바이트 기준을 쓴다.
func encodedExecuteResponseBytes(requestID string, rows []executeAssignmentWire) (int, bool) {
	if !utf8.ValidString(requestID) || len(requestID) == 0 || len(requestID) > maximumEchoIDBytes {
		return 0, false
	}
	if rows == nil {
		rows = []executeAssignmentWire{}
	}
	encoded, err := json.Marshal(executeSuccessEnvelope{RequestID: requestID, OK: true, Result: executeResultEnvelope{Assignments: rows}})
	if err != nil {
		return 0, false
	}
	return len(encoded), len(encoded) <= schema.MaxWireBytes
}

// assignmentListSuccessEnvelope와 assignmentListResultEnvelope는 protocol
// successWire와 PropertyAssignmentListResult의 JSON 모양을 그대로 반영한다.
// 최소 assignment.list 페이지(단일 행, next_page_token 생략, has_more false)의
// 커밋 전 예산 검사에 쓰인다.
type assignmentListSuccessEnvelope struct {
	RequestID string                       `json:"request_id"`
	OK        bool                         `json:"ok"`
	Result    assignmentListResultEnvelope `json:"result"`
}

type assignmentListResultEnvelope struct {
	Assignments   []executeAssignmentWire `json:"assignments"`
	NextPageToken *string                 `json:"next_page_token,omitempty"`
	HasMore       bool                    `json:"has_more"`
}

// encodedAssignmentListResponseFits는 같은 read-back 행의 최소 assignment.list
// 페이지가 최대 길이 sentinel ID(listableProbeRequestID) 기준으로 봉투에 들어가는지
// 검사한다. 이후 조회는 임의의 유효한 요청 ID로 올 수 있고, 목록 봉투는 execute
// 응답보다 has_more 필드만큼 크므로 execute 응답 검사만으로는 불충분하다.
func encodedAssignmentListResponseFits(rows []executeAssignmentWire) (int, bool) {
	if rows == nil {
		rows = []executeAssignmentWire{}
	}
	encoded, err := json.Marshal(assignmentListSuccessEnvelope{RequestID: listableProbeRequestID, OK: true, Result: assignmentListResultEnvelope{Assignments: rows, HasMore: false}})
	if err != nil {
		return 0, false
	}
	return len(encoded), len(encoded) <= schema.MaxWireBytes
}

// projectedReadBack은 아직 쓰지 않은 staged fact로 커밋 후 read-back 행을
// 예측한다. 예산 위반은 이 시점에서 쓰기 전에 거절된다.
func projectedReadBack(staged []resolvedChange, definitions map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition) []executeAssignmentWire {
	rows := make([]executeAssignmentWire, 0, len(staged))
	for _, change := range staged {
		definition := definitions[change.input.PropertyID]
		rows = append(rows, wireAssignment(change.after, definition.ValueType, definition.Cardinality))
	}
	return rows
}

// canonicalReadBack은 커밋 직전 재조회한 persisted fact를 요청 순서대로 정렬해
// 정준 read-back 행과 fact를 돌려준다. 대상 fact가 사라지면 저장소 계약 위반이다.
func canonicalReadBack(
	staged []resolvedChange,
	reread map[assignmentRef]*domainentry.EntryPropertyAssignment,
	definitions map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition,
) ([]executeAssignmentWire, []domainentry.EntryPropertyAssignment, error) {
	rows := make([]executeAssignmentWire, 0, len(staged))
	factsInOrder := make([]domainentry.EntryPropertyAssignment, 0, len(staged))
	for _, change := range staged {
		fact, ok := reread[assignmentRef{entryID: change.entryID, propertyID: change.input.PropertyID}]
		if !ok {
			return nil, nil, ErrCanonicalReadBackIncomplete
		}
		definition := definitions[change.input.PropertyID]
		rows = append(rows, wireAssignment(*fact, definition.ValueType, definition.Cardinality))
		factsInOrder = append(factsInOrder, *fact)
	}
	return rows, factsInOrder, nil
}

// wireAssignment는 durable fact를 정준 read-back 행으로 사상한다.
func wireAssignment(
	fact domainentry.EntryPropertyAssignment,
	valueType domainentry.PropertyType,
	cardinality domainentry.PropertyCardinality,
) executeAssignmentWire {
	return executeAssignmentWire{
		PropertyID:  fact.PropertyID.String(),
		EntryID:     fact.EntryID,
		ValueType:   string(valueType),
		Cardinality: string(cardinality),
		State:       string(fact.State),
		Revision:    int64(fact.RecordRevision),
		Value:       wirePayload(fact),
	}
}

// wirePayload는 상태별 와이어 값을 고른다. unset과 null은 값이 없고 value는
// 스칼라 하나 또는 ordinal 순 many 배열(빈 many는 빈 배열)이다.
func wirePayload(fact domainentry.EntryPropertyAssignment) any {
	switch fact.State {
	case domainentry.AssignmentStateUnset, domainentry.AssignmentStateNull:
		return nil
	case domainentry.AssignmentStateValue:
		if fact.Scalar != nil {
			return wireScalar(*fact.Scalar)
		}
		members := make([]any, 0, len(fact.Many))
		for _, member := range fact.Many {
			members = append(members, wireScalar(member.Value))
		}
		return members
	default:
		return nil
	}
}

// wireScalar는 AssignmentValue의 설정 멤버 하나를 JSON 원시 값으로 바꾼다.
func wireScalar(value domainentry.AssignmentValue) any {
	switch {
	case value.Boolean != nil:
		return *value.Boolean
	case value.Decimal != nil:
		return *value.Decimal
	case value.Date != nil:
		return *value.Date
	case value.Timestamp != nil:
		return *value.Timestamp
	case value.Text != nil:
		return *value.Text
	case value.OptionID != nil:
		return value.OptionID.String()
	default:
		return nil
	}
}
