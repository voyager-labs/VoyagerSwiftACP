package property

import (
	"context"
	"errors"
	"unicode/utf8"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// property.change 유스케이스의 실패 닫기 센티널이다. 모든 거절은 저장소 상태를
// 바꾸지 않는다.
var (
	// ErrInvalidChangeService는 nil 의존성으로 서비스를 만들려는 시도를 거절한다.
	ErrInvalidChangeService = errors.New("invalid property change service")
	// ErrInvalidChangeRequest는 대상 수·원하는 상태·스칼라 바이트 예산 등 신뢰
	// 경계 입력 규칙 위반을 거절한다.
	ErrInvalidChangeRequest = errors.New("invalid property change request")
	// ErrDuplicateChangeTarget은 한 번의 변경에 같은 (entry, property) 참조가
	// 반복될 때 거절한다.
	ErrDuplicateChangeTarget = errors.New("duplicate property change target")
	// ErrStaleAssignmentRevision은 예상 assignment revision이 현재와 다를 때
	// 거절하는 CAS 센티널이다. set→clear ABA도 이 검사가 잡는다.
	ErrStaleAssignmentRevision = errors.New("stale property assignment revision")
	// ErrDefinitionNotEditable은 편집 불가 정의에 대한 값 지정을 거절한다.
	ErrDefinitionNotEditable = errors.New("property definition not editable")
	// ErrRegistryOwnedDefinition은 System Registry 시드(registry_derived) 정의에
	// 대한 사용자 mutation을 거절한다. 시드 digest나 lifecycle을 바꾸면 다음 시작의
	// ApplyCatalogSeed/assembleSnapshot이 실패해 daemon이 기동 전에 종료된다.
	ErrRegistryOwnedDefinition = errors.New("property definition is registry owned")
	// ErrScopeTooLarge는 정준 응답 인코딩이 wire 봉투를 초과해 commit 전에
	// 거절될 때 반환된다. execute의 read-back과 definition.create의 생성 결과
	// 예상 검사가 이 센티널을 공유한다. runtime dispatch가 protocol
	// scope_too_large로 매핑한다.
	ErrScopeTooLarge = errors.New("property change response exceeds wire budget")
	// ErrCanonicalReadBackIncomplete은 커밋 직전 재조회에서 대상 fact가 사라진
	// 저장소 계약 위반을 거절한다.
	ErrCanonicalReadBackIncomplete = errors.New("property change canonical read-back incomplete")
)

// maximumEchoIDBytes는 protocol validEchoID와 같은 요청 ID 상한이다.
const maximumEchoIDBytes = 128

// DesiredAssignment는 목표 상태다. value에서 Scalar와 Many는 정확히 하나만
// 설정하며 Many는 nil과 빈 슬라이스가 구별된다(빈 many = 멤버 없는 value).
type DesiredAssignment struct {
	State  domainentry.AssignmentState
	Scalar *domainentry.AssignmentValue
	Many   []domainentry.AssignmentValue
}

// ChangeTarget은 단일 변경 대상 요청이다. ExpectedAssignmentRevision 0은 implicit
// unset@0을 의미하고 첫 쓰기는 revision 1이 된다.
type ChangeTarget struct {
	LocalPath                  string
	PropertyID                 domainentry.PropertyID
	ExpectedDefinitionRevision int
	ExpectedAssignmentRevision uint64
	Desired                    DesiredAssignment
}

// PreparedChange는 prepare가 계산한 비내구 변경안이다. Before가 nil이면 implicit
// unset이고 After에는 적용 시 사용될 다음 revision이 담긴다.
type PreparedChange struct {
	EntryID    string
	PropertyID domainentry.PropertyID
	Before     *domainentry.EntryPropertyAssignment
	After      domainentry.EntryPropertyAssignment
}

// Proposal은 저장되지 않는 변경 제안이다.
type Proposal struct {
	Changes              []PreparedChange
	RequiresConfirmation bool
}

// ChangeService는 bounded assignment list와 prepare/execute 원자적 변경을
// 소유한다. execute는 정확히 하나의 top-level TransactionRunner.WithinTx 안에서
// CAS 재검증 → 응답 예산 사전 검사 → 일괄 적용 → 정준 read-back → 재검사 순서로
// 수행한다.
type ChangeService struct {
	catalog CatalogRepository
	facts   AssignmentFactRepository
	targets LocalPathResolver
	runner  TransactionRunner
}

// NewChangeService는 저장소·대상 해석기·트랜잭션 경계를 주입받아 서비스를 만든다.
func NewChangeService(
	catalog CatalogRepository,
	facts AssignmentFactRepository,
	targets LocalPathResolver,
	runner TransactionRunner,
) (*ChangeService, error) {
	if catalog == nil || facts == nil || targets == nil || runner == nil {
		return nil, ErrInvalidChangeService
	}
	return &ChangeService{catalog: catalog, facts: facts, targets: targets, runner: runner}, nil
}

// Prepare는 모든 대상을 해석하고 정의·선택지·현재 revision을 batched 읽기로
// 로드한 뒤 유형·개수·상태·선택지 검증을 통과한 비내구 제안을 돌려준다. 어떤
// 대상도 기록하지 않는다.
func (service *ChangeService) Prepare(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	changes []ChangeTarget,
) (Proposal, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return Proposal{}, err
	}
	resolved, err := resolveChangeTargets(service.targets, ctx, changes)
	if err != nil {
		return Proposal{}, err
	}
	snapshot, err := service.loadContracts(ctx, workspace, changePropertyIDs(resolved))
	if err != nil {
		return Proposal{}, err
	}
	current, err := service.facts.LoadAssignmentsByRefs(ctx, workspace, changeRefs(resolved))
	if err != nil {
		return Proposal{}, err
	}
	snapshot.current = indexFacts(current)
	staged, err := stageChanges(workspace, resolved, snapshot)
	if err != nil {
		return Proposal{}, err
	}
	return Proposal{
		Changes:              preparedChanges(staged),
		RequiresConfirmation: anyDurableBefore(staged),
	}, nil
}

