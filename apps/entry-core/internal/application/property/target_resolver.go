package property

import (
	"context"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// TargetClassification은 assignment 대상 identity가 어떻게 유도되었는지
// 구분하는 분류이다. 현 슬라이스는 local_path가 만든 locator 유도 대상만
// 생성하며, 이후 Core-native target 전환에서 구분·migration하는 데 쓰인다.
type TargetClassification string

// TargetClassificationLocatorDerived는 상대 경로 locator에서 유도된
// transitional 대상 분류이다. rename/move 연속성을 보장하지 않는다.
const TargetClassificationLocatorDerived TargetClassification = "locator_derived"

func (classification TargetClassification) valid() bool {
	switch classification {
	case TargetClassificationLocatorDerived:
		return true
	default:
		return false
	}
}

// ResolvedTarget은 local_path 해석이 확정한 assignment 대상이다. 원시 경로는
// 포함하지 않으며 locator 유도 EntryRef와 분류만 운반한다.
type ResolvedTarget struct {
	EntryRef       domainentry.EntryRef
	Classification TargetClassification
}

// Validate는 대상 불변식을 강제한다. 유효한 canonical EntryRef와 알려진
// 분류가 함께 있어야 한다.
func (target ResolvedTarget) Validate() error {
	if target.EntryRef.Validate() != nil || !target.Classification.valid() {
		return ErrInvalidResolvedTarget
	}
	return nil
}

// LocalPathResolver는 clean 절대 UTF-8 로컬 경로 하나를 canonical 대상으로
// 해석하는 Core-owned 계약이다. 상대·비정규·NUL 포함·4096바이트 초과·미존재·
// 접근 불가 경로는 source 계약의 typed error로 거절된다.
type LocalPathResolver interface {
	ResolveLocalPath(ctx context.Context, localPath string) (ResolvedTarget, error)
}
