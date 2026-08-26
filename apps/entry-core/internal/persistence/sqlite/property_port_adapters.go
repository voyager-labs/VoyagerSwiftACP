package sqlite

import (
	"context"
	"sort"

	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// 이 파일은 todo 10 데몬 조합에 필요한 나머지 두 application property 포트
// (AssignmentFactRepository, TransactionRunner)의 SQLite 구현이다. 둘 다 기존
// EntryPropertyRepository와 Store.WithinTx·WithTxScope만 재사용하는 얇은
// adapter다.

// EntryPropertyFactStore는 applicationproperty.AssignmentFactRepository 포트의
// SQLite 구현이다. batched 읽기 결과를 결정적 순서(entry_id, property_id)의
// fact 슬라이스로 변환하고 쓰기는 저장소의 원자적 upsert로 위임한다.
type EntryPropertyFactStore struct {
	repository *EntryPropertyRepository
}

// NewEntryPropertyFactStore는 store에 바인딩된 fact 포트 구현을 돌려준다.
func NewEntryPropertyFactStore(store *Store) *EntryPropertyFactStore {
	return &EntryPropertyFactStore{repository: NewEntryPropertyRepository(store)}
}

// LoadAssignments는 요청 참조의 durable fact를 고정 쿼리 예산으로 읽어
// (entry_id, property_id) 오름차순 슬라이스로 돌려준다. 행이 없는 참조는
// implicit unset이므로 결과에서 제외된다. 저장소가 채운 합성 unset 행은
// RecordRevision 0으로 식별된다(durable row는 항상 1 이상이다). CAS 경계는
// 인덱스 부재를 revision 0과 동일하게 해석하므로 제외가 의미를 바꾸지 않는다.
func (s *EntryPropertyFactStore) LoadAssignments(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	entryIDs []string,
	propertyIDs []domainentry.PropertyID,
) ([]domainentry.EntryPropertyAssignment, error) {
	facts, err := s.repository.LoadAssignments(ctx, workspace, entryIDs, propertyIDs)
	if err != nil {
		return nil, err
	}
	ordered := make([]domainentry.EntryPropertyAssignment, 0, len(facts))
	for _, fact := range facts {
		if fact.RecordRevision == 0 {
			continue
		}
		ordered = append(ordered, fact)
	}
	sort.Slice(ordered, func(left, right int) bool {
		if ordered[left].EntryID != ordered[right].EntryID {
			return ordered[left].EntryID < ordered[right].EntryID
		}
		return ordered[left].PropertyID.String() < ordered[right].PropertyID.String()
	})
	return ordered, nil
}

// SaveAssignments는 fact 배치를 하나의 원자적 트랜잭션으로 위임한다.
func (s *EntryPropertyFactStore) SaveAssignments(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	facts []domainentry.EntryPropertyAssignment,
) error {
	return s.repository.SaveAssignments(ctx, workspace, facts)
}

// StoreTransactionRunner는 applicationproperty.TransactionRunner 포트의 SQLite
// 구현이다. fn에는 tx 스코프가 붙은 ctx가 전달되므로 포트 저장소의 읽기·쓰기가
// 같은 트랜잭션에 참여한다.
type StoreTransactionRunner struct {
	store *Store
}

// NewStoreTransactionRunner는 store에 바인딩된 트랜잭션 포트 구현을 돌려준다.
func NewStoreTransactionRunner(store *Store) *StoreTransactionRunner {
	return &StoreTransactionRunner{store: store}
}

// WithinTx는 단일 mutation boundary 안에서 fn을 실행하고 tx 스코프 ctx를
// 전달한다.
func (r *StoreTransactionRunner) WithinTx(ctx context.Context, fn func(ctx context.Context) error) error {
	return r.store.WithinTx(ctx, func(tx *gorm.DB) error {
		return fn(r.store.WithTxScope(ctx, tx))
	})
}
