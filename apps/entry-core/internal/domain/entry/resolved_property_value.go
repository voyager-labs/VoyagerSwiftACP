package entry

import (
	"errors"
	"time"
)

var ErrInvalidResolvedObservation = errors.New("invalid resolved observation")

// ResolvedProducer는 resolved projection의 값 생산자다.
type ResolvedProducer string

const (
	ResolvedProducerLocal  ResolvedProducer = "local"
	ResolvedProducerSource ResolvedProducer = "source"
)

// ResolvedObservationState는 소스 관측 상태다. source unknown/error/not_applicable은
// 로컬 사용자 assignment 사실이 아니라 read projection에만 남는다.
type ResolvedObservationState string

const (
	ResolvedObservationOK            ResolvedObservationState = "ok"
	ResolvedObservationUnknown       ResolvedObservationState = "unknown"
	ResolvedObservationError         ResolvedObservationState = "error"
	ResolvedObservationNotApplicable ResolvedObservationState = "not_applicable"
)

func (state ResolvedObservationState) valid() bool {
	switch state {
	case ResolvedObservationOK, ResolvedObservationUnknown, ResolvedObservationError, ResolvedObservationNotApplicable:
		return true
	default:
		return false
	}
}

// ResolvedObservation은 provider 관측 메타데이터 봉투다. 권위 assignment 사실
// 밖에서만 존재하며 freshness/가용성의 유일한 자리다.
type ResolvedObservation struct {
	Producer   ResolvedProducer
	State      ResolvedObservationState
	ObservedAt time.Time
}

func (observation ResolvedObservation) Validate() error {
	switch observation.Producer {
	case ResolvedProducerLocal, ResolvedProducerSource:
	default:
		return ErrInvalidResolvedObservation
	}
	if !observation.State.valid() {
		return ErrInvalidResolvedObservation
	}
	if observation.ObservedAt.IsZero() || !validTimestamp(observation.ObservedAt) {
		return ErrInvalidResolvedObservation
	}
	return nil
}

// ResolvedPropertyValue는 정의와 로컬/소스 생산자를 해석한 읽기 전용 projection이다.
// Type, cardinality, editability는 정의에서 합성되고 State/revision/payload는
// assignment 권위 사실이며, Observation은 권위 밖 관측 봉투다.
type ResolvedPropertyValue struct {
	WorkspaceID WorkspaceID
	EntryID     string
	PropertyID  PropertyID

	Type        PropertyType
	Cardinality PropertyCardinality
	Editable    bool

	State          AssignmentState
	RecordRevision RecordRevision

	Scalar *AssignmentValue
	Many   []OrderedAssignmentValue

	Observation *ResolvedObservation
}

// Resolve는 assignment 권위 사실을 정의 계약과 합성해 read projection을 만든다.
// Provider 관측은 여기서만 받는다 — 권위 사실에는 절대 저장되지 않는다.
func (assignment EntryPropertyAssignment) Resolve(contract AssignmentContract, editable bool, observation *ResolvedObservation) (ResolvedPropertyValue, error) {
	if err := assignment.Validate(contract); err != nil {
		return ResolvedPropertyValue{}, err
	}
	resolved := ResolvedPropertyValue{
		WorkspaceID:    assignment.WorkspaceID,
		EntryID:        assignment.EntryID,
		PropertyID:     assignment.PropertyID,
		Type:           contract.Type,
		Cardinality:    contract.Cardinality,
		Editable:       editable,
		State:          assignment.State,
		RecordRevision: assignment.RecordRevision,
		Scalar:         cloneAssignmentValue(assignment.Scalar),
		Many:           cloneOrderedAssignmentValues(assignment.Many),
	}
	if observation != nil {
		if err := observation.Validate(); err != nil {
			return ResolvedPropertyValue{}, err
		}
		validated := *observation
		resolved.Observation = &validated
	}
	return resolved, nil
}
