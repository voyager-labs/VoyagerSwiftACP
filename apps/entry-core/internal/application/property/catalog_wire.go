package property

import (
	schema "github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// DefinitionViewToWire는 정의 뷰를 wire DTO로 사상한다. tombstoned는 wire의
// disabled 상태에 대응한다. runtime dispatch와 create의 커밋 전 응답 예산
// 검사가 같은 사상을 공유해야 하므로 application 패키지가 단일 소유자다.
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
		PropertyID:  view.Definition.PropertyID.String(),
		Key:         view.Definition.CanonicalKey,
		Name:        view.Definition.DisplayName,
		ValueType:   string(view.Definition.ValueType),
		Cardinality: string(view.Definition.Cardinality),
		State:       state,
		Revision:    int64(view.Definition.DefinitionRev),
		Options:     options,
	}
	if definition.Validate() != nil {
		return schema.PropertyDefinition{}, schema.ErrorInternal
	}
	return definition, ""
}

// encodedCreateResponseFits은 definition 생성 결과의 성공 응답이 wire 봉투에
// 들어가는지 protocol EncodedSuccessBytes로 검사한다. execute의 commit 전 예산
// 검사와 같은 65,536바이트 기준이다.
func encodedCreateResponseFits(requestID string, view DefinitionView) bool {
	wire, code := DefinitionViewToWire(view)
	if code != "" {
		return false
	}
	_, fits := schema.EncodedSuccessBytes(requestID, schema.PropertyDefinitionResult{Definition: wire})
	return fits
}
