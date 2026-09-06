package schema

import (
	"encoding/json"
	"slices"
	"strings"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// Property wire contract 상한은 서로 독립적인 캡이다. 어떤 캡을 통과해도
// 인코딩된 요청/응답이 65,536바이트 봉투를 넘을 수 있으므로 봉투 검사는 항상
// 별도로 수행한다.
const (
	maximumPropertyScalarBytes = 4096 // local path, text/URL/email 스칼라
	maximumPropertyNameBytes   = 256  // definition key/name, option label
	maximumPropertyIDs         = 256  // 요청 PropertyID 배열 길이
	maximumPropertyTargets     = 256  // prepare/execute 변경 대상 수
	maximumPropertyManyItems   = 256  // many-value 멤버 수
)

// Property UDS 메서드 상수.
const (
	MethodPropertyDefinitionList    Method = "property.definition.list"
	MethodPropertyDefinitionCreate  Method = "property.definition.create"
	MethodPropertyDefinitionUpdate  Method = "property.definition.update"
	MethodPropertyDefinitionDisable Method = "property.definition.disable"
	MethodPropertyOptionCreate      Method = "property.option.create"
	MethodPropertyOptionUpdate      Method = "property.option.update"
	MethodPropertyOptionReorder     Method = "property.option.reorder"
	MethodPropertyOptionDisable     Method = "property.option.disable"
	MethodPropertyAssignmentList    Method = "property.assignment.list"
	MethodPropertyChangePrepare     Method = "property.change.prepare"
	MethodPropertyChangeExecute     Method = "property.change.execute"
	MethodPropertyConditionQuery    Method = "property.condition.query"
)

// Property 계약에 필요한 추가 안정 에러. 메시지는 고정·redacted다.
const (
	ErrorPropertyNotFound ErrorCode = "property_not_found"
	ErrorResponseTooLarge ErrorCode = "response_too_large"
)

// propertyMethodValid는 Property 메서드 게이트 분리 열거다.
func propertyMethodValid(method Method) bool {
	switch method {
	case MethodPropertyDefinitionList, MethodPropertyDefinitionCreate, MethodPropertyDefinitionUpdate, MethodPropertyDefinitionDisable,
		MethodPropertyOptionCreate, MethodPropertyOptionUpdate, MethodPropertyOptionReorder, MethodPropertyOptionDisable,
		MethodPropertyAssignmentList, MethodPropertyChangePrepare, MethodPropertyChangeExecute, MethodPropertyConditionQuery:
		return true
	default:
		return false
	}
}

// --- 공용 DTO ---

// PropertyTargetSelector는 명시적 태그 선택자다. 현재 호환 variant는 local_path뿐이다.
type PropertyTargetSelector struct {
	Kind      string `json:"kind"`
	LocalPath string `json:"local_path"`
}

// PropertyDesiredState는 execute가 운반하는 타입화된 목표 상태다.
type PropertyDesiredState struct {
	State       string           `json:"state"`
	ValueType   string           `json:"value_type,omitempty"`
	Cardinality string           `json:"cardinality,omitempty"`
	Payload     *PropertyPayload `json:"value,omitempty"`
}

// PropertyChangeTarget은 prepare/execute가 공유하는 경계 대상이다.
type PropertyChangeTarget struct {
	Target PropertyTargetSelector `json:"target"`
	// EntryID is optional for prepare, which resolves the stable identity and
	// returns it in PropertyPreparedChange. Execute must provide it.
	EntryID                    string               `json:"entry_id,omitempty"`
	PropertyID                 string               `json:"property_id"`
	ExpectedDefinitionRevision int64                `json:"expected_definition_revision"`
	ExpectedAssignmentRevision int64                `json:"expected_assignment_revision"`
	Desired                    PropertyDesiredState `json:"desired"`
}

type PropertyDefinition struct {
	PropertyID          string                      `json:"property_id"`
	Key                 string                      `json:"key"`
	Name                string                      `json:"name"`
	ValueType           string                      `json:"value_type"`
	Cardinality         string                      `json:"cardinality"`
	State               string                      `json:"state"`
	Origin              string                      `json:"origin"`
	Revision            int64                       `json:"revision"`
	Options             []PropertyOption            `json:"options"`
	ConditionCapability PropertyConditionCapability `json:"condition_capability"`
}

// PropertyConditionCapability is a strict supported/unsupported union. A
// supported capability carries the complete local evaluator contract; an
// unsupported capability carries exactly one stable reason.
type PropertyConditionCapability struct {
	Supported        bool     `json:"supported"`
	EvaluationScope  string   `json:"evaluation_scope,omitempty"`
	CatalogVersion   string   `json:"catalog_version,omitempty"`
	NativeType       string   `json:"native_type,omitempty"`
	AllowedOperators []string `json:"allowed_operators,omitempty"`
	Reason           string   `json:"reason,omitempty"`
}

type PropertyOption struct {
	OptionID string `json:"option_id"`
	Label    string `json:"label"`
	Position int64  `json:"position"`
	State    string `json:"state"`
}

// PropertyAssignment는 정본 저장 assignment 표현이다. execute 성공은 이 형태의
// 정준 read-back을 운반한다.
type PropertyAssignment struct {
	PropertyID  string           `json:"property_id"`
	EntryID     string           `json:"entry_id"`
	ValueType   string           `json:"value_type"`
	Cardinality string           `json:"cardinality"`
	State       string           `json:"state"`
	Revision    int64            `json:"revision"`
	Payload     *PropertyPayload `json:"value,omitempty"`
}

type PropertyPreparedChange struct {
	Target     PropertyTargetSelector `json:"target"`
	PropertyID string                 `json:"property_id"`
	EntryID    string                 `json:"entry_id"`
	Before     *PropertyAssignment    `json:"before"`
	After      PropertyDesiredState   `json:"after"`
}

// --- 요청 파라미터 ---

type PropertyDefinitionListParams struct {
	PageSize             int
	RequestedPropertyIDs []string
	IncludeDisabled      bool
	PageToken            *string
}

type PropertyDefinitionCreateParams struct {
	Key          string
	Name         string
	ValueType    string
	Cardinality  string
	OptionLabels []string
}

type PropertyDefinitionUpdateParams struct {
	PropertyID                 string
	ExpectedDefinitionRevision int64
	Name                       string
}

type PropertyDefinitionDisableParams struct {
	PropertyID                 string
	ExpectedDefinitionRevision int64
}

type PropertyOptionCreateParams struct {
	PropertyID                 string
	ExpectedDefinitionRevision int64
	Label                      string
}

type PropertyOptionUpdateParams struct {
	PropertyID                 string
	OptionID                   string
	ExpectedDefinitionRevision int64
	Label                      string
}

type PropertyOptionReorderParams struct {
	PropertyID                 string
	ExpectedDefinitionRevision int64
	OptionIDs                  []string
}

type PropertyOptionDisableParams struct {
	PropertyID                 string
	OptionID                   string
	ExpectedDefinitionRevision int64
}

type PropertyAssignmentListParams struct {
	PageSize             int
	RequestedPropertyIDs []string
	Target               PropertyTargetSelector
	PageToken            *string
}

type PropertyChangePrepareParams struct {
	Changes []PropertyChangeTarget
}

type PropertyChangeExecuteParams struct {
	Changes []PropertyChangeTarget
}

type PropertyConditionOperand struct {
	Kind    string   `json:"kind"`
	Values  []string `json:"values,omitempty"`
	Boolean *bool    `json:"boolean,omitempty"`
}

type PropertyCondition struct {
	PropertyID string                   `json:"property_id"`
	Operator   string                   `json:"operator"`
	Operand    PropertyConditionOperand `json:"operand"`
}

type PropertyConditionQueryParams struct {
	Targets               []PropertyTargetSelector `json:"targets"`
	Combinator            string                   `json:"combinator"`
	Conditions            []PropertyCondition      `json:"conditions"`
	ProjectionPropertyIDs []string                 `json:"projection_property_ids"`
	EvaluationDate        string                   `json:"evaluation_date"`
	PageSize              int                      `json:"page_size"`
	PageToken             *string                  `json:"page_token,omitempty"`
}

// --- 결과 ---

type PropertyDefinitionListResult struct {
	Definitions   []PropertyDefinition `json:"definitions"`
	NextPageToken *string              `json:"next_page_token,omitempty"`
	HasMore       bool                 `json:"has_more"`
}

func (PropertyDefinitionListResult) isResult() {}

type PropertyDefinitionResult struct {
	Definition PropertyDefinition `json:"definition"`
}

func (PropertyDefinitionResult) isResult() {}

type PropertyAssignmentListResult struct {
	Assignments   []PropertyAssignment `json:"assignments"`
	NextPageToken *string              `json:"next_page_token,omitempty"`
	HasMore       bool                 `json:"has_more"`
}

func (PropertyAssignmentListResult) isResult() {}

type PropertyChangePrepareResult struct {
	Changes              []PropertyPreparedChange `json:"changes"`
	RequiresConfirmation bool                     `json:"requires_confirmation"`
}

func (PropertyChangePrepareResult) isResult() {}

type PropertyChangeExecuteResult struct {
	Assignments []PropertyAssignment `json:"assignments"`
}

func (PropertyChangeExecuteResult) isResult() {}

type PropertyConditionQueryItem struct {
	CandidateIndex int                  `json:"candidate_index"`
	EntryID        string               `json:"entry_id"`
	Projection     []PropertyAssignment `json:"projection"`
}

type PropertyConditionQueryResult struct {
	Items                      []PropertyConditionQueryItem `json:"items"`
	UnresolvedCandidateIndices []int                        `json:"unresolved_candidate_indices"`
	CatalogVersion             string                       `json:"catalog_version"`
	NextPageToken              *string                      `json:"next_page_token,omitempty"`
	HasMore                    bool                         `json:"has_more"`
}

func (PropertyConditionQueryResult) isResult() {}

// EncodedSuccessBytes는 성공 응답의 정확한 인코딩 바이트 수를 계산한다.
// execute는 mutation 전에 이 값으로 정준 read-back 바이트를 검증해야 하며,
// 봉투 초과 시 mutation 없이 ErrorResponseTooLarge로 실패한다.
func EncodedSuccessBytes(requestID string, result Result) (int, bool) {
	if !validEchoID(requestID) || !validResult(result) {
		return 0, false
	}
	encoded, err := json.Marshal(successWire{RequestID: requestID, OK: true, Result: result})
	if err != nil {
		return 0, false
	}
	return len(encoded), len(encoded) <= MaxWireBytes
}

// --- runtime dispatch 전용 최소 seam ---
//
// PropertyPayload 멤버는 패키지 비공개라 wire 계약 불변식을 해치지 않으려면
// 생성과 읽기가 모두 이 패키지를 통과해야 한다. internal/runtime의 정준
// read-back 사상은 아래 생성자와 접근자만 사용하고 그 외 경로는 금지된다.

// NewPropertyPayload는 디코딩 규칙과 동일한 검증을 통과한 payload를 만든다.
// one과 many 중 카디널리티에 맞는 멤버 정확히 하나를 운반해야 한다.
func NewPropertyPayload(valueType, cardinality string, one any, many any) (PropertyPayload, bool) {
	payload := PropertyPayload{kind: valueType, one: one, many: many}
	if !validPropertyChangePayload(payload, valueType, cardinality) {
		return PropertyPayload{}, false
	}
	return payload, true
}

// One은 스칼라(one) 멤버 원본을 돌려준다.
func (payload PropertyPayload) One() any { return payload.one }

// Many는 배열(many) 멤버 원본을 돌려준다.
func (payload PropertyPayload) Many() any { return payload.many }

// --- 검증 헬퍼 ---

// validPropertyIDText는 wire 수준의 canonical UUID 텍스트 규칙(8-4-4-4-12
// 소문자 hex + RFC 9562 variant)만 검증한다. 버전 니블과 스킴 대조 같은 타입
// 의미 검증은 domain 진입 시 typed ID로 수행한다.
func validPropertyIDText(value string) bool {
	if len(value) != 36 {
		return false
	}
	groups := [5]int{8, 4, 4, 4, 12}
	offset := 0
	for index, length := range groups {
		if index > 0 {
			if value[offset] != '-' {
				return false
			}
			offset++
		}
		for _, ch := range []byte(value[offset : offset+length]) {
			if (ch < '0' || ch > '9') && (ch < 'a' || ch > 'f') {
				return false
			}
		}
		offset += length
	}
	// RFC 9562 variant 비트 0b10: 네 번째 그룹 첫 바이트의 상위 2비트.
	switch value[19] {
	case '8', '9', 'a', 'b':
		return true
	default:
		return false
	}
}

func validPropertyOptionIDText(value string) bool {
	return validPropertyIDText(value) && value[14] == '7'
}

func validPropertyValueType(value string) bool {
	return oneOf(value, "text", "number", "date", "datetime", "boolean", "select")
}

func validPropertyCardinality(value string) bool {
	return oneOf(value, "one", "many")
}

func validPropertyDate(value string) bool {
	parsed, err := time.Parse("2006-01-02", value)
	return err == nil && parsed.Format("2006-01-02") == value
}

func validLocalPath(path string) bool {
	if !validUTF8Bytes(path, 1, maximumPropertyScalarBytes) || path[0] != '/' {
		return false
	}
	// 소스 루트 자체는 assignment 대상 entry가 아니다 — production resolver가
	// 거절하므로 wire 경계에서 invalid_path로 실패 닫기해야 internal_error가
	// 노출되지 않는다.
	if path == "/" {
		return false
	}
	if path[len(path)-1] == '/' || strings.Contains(path, "//") {
		return false
	}
	for index := 0; index < len(path); index++ {
		if path[index] < 0x20 || path[index] == 0x7f {
			return false
		}
	}
	for _, segment := range strings.Split(path[1:], "/") {
		if segment == "" || segment == "." || segment == ".." {
			return false
		}
	}
	return true
}

func validPropertyChangePayload(payload PropertyPayload, valueType, cardinality string) bool {
	checkString := func(value string) bool {
		switch valueType {
		case "text":
			return validUTF8Bytes(value, 0, maximumPropertyScalarBytes)
		case "number":
			return validCanonicalDecimal(value)
		case "date":
			return validPropertyDate(value)
		case "datetime":
			return canonicalTimestamp(value)
		case "select":
			return validPropertyOptionIDText(value)
		default:
			return false
		}
	}
	if cardinality == "one" {
		if valueType == "boolean" {
			_, ok := payload.one.(bool)
			return ok
		}
		value, ok := payload.one.(string)
		return ok && checkString(value)
	}
	if cardinality != "many" {
		return false
	}
	if valueType == "boolean" {
		values, ok := payload.many.([]bool)
		return ok && len(values) <= maximumPropertyManyItems
	}
	values, ok := payload.many.([]string)
	if !ok || len(values) > maximumPropertyManyItems {
		return false
	}
	for _, value := range values {
		if !checkString(value) {
			return false
		}
	}
	return true
}

func (desired PropertyDesiredState) Validate() error {
	switch desired.State {
	case "null", "unknown", "not_applicable":
		if desired.Payload != nil || desired.ValueType != "" || desired.Cardinality != "" {
			return ErrInvalidResponse
		}
		return nil
	case "value":
		if desired.Payload == nil || !validPropertyValueType(desired.ValueType) || !validPropertyCardinality(desired.Cardinality) {
			return ErrInvalidResponse
		}
		if !validPropertyChangePayload(*desired.Payload, desired.ValueType, desired.Cardinality) {
			return ErrInvalidResponse
		}
		return nil
	default:
		return ErrInvalidResponse
	}
}

func (target PropertyTargetSelector) Validate() error {
	if target.Kind != "local_path" || !validLocalPath(target.LocalPath) {
		return ErrInvalidResponse
	}
	return nil
}

func (change PropertyChangeTarget) Validate() error {
	if change.Target.Validate() != nil ||
		(change.EntryID != "" && !validEntryID(change.EntryID)) ||
		!validPropertyIDText(change.PropertyID) ||
		change.ExpectedDefinitionRevision < 1 || change.ExpectedAssignmentRevision < 0 ||
		change.Desired.Validate() != nil {
		return ErrInvalidResponse
	}
	return nil
}

func (definition PropertyDefinition) Validate() error {
	if !validPropertyIDText(definition.PropertyID) || !validUTF8Bytes(definition.Key, 1, maximumPropertyNameBytes) ||
		!validUTF8Bytes(definition.Name, 1, maximumPropertyNameBytes) || !validPropertyValueType(definition.ValueType) ||
		!validPropertyCardinality(definition.Cardinality) || !oneOf(definition.State, "active", "disabled") ||
		definition.Revision < 1 || definition.Options == nil || len(definition.Options) > maximumPropertyIDs || definition.ConditionCapability.Validate() != nil {
		return ErrInvalidResponse
	}
	if !validConditionCapabilityForDefinition(definition) {
		return ErrInvalidResponse
	}
	if definition.ValueType != "select" && len(definition.Options) > 0 {
		return ErrInvalidResponse
	}
	seen := make(map[string]struct{}, len(definition.Options))
	for index, option := range definition.Options {
		if !validPropertyOptionIDText(option.OptionID) || !validUTF8Bytes(option.Label, 1, maximumPropertyNameBytes) ||
			!oneOf(option.State, "active", "disabled") || option.Position < 0 {
			return ErrInvalidResponse
		}
		if _, duplicate := seen[option.OptionID]; duplicate {
			return ErrInvalidResponse
		}
		seen[option.OptionID] = struct{}{}
		if index > 0 && definition.Options[index-1].Position >= option.Position {
			return ErrInvalidResponse
		}
	}
	return nil
}

func (capability PropertyConditionCapability) Validate() error {
	if capability.Supported {
		// relation table은 고정 catalog 버전을 미러링하므로 다른 버전의
		// semantics는 fail closed로 거절한다 (Swift PropertyConditionCatalog와
		// 동일 경계).
		if capability.EvaluationScope != "local_assignment" ||
			capability.CatalogVersion != domainentry.ConditionCatalogVersion ||
			!oneOf(capability.NativeType, "string", "number", "date", "boolean", "string_list", "categorical") ||
			capability.Reason != "" || capability.AllowedOperators == nil {
			return ErrInvalidResponse
		}
		previous := ""
		for _, operator := range capability.AllowedOperators {
			if !validConditionOperator(operator) || (previous != "" && previous >= operator) {
				return ErrInvalidResponse
			}
			previous = operator
		}
		return nil
	}
	if capability.EvaluationScope != "" || capability.CatalogVersion != "" || capability.NativeType != "" || capability.AllowedOperators != nil ||
		!oneOf(capability.Reason, "definition_disabled", "source_runtime_unavailable", "unsupported_value_contract") {
		return ErrInvalidResponse
	}
	return nil
}

func validConditionOperator(operator string) bool {
	return oneOf(operator, "all", "any", "btw", "cn", "empty", "eq", "ew", "exists", "gt", "gte", "lt", "lte", "miss", "nbtw", "nc", "neq", "none", "rx", "sw", "today")
}

func (assignment PropertyAssignment) Validate() error {
	if !validPropertyIDText(assignment.PropertyID) || !validEntryID(assignment.EntryID) ||
		!validPropertyValueType(assignment.ValueType) || !validPropertyCardinality(assignment.Cardinality) ||
		!oneOf(assignment.State, "value", "null", "unknown", "not_applicable") || assignment.Revision < 1 {
		return ErrInvalidResponse
	}
	if (assignment.State == "value") != (assignment.Payload != nil) {
		return ErrInvalidResponse
	}
	if assignment.Payload != nil && !validPropertyChangePayload(*assignment.Payload, assignment.ValueType, assignment.Cardinality) {
		return ErrInvalidResponse
	}
	return nil
}

func (prepared PropertyPreparedChange) Validate() error {
	if prepared.Target.Validate() != nil || !validPropertyIDText(prepared.PropertyID) ||
		!validEntryID(prepared.EntryID) || prepared.After.Validate() != nil {
		return ErrInvalidResponse
	}
	if prepared.Before != nil && prepared.Before.Validate() != nil {
		return ErrInvalidResponse
	}
	return nil
}

func (result PropertyDefinitionListResult) Validate() error {
	if result.Definitions == nil || len(result.Definitions) > maximumPropertyIDs || result.HasMore != (result.NextPageToken != nil) {
		return ErrInvalidResponse
	}
	if result.NextPageToken != nil && !validOpaqueASCII(*result.NextPageToken, 1, maximumPageTokenBytes) {
		return ErrInvalidResponse
	}
	seen := make(map[string]struct{}, len(result.Definitions))
	for _, definition := range result.Definitions {
		if definition.Validate() != nil {
			return ErrInvalidResponse
		}
		if _, duplicate := seen[definition.PropertyID]; duplicate {
			return ErrInvalidResponse
		}
		seen[definition.PropertyID] = struct{}{}
	}
	return nil
}

func (result PropertyDefinitionResult) Validate() error {
	return result.Definition.Validate()
}

func (result PropertyAssignmentListResult) Validate() error {
	if result.Assignments == nil || len(result.Assignments) > maximumPropertyIDs || result.HasMore != (result.NextPageToken != nil) {
		return ErrInvalidResponse
	}
	if result.NextPageToken != nil && !validOpaqueASCII(*result.NextPageToken, 1, maximumPageTokenBytes) {
		return ErrInvalidResponse
	}
	seen := make(map[string]struct{}, len(result.Assignments))
	firstEntryID := ""
	for _, assignment := range result.Assignments {
		if assignment.Validate() != nil {
			return ErrInvalidResponse
		}
		if _, duplicate := seen[assignment.PropertyID]; duplicate {
			return ErrInvalidResponse
		}
		seen[assignment.PropertyID] = struct{}{}
		// assignment-list는 단일 local-path target을 한 entry로 해석해
		// 조회한다. 서로 다른 entry의 값이 섞인 페이지는 생성 불가능한
		// 응답이다.
		if firstEntryID == "" {
			firstEntryID = assignment.EntryID
		} else if assignment.EntryID != firstEntryID {
			return ErrInvalidResponse
		}
	}
	return nil
}

func (result PropertyChangePrepareResult) Validate() error {
	if !result.RequiresConfirmation || result.Changes == nil || len(result.Changes) < 1 || len(result.Changes) > maximumPropertyTargets {
		return ErrInvalidResponse
	}
	for _, change := range result.Changes {
		if change.Validate() != nil {
			return ErrInvalidResponse
		}
	}
	return nil
}

func (result PropertyChangeExecuteResult) Validate() error {
	if result.Assignments == nil || len(result.Assignments) < 1 || len(result.Assignments) > maximumPropertyTargets {
		return ErrInvalidResponse
	}
	seen := make(map[string]struct{}, len(result.Assignments))
	for _, assignment := range result.Assignments {
		if assignment.Validate() != nil {
			return ErrInvalidResponse
		}
		key := assignment.EntryID + "\x00" + assignment.PropertyID
		if _, duplicate := seen[key]; duplicate {
			return ErrInvalidResponse
		}
		seen[key] = struct{}{}
	}
	return nil
}

func (result PropertyConditionQueryResult) Validate() error {
	// 모든 유효 요청의 target·projection 상한은 256이므로 결과 배열과
	// candidate index도 같은 상한 안에 있어야 한다. 이를 벗어난 index는
	// 어떤 요청에도 대응할 수 없는 wire 계약 위반이다.
	if result.Items == nil || len(result.Items) > maximumPropertyTargets ||
		result.UnresolvedCandidateIndices == nil || len(result.UnresolvedCandidateIndices) > maximumPropertyTargets ||
		result.CatalogVersion != domainentry.ConditionCatalogVersion ||
		result.HasMore != (result.NextPageToken != nil) {
		return ErrInvalidResponse
	}
	// page completion은 pageSize번째 match를 채운 뒤에만 has_more을 설정한다.
	// 따라서 has_more 페이지에 item이 없다는 것은 생성될 수 없는 응답이다.
	if result.HasMore && len(result.Items) == 0 {
		return ErrInvalidResponse
	}
	if result.NextPageToken != nil && !validOpaqueASCII(*result.NextPageToken, 1, maximumPageTokenBytes) {
		return ErrInvalidResponse
	}
	matchedIndices := make(map[int]struct{}, len(result.Items))
	last := -1
	for _, item := range result.Items {
		if item.CandidateIndex <= last || item.CandidateIndex >= maximumPropertyTargets ||
			!validEntryID(item.EntryID) || item.Projection == nil || len(item.Projection) > maximumPropertyIDs {
			return ErrInvalidResponse
		}
		matchedIndices[item.CandidateIndex] = struct{}{}
		last = item.CandidateIndex
		previousID := ""
		for _, assignment := range item.Projection {
			if assignment.EntryID != item.EntryID || assignment.Validate() != nil || (previousID != "" && previousID >= assignment.PropertyID) {
				return ErrInvalidResponse
			}
			previousID = assignment.PropertyID
		}
	}
	last = -1
	for _, index := range result.UnresolvedCandidateIndices {
		if index <= last || index >= maximumPropertyTargets {
			return ErrInvalidResponse
		}
		// 같은 candidate가 일치 결과와 해석 실패 대상에 동시에 있으면 caller가
		// 한 경로를 두 의미로 처리하게 되므로 모순 응답을 거절한다.
		if _, matched := matchedIndices[index]; matched {
			return ErrInvalidResponse
		}
		last = index
	}
	return nil
}

// ReconcileConditionQueryResult는 응답이 원래 요청 경계를 벗어나지 않는지
// 검증한다. 저장소가 property_id > after로 조회하고 pageSize번째 match에서
// 중단하므로, page_size 초과 item·target 범위 밖 candidate·요청하지 않은
// projection은 생성될 수 없다. (Swift queryPageMatchesRequest와 동일 경계)
func ReconcileConditionQueryResult(
	result PropertyConditionQueryResult,
	params PropertyConditionQueryParams,
) error {
	if len(result.Items) > params.PageSize {
		return ErrInvalidResponse
	}
	for _, item := range result.Items {
		if item.CandidateIndex >= len(params.Targets) {
			return ErrInvalidResponse
		}
		for _, assignment := range item.Projection {
			if !slices.Contains(params.ProjectionPropertyIDs, assignment.PropertyID) {
				return ErrInvalidResponse
			}
		}
	}
	for _, index := range result.UnresolvedCandidateIndices {
		if index >= len(params.Targets) {
			return ErrInvalidResponse
		}
	}
	// page completion 조건상 has_more 페이지는 page_size를 정확히 채우고,
	// unresolved는 마지막 matched index 이전에만 나타난다. 이를 벗어나는
	// 응답은 다음 페이지와 모순되므로 거절한다.
	if result.HasMore {
		if len(result.Items) != params.PageSize {
			return ErrInvalidResponse
		}
		last := result.Items[len(result.Items)-1].CandidateIndex
		// 마지막 matched index 뒤에도 후보가 남아 있어야 has_more다.
		if last >= len(params.Targets)-1 {
			return ErrInvalidResponse
		}
		if unresolved := result.UnresolvedCandidateIndices; len(unresolved) > 0 &&
			unresolved[len(unresolved)-1] >= last {
			return ErrInvalidResponse
		}
	}
	return nil
}

// --- 요청 디코딩 ---

func decodePageSize(value jsonValue) (int, bool) {
	pageSize, ok := lexicalInteger(value)
	return int(pageSize), ok && pageSize >= 1 && pageSize <= 256
}

func decodeExpectedRevision(value jsonValue) (int64, bool) {
	revision, ok := lexicalInteger(value)
	return revision, ok && revision >= 1
}

// decodeExpectedAssignmentRevision은 expected_assignment_revision 전용 decoder다.
// 0은 implicit unset@0 첫 쓰기(set→clear ABA 포함)의 CAS 토큰으로 계약상
// 유효하고, 이후 변경은 read-back revision을 그대로 전달한다.
func decodeExpectedAssignmentRevision(value jsonValue) (int64, bool) {
	revision, ok := lexicalInteger(value)
	return revision, ok && revision >= 0
}

func decodePropertyIDField(value jsonValue) (string, bool) {
	return value.text, value.kind == jsonString && validPropertyIDText(value.text)
}

func decodePropertyOptionIDField(value jsonValue) (string, bool) {
	return value.text, value.kind == jsonString && validPropertyOptionIDText(value.text)
}

func decodePropertyIDFilter(value jsonValue) ([]string, bool) {
	if value.kind != jsonArray || len(value.items) > maximumPropertyIDs {
		return nil, false
	}
	result := make([]string, len(value.items))
	for index, item := range value.items {
		text, ok := decodePropertyIDField(item)
		if !ok {
			return nil, false
		}
		if index > 0 && result[index-1] >= text {
			return nil, false
		}
		result[index] = text
	}
	return result, true
}

func decodePropertyTargetSelector(value jsonValue) (PropertyTargetSelector, ErrorCode) {
	fields, ok := objectFields(value, "kind", "local_path")
	if !ok || fields["kind"].text != "local_path" || fields["local_path"].kind != jsonString {
		return PropertyTargetSelector{}, ErrorInvalidRequest
	}
	selector := PropertyTargetSelector{Kind: "local_path", LocalPath: fields["local_path"].text}
	if !validLocalPath(selector.LocalPath) {
		return PropertyTargetSelector{}, ErrorInvalidPath
	}
	return selector, ""
}

func decodePropertyDesiredState(value jsonValue) (PropertyDesiredState, bool) {
	if fields, ok := objectFields(value, "state"); ok {
		state := fields["state"].text
		desired := PropertyDesiredState{State: state}
		return desired, state == "null" || state == "unknown" || state == "not_applicable"
	}
	fields, ok := objectFields(value, "state", "value_type", "cardinality", "value")
	if !ok || fields["state"].text != "value" {
		return PropertyDesiredState{}, false
	}
	valueType, cardinality := fields["value_type"].text, fields["cardinality"].text
	payload, ok := decodePropertyChangePayload(fields["value"], valueType, cardinality)
	if !ok {
		return PropertyDesiredState{}, false
	}
	desired := PropertyDesiredState{State: "value", ValueType: valueType, Cardinality: cardinality, Payload: &payload}
	return desired, desired.Validate() == nil
}

func decodePropertyChangePayload(value jsonValue, valueType, cardinality string) (PropertyPayload, bool) {
	payload := PropertyPayload{kind: valueType}
	scalar := func(item jsonValue) (any, bool) {
		switch valueType {
		case "boolean":
			return item.boolean, item.kind == jsonBool
		case "text":
			return item.text, item.kind == jsonString && validUTF8Bytes(item.text, 0, maximumPropertyScalarBytes)
		case "number":
			return item.text, item.kind == jsonString && validCanonicalDecimal(item.text)
		case "date":
			return item.text, item.kind == jsonString && validPropertyDate(item.text)
		case "datetime":
			return item.text, item.kind == jsonString && canonicalTimestamp(item.text)
		case "select":
			return item.text, item.kind == jsonString && validPropertyOptionIDText(item.text)
		default:
			return nil, false
		}
	}
	if cardinality == "one" {
		item, ok := scalar(value)
		if !ok {
			return payload, false
		}
		payload.one = item
		return payload, true
	}
	if cardinality != "many" || value.kind != jsonArray || len(value.items) > maximumPropertyManyItems {
		return payload, false
	}
	if valueType == "boolean" {
		items := make([]bool, len(value.items))
		for index, item := range value.items {
			if item.kind != jsonBool {
				return payload, false
			}
			items[index] = item.boolean
		}
		payload.many = items
		return payload, true
	}
	items := make([]string, len(value.items))
	for index, item := range value.items {
		decoded, ok := scalar(item)
		if !ok {
			return payload, false
		}
		text, _ := decoded.(string)
		items[index] = text
	}
	payload.many = items
	return payload, true
}

func decodePropertyChangeTarget(value jsonValue) (PropertyChangeTarget, bool) {
	fields, ok := objectFieldsWithOptional(value,
		[]string{"target", "property_id", "expected_definition_revision", "expected_assignment_revision", "desired"},
		[]string{"entry_id"},
	)
	if !ok {
		return PropertyChangeTarget{}, false
	}
	target, targetCode := decodePropertyTargetSelector(fields["target"])
	entryID := ""
	entryIDValid := true
	if field, exists := fields["entry_id"]; exists {
		entryIDValid = field.kind == jsonString && validEntryID(field.text)
		if entryIDValid {
			entryID = field.text
		}
	}
	propertyID, b := decodePropertyIDField(fields["property_id"])
	definitionRevision, c := decodeExpectedRevision(fields["expected_definition_revision"])
	assignmentRevision, d := decodeExpectedAssignmentRevision(fields["expected_assignment_revision"])
	desired, e := decodePropertyDesiredState(fields["desired"])
	change := PropertyChangeTarget{Target: target, EntryID: entryID, PropertyID: propertyID, ExpectedDefinitionRevision: definitionRevision, ExpectedAssignmentRevision: assignmentRevision, Desired: desired}
	return change, targetCode == "" && entryIDValid && b && c && d && e && change.Validate() == nil
}

func decodePropertyDefinitionListParams(value jsonValue) (PropertyDefinitionListParams, ErrorCode) {
	fields, ok := objectFieldsWithOptional(value, []string{"page_size", "requested_property_ids"}, []string{"include_disabled", "page_token"})
	if !ok {
		return PropertyDefinitionListParams{}, ErrorInvalidRequest
	}
	pageSize, ok := decodePageSize(fields["page_size"])
	if !ok {
		return PropertyDefinitionListParams{}, ErrorInvalidRequest
	}
	ids, ok := decodePropertyIDFilter(fields["requested_property_ids"])
	if !ok {
		return PropertyDefinitionListParams{}, ErrorInvalidRequest
	}
	params := PropertyDefinitionListParams{PageSize: pageSize, RequestedPropertyIDs: ids}
	if field, exists := fields["include_disabled"]; exists {
		if field.kind != jsonBool {
			return PropertyDefinitionListParams{}, ErrorInvalidRequest
		}
		params.IncludeDisabled = field.boolean
	}
	if field, exists := fields["page_token"]; exists {
		if field.kind != jsonString || !validOpaqueASCII(field.text, 1, maximumPageTokenBytes) {
			return PropertyDefinitionListParams{}, ErrorInvalidRequest
		}
		params.PageToken = stringPointer(field.text)
	}
	return params, ""
}

func decodePropertyDefinitionCreateParams(value jsonValue) (PropertyDefinitionCreateParams, ErrorCode) {
	fields, ok := objectFieldsWithOptional(value, []string{"key", "name", "value_type", "cardinality"}, []string{"options"})
	if !ok || !allStrings(fields, "key", "name", "value_type", "cardinality") {
		return PropertyDefinitionCreateParams{}, ErrorInvalidRequest
	}
	params := PropertyDefinitionCreateParams{Key: fields["key"].text, Name: fields["name"].text, ValueType: fields["value_type"].text, Cardinality: fields["cardinality"].text}
	if !validUTF8Bytes(params.Key, 1, maximumPropertyNameBytes) || !validUTF8Bytes(params.Name, 1, maximumPropertyNameBytes) ||
		!validPropertyValueType(params.ValueType) || !validPropertyCardinality(params.Cardinality) {
		return PropertyDefinitionCreateParams{}, ErrorInvalidRequest
	}
	if field, exists := fields["options"]; exists {
		if params.ValueType != "select" || field.kind != jsonArray || len(field.items) > maximumPropertyIDs {
			return PropertyDefinitionCreateParams{}, ErrorInvalidRequest
		}
		labels := make([]string, len(field.items))
		for index, item := range field.items {
			optionFields, valid := objectFields(item, "label")
			if !valid || optionFields["label"].kind != jsonString || !validUTF8Bytes(optionFields["label"].text, 1, maximumPropertyNameBytes) {
				return PropertyDefinitionCreateParams{}, ErrorInvalidRequest
			}
			labels[index] = optionFields["label"].text
		}
		params.OptionLabels = labels
	}
	return params, ""
}

func decodePropertyDefinitionUpdateParams(value jsonValue) (PropertyDefinitionUpdateParams, ErrorCode) {
	fields, ok := objectFields(value, "property_id", "expected_definition_revision", "name")
	if !ok || fields["name"].kind != jsonString {
		return PropertyDefinitionUpdateParams{}, ErrorInvalidRequest
	}
	propertyID, a := decodePropertyIDField(fields["property_id"])
	revision, b := decodeExpectedRevision(fields["expected_definition_revision"])
	if !a || !b || !validUTF8Bytes(fields["name"].text, 1, maximumPropertyNameBytes) {
		return PropertyDefinitionUpdateParams{}, ErrorInvalidRequest
	}
	return PropertyDefinitionUpdateParams{PropertyID: propertyID, ExpectedDefinitionRevision: revision, Name: fields["name"].text}, ""
}

func decodePropertyDefinitionDisableParams(value jsonValue) (PropertyDefinitionDisableParams, ErrorCode) {
	fields, ok := objectFields(value, "property_id", "expected_definition_revision")
	if !ok {
		return PropertyDefinitionDisableParams{}, ErrorInvalidRequest
	}
	propertyID, a := decodePropertyIDField(fields["property_id"])
	revision, b := decodeExpectedRevision(fields["expected_definition_revision"])
	if !a || !b {
		return PropertyDefinitionDisableParams{}, ErrorInvalidRequest
	}
	return PropertyDefinitionDisableParams{PropertyID: propertyID, ExpectedDefinitionRevision: revision}, ""
}

func decodePropertyOptionCreateParams(value jsonValue) (PropertyOptionCreateParams, ErrorCode) {
	fields, ok := objectFields(value, "property_id", "expected_definition_revision", "label")
	if !ok || fields["label"].kind != jsonString {
		return PropertyOptionCreateParams{}, ErrorInvalidRequest
	}
	propertyID, a := decodePropertyIDField(fields["property_id"])
	revision, b := decodeExpectedRevision(fields["expected_definition_revision"])
	if !a || !b || !validUTF8Bytes(fields["label"].text, 1, maximumPropertyNameBytes) {
		return PropertyOptionCreateParams{}, ErrorInvalidRequest
	}
	return PropertyOptionCreateParams{PropertyID: propertyID, ExpectedDefinitionRevision: revision, Label: fields["label"].text}, ""
}

func decodePropertyOptionUpdateParams(value jsonValue) (PropertyOptionUpdateParams, ErrorCode) {
	fields, ok := objectFields(value, "property_id", "option_id", "expected_definition_revision", "label")
	if !ok || fields["label"].kind != jsonString {
		return PropertyOptionUpdateParams{}, ErrorInvalidRequest
	}
	propertyID, a := decodePropertyIDField(fields["property_id"])
	optionID, b := decodePropertyOptionIDField(fields["option_id"])
	revision, c := decodeExpectedRevision(fields["expected_definition_revision"])
	if !a || !b || !c || !validUTF8Bytes(fields["label"].text, 1, maximumPropertyNameBytes) {
		return PropertyOptionUpdateParams{}, ErrorInvalidRequest
	}
	return PropertyOptionUpdateParams{PropertyID: propertyID, OptionID: optionID, ExpectedDefinitionRevision: revision, Label: fields["label"].text}, ""
}

func decodePropertyOptionReorderParams(value jsonValue) (PropertyOptionReorderParams, ErrorCode) {
	fields, ok := objectFields(value, "property_id", "expected_definition_revision", "option_ids")
	if !ok || fields["option_ids"].kind != jsonArray {
		return PropertyOptionReorderParams{}, ErrorInvalidRequest
	}
	propertyID, a := decodePropertyIDField(fields["property_id"])
	revision, b := decodeExpectedRevision(fields["expected_definition_revision"])
	items := fields["option_ids"].items
	if !a || !b || len(items) < 1 || len(items) > maximumPropertyIDs {
		return PropertyOptionReorderParams{}, ErrorInvalidRequest
	}
	optionIDs := make([]string, len(items))
	seen := make(map[string]struct{}, len(items))
	for index, item := range items {
		text, valid := decodePropertyOptionIDField(item)
		if !valid {
			return PropertyOptionReorderParams{}, ErrorInvalidRequest
		}
		if _, duplicate := seen[text]; duplicate {
			return PropertyOptionReorderParams{}, ErrorInvalidRequest
		}
		seen[text] = struct{}{}
		optionIDs[index] = text
	}
	return PropertyOptionReorderParams{PropertyID: propertyID, ExpectedDefinitionRevision: revision, OptionIDs: optionIDs}, ""
}

func decodePropertyOptionDisableParams(value jsonValue) (PropertyOptionDisableParams, ErrorCode) {
	fields, ok := objectFields(value, "property_id", "option_id", "expected_definition_revision")
	if !ok {
		return PropertyOptionDisableParams{}, ErrorInvalidRequest
	}
	propertyID, a := decodePropertyIDField(fields["property_id"])
	optionID, b := decodePropertyOptionIDField(fields["option_id"])
	revision, c := decodeExpectedRevision(fields["expected_definition_revision"])
	if !a || !b || !c {
		return PropertyOptionDisableParams{}, ErrorInvalidRequest
	}
	return PropertyOptionDisableParams{PropertyID: propertyID, OptionID: optionID, ExpectedDefinitionRevision: revision}, ""
}

func decodePropertyAssignmentListParams(value jsonValue) (PropertyAssignmentListParams, ErrorCode) {
	fields, ok := objectFieldsWithOptional(value, []string{"page_size", "requested_property_ids", "target"}, []string{"page_token"})
	if !ok {
		return PropertyAssignmentListParams{}, ErrorInvalidRequest
	}
	pageSize, ok := decodePageSize(fields["page_size"])
	if !ok {
		return PropertyAssignmentListParams{}, ErrorInvalidRequest
	}
	ids, ok := decodePropertyIDFilter(fields["requested_property_ids"])
	if !ok {
		return PropertyAssignmentListParams{}, ErrorInvalidRequest
	}
	target, code := decodePropertyTargetSelector(fields["target"])
	if code != "" {
		return PropertyAssignmentListParams{}, code
	}
	params := PropertyAssignmentListParams{PageSize: pageSize, RequestedPropertyIDs: ids, Target: target}
	if field, exists := fields["page_token"]; exists {
		if field.kind != jsonString || !validOpaqueASCII(field.text, 1, maximumPageTokenBytes) {
			return PropertyAssignmentListParams{}, ErrorInvalidRequest
		}
		params.PageToken = stringPointer(field.text)
	}
	return params, ""
}

func decodePropertyChangeParams(value jsonValue) ([]PropertyChangeTarget, ErrorCode) {
	fields, ok := objectFields(value, "changes")
	if !ok || fields["changes"].kind != jsonArray {
		return nil, ErrorInvalidRequest
	}
	items := fields["changes"].items
	if len(items) < 1 || len(items) > maximumPropertyTargets {
		return nil, ErrorInvalidRequest
	}
	changes := make([]PropertyChangeTarget, len(items))
	for index, item := range items {
		change, valid := decodePropertyChangeTarget(item)
		if !valid {
			return nil, ErrorInvalidRequest
		}
		changes[index] = change
	}
	return changes, ""
}

func decodePropertyConditionQueryParams(value jsonValue) (PropertyConditionQueryParams, ErrorCode) {
	fields, ok := objectFieldsWithOptional(value,
		[]string{"targets", "combinator", "conditions", "projection_property_ids", "evaluation_date", "page_size"},
		[]string{"page_token"})
	if !ok || fields["targets"].kind != jsonArray || fields["conditions"].kind != jsonArray ||
		fields["projection_property_ids"].kind != jsonArray || fields["combinator"].kind != jsonString ||
		fields["evaluation_date"].kind != jsonString {
		return PropertyConditionQueryParams{}, ErrorInvalidRequest
	}
	if len(fields["targets"].items) < 1 || len(fields["targets"].items) > maximumPropertyTargets ||
		len(fields["conditions"].items) < 1 || len(fields["conditions"].items) > maximumPropertyIDs ||
		!oneOf(fields["combinator"].text, "all", "any") || !validPropertyDate(fields["evaluation_date"].text) {
		return PropertyConditionQueryParams{}, ErrorInvalidRequest
	}
	pageSize, ok := decodePageSize(fields["page_size"])
	if !ok {
		return PropertyConditionQueryParams{}, ErrorInvalidRequest
	}
	params := PropertyConditionQueryParams{Combinator: fields["combinator"].text, EvaluationDate: fields["evaluation_date"].text, PageSize: pageSize}
	seenTargets := make(map[string]struct{}, len(fields["targets"].items))
	for _, item := range fields["targets"].items {
		target, code := decodePropertyTargetSelector(item)
		if code != "" {
			return PropertyConditionQueryParams{}, code
		}
		if _, duplicate := seenTargets[target.LocalPath]; duplicate {
			return PropertyConditionQueryParams{}, ErrorInvalidRequest
		}
		seenTargets[target.LocalPath] = struct{}{}
		params.Targets = append(params.Targets, target)
	}
	seenConditions := make(map[string]struct{}, len(fields["conditions"].items))
	for _, item := range fields["conditions"].items {
		condition, valid := decodePropertyCondition(item)
		if !valid {
			return PropertyConditionQueryParams{}, ErrorInvalidRequest
		}
		if _, duplicate := seenConditions[condition.PropertyID]; duplicate {
			return PropertyConditionQueryParams{}, ErrorInvalidRequest
		}
		seenConditions[condition.PropertyID] = struct{}{}
		params.Conditions = append(params.Conditions, condition)
	}
	projection, ok := decodePropertyIDFilter(fields["projection_property_ids"])
	if !ok {
		return PropertyConditionQueryParams{}, ErrorInvalidRequest
	}
	for index := 1; index < len(projection); index++ {
		if projection[index-1] >= projection[index] {
			return PropertyConditionQueryParams{}, ErrorInvalidRequest
		}
	}
	params.ProjectionPropertyIDs = projection
	unique := make(map[string]struct{}, len(seenConditions)+len(projection))
	for id := range seenConditions {
		unique[id] = struct{}{}
	}
	for _, id := range projection {
		unique[id] = struct{}{}
	}
	if len(params.Targets)*len(unique) > 4096 {
		return PropertyConditionQueryParams{}, ErrorScopeTooLarge
	}
	if field, exists := fields["page_token"]; exists {
		if field.kind != jsonString || !validOpaqueASCII(field.text, 1, maximumPageTokenBytes) {
			return PropertyConditionQueryParams{}, ErrorInvalidRequest
		}
		params.PageToken = stringPointer(field.text)
	}
	return params, ""
}

func decodePropertyCondition(value jsonValue) (PropertyCondition, bool) {
	fields, ok := objectFields(value, "property_id", "operator", "operand")
	if !ok || fields["operator"].kind != jsonString || !validConditionOperator(fields["operator"].text) {
		return PropertyCondition{}, false
	}
	propertyID, ok := decodePropertyIDField(fields["property_id"])
	if !ok {
		return PropertyCondition{}, false
	}
	operand, ok := decodePropertyConditionOperand(fields["operand"])
	if !ok || !validConditionOperandShape(fields["operator"].text, operand) {
		return PropertyCondition{}, false
	}
	return PropertyCondition{PropertyID: propertyID, Operator: fields["operator"].text, Operand: operand}, true
}

func validConditionOperandShape(operator string, operand PropertyConditionOperand) bool {
	switch operator {
	case "empty", "exists", "today":
		return operand.Kind == "none"
	case "btw", "nbtw":
		return (operand.Kind == "number" || operand.Kind == "date") && len(operand.Values) == 2
	case "all", "any", "miss", "none":
		return (operand.Kind == "text" || operand.Kind == "option_ref") && len(operand.Values) >= 1
	case "cn", "nc", "sw", "ew", "rx":
		return operand.Kind == "text" && len(operand.Values) == 1
	case "eq":
		return (operand.Kind == "boolean" && operand.Boolean != nil) ||
			((operand.Kind == "text" || operand.Kind == "number" || operand.Kind == "date") && len(operand.Values) == 1)
	case "neq", "gt", "gte", "lt", "lte":
		return (operand.Kind == "text" || operand.Kind == "number" || operand.Kind == "date") && len(operand.Values) == 1
	default:
		return false
	}
}

func decodePropertyConditionOperand(value jsonValue) (PropertyConditionOperand, bool) {
	if fields, ok := objectFields(value, "kind"); ok && fields["kind"].kind == jsonString && fields["kind"].text == "none" {
		return PropertyConditionOperand{Kind: "none"}, true
	}
	if fields, ok := objectFields(value, "kind", "boolean"); ok && fields["kind"].kind == jsonString && fields["kind"].text == "boolean" && fields["boolean"].kind == jsonBool {
		boolean := fields["boolean"].boolean
		return PropertyConditionOperand{Kind: "boolean", Boolean: &boolean}, true
	}
	fields, ok := objectFields(value, "kind", "values")
	if !ok || fields["kind"].kind != jsonString || fields["values"].kind != jsonArray ||
		!oneOf(fields["kind"].text, "text", "number", "date", "option_ref") || len(fields["values"].items) > maximumPropertyManyItems {
		return PropertyConditionOperand{}, false
	}
	values := make([]string, len(fields["values"].items))
	for index, item := range fields["values"].items {
		if item.kind != jsonString {
			return PropertyConditionOperand{}, false
		}
		text := item.text
		valid := validUTF8Bytes(text, 0, maximumPropertyScalarBytes)
		switch fields["kind"].text {
		case "number":
			valid = validCanonicalDecimal(text)
		case "date":
			valid = validPropertyDate(text)
		case "option_ref":
			valid = validPropertyOptionIDText(text)
		}
		if !valid {
			return PropertyConditionOperand{}, false
		}
		values[index] = text
	}
	return PropertyConditionOperand{Kind: fields["kind"].text, Values: values}, true
}

// --- 결과 디코딩 ---

func decodePropertyDefinition(value jsonValue) (PropertyDefinition, bool) {
	fields, ok := objectFields(value, "property_id", "key", "name", "value_type", "cardinality", "state", "origin", "revision", "options", "condition_capability")
	if !ok || !allStrings(fields, "property_id", "key", "name", "value_type", "cardinality", "state", "origin") || fields["options"].kind != jsonArray {
		return PropertyDefinition{}, false
	}
	revision, valid := decodeExpectedRevision(fields["revision"])
	if !valid {
		return PropertyDefinition{}, false
	}
	definition := PropertyDefinition{
		PropertyID:  fields["property_id"].text,
		Key:         fields["key"].text,
		Name:        fields["name"].text,
		ValueType:   fields["value_type"].text,
		Cardinality: fields["cardinality"].text,
		State:       fields["state"].text,
		Origin:      fields["origin"].text,
		Revision:    revision,
		Options:     make([]PropertyOption, len(fields["options"].items)),
	}
	capability, valid := decodePropertyConditionCapability(fields["condition_capability"])
	if !valid {
		return PropertyDefinition{}, false
	}
	definition.ConditionCapability = capability
	for index, item := range fields["options"].items {
		optionFields, valid := objectFields(item, "option_id", "label", "position", "state")
		if !valid || !allStrings(optionFields, "option_id", "label", "state") {
			return PropertyDefinition{}, false
		}
		position, valid := decodeExpectedRevision(optionFields["position"])
		if !valid {
			return PropertyDefinition{}, false
		}
		definition.Options[index] = PropertyOption{OptionID: optionFields["option_id"].text, Label: optionFields["label"].text, Position: position - 1, State: optionFields["state"].text}
	}
	return definition, definition.Validate() == nil
}

func decodePropertyConditionCapability(value jsonValue) (PropertyConditionCapability, bool) {
	if fields, ok := objectFields(value, "supported", "reason"); ok && fields["supported"].kind == jsonBool && !fields["supported"].boolean && fields["reason"].kind == jsonString {
		capability := PropertyConditionCapability{Reason: fields["reason"].text}
		return capability, capability.Validate() == nil
	}
	fields, ok := objectFields(value, "supported", "evaluation_scope", "catalog_version", "native_type", "allowed_operators")
	if !ok || fields["supported"].kind != jsonBool || !fields["supported"].boolean ||
		!allStrings(fields, "evaluation_scope", "catalog_version", "native_type") || fields["allowed_operators"].kind != jsonArray {
		return PropertyConditionCapability{}, false
	}
	capability := PropertyConditionCapability{Supported: true, EvaluationScope: fields["evaluation_scope"].text, CatalogVersion: fields["catalog_version"].text, NativeType: fields["native_type"].text, AllowedOperators: make([]string, len(fields["allowed_operators"].items))}
	for index, item := range fields["allowed_operators"].items {
		if item.kind != jsonString {
			return PropertyConditionCapability{}, false
		}
		capability.AllowedOperators[index] = item.text
	}
	return capability, capability.Validate() == nil
}

func decodePropertyAssignment(value jsonValue) (PropertyAssignment, bool) {
	fields, ok := objectFieldsWithOptional(value, []string{"property_id", "entry_id", "value_type", "cardinality", "state", "revision"}, []string{"value"})
	if !ok || !allStrings(fields, "property_id", "entry_id", "value_type", "cardinality", "state") {
		return PropertyAssignment{}, false
	}
	revision, valid := decodeExpectedRevision(fields["revision"])
	if !valid {
		return PropertyAssignment{}, false
	}
	assignment := PropertyAssignment{
		PropertyID:  fields["property_id"].text,
		EntryID:     fields["entry_id"].text,
		ValueType:   fields["value_type"].text,
		Cardinality: fields["cardinality"].text,
		State:       fields["state"].text,
		Revision:    revision,
	}
	if field, exists := fields["value"]; exists {
		payload, valid := decodePropertyChangePayload(field, assignment.ValueType, assignment.Cardinality)
		if !valid {
			return PropertyAssignment{}, false
		}
		assignment.Payload = &payload
	}
	return assignment, assignment.Validate() == nil
}

func decodePropertyPagedToken(fields map[string]jsonValue) (*string, bool) {
	field, exists := fields["next_page_token"]
	if !exists {
		return nil, true
	}
	if field.kind != jsonString || !validOpaqueASCII(field.text, 1, maximumPageTokenBytes) {
		return nil, false
	}
	return stringPointer(field.text), true
}

func decodePropertyDefinitionListResult(value jsonValue) (PropertyDefinitionListResult, bool) {
	fields, ok := objectFieldsWithOptional(value, []string{"definitions", "has_more"}, []string{"next_page_token"})
	if !ok || fields["definitions"].kind != jsonArray || fields["has_more"].kind != jsonBool {
		return PropertyDefinitionListResult{}, false
	}
	token, valid := decodePropertyPagedToken(fields)
	if !valid {
		return PropertyDefinitionListResult{}, false
	}
	result := PropertyDefinitionListResult{Definitions: make([]PropertyDefinition, len(fields["definitions"].items)), NextPageToken: token, HasMore: fields["has_more"].boolean}
	for index, item := range fields["definitions"].items {
		definition, valid := decodePropertyDefinition(item)
		if !valid {
			return PropertyDefinitionListResult{}, false
		}
		result.Definitions[index] = definition
	}
	return result, result.Validate() == nil
}

func decodePropertyDefinitionResult(value jsonValue) (PropertyDefinitionResult, bool) {
	fields, ok := objectFields(value, "definition")
	if !ok {
		return PropertyDefinitionResult{}, false
	}
	definition, valid := decodePropertyDefinition(fields["definition"])
	return PropertyDefinitionResult{Definition: definition}, valid
}

func decodePropertyAssignmentListResult(value jsonValue) (PropertyAssignmentListResult, bool) {
	fields, ok := objectFieldsWithOptional(value, []string{"assignments", "has_more"}, []string{"next_page_token"})
	if !ok || fields["assignments"].kind != jsonArray || fields["has_more"].kind != jsonBool {
		return PropertyAssignmentListResult{}, false
	}
	token, valid := decodePropertyPagedToken(fields)
	if !valid {
		return PropertyAssignmentListResult{}, false
	}
	result := PropertyAssignmentListResult{Assignments: make([]PropertyAssignment, len(fields["assignments"].items)), NextPageToken: token, HasMore: fields["has_more"].boolean}
	for index, item := range fields["assignments"].items {
		assignment, valid := decodePropertyAssignment(item)
		if !valid {
			return PropertyAssignmentListResult{}, false
		}
		result.Assignments[index] = assignment
	}
	return result, result.Validate() == nil
}

func decodePropertyPreparedChange(value jsonValue) (PropertyPreparedChange, bool) {
	fields, ok := objectFields(value, "target", "property_id", "entry_id", "before", "after")
	if !ok || fields["entry_id"].kind != jsonString {
		return PropertyPreparedChange{}, false
	}
	target, targetCode := decodePropertyTargetSelector(fields["target"])
	propertyID, b := decodePropertyIDField(fields["property_id"])
	desired, c := decodePropertyDesiredState(fields["after"])
	prepared := PropertyPreparedChange{Target: target, PropertyID: propertyID, EntryID: fields["entry_id"].text, After: desired}
	if targetCode != "" || !b || !c {
		return PropertyPreparedChange{}, false
	}
	if fields["before"].kind != jsonNull {
		before, valid := decodePropertyAssignment(fields["before"])
		if !valid {
			return PropertyPreparedChange{}, false
		}
		prepared.Before = &before
	}
	return prepared, prepared.Validate() == nil
}

func decodePropertyChangePrepareResult(value jsonValue) (PropertyChangePrepareResult, bool) {
	fields, ok := objectFields(value, "changes", "requires_confirmation")
	if !ok || fields["changes"].kind != jsonArray || fields["requires_confirmation"].kind != jsonBool {
		return PropertyChangePrepareResult{}, false
	}
	result := PropertyChangePrepareResult{Changes: make([]PropertyPreparedChange, len(fields["changes"].items)), RequiresConfirmation: fields["requires_confirmation"].boolean}
	for index, item := range fields["changes"].items {
		change, valid := decodePropertyPreparedChange(item)
		if !valid {
			return PropertyChangePrepareResult{}, false
		}
		result.Changes[index] = change
	}
	return result, result.Validate() == nil
}

func decodePropertyChangeExecuteResult(value jsonValue) (PropertyChangeExecuteResult, bool) {
	fields, ok := objectFields(value, "assignments")
	if !ok || fields["assignments"].kind != jsonArray {
		return PropertyChangeExecuteResult{}, false
	}
	result := PropertyChangeExecuteResult{Assignments: make([]PropertyAssignment, len(fields["assignments"].items))}
	for index, item := range fields["assignments"].items {
		assignment, valid := decodePropertyAssignment(item)
		if !valid {
			return PropertyChangeExecuteResult{}, false
		}
		result.Assignments[index] = assignment
	}
	return result, result.Validate() == nil
}

func decodePropertyConditionQueryResult(value jsonValue) (PropertyConditionQueryResult, bool) {
	fields, ok := objectFieldsWithOptional(value, []string{"items", "unresolved_candidate_indices", "catalog_version", "has_more"}, []string{"next_page_token"})
	if !ok || fields["items"].kind != jsonArray || fields["unresolved_candidate_indices"].kind != jsonArray || fields["catalog_version"].kind != jsonString || fields["has_more"].kind != jsonBool {
		return PropertyConditionQueryResult{}, false
	}
	token, ok := decodePropertyPagedToken(fields)
	if !ok {
		return PropertyConditionQueryResult{}, false
	}
	result := PropertyConditionQueryResult{Items: make([]PropertyConditionQueryItem, len(fields["items"].items)), UnresolvedCandidateIndices: make([]int, len(fields["unresolved_candidate_indices"].items)), CatalogVersion: fields["catalog_version"].text, HasMore: fields["has_more"].boolean, NextPageToken: token}
	for index, item := range fields["items"].items {
		itemFields, valid := objectFields(item, "candidate_index", "entry_id", "projection")
		if !valid || itemFields["entry_id"].kind != jsonString || itemFields["projection"].kind != jsonArray {
			return PropertyConditionQueryResult{}, false
		}
		candidateIndex, valid := lexicalInteger(itemFields["candidate_index"])
		if !valid || candidateIndex < 0 {
			return PropertyConditionQueryResult{}, false
		}
		mapped := PropertyConditionQueryItem{CandidateIndex: int(candidateIndex), EntryID: itemFields["entry_id"].text, Projection: make([]PropertyAssignment, len(itemFields["projection"].items))}
		for projectionIndex, projectionItem := range itemFields["projection"].items {
			assignment, valid := decodePropertyAssignment(projectionItem)
			if !valid {
				return PropertyConditionQueryResult{}, false
			}
			mapped.Projection[projectionIndex] = assignment
		}
		result.Items[index] = mapped
	}
	for index, item := range fields["unresolved_candidate_indices"].items {
		candidateIndex, valid := lexicalInteger(item)
		if !valid || candidateIndex < 0 {
			return PropertyConditionQueryResult{}, false
		}
		result.UnresolvedCandidateIndices[index] = int(candidateIndex)
	}
	return result, result.Validate() == nil
}
