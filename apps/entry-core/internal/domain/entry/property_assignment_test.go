package entry

import (
	"errors"
	"strings"
	"testing"
)

// 테스트 픽스처: 유효한 identity 값들.
var (
	testAssignmentWorkspace = func() WorkspaceID {
		id, err := NewWorkspaceID()
		if err != nil {
			panic(err)
		}
		return id
	}()
	testAssignmentEntryID  = "ent:" + strings.Repeat("A", 43)
	testAssignmentProperty = MustPropertyID("4e25d517-09e2-5cbb-83f9-ed2290161e08")
	testOptionIDA          = MustPropertyOptionID("0198f0a2-7b3c-7456-9abc-def012345678")
	testOptionIDB          = MustPropertyOptionID("0198f0a2-7b3c-7abc-abcd-def012345678")
)

func textContract() AssignmentContract {
	return AssignmentContract{Type: PropertyTypeText, Cardinality: PropertyCardinalityOne}
}

func multiSelectContract(active ...PropertyOptionID) AssignmentContract {
	options := make(map[PropertyOptionID]struct{}, len(active))
	for _, id := range active {
		options[id] = struct{}{}
	}
	return AssignmentContract{
		Type: PropertyTypeSelect, Cardinality: PropertyCardinalityMany,
		Nullable: true, ActiveOptions: options,
	}
}

func TestEntryPropertyAssignmentImplicitUnsetAtRevisionZero(t *testing.T) {
	// Given: 저장 row가 없는 (workspace, entry, property) 삼중
	// When: implicit unset 사실을 구성하면
	fact := ImplicitUnsetEntryPropertyAssignment(testAssignmentWorkspace, testAssignmentEntryID, testAssignmentProperty)
	// Then: 상태는 unset, 기록 revision은 정확히 0이고 payload가 없다.
	if fact.State != AssignmentStateUnset {
		t.Fatalf("implicit unset state = %q", fact.State)
	}
	if fact.RecordRevision != 0 || fact.ValueContractRevision != 0 {
		t.Fatalf("implicit unset revisions = %d/%d, want 0/0", fact.RecordRevision, fact.ValueContractRevision)
	}
	if fact.Scalar != nil || len(fact.Many) != 0 {
		t.Fatal("implicit unset must carry no payload")
	}
	if err := fact.Validate(textContract()); err != nil {
		t.Fatalf("implicit unset must validate against any contract: %v", err)
	}
}

func TestEntryPropertyAssignmentDurableStates(t *testing.T) {
	booleanTrue := true
	textValue := "hello"
	cases := []struct {
		name     string
		fact     EntryPropertyAssignment
		contract AssignmentContract
	}{
		{
			name: "durable_unset_row",
			fact: EntryPropertyAssignment{
				WorkspaceID: testAssignmentWorkspace, EntryID: testAssignmentEntryID, PropertyID: testAssignmentProperty,
				TargetKind: AssignmentTargetCoreNative, State: AssignmentStateUnset,
				RecordRevision: 3, ValueContractRevision: 1,
			},
			contract: textContract(),
		},
		{
			name: "durable_null_row",
			fact: EntryPropertyAssignment{
				WorkspaceID: testAssignmentWorkspace, EntryID: testAssignmentEntryID, PropertyID: testAssignmentProperty,
				TargetKind: AssignmentTargetLocatorDerived, State: AssignmentStateNull,
				RecordRevision: 1, ValueContractRevision: 2,
			},
			contract: AssignmentContract{Type: PropertyTypeText, Cardinality: PropertyCardinalityOne, Nullable: true},
		},
		{
			name: "durable_scalar_value_row",
			fact: EntryPropertyAssignment{
				WorkspaceID: testAssignmentWorkspace, EntryID: testAssignmentEntryID, PropertyID: testAssignmentProperty,
				TargetKind: AssignmentTargetCoreNative, State: AssignmentStateValue,
				RecordRevision: 7, ValueContractRevision: 1,
				Scalar: &AssignmentValue{Text: &textValue},
			},
			contract: textContract(),
		},
		{
			name: "durable_boolean_false_value_row",
			fact: EntryPropertyAssignment{
				WorkspaceID: testAssignmentWorkspace, EntryID: testAssignmentEntryID, PropertyID: testAssignmentProperty,
				TargetKind: AssignmentTargetCoreNative, State: AssignmentStateValue,
				RecordRevision: 1, ValueContractRevision: 1,
				Scalar: &AssignmentValue{Boolean: &booleanTrue},
			},
			contract: AssignmentContract{Type: PropertyTypeBoolean, Cardinality: PropertyCardinalityOne},
		},
		{
			name: "empty_many_is_value_state",
			fact: EntryPropertyAssignment{
				WorkspaceID: testAssignmentWorkspace, EntryID: testAssignmentEntryID, PropertyID: testAssignmentProperty,
				TargetKind: AssignmentTargetCoreNative, State: AssignmentStateValue,
				RecordRevision: 2, ValueContractRevision: 1,
				Many: []OrderedAssignmentValue{},
			},
			contract: multiSelectContract(testOptionIDA),
		},
		{
			name: "ordered_many_values",
			fact: EntryPropertyAssignment{
				WorkspaceID: testAssignmentWorkspace, EntryID: testAssignmentEntryID, PropertyID: testAssignmentProperty,
				TargetKind: AssignmentTargetCoreNative, State: AssignmentStateValue,
				RecordRevision: 2, ValueContractRevision: 1,
				Many: []OrderedAssignmentValue{
					{Ordinal: 0, Value: AssignmentValue{OptionID: &testOptionIDA}},
					{Ordinal: 1, Value: AssignmentValue{OptionID: &testOptionIDB}},
				},
			},
			contract: multiSelectContract(testOptionIDA, testOptionIDB),
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			// Given: revision >= 1의 durable row 사실과 일치하는 계약
			// When: 검증하면
			stored, err := NewEntryPropertyAssignment(testCase.fact, testCase.contract)
			// Then: 통과하고 payload는 별칭 없이 복제된다.
			if err != nil {
				t.Fatalf("NewEntryPropertyAssignment returned error: %v", err)
			}
			if stored.State != testCase.fact.State || stored.RecordRevision != testCase.fact.RecordRevision {
				t.Fatal("stored fact must preserve state and revision")
			}
		})
	}
}

