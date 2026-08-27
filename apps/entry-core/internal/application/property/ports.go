// Package property는 Property 정의·할당 유스케이스와 Core-owned target
// resolution의 application 경계를 소유한다. 이 패키지는 SQLite/GORM을 import하지
// 않으며 모든 저장소 호출은 데몬이 주입한 WorkspaceContext를 요구한다.
package property

import (
	"context"
	"errors"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

var (
	// ErrWorkspaceRequired는 데몬이 주입한 workspace 식별 없이 저장소를 호출한
	// 요청을 거절하는 실패 닫기 센티널이다.
	ErrWorkspaceRequired = errors.New("workspace context required")
	// ErrInvalidResolvedTarget은 해석된 대상이 계약 불변식을 만족하지 않을 때
	// 거절하는 센티널이다.
	ErrInvalidResolvedTarget = errors.New("invalid resolved target")
)

// ValidateWorkspaceContext는 영 workspace 식별을 거절하고 데몬이 주입한 typed
// UUIDv7 identity만 허용한다. 모든 저장소 구현의 첫 검사로 사용한다.
func ValidateWorkspaceContext(workspace domainentry.WorkspaceContext) error {
	if workspace.ID == (domainentry.WorkspaceID{}) {
		return ErrWorkspaceRequired
	}
	return nil
}

// DefinitionRepository는 워크스페이스 범위의 Property 정의 읽기 계약이다.
// 비활성 정의도 과거 할당 해석을 위해 읽힌다.
type DefinitionRepository interface {
	ListDefinitions(ctx context.Context, workspace domainentry.WorkspaceContext) ([]domainentry.PropertyDefinition, error)
	Definition(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID) (domainentry.PropertyDefinition, error)
}

// AssignmentRepository는 (workspace, entry, property) 키의 local authoritative
// assignment fact에 대한 좁은 읽기 계약이다. 행이 없으면 implicit unset 상태로
// revision 0과 false를 반환한다.
type AssignmentRepository interface {
	AssignmentRevision(ctx context.Context, workspace domainentry.WorkspaceContext, entryID string, propertyID domainentry.PropertyID) (uint64, bool, error)
}

// AssignmentFactRepository는 정준 assignment fact의 batched 읽기와 tx 안 일괄
// 쓰기 계약이다. LoadAssignments는 요청한 참조 중 행이 없는 것을 결과에서
// 제외한다(implicit unset). SaveAssignments는 TransactionRunner.WithinTx 안에서만
// 호출되며 부분 집합이 아닌 전체 배치를 한 번에 받는다.
type AssignmentFactRepository interface {
	LoadAssignments(ctx context.Context, workspace domainentry.WorkspaceContext, entryIDs []string, propertyIDs []domainentry.PropertyID) ([]domainentry.EntryPropertyAssignment, error)
	// LoadAssignmentsPage는 assignment.list의 저장소 단계 페이징이다. page_size
	// 적용 전 전체 header/value/정의 적재를 차단한다.
	LoadAssignmentsPage(ctx context.Context, workspace domainentry.WorkspaceContext, entryID string, requestedIDs []domainentry.PropertyID, after *domainentry.PropertyID, limit int) ([]domainentry.EntryPropertyAssignment, *domainentry.PropertyID, bool, error)
	LoadAssignmentsByRefs(ctx context.Context, workspace domainentry.WorkspaceContext, refs []AssignmentRef) ([]domainentry.EntryPropertyAssignment, error)
	SaveAssignments(ctx context.Context, workspace domainentry.WorkspaceContext, facts []domainentry.EntryPropertyAssignment) error
}

// AssignmentRef는 change 경로 exact-pair 읽기의 요청 키다. entry IN × property
// IN 교차가 아니라 이 쌍들만 저장소가 읽는다.
type AssignmentRef struct {
	EntryID    string
	PropertyID domainentry.PropertyID
}

// TransactionRunner는 하나의 원자적 mutation boundary를 제공한다. 구현은
// tx-scoped 저장소를 ctx에 붙여 fn에 전달하며 application 계약은 DB 핸들을
// 노출하지 않는다.
type TransactionRunner interface {
	WithinTx(ctx context.Context, fn func(ctx context.Context) error) error
}

// PropertyOverlayReader는 Entry 읽기에 끼워 넣는 batched Property overlay
// port다. Entry별 N+1 조회를 피하기 위해 EntryID 집합당 한 번 로드한다.
type PropertyOverlayReader interface {
	LoadOverlay(ctx context.Context, workspace domainentry.WorkspaceContext, entryIDs []string, propertyIDs []domainentry.PropertyID) (map[string][]domainentry.PropertyValue, error)
}
