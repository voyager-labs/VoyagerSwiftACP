package property

import (
	"errors"
	"testing"
)

// TestTargetClassificationEnumeratesProducedValues는 현 슬라이스가 생성하는
// 분류 값을 열거하고 알 수 없는 값이 실패로 닫히는지 증명한다.
func TestTargetClassificationEnumeratesProducedValues(t *testing.T) {
	produced := []TargetClassification{TargetClassificationLocatorDerived}
	if len(produced) != 1 {
		t.Fatalf("produced classification count = %d, want 1", len(produced))
	}
	for _, classification := range produced {
		if !classification.valid() {
			t.Fatalf("produced classification %q must be valid", classification)
		}
	}
	for _, unknown := range []TargetClassification{"", "stable", "locator_derived ", "LOCATOR_DERIVED"} {
		if unknown.valid() {
			t.Fatalf("unknown classification %q must be invalid", unknown)
		}
	}
}

// TestResolvedTargetValidation은 대상 검증이 EntryRef와 분류를 함께 강제하는지
// 증명한다.
func TestResolvedTargetValidation(t *testing.T) {
	valid := mustResolvedTargetFixture(t)
	if err := valid.Validate(); err != nil {
		t.Fatalf("valid target Validate() error = %v", err)
	}

	missingClassification := valid
	missingClassification.Classification = ""
	if err := missingClassification.Validate(); !errors.Is(err, ErrInvalidResolvedTarget) {
		t.Fatalf("missing classification error = %v, want %v", err, ErrInvalidResolvedTarget)
	}

	invalidRef := valid
	invalidRef.EntryRef.EntryID = "ent:broken"
	if err := invalidRef.Validate(); !errors.Is(err, ErrInvalidResolvedTarget) {
		t.Fatalf("invalid ref error = %v, want %v", err, ErrInvalidResolvedTarget)
	}
}
