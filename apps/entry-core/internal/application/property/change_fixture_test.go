package property

import (
	"context"
	"errors"
	"reflect"
	"sort"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

// factKey는 (entry, property) assignment 참조의 in-memory 키다.
type factKey struct {
	entryID    string
	propertyID domainentry.PropertyID
}

// memFactStore는 AssignmentFactRepository의 in-memory fake이다. TransactionRunner
// 경계에서 pending 버퍼를 통해 실제 tx 의미(커밋 전까지 관찰 불가, 오류 시 전체
// 폐기, tx 안 read-your-writes)를 모방한다. failAfter가 설정되면 앞의 N개 fact를
// 적용한 뒤 오류를 반환해 "이전 쓰기 존재 후 저장소 오류" 롤백을 재현한다.
type memFactStore struct {
	facts     map[factKey]domainentry.EntryPropertyAssignment
	pending   map[factKey]domainentry.EntryPropertyAssignment
	depth     int
	failAfter int // 0 = 실패 없음
	saveCalls int
	loadCalls int
}

func newMemFactStore() *memFactStore {
	return &memFactStore{facts: make(map[factKey]domainentry.EntryPropertyAssignment)}
}

func keyOf(fact domainentry.EntryPropertyAssignment) factKey {
	return factKey{entryID: fact.EntryID, propertyID: fact.PropertyID}
}

func (store *memFactStore) begin() {
	store.pending = make(map[factKey]domainentry.EntryPropertyAssignment)
}

func (store *memFactStore) commit() {
	for key, fact := range store.pending {
		store.facts[key] = fact
	}
	store.pending = nil
}

func (store *memFactStore) rollback() {
	store.pending = nil
}

func (store *memFactStore) LoadAssignments(_ context.Context, workspace domainentry.WorkspaceContext, entryIDs []string, propertyIDs []domainentry.PropertyID) ([]domainentry.EntryPropertyAssignment, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return nil, err
	}
	store.loadCalls++
	wanted := make(map[factKey]struct{}, len(entryIDs)*len(propertyIDs))
	for _, entryID := range entryIDs {
		for _, propertyID := range propertyIDs {
			wanted[factKey{entryID: entryID, propertyID: propertyID}] = struct{}{}
		}
	}
	out := make([]domainentry.EntryPropertyAssignment, 0)
	for key, fact := range store.facts {
		if _, want := wanted[key]; want {
			out = append(out, fact)
		}
	}
	for key, fact := range store.pending {
		if _, want := wanted[key]; want {
			out = append(out, fact)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].EntryID != out[j].EntryID {
			return out[i].EntryID < out[j].EntryID
		}
		return out[i].PropertyID.String() < out[j].PropertyID.String()
	})
	return out, nil
}

func (store *memFactStore) SaveAssignments(_ context.Context, workspace domainentry.WorkspaceContext, facts []domainentry.EntryPropertyAssignment) error {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return err
	}
	store.saveCalls++
	applied := 0
	for _, fact := range facts {
		if store.failAfter > 0 && applied >= store.failAfter {
			return errInjectedSaveFailure
		}
		if store.pending == nil {
			store.pending = make(map[factKey]domainentry.EntryPropertyAssignment)
		}
		store.pending[keyOf(fact)] = fact
		applied++
	}
	return nil
}

// snapshot은 커밋된 fact 상태의 불변 검증용 복사본이다.
func (store *memFactStore) snapshot() map[factKey]domainentry.EntryPropertyAssignment {
	frozen := make(map[factKey]domainentry.EntryPropertyAssignment, len(store.facts))
	for key, fact := range store.facts {
		frozen[key] = fact
	}
	return frozen
}

// mustEqualFactSnapshot은 거절된 execute 이후 커밋된 fact 상태가 전혀 바뀌지
// 않았음을 증명한다.
func mustEqualFactSnapshot(t *testing.T, want, got map[factKey]domainentry.EntryPropertyAssignment) {
	t.Helper()
	if len(want) != len(got) {
		t.Fatalf("fact count changed: want %d, got %d", len(want), len(got))
	}
	for key, wantFact := range want {
		gotFact, ok := got[key]
		if !ok || !reflect.DeepEqual(wantFact, gotFact) {
			t.Fatalf("fact %v changed after rejected execute", key)
		}
	}
}

