package entry

// AssignmentValue는 정확히 하나의 멤버만 설정되는 판별 가능한 스칼라 값이다.
// 포인터 멤버는 false/영값도 유효한 값으로 다루기 위한 존재 표시다.
type AssignmentValue struct {
	Boolean   *bool
	Decimal   *string
	Date      *string
	Timestamp *string
	Text      *string
	OptionID  *PropertyOptionID
}

// Kind는 설정된 멤버로 값 종류를 판별한다. 멤버가 정확히 하나가 아니면 실패한다.
func (value AssignmentValue) Kind() (PropertyValueKind, bool) {
	set := 0
	var kind PropertyValueKind
	if value.Boolean != nil {
		set++
		kind = PropertyValueKindBoolean
	}
	if value.Decimal != nil {
		set++
		kind = PropertyValueKindDecimal
	}
	if value.Date != nil {
		set++
		kind = PropertyValueKindDate
	}
	if value.Timestamp != nil {
		set++
		kind = PropertyValueKindTimestamp
	}
	if value.Text != nil {
		set++
		kind = PropertyValueKindText
	}
	if value.OptionID != nil {
		set++
		kind = PropertyValueKindOptionRef
	}
	if set != 1 {
		return "", false
	}
	return kind, true
}

func (value AssignmentValue) ValidateContent() error {
	kind, ok := value.Kind()
	if !ok {
		return ErrAssignmentValueTypeMismatch
	}
	return validateScalarContent(kind, value)
}

func cloneAssignmentValue(value *AssignmentValue) *AssignmentValue {
	if value == nil {
		return nil
	}
	cloned := *value
	cloned.Decimal = cloneString(value.Decimal)
	cloned.Date = cloneString(value.Date)
	cloned.Timestamp = cloneString(value.Timestamp)
	cloned.Text = cloneString(value.Text)
	if value.Boolean != nil {
		copied := *value.Boolean
		cloned.Boolean = &copied
	}
	if value.OptionID != nil {
		copied := *value.OptionID
		cloned.OptionID = &copied
	}
	return &cloned
}

func cloneOrderedAssignmentValues(values []OrderedAssignmentValue) []OrderedAssignmentValue {
	if values == nil {
		return nil
	}
	cloned := make([]OrderedAssignmentValue, len(values))
	for index, member := range values {
		cloned[index] = OrderedAssignmentValue{Ordinal: member.Ordinal, Value: *cloneAssignmentValue(&member.Value)}
	}
	return cloned
}
