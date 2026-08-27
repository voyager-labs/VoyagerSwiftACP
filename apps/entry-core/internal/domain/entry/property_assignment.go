package entry

import (
	"errors"
	"fmt"
)

var (
	ErrInvalidEntryPropertyAssignment = errors.New("invalid entry property assignment")
	ErrInvalidAssignmentTargetKind    = errors.New("invalid assignment target kind")
	ErrInvalidAssignmentState         = errors.New("invalid assignment state")
	ErrAssignmentRevisionRequired     = errors.New("durable assignment row requires positive revisions")
	ErrAssignmentNullNotAllowed       = errors.New("assignment null state requires nullable definition")
	ErrAssignmentPayloadNotAllowed    = errors.New("assignment state forbids payload")
	ErrAssignmentPayloadRequired      = errors.New("assignment value state requires payload")
	ErrAssignmentValueTypeMismatch    = errors.New("assignment value kind does not match property type")
	ErrAssignmentCardinalityMismatch  = errors.New("assignment cardinality does not match property contract")
	ErrAssignmentInactiveOption       = errors.New("assignment references inactive property option")
	ErrAssignmentDuplicateOrdinal     = errors.New("assignment many values contain duplicate or non-contiguous ordinals")
	ErrAssignmentDuplicateOption      = errors.New("assignment many values contain duplicate options")
	ErrAssignmentEmptyScalar          = errors.New("assignment scalar value is empty")
	ErrInvalidAssignmentScalar        = errors.New("invalid assignment scalar content")
	ErrInvalidAssignmentContract      = errors.New("invalid assignment contract")
)

// AssignmentTargetKind는 assignment 대상 identity의 분류다. core_native는
// canonical EntryRef 유래 대상, locator_derived는 local_path 같은 transitional
// locator 대상이다. 후속 migration/cleanup이 이 분류로 구별한다.
type AssignmentTargetKind string

const (
	AssignmentTargetCoreNative     AssignmentTargetKind = "core_native"
	AssignmentTargetLocatorDerived AssignmentTargetKind = "locator_derived"
)

// RecordRevision은 assignment row의 기록 revision 카운터다. 0은 저장되지 않은
// implicit unset뿐이고 durable row는 항상 1 이상이다.
type RecordRevision int

// ValueContractRevision은 row가 기록된 값 계약 버전이다. durable row는 항상
// 1 이상의 계약 아래에서 기록된다.
type ValueContractRevision int

// AssignmentState는 durable 값 상태다. unset(값 지정 없음), null(nullable 정의에
// 명시적으로 저장된 null), value(유형에 맞는 값)는 서로 collapse되지 않는다.
type AssignmentState string

const (
	AssignmentStateUnset AssignmentState = "unset"
	AssignmentStateNull  AssignmentState = "null"
	AssignmentStateValue AssignmentState = "value"
)

// OrderedAssignmentValue는 many 개수 규칙에서 순서를 담당하는 멤버다. Ordinal은
// 0부터 연속적으로 증가해야 한다.
type OrderedAssignmentValue struct {
	Ordinal int
	Value   AssignmentValue
}

// AssignmentContract는 assignment 검증에 필요한 정의 유래 계약 입력이다. 검증에만
// 쓰이고 durable row에는 저장되지 않는다(정의에서 유도 가능한 중복 금지).
type AssignmentContract struct {
	Type          PropertyType
	Cardinality   PropertyCardinality
	Nullable      bool
	ActiveOptions map[PropertyOptionID]struct{}
}

func (contract AssignmentContract) Validate() error {
	if !canonicalPropertyType(contract.Type) {
		return ErrUnsupportedPropertyType
	}
	if !contract.Cardinality.valid() {
		return ErrInvalidAssignmentContract
	}
	if contract.Type == PropertyTypeSelect && contract.ActiveOptions == nil {
		return ErrInvalidAssignmentContract
	}
	return nil
}

