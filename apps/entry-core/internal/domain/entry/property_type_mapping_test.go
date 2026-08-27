package entry

import (
	"errors"
	"testing"
)

// TestPropertyTypeMappingExhaustive는 지원되는 모든 PropertyType 상수를 정확히 한 번씩
// 열거하는 mapping completeness 테스트다. canonical 6종은 허용 값 종류와 many 지원 여부가
// 고정되고, legacy 6종은 명시적으로 거부된다. 새 PropertyType 상수 추가 시 이 테스트가
// 매핑 누락을 컴파일 이후 첫 실행에서 잡는다.
func TestPropertyTypeMappingExhaustive(t *testing.T) {
	allTypes := []PropertyValueType{
		// canonical assignment 계약 6종.
		PropertyTypeText, PropertyTypeNumber, PropertyTypeDate, PropertyTypeDateTime,
		PropertyTypeBoolean, PropertyTypeSelect,
		// legacy payload 유형 6종은 assignment 계약에서 명시적으로 거부한다.
		PropertyValueTypeString, PropertyValueTypeInt64, PropertyValueTypeDecimal,
		PropertyValueTypeBool, PropertyValueTypeTimestamp, PropertyValueTypeStringList,
	}
	seen := make(map[PropertyValueType]int, len(allTypes))
	for _, valueType := range allTypes {
		seen[valueType]++
		if seen[valueType] != 1 {
			t.Fatalf("type %q enumerated more than once", valueType)
		}
	}

	expectedKinds := map[PropertyValueType][]PropertyValueKind{
		PropertyTypeText:     {PropertyValueKindText},
		PropertyTypeNumber:   {PropertyValueKindDecimal},
		PropertyTypeDate:     {PropertyValueKindDate},
		PropertyTypeDateTime: {PropertyValueKindTimestamp},
		PropertyTypeBoolean:  {PropertyValueKindBoolean},
		PropertyTypeSelect:   {PropertyValueKindOptionRef},
	}
	for _, valueType := range allTypes {
		kinds, err := propertyTypeValueKinds(valueType)
		if want, mapped := expectedKinds[valueType], expectedKinds[valueType] != nil; mapped {
			// Given: 매핑된 canonical 유형
			// When: 허용 값 종류를 조회하면
			if err != nil {
				t.Fatalf("propertyTypeValueKinds(%q) returned error: %v", valueType, err)
			}
			// Then: 고정된 종류 집합을 반환한다.
			if len(kinds) != len(want) {
				t.Fatalf("type %q kinds = %v, want %v", valueType, kinds, want)
			}
			for index, kind := range want {
				if kinds[index] != kind {
					t.Fatalf("type %q kinds[%d] = %q, want %q", valueType, index, kinds[index], kind)
				}
			}
		} else if !errors.Is(err, ErrUnsupportedPropertyType) {
			// Then: 거부 목록의 유형은 typed 오류로 실패 닫기한다.
			t.Fatalf("legacy type %q must be rejected with ErrUnsupportedPropertyType, got %v", valueType, err)
		}
	}
}

func TestPropertyTypeMappingTextFormats(t *testing.T) {
	// Given: text 서식 3종
	// When: 유효성을 검사하면
	for _, format := range []PropertyTextFormat{PropertyTextFormatPlain, PropertyTextFormatURL, PropertyTextFormatEmail} {
		if !format.valid() {
			t.Fatalf("format %q must be valid", format)
		}
	}
	// Then: 미지정 서식은 실패 닫기하고 url/email은 text 유형에만 적용된다.
	if PropertyTextFormat("markdown").valid() {
		t.Fatal("unknown text format must be invalid")
	}
	if err := validateTextFormat(PropertyTypeText, PropertyTextFormatURL); err != nil {
		t.Fatalf("url format on text: %v", err)
	}
	if err := validateTextFormat(PropertyTypeText, PropertyTextFormatEmail); err != nil {
		t.Fatalf("email format on text: %v", err)
	}
	for _, valueType := range []PropertyType{PropertyTypeNumber, PropertyTypeDate, PropertyTypeDateTime, PropertyTypeBoolean, PropertyTypeSelect} {
		if err := validateTextFormat(valueType, PropertyTextFormatURL); !errors.Is(err, ErrInvalidAssignmentContract) {
			t.Fatalf("url format on %q must fail closed, got %v", valueType, err)
		}
	}
}