func TestEntryPropertyAssignmentRejectsFailClosed(t *testing.T) {
	booleanFalse := false
	emptyText := ""
	inactiveOption := MustPropertyOptionID("0198f0a2-7b3c-7000-babc-def012345678")

	base := func() EntryPropertyAssignment {
		return EntryPropertyAssignment{
			WorkspaceID: testAssignmentWorkspace, EntryID: testAssignmentEntryID, PropertyID: testAssignmentProperty,
			TargetKind: AssignmentTargetCoreNative, State: AssignmentStateValue,
			RecordRevision: 1, ValueContractRevision: 1,
		}
	}

	cases := []struct {
		name     string
		fact     EntryPropertyAssignment
		contract AssignmentContract
		wantErr  error
	}{
		{
			name: "revision_zero_durable_row",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.State = AssignmentStateUnset
				fact.RecordRevision = 0
				fact.ValueContractRevision = 0
				return fact
			}(),
			contract: textContract(),
			wantErr:  ErrAssignmentRevisionRequired,
		},
		{
			name: "negative_revision",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.State = AssignmentStateUnset
				fact.RecordRevision = -1
				return fact
			}(),
			contract: textContract(),
			wantErr:  ErrAssignmentRevisionRequired,
		},
		{
			name: "null_state_on_non_nullable_definition",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.State = AssignmentStateNull
				return fact
			}(),
			contract: textContract(),
			wantErr:  ErrAssignmentNullNotAllowed,
		},
		{
			name: "unset_state_carrying_payload",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.State = AssignmentStateUnset
				fact.Scalar = &AssignmentValue{Boolean: &booleanFalse}
				return fact
			}(),
			contract: AssignmentContract{Type: PropertyTypeBoolean, Cardinality: PropertyCardinalityOne},
			wantErr:  ErrAssignmentPayloadNotAllowed,
		},
		{
			name: "value_state_without_payload",
			fact: base(),
			contract: AssignmentContract{
				Type: PropertyTypeSelect, Cardinality: PropertyCardinalityMany,
				ActiveOptions: map[PropertyOptionID]struct{}{},
			},
			wantErr: ErrAssignmentPayloadRequired,
		},
		{
			name: "wrong_value_kind",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.Scalar = &AssignmentValue{Boolean: &booleanFalse}
				return fact
			}(),
			contract: textContract(),
			wantErr:  ErrAssignmentValueTypeMismatch,
		},
		{
			name: "empty_scalar_text",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.Scalar = &AssignmentValue{Text: &emptyText}
				return fact
			}(),
			contract: textContract(),
			wantErr:  ErrAssignmentEmptyScalar,
		},
		{
			name: "inactive_selected_option",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.Many = []OrderedAssignmentValue{{Ordinal: 0, Value: AssignmentValue{OptionID: &inactiveOption}}}
				return fact
			}(),
			contract: multiSelectContract(testOptionIDA),
			wantErr:  ErrAssignmentInactiveOption,
		},
		{
			name: "duplicate_ordinals",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.Many = []OrderedAssignmentValue{
					{Ordinal: 0, Value: AssignmentValue{OptionID: &testOptionIDA}},
					{Ordinal: 0, Value: AssignmentValue{OptionID: &testOptionIDB}},
				}
				return fact
			}(),
			contract: multiSelectContract(testOptionIDA, testOptionIDB),
			wantErr:  ErrAssignmentDuplicateOrdinal,
		},
		{
			name: "non_contiguous_ordinals",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.Many = []OrderedAssignmentValue{
					{Ordinal: 0, Value: AssignmentValue{OptionID: &testOptionIDA}},
					{Ordinal: 5, Value: AssignmentValue{OptionID: &testOptionIDB}},
				}
				return fact
			}(),
			contract: multiSelectContract(testOptionIDA, testOptionIDB),
			wantErr:  ErrAssignmentDuplicateOrdinal,
		},
		{
			name: "duplicate_option_selection",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.Many = []OrderedAssignmentValue{
					{Ordinal: 0, Value: AssignmentValue{OptionID: &testOptionIDA}},
					{Ordinal: 1, Value: AssignmentValue{OptionID: &testOptionIDA}},
				}
				return fact
			}(),
			contract: multiSelectContract(testOptionIDA),
			wantErr:  ErrAssignmentDuplicateOption,
		},
		{
			name: "many_payload_on_one_cardinality",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.Many = []OrderedAssignmentValue{{Ordinal: 0, Value: AssignmentValue{OptionID: &testOptionIDA}}}
				return fact
			}(),
			contract: AssignmentContract{
				Type: PropertyTypeSelect, Cardinality: PropertyCardinalityOne,
				ActiveOptions: map[PropertyOptionID]struct{}{testOptionIDA: {}},
			},
			wantErr: ErrAssignmentCardinalityMismatch,
		},
		{
			name: "invalid_target_kind",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.State = AssignmentStateUnset
				fact.TargetKind = "unknown"
				return fact
			}(),
			contract: textContract(),
			wantErr:  ErrInvalidAssignmentTargetKind,
		},
		{
			name: "unsupported_legacy_type_contract",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.State = AssignmentStateUnset
				return fact
			}(),
			contract: AssignmentContract{Type: PropertyValueTypeStringList, Cardinality: PropertyCardinalityMany},
			wantErr:  ErrUnsupportedPropertyType,
		},
		{
			name: "malformed_entry_id",
			fact: func() EntryPropertyAssignment {
				fact := base()
				fact.State = AssignmentStateUnset
				fact.EntryID = "not-an-entry-id"
				return fact
			}(),
			contract: textContract(),
			wantErr:  ErrInvalidEntryPropertyAssignment,
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			// Given: 계약을 위반하는 durable 사실
			// When: 검증하면
			_, err := NewEntryPropertyAssignment(testCase.fact, testCase.contract)
			// Then: 지정된 typed 오류로 실패 닫기한다.
			if !errors.Is(err, testCase.wantErr) {
				t.Fatalf("want %v, got %v", testCase.wantErr, err)
			}
		})
	}
}