// EntryPropertyAssignment는 SQLite에 저장되는 사용자 입력 로컬 권위 사실이다.
// Durable identity는 (workspace_id, entry_id, property_id) tuple이며 surrogate
// ID는 없다. Provider 관측, source revision, freshness는 여기에 절대 저장되지
// 않는다 — ResolvedPropertyValue projection 전용이다.
type EntryPropertyAssignment struct {
	WorkspaceID WorkspaceID
	EntryID     string
	PropertyID  PropertyID

	TargetKind AssignmentTargetKind

	State                 AssignmentState
	RecordRevision        RecordRevision
	ValueContractRevision ValueContractRevision

	Scalar *AssignmentValue
	Many   []OrderedAssignmentValue
}

// ImplicitUnsetEntryPropertyAssignment는 저장 row가 없을 때의 암묵적 사실을
// 구성한다: unset 상태, revision 0, payload 없음. 이 값은 저장되지 않는다.
func ImplicitUnsetEntryPropertyAssignment(workspaceID WorkspaceID, entryID string, propertyID PropertyID) EntryPropertyAssignment {
	return EntryPropertyAssignment{
		WorkspaceID: workspaceID,
		EntryID:     entryID,
		PropertyID:  propertyID,
		TargetKind:  AssignmentTargetCoreNative,
		State:       AssignmentStateUnset,
	}
}

// NewEntryPropertyAssignment는 저장될 durable row 사실을 검증해 복사본으로
// 반환한다. revision 0은 implicit unset 전용이므로 durable row로는 항상 거부된다.
func NewEntryPropertyAssignment(fact EntryPropertyAssignment, contract AssignmentContract) (EntryPropertyAssignment, error) {
	if err := fact.Validate(contract); err != nil {
		return EntryPropertyAssignment{}, err
	}
	if fact.RecordRevision < 1 || fact.ValueContractRevision < 1 {
		return EntryPropertyAssignment{}, ErrAssignmentRevisionRequired
	}
	return EntryPropertyAssignment{
		WorkspaceID:           fact.WorkspaceID,
		EntryID:               fact.EntryID,
		PropertyID:            fact.PropertyID,
		TargetKind:            fact.TargetKind,
		State:                 fact.State,
		RecordRevision:        fact.RecordRevision,
		ValueContractRevision: fact.ValueContractRevision,
		Scalar:                cloneAssignmentValue(fact.Scalar),
		Many:                  cloneOrderedAssignmentValues(fact.Many),
	}, nil
}

// Validate는 assignment 상태 기계를 검증한다. unset@0(implicit), durable
// unset|null|value@>=1, ordered many ordinal 연속성, empty-many=value 상태를
// 강제한다.
func (assignment EntryPropertyAssignment) Validate(contract AssignmentContract) error {
	if err := contract.Validate(); err != nil {
		return err
	}
	if assignment.WorkspaceID == (WorkspaceID{}) || !validPrefixedDigest(assignment.EntryID, entryIDPrefix) ||
		!assignment.PropertyID.valid() {
		return fmt.Errorf("%w: identity", ErrInvalidEntryPropertyAssignment)
	}
	switch assignment.TargetKind {
	case AssignmentTargetCoreNative, AssignmentTargetLocatorDerived:
	default:
		return ErrInvalidAssignmentTargetKind
	}
	if assignment.RecordRevision < 0 || assignment.ValueContractRevision < 0 {
		return ErrAssignmentRevisionRequired
	}
	switch assignment.State {
	case AssignmentStateUnset, AssignmentStateNull, AssignmentStateValue:
	default:
		return ErrInvalidAssignmentState
	}

	hasScalar := assignment.Scalar != nil
	manyPresent := assignment.Many != nil

	if assignment.RecordRevision == 0 {
		// revision 0은 payload 없는 implicit unset뿐이다.
		if assignment.ValueContractRevision != 0 || assignment.State != AssignmentStateUnset ||
			hasScalar || manyPresent {
			return ErrAssignmentRevisionRequired
		}
		return nil
	}
	if assignment.ValueContractRevision < 1 {
		return ErrAssignmentRevisionRequired
	}

	switch assignment.State {
	case AssignmentStateUnset:
		if hasScalar || manyPresent {
			return ErrAssignmentPayloadNotAllowed
		}
	case AssignmentStateNull:
		if hasScalar || manyPresent {
			return ErrAssignmentPayloadNotAllowed
		}
		if !contract.Nullable {
			return ErrAssignmentNullNotAllowed
		}
	case AssignmentStateValue:
		if !hasScalar && !manyPresent {
			return ErrAssignmentPayloadRequired
		}
		if hasScalar && manyPresent {
			return ErrAssignmentCardinalityMismatch
		}
		allowedKinds, err := propertyTypeValueKinds(contract.Type)
		if err != nil {
			return err
		}
		if contract.Cardinality == PropertyCardinalityMany {
			if hasScalar {
				return ErrAssignmentCardinalityMismatch
			}
			return assignment.validateManyValues(contract)
		}
		if manyPresent {
			return ErrAssignmentCardinalityMismatch
		}
		return assignment.validateScalarValue(allowedKinds)
	}
	return nil
}

