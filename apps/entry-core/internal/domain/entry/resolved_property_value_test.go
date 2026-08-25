package entry

import (
	"errors"
	"testing"
	"time"
)

func TestResolvedPropertyValueSynthesis(t *testing.T) {
	textValue := "hello"
	// Given: text 정의 계약과 값이 저장된 durable assignment
	fact := EntryPropertyAssignment{
		WorkspaceID: testAssignmentWorkspace, EntryID: testAssignmentEntryID, PropertyID: testAssignmentProperty,
		TargetKind: AssignmentTargetCoreNative, State: AssignmentStateValue,
		RecordRevision: 4, ValueContractRevision: 1,
		Scalar: &AssignmentValue{Text: &textValue},
	}
	stored, err := NewEntryPropertyAssignment(fact, textContract())
	if err != nil {
		t.Fatalf("fixture invalid: %v", err)
	}

	// When: 정의 계약과 편집 가능 여부로 projection을 합성하면
	resolved, err := stored.Resolve(textContract(), true, nil)
	// Then: 유형·개수·편집 가능성과 assignment 사실이 함께 담긴다.
	if err != nil {
		t.Fatalf("Resolve returned error: %v", err)
	}
	if resolved.Type != PropertyTypeText || resolved.Cardinality != PropertyCardinalityOne {
		t.Fatalf("resolved contract = %q/%q", resolved.Type, resolved.Cardinality)
	}
	if !resolved.Editable {
		t.Fatal("resolved editable flag must be preserved")
	}
	if resolved.State != AssignmentStateValue || resolved.RecordRevision != 4 {
		t.Fatalf("resolved fact = %q@%d", resolved.State, resolved.RecordRevision)
	}
	if resolved.Scalar == nil || resolved.Scalar.Text == nil || *resolved.Scalar.Text != "hello" {
		t.Fatal("resolved scalar payload mismatch")
	}
	if resolved.Observation != nil {
		t.Fatal("nil observation must stay nil")
	}
}

func TestResolvedPropertyValueImplicitUnsetProjection(t *testing.T) {
	// Given: row가 없는 implicit unset 사실
	fact := ImplicitUnsetEntryPropertyAssignment(testAssignmentWorkspace, testAssignmentEntryID, testAssignmentProperty)
	// When: projection으로 합성하면
	resolved, err := fact.Resolve(textContract(), false, nil)
	// Then: unset@0 상태가 그대로 투영된다.
	if err != nil {
		t.Fatalf("Resolve returned error: %v", err)
	}
	if resolved.State != AssignmentStateUnset || resolved.RecordRevision != 0 {
		t.Fatalf("resolved implicit state = %q@%d", resolved.State, resolved.RecordRevision)
	}
	if resolved.Scalar != nil || len(resolved.Many) != 0 {
		t.Fatal("implicit unset projection must carry no payload")
	}
}

func TestResolvedPropertyValueObservationOutsideAuthority(t *testing.T) {
	observedAt := time.Date(2026, 8, 25, 9, 0, 0, 0, time.UTC)
	observation := ResolvedObservation{
		Producer: ResolvedProducerSource, State: ResolvedObservationUnknown, ObservedAt: observedAt,
	}
	// Given: 소스 관측(unknown)이 붙은 projection 요청
	fact := ImplicitUnsetEntryPropertyAssignment(testAssignmentWorkspace, testAssignmentEntryID, testAssignmentProperty)
	resolved, err := fact.Resolve(textContract(), false, &observation)
	if err != nil {
		t.Fatalf("Resolve returned error: %v", err)
	}
	// Then: 관측은 projection에만 존재하고 권위 assignment 사실에는 없다.
	if resolved.Observation == nil || resolved.Observation.State != ResolvedObservationUnknown {
		t.Fatal("projection must carry the observation envelope")
	}
	if fact.hasObservationFields() {
		t.Fatal("authoritative assignment must not carry observation fields")
	}

	failures := []ResolvedObservation{
		{Producer: "provider", State: ResolvedObservationOK, ObservedAt: observedAt},
		{Producer: ResolvedProducerSource, State: "stale", ObservedAt: observedAt},
		{Producer: ResolvedProducerSource, State: ResolvedObservationError},
	}
	for _, invalid := range failures {
		// When: 잘못된 관측 봉투를 넣으면
		_, err := fact.Resolve(textContract(), false, &invalid)
		// Then: typed 오류로 실패 닫기한다.
		if !errors.Is(err, ErrInvalidResolvedObservation) {
			t.Fatalf("want ErrInvalidResolvedObservation, got %v", err)
		}
	}
}