func TestPropertyOptionValidateAndSet(t *testing.T) {
	validOption := func() PropertyOption {
		return PropertyOption{
			OptionID: testOptionIDA, PropertyID: testAssignmentProperty,
			Label: "In Progress", Color: "#ffaa00", Ordinal: 0, Active: true,
		}
	}
	// Given: 유효한 선택지
	// When: 생성하면
	option, err := NewPropertyOption(validOption())
	// Then: 통과한다.
	if err != nil {
		t.Fatalf("NewPropertyOption returned error: %v", err)
	}
	if option.Label != "In Progress" {
		t.Fatal("option label must be preserved")
	}

	failures := map[string]PropertyOption{
		"empty_label":    func() PropertyOption { option := validOption(); option.Label = ""; return option }(),
		"zero_option_id": func() PropertyOption { option := validOption(); option.OptionID = PropertyOptionID{}; return option }(),
		"zero_property":  func() PropertyOption { option := validOption(); option.PropertyID = PropertyID{}; return option }(),
		"negative_ordinal": func() PropertyOption {
			option := validOption()
			option.Ordinal = -1
			return option
		}(),
	}
	for name, invalid := range failures {
		t.Run(name, func(t *testing.T) {
			if _, err := NewPropertyOption(invalid); !errors.Is(err, ErrInvalidPropertyOption) {
				t.Fatalf("want ErrInvalidPropertyOption, got %v", err)
			}
		})
	}

	t.Run("duplicate_ordinals_fail_closed", func(t *testing.T) {
		// Given: 같은 ordinal을 공유하는 선택지 집합
		first := validOption()
		second := validOption()
		second.OptionID = testOptionIDB
		// When: 집합을 검증하면
		err := ValidatePropertyOptions([]PropertyOption{first, second})
		// Then: 중복 ordinal typed 오류로 실패 닫기한다.
		if !errors.Is(err, ErrDuplicatePropertyOptionOrdinal) {
			t.Fatalf("want ErrDuplicatePropertyOptionOrdinal, got %v", err)
		}
	})

	t.Run("duplicate_option_ids_fail_closed", func(t *testing.T) {
		first := validOption()
		second := validOption()
		second.Ordinal = 1
		if err := ValidatePropertyOptions([]PropertyOption{first, second}); !errors.Is(err, ErrDuplicatePropertyOptionID) {
			t.Fatalf("want ErrDuplicatePropertyOptionID, got %v", err)
		}
	})

	t.Run("mixed_owner_fail_closed", func(t *testing.T) {
		first := validOption()
		second := validOption()
		second.Ordinal = 1
		second.PropertyID = MustPropertyID("0198f0a2-7b3c-7777-9abc-def012345678")
		if err := ValidatePropertyOptions([]PropertyOption{first, second}); !errors.Is(err, ErrInvalidPropertyOptionSet) {
			t.Fatalf("want ErrInvalidPropertyOptionSet, got %v", err)
		}
	})
}

