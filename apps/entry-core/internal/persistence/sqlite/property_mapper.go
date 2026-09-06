package sqlite

import (
	"errors"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// VOY-765 property 저장소의 explicit row<->domain 매핑 센티널이다. catalog
// 매핑 관례와 같이 메타데이터 전용이며 행 payload는 오류 메시지에 들어가지
// 않는다.
var (
	// ErrInvalidPropertyRow는 물리 제약을 우회해 들어온 corrupt row를 read 시점에
	// 실패 닫기하는 센티널이다.
	ErrInvalidPropertyRow = errors.New("invalid property persistence row")
	// ErrEntryPropertyOrphanRef는 header가 active 정의를 가리키지 않거나 값 행이
	// header 없이 존재할 때 스냅샷 일관성을 지키기 위해 실패 닫기하는 센티널이다.
	ErrEntryPropertyOrphanRef = errors.New("entry property orphan reference")
	// ErrEntryPropertyWorkspaceMismatch는 fact의 워크스페이스가 호출 범위와 다를
	// 때 거절하는 cross-workspace 실패 닫기 센티널이다.
	ErrEntryPropertyWorkspaceMismatch = errors.New("entry property workspace mismatch")
	// ErrEntryPropertyDefinitionMissing은 쓰기 대상 정의가 없거나 tombstoned일 때
	// 거절하는 센티널이다.
	ErrEntryPropertyDefinitionMissing = errors.New("entry property definition missing")
	// ErrDuplicateAssignmentRef는 한 번의 쓰기 호출에 같은 (entry, property) 참조가
	// 중복될 때 거절하는 센티널이다.
	ErrDuplicateAssignmentRef = errors.New("duplicate entry property assignment ref")
)

// assignmentStateForRow는 state 컬럼 값을 domain 상태로 변환한다. 인식 불가
// 값은 실패 닫기한다.
func assignmentStateForRow(raw string) (domainentry.AssignmentState, error) {
	switch raw {
	case string(domainentry.AssignmentStateUnset):
		return domainentry.AssignmentStateUnset, nil
	case string(domainentry.AssignmentStateNull):
		return domainentry.AssignmentStateNull, nil
	case string(domainentry.AssignmentStateValue):
		return domainentry.AssignmentStateValue, nil
	default:
		return "", ErrInvalidPropertyRow
	}
}

// assignmentTargetKindForRow는 target_kind 컬럼 값을 domain 분류로 변환한다.
func assignmentTargetKindForRow(raw string) (domainentry.AssignmentTargetKind, error) {
	switch raw {
	case string(domainentry.AssignmentTargetCoreNative):
		return domainentry.AssignmentTargetCoreNative, nil
	case string(domainentry.AssignmentTargetLocatorDerived):
		return domainentry.AssignmentTargetLocatorDerived, nil
	default:
		return "", ErrInvalidPropertyRow
	}
}

// fillAssignmentValueColumns는 AssignmentValue의 설정된 멤버 하나를 row의 typed
// payload 컬럼에 옮긴다. 멤버가 정확히 하나가 아니면 도메인 위반이므로 실패한다.
func fillAssignmentValueColumns(row *EntryPropertyAssignmentValueRow, value domainentry.AssignmentValue) error {
	kind, ok := value.Kind()
	if !ok {
		return ErrInvalidPropertyRow
	}
	row.ValueKind = string(kind)
	switch kind {
	case domainentry.PropertyValueKindBoolean:
		row.BooleanValue = value.Boolean
	case domainentry.PropertyValueKindDecimal:
		row.DecimalValue = value.Decimal
	case domainentry.PropertyValueKindDate:
		row.DateValue = value.Date
	case domainentry.PropertyValueKindTimestamp:
		row.TimestampValue = value.Timestamp
	case domainentry.PropertyValueKindText:
		row.TextValue = value.Text
	case domainentry.PropertyValueKindOptionRef:
		row.OptionID = value.OptionID.Bytes()
	default:
		return ErrInvalidPropertyRow
	}
	return nil
}

// assignmentValueFromRow는 값 행을 domain AssignmentValue로 재구성한다.
// 설정된 payload가 정확히 하나여야 하고 그 종류가 value_kind 판별 컬럼과
// 일치해야 한다(XOR CHECK의 Go 경계 재검증).
func assignmentValueFromRow(row EntryPropertyAssignmentValueRow) (domainentry.AssignmentValue, error) {
	value := domainentry.AssignmentValue{}
	set := 0
	var kind domainentry.PropertyValueKind
	if row.BooleanValue != nil {
		set++
		kind = domainentry.PropertyValueKindBoolean
		value.Boolean = row.BooleanValue
	}
	if row.DecimalValue != nil {
		set++
		kind = domainentry.PropertyValueKindDecimal
		value.Decimal = row.DecimalValue
	}
	if row.DateValue != nil {
		set++
		kind = domainentry.PropertyValueKindDate
		value.Date = row.DateValue
	}
	if row.TimestampValue != nil {
		set++
		kind = domainentry.PropertyValueKindTimestamp
		value.Timestamp = row.TimestampValue
	}
	if row.TextValue != nil {
		set++
		kind = domainentry.PropertyValueKindText
		value.Text = row.TextValue
	}
	if row.OptionID != nil {
		if len(row.OptionID) != len(domainentry.PropertyOptionID{}) {
			return domainentry.AssignmentValue{}, ErrInvalidPropertyRow
		}
		optionID := domainentry.PropertyOptionID{}
		copy(optionID[:], row.OptionID)
		set++
		kind = domainentry.PropertyValueKindOptionRef
		value.OptionID = &optionID
	}
	if set != 1 || string(kind) != row.ValueKind {
		return domainentry.AssignmentValue{}, ErrInvalidPropertyRow
	}
	return value, nil
}

// assignmentContractFor는 정의 행과 그 선택지 행으로 domain 검증 계약을 만든다.
// writeTime=true는 새로운 쓰기 규칙(active 옵션만 참조 가능)을 적용하고,
// false는 read-back 보존 규칙(비활성 옵션 참조도 보존)을 적용한다.
func assignmentContractFor(
	def WorkspacePropertyDefinitionRow,
	options []WorkspacePropertyOptionRow,
	writeTime bool,
) (domainentry.AssignmentContract, error) {
	propertyID, err := parsePropertyIDBlob(def.PropertyID)
	if err != nil {
		return domainentry.AssignmentContract{}, err
	}
	contract := domainentry.AssignmentContract{
		Type:        domainentry.PropertyType(def.ValueType),
		Cardinality: domainentry.PropertyCardinality(def.Cardinality),
		Nullable:    def.Nullable,
	}
	if contract.Type != domainentry.PropertyTypeSelect {
		return contract, nil
	}
	contract.ActiveOptions = make(map[domainentry.PropertyOptionID]struct{}, len(options))
	for _, option := range options {
		optionOwner, err := parsePropertyIDBlob(option.PropertyID)
		if err != nil || optionOwner != propertyID {
			continue
		}
		if writeTime && !option.Active {
			continue
		}
		optionID, err := parsePropertyIDBlob(option.OptionID)
		if err != nil {
			return domainentry.AssignmentContract{}, err
		}
		contract.ActiveOptions[domainentry.PropertyOptionID(optionID)] = struct{}{}
	}
	return contract, nil
}
