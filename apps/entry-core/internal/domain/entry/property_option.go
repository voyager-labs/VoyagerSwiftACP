package entry

import "errors"

var (
	ErrInvalidPropertyOption          = errors.New("invalid property option")
	ErrInvalidPropertyOptionSet       = errors.New("invalid property option set")
	ErrDuplicatePropertyOptionID      = errors.New("duplicate property option id")
	ErrDuplicatePropertyOptionOrdinal = errors.New("duplicate property option ordinal")
)

// PropertyOption은 select 정의의 선택지 하나에 대한 stable identity와 표시
// 메타데이터를 소유한다. Option value는 rename 가능한 label이 아니라
// PropertyOptionID로 참조되며, disable은 기존 assignment와 read-back을 보존한다.
type PropertyOption struct {
	OptionID   PropertyOptionID
	PropertyID PropertyID
	Label      string
	Color      string
	Ordinal    int
	Active     bool
}

// NewPropertyOption은 선택지를 검증해 복사본으로 반환한다.
func NewPropertyOption(option PropertyOption) (PropertyOption, error) {
	if err := option.Validate(); err != nil {
		return PropertyOption{}, err
	}
	return option, nil
}

func (option PropertyOption) Validate() error {
	if !option.OptionID.valid() || !option.PropertyID.valid() ||
		!validUTF8Bytes(option.Label, 1, 256) || !validUTF8Bytes(option.Color, 0, 64) ||
		option.Ordinal < 0 {
		return ErrInvalidPropertyOption
	}
	return nil
}

// ValidatePropertyOptions는 같은 정의에 속한 선택지 집합을 검증한다. 모든 선택지는
// 동일한 소유 정의를 가져야 하고 option id와 ordinal은 각각 유일해야 한다. 빈
// 집합과 최대치 초과도 실패 닫기한다.
func ValidatePropertyOptions(options []PropertyOption) error {
	if len(options) < 1 || len(options) > maximumAllowedOptions {
		return ErrInvalidPropertyOptionSet
	}
	ids := make(map[PropertyOptionID]struct{}, len(options))
	ordinals := make(map[int]struct{}, len(options))
	for index, option := range options {
		if err := option.Validate(); err != nil {
			return err
		}
		if index > 0 && option.PropertyID != options[0].PropertyID {
			return ErrInvalidPropertyOptionSet
		}
		if _, exists := ids[option.OptionID]; exists {
			return ErrDuplicatePropertyOptionID
		}
		if _, exists := ordinals[option.Ordinal]; exists {
			return ErrDuplicatePropertyOptionOrdinal
		}
		ids[option.OptionID] = struct{}{}
		ordinals[option.Ordinal] = struct{}{}
	}
	return nil
}
