package property

import (
	"context"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// 변경 신뢰 경계 상한이다. protocol wire 캡과 같은 값이며 application도 호출자를
// 신뢰하지 않고 재검증한다.
const (
	maximumChangeTargets     = 256
	maximumChangeManyMembers = 256
	maximumChangeScalarBytes = 4096
)

// assignmentRef는 (entry, property) 참조의 내부 키다.
type assignmentRef struct {
	entryID    string
	propertyID domainentry.PropertyID
}

// resolvedChange는 해석·검증·stage를 통과한 단일 변경이다.
type resolvedChange struct {
	input      ChangeTarget
	entryID    string
	targetKind domainentry.AssignmentTargetKind
	before     *domainentry.EntryPropertyAssignment
	after      domainentry.EntryPropertyAssignment
}

// validateChangeRequest는 저장소 접근 전 신뢰 경계 규칙을 강제한다. 대상 수,
// identity, 원하는 상태 변형, 스칼라 바이트 예산, many 멤버 상한이 여기서
// 거절된다.
func validateChangeRequest(changes []ChangeTarget) error {
	if len(changes) == 0 || len(changes) > maximumChangeTargets {
		return ErrInvalidChangeRequest
	}
	for _, change := range changes {
		if change.PropertyID == (domainentry.PropertyID{}) || change.LocalPath == "" || change.ExpectedDefinitionRevision < 0 {
			return ErrInvalidChangeRequest
		}
		switch change.Desired.State {
		case domainentry.AssignmentStateUnset, domainentry.AssignmentStateNull:
			if change.Desired.Scalar != nil || change.Desired.Many != nil {
				return ErrInvalidChangeRequest
			}
		case domainentry.AssignmentStateValue:
			if (change.Desired.Scalar == nil) == (change.Desired.Many == nil) {
				return ErrInvalidChangeRequest
			}
		default:
			return ErrInvalidChangeRequest
		}
		if change.Desired.Scalar != nil && scalarExceedsBudget(*change.Desired.Scalar) {
			return ErrInvalidChangeRequest
		}
		if len(change.Desired.Many) > maximumChangeManyMembers {
			return ErrInvalidChangeRequest
		}
	}
	return nil
}

// scalarExceedsBudget은 스칼라 문자열 멤버가 와이어 스칼라 예산을 넘는지 보고한다.
func scalarExceedsBudget(value domainentry.AssignmentValue) bool {
	for _, member := range []*string{value.Text, value.Decimal, value.Date, value.Timestamp} {
		if member != nil && len(*member) > maximumChangeScalarBytes {
			return true
		}
	}
	return false
}

// resolveChangeTargets는 모든 local path를 Core-owned 해석기로 대상화하고 중복
// (entry, property) 참조를 거절한다. execute에서는 호출자가 전달한 stable
// EntryID와 현재 해석 결과도 비교한다. 해석은 트랜잭션 밖에서 수행된다.
func resolveChangeTargets(resolver LocalPathResolver, ctx context.Context, changes []ChangeTarget, requireStableIdentity bool) ([]resolvedChange, error) {
	if err := validateChangeRequest(changes); err != nil {
		return nil, err
	}
	resolved := make([]resolvedChange, 0, len(changes))
	seen := make(map[assignmentRef]struct{}, len(changes))
	for _, input := range changes {
		if requireStableIdentity && input.EntryID == "" {
			return nil, ErrInvalidChangeRequest
		}
		target, err := resolver.ResolveLocalPath(ctx, input.LocalPath)
		if err != nil {
			return nil, err
		}
		if err := target.Validate(); err != nil {
			return nil, err
		}
		if input.EntryID != "" && input.EntryID != target.EntryRef.EntryID {
			return nil, ErrStaleTargetIdentity
		}
		ref := assignmentRef{entryID: target.EntryRef.EntryID, propertyID: input.PropertyID}
		if _, duplicate := seen[ref]; duplicate {
			return nil, ErrDuplicateChangeTarget
		}
		seen[ref] = struct{}{}
		resolved = append(resolved, resolvedChange{
			input:      input,
			entryID:    target.EntryRef.EntryID,
			targetKind: classificationToTargetKind(target.Classification),
		})
	}
	return resolved, nil
}

// classificationToTargetKind는 해석 분류를 durable target kind로 사상한다. 현재
// 유효 분류는 locator_derived뿐이다.
func classificationToTargetKind(classification TargetClassification) domainentry.AssignmentTargetKind {
	switch classification {
	case TargetClassificationLocatorDerived:
		return domainentry.AssignmentTargetLocatorDerived
	default:
		return domainentry.AssignmentTargetCoreNative
	}
}