// Execute는 신뢰 경계 검증 전체를 반복하고, 하나의 WithinTx 안에서 정의와 각
// assignment revision을 재조회·비교한 뒤 모든 대상을 적용하고 정준 persisted
// read-back을 재조회한다. 응답 인코딩이 65,536바이트를 넘으면 commit 전에
// 실패한다.
func (service *ChangeService) Execute(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	requestID string,
	changes []ChangeTarget,
) ([]domainentry.EntryPropertyAssignment, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return nil, err
	}
	if !utf8.ValidString(requestID) || len(requestID) == 0 || len(requestID) > maximumEchoIDBytes {
		return nil, ErrInvalidChangeRequest
	}
	resolved, err := resolveChangeTargets(service.targets, ctx, changes)
	if err != nil {
		return nil, err
	}
	propertyIDs := changePropertyIDs(resolved)

	var readBack []domainentry.EntryPropertyAssignment
	err = service.runner.WithinTx(ctx, func(txCtx context.Context) error {
		snapshot, err := service.loadContracts(txCtx, workspace, propertyIDs)
		if err != nil {
			return err
		}
		current, err := service.facts.LoadAssignmentsByRefs(txCtx, workspace, changeRefs(resolved))
		if err != nil {
			return err
		}
		snapshot.current = indexFacts(current)
		staged, err := stageChanges(workspace, resolved, snapshot)
		if err != nil {
			return err
		}
		if _, ok := encodedExecuteResponseBytes(requestID, projectedReadBack(staged, snapshot.definitions)); !ok {
			return ErrScopeTooLarge
		}
		if err := service.facts.SaveAssignments(txCtx, workspace, stagedFacts(staged)); err != nil {
			return err
		}
		reread, err := service.facts.LoadAssignmentsByRefs(txCtx, workspace, changeRefs(resolved))
		if err != nil {
			return err
		}
		rows, factsInOrder, err := canonicalReadBack(staged, indexFacts(reread), snapshot.definitions)
		if err != nil {
			return err
		}
		if _, ok := encodedExecuteResponseBytes(requestID, rows); !ok {
			return ErrScopeTooLarge
		}
		readBack = factsInOrder
		return nil
	})
	if err != nil {
		return nil, err
	}
	return readBack, nil
}

// ListAssignments는 한 대상의 assignment fact를 bounded로 읽어 PropertyID
// 오름차순으로 돌려준다.
func (service *ChangeService) ListAssignments(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	localPath string,
	propertyIDs []domainentry.PropertyID,
) ([]domainentry.EntryPropertyAssignment, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return nil, err
	}
	if len(propertyIDs) > maximumChangeTargets {
		return nil, ErrInvalidChangeRequest
	}
	target, err := service.targets.ResolveLocalPath(ctx, localPath)
	if err != nil {
		return nil, err
	}
	facts, err := service.facts.LoadAssignments(ctx, workspace, []string{target.EntryRef.EntryID}, propertyIDs)
	if err != nil {
		return nil, err
	}
	sortFactsByProperty(facts)
	return facts, nil
}