var (
	firstDescription  = "first description"
	secondDescription = "second description"
	notANumber        = "not a number"
	emptyMemberText   = ""
	gapFirst          = "first"
	gapThird          = "third"
)

// text+many 정의(System Registry 2.4.1 시드가 27개 보유)는 many 스칼라
// assignment가 가능해야 한다. select 한정이었던 구계약의 회귀를 잠근다.
func TestManySupportsScalarTypes(t *testing.T) {
	contract := AssignmentContract{Type: PropertyTypeText, Cardinality: PropertyCardinalityMany}
	fact := EntryPropertyAssignment{
		WorkspaceID: testAssignmentWorkspace, EntryID: testAssignmentEntryID, PropertyID: testAssignmentProperty,
		TargetKind: AssignmentTargetLocatorDerived, State: AssignmentStateValue,
		RecordRevision: 1, ValueContractRevision: 1,
		Many: []OrderedAssignmentValue{
			{Ordinal: 0, Value: AssignmentValue{Text: &firstDescription}},
			{Ordinal: 1, Value: AssignmentValue{Text: &secondDescription}},
		},
	}
	if _, err := NewEntryPropertyAssignment(fact, contract); err != nil {
		t.Fatalf("text+many assignment = %v, want accepted", err)
	}

	// 멤버 내용 검증은 one과 같은 스칼라 규칙을 따른다.
	badNumber := fact
	badNumber.Many = []OrderedAssignmentValue{
		{Ordinal: 0, Value: AssignmentValue{Text: &notANumber}},
	}
	numberContract := AssignmentContract{Type: PropertyTypeNumber, Cardinality: PropertyCardinalityMany}
	if _, err := NewEntryPropertyAssignment(badNumber, numberContract); !errors.Is(err, ErrAssignmentValueTypeMismatch) {
		t.Fatalf("kind mismatch = %v, want ErrAssignmentValueTypeMismatch", err)
	}

	badFormat := fact
	badFormat.Many = []OrderedAssignmentValue{
		{Ordinal: 0, Value: AssignmentValue{Text: &emptyMemberText}},
	}
	if _, err := NewEntryPropertyAssignment(badFormat, contract); !errors.Is(err, ErrAssignmentEmptyScalar) {
		t.Fatalf("empty member = %v, want ErrAssignmentEmptyScalar", err)
	}

	// ordinal 연속 규칙은 유형과 무관하게 유지된다.
	gapped := fact
	gapped.Many = []OrderedAssignmentValue{
		{Ordinal: 0, Value: AssignmentValue{Text: &gapFirst}},
		{Ordinal: 2, Value: AssignmentValue{Text: &gapThird}},
	}
	if _, err := NewEntryPropertyAssignment(gapped, contract); !errors.Is(err, ErrAssignmentDuplicateOrdinal) {
		t.Fatalf("gap = %v, want ErrAssignmentDuplicateOrdinal", err)
	}
}
