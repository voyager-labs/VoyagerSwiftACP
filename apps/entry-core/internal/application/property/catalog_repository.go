package property

import (
	"context"
	"errors"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// 정의·선택지 명령 서비스의 실패 닫기 센티널이다. 모든 거절은 저장소 상태를
// 바꾸지 않으며 물리 삭제 경로는 계약상 존재하지 않는다.
var (
	// ErrInvalidCatalogService는 nil 의존성으로 서비스를 만들려는 시도를 거절한다.
	ErrInvalidCatalogService = errors.New("invalid property catalog service")
	// ErrDefinitionNotFound는 요청한 정의가 이 워크스페이스에 없을 때 거절한다.
	ErrDefinitionNotFound = errors.New("property definition not found")
	// ErrDuplicateDefinitionKey는 활성·비활성 무관하게 같은 (namespace, key)가
	// 이미 존재할 때 거절한다. 물리 유일 인덱스가 tombstoned 행도 보유하므로
	// 재사용은 불가능하다.
	ErrDuplicateDefinitionKey = errors.New("duplicate property definition key")
	// ErrStaleDefinitionRevision은 예상 revision이 현재와 다를 때 거절하는 CAS
	// 센티널이다.
	ErrStaleDefinitionRevision = errors.New("stale property definition revision")
	// ErrDefinitionInactive는 비활성(tombstoned) 정의를 대상으로 한 mutation을
	// 거절한다. 재활성화 경로는 존재하지 않는다.
	ErrDefinitionInactive = errors.New("property definition inactive")
	// ErrImmutableDefinitionField는 생성 후 변경 불가인 필드의 변경 시도를
	// 거절한다.
	ErrImmutableDefinitionField = errors.New("immutable property definition field")
	// ErrDefinitionNotSelectable은 select가 아닌 정의에 선택지 조작을 시도할 때
	// 거절한다.
	ErrDefinitionNotSelectable = errors.New("property definition is not select typed")
	// ErrOptionNotFound는 요청한 선택지가 없을 때 거절한다.
	ErrOptionNotFound = errors.New("property option not found")
	// ErrOptionInactive는 비활성 선택지를 대상으로 한 mutation을 거절한다.
	ErrOptionInactive = errors.New("property option inactive")
	// ErrInvalidOptionOwner은 선택지가 다른 정의에 속할 때 거절한다.
	ErrInvalidOptionOwner = errors.New("property option owner mismatch")
	// ErrInvalidOptionOrder은 reorder 입력이 활성 선택지의 정확한 순열이 아닐 때
	// 거절한다.
	ErrInvalidOptionOrder = errors.New("invalid property option order")
	// ErrDuplicateOptionID는 같은 정의에 동일 option id가 반복될 때 거절한다.
	ErrDuplicateOptionID = errors.New("duplicate property option id")
)

// DefinitionView는 정의 하나와 그 선택지 전체(비활성 포함)의 읽기 모델이다.
// 과거 assignment 해석을 위해 비활성 행도 잃지 않고 운반하며, 필터링은
// 호출자가 IsActive 등으로 명시적으로 수행한다.
type DefinitionView struct {
	Definition domainentry.WorkspacePropertyDefinition
	Options    []domainentry.PropertyOption
}

// IsActive는 정의가 새 값 지정에 사용될 수 있는 상태인지 보고한다.
func (view DefinitionView) IsActive() bool {
	return view.Definition.Lifecycle == domainentry.PropertyLifecycleActive
}

// CatalogRepository는 정의·선택지 카탈로그의 읽기와 쓰기를 소유하는 저장소
// 계약이다. delete 메서드가 의도적으로 없어 서비스 계층은 행을 물리 삭제할 수
// 없다. 모든 메서드는 데몬이 주입한 WorkspaceContext를 요구하며, mutation
// 메서드는 TransactionRunner.WithinTx 안에서만 호출된다(tx 구현은 ctx에서
// 트랜잭션을 해석한다). Options와 Option 읽기는 비활성 행도 포함하고 ordinal
// 오름차순으로 돌려준다.
type CatalogRepository interface {
	Definition(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID) (domainentry.WorkspacePropertyDefinition, error)
	Definitions(ctx context.Context, workspace domainentry.WorkspaceContext) ([]domainentry.WorkspacePropertyDefinition, error)
	Option(ctx context.Context, workspace domainentry.WorkspaceContext, optionID domainentry.PropertyOptionID) (domainentry.PropertyOption, error)
	Options(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID) ([]domainentry.PropertyOption, error)
	PutDefinition(ctx context.Context, definition domainentry.WorkspacePropertyDefinition) error
	SaveDefinition(ctx context.Context, definition domainentry.WorkspacePropertyDefinition) error
	PutOption(ctx context.Context, option domainentry.PropertyOption) error
	SaveOptions(ctx context.Context, options []domainentry.PropertyOption) error
}
