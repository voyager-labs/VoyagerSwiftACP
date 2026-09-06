package property

import (
	"strings"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	schema "github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// listableProbeRequestID는 최소 목록 페이지 봉투 검사에 쓰는 최대 길이(maximumEchoIDBytes)
// sentinel 요청 ID다. 이후 조회는 임의의 유효한 길이로 올 수 있으므로 상한 기준으로 검사한다.
var listableProbeRequestID = strings.Repeat("0", maximumEchoIDBytes)

// DefinitionViewToWire는 정의 뷰를 wire DTO로 사상한다. tombstoned는 wire의
// disabled 상태에 대응한다. runtime dispatch와 카탈로그 mutation의 커밋 전
// 응답 예산 검사가 같은 사상을 공유해야 하므로 application 패키지가 단일
// 소유자다.
func DefinitionViewToWire(view DefinitionView) (schema.PropertyDefinition, schema.ErrorCode) {
	state := "disabled"
	if view.IsActive() {
		state = "active"
	}
	options := make([]schema.PropertyOption, len(view.Options))
	for index, option := range view.Options {
		optionState := "disabled"
		if option.Active {
			optionState = "active"
		}
		// wire position은 1-based다(domain ordinal + 1). decodePropertyDefinition이
		// position ≥ 1을 요구하고 −1로 되돌리므로 0-based 값을 그대로 내보내면
		// 모든 option-bearing 정의 응답이 정준 디코딩에 실패한다.
		options[index] = schema.PropertyOption{OptionID: option.OptionID.String(), Label: option.Label, Position: int64(option.Ordinal) + 1, State: optionState}
	}
	definition := schema.PropertyDefinition{
		PropertyID:          view.Definition.PropertyID.String(),
		Key:                 view.Definition.CanonicalKey,
		Name:                view.Definition.DisplayName,
		ValueType:           string(view.Definition.ValueType),
		Cardinality:         string(view.Definition.Cardinality),
		State:               state,
		Origin:              string(view.Definition.Origin),
		Revision:            int64(view.Definition.DefinitionRev),
		Options:             options,
		ConditionCapability: conditionCapabilityToWire(ConditionCapabilityFor(view.Definition)),
	}
	if definition.Validate() != nil {
		return schema.PropertyDefinition{}, schema.ErrorInternal
	}
	return definition, ""
}

func conditionCapabilityToWire(capability ConditionCapability) schema.PropertyConditionCapability {
	if !capability.Supported {
		return schema.PropertyConditionCapability{Reason: capability.Reason}
	}
	return schema.PropertyConditionCapability{
		Supported:        true,
		EvaluationScope:  "local_assignment",
		CatalogVersion:   domainentry.ConditionCatalogVersion,
		NativeType:       string(capability.NativeType),
		AllowedOperators: append([]string(nil), capability.AllowedOperators...),
	}
}

// encodedDefinitionResponseFits은 정의 뷰 결과의 성공 응답이 wire 봉투에 들어가는지
// protocol EncodedSuccessBytes로 검사한다. execute의 commit 전 예산 검사와 같은
// 65,536바이트 기준이다. 요청이 봉투에 들어도 발급 UUID와 상태 필드가 추가된
// 성공 응답은 초과할 수 있으므로 모든 카탈로그 mutation이 커밋 전에 이를 확인한다.
// 단일 정의 결과가 들어가도 최소 목록 페이지(ID 필터 page_size 1)는 definitions
// 배열과 has_more 필드로 더 크다. 목록 조회는 이후 임의의 유효한 요청 ID로 올 수
// 있으므로 이 검사는 mutation의 실제 ID가 아니라 최대 길이 sentinel 기준이다.
func encodedDefinitionResponseFits(requestID string, view DefinitionView) bool {
	wire, code := DefinitionViewToWire(view)
	if code != "" {
		return false
	}
	_, fits := schema.EncodedSuccessBytes(requestID, schema.PropertyDefinitionResult{Definition: wire})
	if !fits {
		return false
	}
	_, fits = schema.EncodedSuccessBytes(listableProbeRequestID, schema.PropertyDefinitionListResult{Definitions: []schema.PropertyDefinition{wire}, HasMore: false})
	return fits
}