// changeTxRunner는 TransactionRunner fake으로 top-level 호출 수를 세고 memFactStore의
// tx 버퍼링을 구동한다. 중첩 WithinTx도 별도 호출로 기록되어 "정확히 하나의
// top-level WithinTx" 검증에 쓰인다.
type changeTxRunner struct {
	facts *memFactStore
	calls int
}

func (runner *changeTxRunner) WithinTx(ctx context.Context, fn func(context.Context) error) error {
	runner.calls++
	if runner.facts.depth == 0 {
		runner.facts.begin()
	}
	runner.facts.depth++
	err := fn(ctx)
	runner.facts.depth--
	if runner.facts.depth == 0 {
		if err == nil {
			runner.facts.commit()
		} else {
			runner.facts.rollback()
		}
	}
	return err
}

// stubPathResolver는 고정 경로→대상 표로 응답하는 LocalPathResolver fake이다.
type stubPathResolver struct {
	paths map[string]ResolvedTarget
	err   error
}

func (resolver stubPathResolver) ResolveLocalPath(_ context.Context, localPath string) (ResolvedTarget, error) {
	if resolver.err != nil {
		return ResolvedTarget{}, resolver.err
	}
	target, ok := resolver.paths[localPath]
	if !ok {
		return ResolvedTarget{}, errUnknownPath
	}
	return target, nil
}

// mustResolvedTargetFor는 이름별로 서로 다른 canonical EntryRef를 가진 유효한
// locator 유도 대상을 만든다.
func mustResolvedTargetFor(t *testing.T, name string) ResolvedTarget {
	t.Helper()
	sourceIdentity, err := source.DeriveSourceIdentity("localfs", "/fixture", domainentry.IdentityStrengthLocator)
	if err != nil {
		t.Fatal(err)
	}
	locator, err := source.NewCanonicalSourceLocator(make([]byte, 32), "localfs", sourceIdentity.SourceID, []byte("/fixture/"+name))
	if err != nil {
		t.Fatal(err)
	}
	locatorRef, err := locator.LocatorRef()
	if err != nil {
		t.Fatal(err)
	}
	entryID := domainentry.DeriveEntryID(sourceIdentity.SourceID, "file", name)
	ref, err := domainentry.NewEntryRef(entryID, sourceIdentity.SourceID, name, "file", locatorRef, domainentry.IdentityStrengthLocator)
	if err != nil {
		t.Fatal(err)
	}
	return ResolvedTarget{EntryRef: ref, Classification: TargetClassificationLocatorDerived}
}

// mustChangeService는 공유 카탈로그와 fact 저장소 위에 변경 서비스를 만든다.
func mustChangeService(t *testing.T, catalog *memCatalogStore, facts *memFactStore, resolver LocalPathResolver) (*ChangeService, *changeTxRunner) {
	t.Helper()
	runner := &changeTxRunner{facts: facts}
	service, err := NewChangeService(catalog, facts, resolver, runner)
	if err != nil {
		t.Fatal(err)
	}
	return service, runner
}

// textValue와 selectValue는 테스트 스칼라 값을 만드는 헬퍼다.
func textValue(text string) *domainentry.AssignmentValue {
	return &domainentry.AssignmentValue{Text: &text}
}

func optionValue(id domainentry.PropertyOptionID) *domainentry.AssignmentValue {
	return &domainentry.AssignmentValue{OptionID: &id}
}

func manyOptions(ids ...domainentry.PropertyOptionID) []domainentry.AssignmentValue {
	out := make([]domainentry.AssignmentValue, 0, len(ids))
	for _, id := range ids {
		out = append(out, domainentry.AssignmentValue{OptionID: &id})
	}
	return out
}

// firstOptionID와 secondOptionID는 select 픽스처의 활성 선택지 ID를 돌려준다.
func firstOptionID(t *testing.T, view DefinitionView) domainentry.PropertyOptionID {
	t.Helper()
	return view.Options[0].OptionID
}

// 변경 픽스처 전용 오류다. 저장소 쓰기 실패와 미등록 경로를 재현한다.
var (
	errInjectedSaveFailure = errors.New("injected save failure")
	errUnknownPath         = errors.New("unknown path fixture")
)
