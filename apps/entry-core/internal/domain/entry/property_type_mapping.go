package entry

import (
	"errors"
	"time"
)

var ErrUnsupportedPropertyType = errors.New("unsupported property type")

// PropertyTextFormat은 text 유형의 서식 변형이다. url과 email은 formatted text
// 유형이며 text 정의에만 적용된다.
type PropertyTextFormat string

const (
	PropertyTextFormatPlain PropertyTextFormat = "plain"
	PropertyTextFormatURL   PropertyTextFormat = "url"
	PropertyTextFormatEmail PropertyTextFormat = "email"
)

func (format PropertyTextFormat) valid() bool {
	switch format {
	case PropertyTextFormatPlain, PropertyTextFormatURL, PropertyTextFormatEmail:
		return true
	default:
		return false
	}
}

// validateTextFormat은 서식이 적용 가능한 유형과의 호환을 강제한다. url/email은
// text 유형 전용이고, 나머지 조합은 실패 닫기한다.
func validateTextFormat(valueType PropertyType, format PropertyTextFormat) error {
	if !canonicalPropertyType(valueType) {
		return ErrUnsupportedPropertyType
	}
	if !format.valid() {
		return ErrInvalidAssignmentContract
	}
	if format != PropertyTextFormatPlain && valueType != PropertyTypeText {
		return ErrInvalidAssignmentContract
	}
	return nil
}

// PropertyValueKind는 assignment가 운반하는 구체 값의 종류다. 유형별 허용 종류는
// propertyTypeValueKinds가 소유하며 이 표가 유일한 권위 매핑이다.
type PropertyValueKind string

const (
	PropertyValueKindBoolean   PropertyValueKind = "boolean"
	PropertyValueKindDecimal   PropertyValueKind = "decimal"
	PropertyValueKindDate      PropertyValueKind = "date"
	PropertyValueKindTimestamp PropertyValueKind = "timestamp"
	PropertyValueKindText      PropertyValueKind = "text"
	PropertyValueKindOptionRef PropertyValueKind = "option_ref"
)

// propertyTypeValueKinds는 지원되는 모든 PropertyType에 대해 허용되는 값 종류를
// 반환한다. canonical 6종(text, number, date, datetime, boolean, select)만
// 매핑되고 legacy payload 유형을 포함한 나머지는 ErrUnsupportedPropertyType으로
// 실패 닫기한다. 새 PropertyType 상수 추가 시 이 switch와 그 열거 테스트가 함께
// 갱신되어야 한다.
func propertyTypeValueKinds(valueType PropertyType) ([]PropertyValueKind, error) {
	switch valueType {
	case PropertyTypeText:
		return []PropertyValueKind{PropertyValueKindText}, nil
	case PropertyTypeNumber:
		return []PropertyValueKind{PropertyValueKindDecimal}, nil
	case PropertyTypeDate:
		return []PropertyValueKind{PropertyValueKindDate}, nil
	case PropertyTypeDateTime:
		return []PropertyValueKind{PropertyValueKindTimestamp}, nil
	case PropertyTypeBoolean:
		return []PropertyValueKind{PropertyValueKindBoolean}, nil
	case PropertyTypeSelect:
		return []PropertyValueKind{PropertyValueKindOptionRef}, nil
	default:
		return nil, ErrUnsupportedPropertyType
	}
}

// typeSupportsMany는 many 개수 규칙을 지원하는 유형을 select로 한정한다.
// multi-select가 유일한 many 사례다.
func typeSupportsMany(valueType PropertyType) bool {
	return valueType == PropertyTypeSelect
}

// validateScalarContent는 스칼라 값 내용이 종류별 형식을 만족하는지 검사한다.
// 빈 문자열은 ErrAssignmentEmptyScalar, 형식 위반은 ErrInvalidAssignmentScalar로
// 구분해 실패 닫기한다.
func validateScalarContent(kind PropertyValueKind, value AssignmentValue) error {
	switch kind {
	case PropertyValueKindBoolean:
		return nil
	case PropertyValueKindDecimal:
		if len(*value.Decimal) == 0 {
			return ErrAssignmentEmptyScalar
		}
		if !validCanonicalDecimal(*value.Decimal) {
			return ErrInvalidAssignmentScalar
		}
		return nil
	case PropertyValueKindDate:
		if len(*value.Date) == 0 {
			return ErrAssignmentEmptyScalar
		}
		parsed, err := time.Parse("2006-01-02", *value.Date)
		if err != nil || parsed.Format("2006-01-02") != *value.Date {
			return ErrInvalidAssignmentScalar
		}
		return nil
	case PropertyValueKindTimestamp:
		if len(*value.Timestamp) == 0 {
			return ErrAssignmentEmptyScalar
		}
		parsed, err := time.Parse(time.RFC3339Nano, *value.Timestamp)
		if err != nil || parsed.Round(0).UTC().Format(time.RFC3339Nano) != *value.Timestamp {
			return ErrInvalidAssignmentScalar
		}
		return nil
	case PropertyValueKindText:
		if len(*value.Text) == 0 {
			return ErrAssignmentEmptyScalar
		}
		if !validUTF8Bytes(*value.Text, 1, maximumPropertyTextBytes) {
			return ErrInvalidAssignmentScalar
		}
		return nil
	case PropertyValueKindOptionRef:
		if !value.OptionID.valid() {
			return ErrInvalidAssignmentScalar
		}
		return nil
	default:
		return ErrUnsupportedPropertyType
	}
}