func (assignment EntryPropertyAssignment) validateScalarValue(allowedKinds []PropertyValueKind) error {
	kind, ok := assignment.Scalar.Kind()
	if !ok {
		return ErrAssignmentValueTypeMismatch
	}
	for _, allowed := range allowedKinds {
		if kind == allowed {
			return assignment.Scalar.ValidateContent()
		}
	}
	return ErrAssignmentValueTypeMismatch
}

func (assignment EntryPropertyAssignment) validateManyValues(contract AssignmentContract) error {
	// many는 select뿐 아니라 스칼라 유형도 지원한다(System Registry 2.4.1의
	// text+many 정의가 authority). select는 옵션 참조 검증을, 나머지는 정의
	// 유형과 일치하는 스칼라 내용 검증을 적용한다.
	expectedKind, err := soleKind(contract.Type)
	if err != nil {
		return err
	}
	for index, member := range assignment.Many {
		// ordinal은 0부터 연속 증가해야 한다. 중복과 간격을 한 규칙으로 실패 닫기한다.
		if member.Ordinal != index {
			return ErrAssignmentDuplicateOrdinal
		}
		kind, ok := member.Value.Kind()
		if !ok {
			return ErrAssignmentValueTypeMismatch
		}
		if contract.Type == PropertyTypeSelect {
			if kind != PropertyValueKindOptionRef {
				return ErrAssignmentValueTypeMismatch
			}
			if _, active := contract.ActiveOptions[*member.Value.OptionID]; !active {
				return ErrAssignmentInactiveOption
			}
			continue
		}
		if kind != expectedKind {
			return ErrAssignmentValueTypeMismatch
		}
		if err := validateScalarContent(kind, member.Value); err != nil {
			return err
		}
	}
	if contract.Type != PropertyTypeSelect {
		return nil
	}
	seenOptions := make(map[PropertyOptionID]struct{}, len(assignment.Many))
	for _, member := range assignment.Many {
		if _, duplicate := seenOptions[*member.Value.OptionID]; duplicate {
			return ErrAssignmentDuplicateOption
		}
		seenOptions[*member.Value.OptionID] = struct{}{}
	}
	return nil
}

// soleKind는 정의 유형이 운반하는 단일 값 종류를 돌려준다. canonical 유형의
// 허용 종류는 항상 하나다.
func soleKind(valueType PropertyType) (PropertyValueKind, error) {
	kinds, err := propertyTypeValueKinds(valueType)
	if err != nil {
		return "", err
	}
	return kinds[0], nil
}

// hasObservationFields는 권위 assignment가 관측 필드를 carry하지 않음을 실행
// 시점에 증명하는 구조 보증이다. ResolvedObservation은 ResolvedPropertyValue에만
// 존재한다.
func (assignment EntryPropertyAssignment) hasObservationFields() bool {
	return false
}
