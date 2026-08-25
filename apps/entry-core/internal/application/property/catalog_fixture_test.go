package property

import (
	"context"
	"reflect"
	"sort"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// memCatalogStore는 CatalogRepository의 in-memory fake이다. delete 메서드가
// 없다는 사실 자체가 "서비스는 행을 물리 삭제할 수 없다" 계약의 일부다.
type memCatalogStore struct {
	defs map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition
	opts map[domainentry.PropertyID][]domainentry.PropertyOption
}

// 컴파일 시점 계약 적합성: fake가 저장소 port를 만족해야 한다.
var _ CatalogRepository = (*memCatalogStore)(nil)

func newMemCatalogStore() *memCatalogStore {
	return &memCatalogStore{
		defs: make(map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition),
		opts: make(map[domainentry.PropertyID][]domainentry.PropertyOption),
	}
}

func (store *memCatalogStore) Definition(_ context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID) (domainentry.WorkspacePropertyDefinition, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return domainentry.WorkspacePropertyDefinition{}, err
	}
	def, ok := store.defs[propertyID]
	if !ok {
		return domainentry.WorkspacePropertyDefinition{}, ErrDefinitionNotFound
	}
	return def, nil
}

func (store *memCatalogStore) Option(_ context.Context, workspace domainentry.WorkspaceContext, optionID domainentry.PropertyOptionID) (domainentry.PropertyOption, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return domainentry.PropertyOption{}, err
	}
	for _, rows := range store.opts {
		for _, option := range rows {
			if option.OptionID == optionID {
				return option, nil
			}
		}
	}
	return domainentry.PropertyOption{}, ErrOptionNotFound
}

func (store *memCatalogStore) Definitions(_ context.Context, workspace domainentry.WorkspaceContext) ([]domainentry.WorkspacePropertyDefinition, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return nil, err
	}
	out := make([]domainentry.WorkspacePropertyDefinition, 0, len(store.defs))
	for _, def := range store.defs {
		out = append(out, def)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].PropertyID.String() < out[j].PropertyID.String() })
	return out, nil
}

func (store *memCatalogStore) Options(_ context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID) ([]domainentry.PropertyOption, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return nil, err
	}
	rows := store.opts[propertyID]
	out := make([]domainentry.PropertyOption, len(rows))
	copy(out, rows)
	sort.Slice(out, func(i, j int) bool { return out[i].Ordinal < out[j].Ordinal })
	return out, nil
}

func (store *memCatalogStore) PutDefinition(_ context.Context, def domainentry.WorkspacePropertyDefinition) error {
	if _, exists := store.defs[def.PropertyID]; exists {
		return ErrDuplicateDefinitionKey
	}
	store.defs[def.PropertyID] = def
	store.opts[def.PropertyID] = nil
	return nil
}

func (store *memCatalogStore) SaveDefinition(_ context.Context, def domainentry.WorkspacePropertyDefinition) error {
	if _, exists := store.defs[def.PropertyID]; !exists {
		return ErrDefinitionNotFound
	}
	store.defs[def.PropertyID] = def
	return nil
}

func (store *memCatalogStore) PutOption(_ context.Context, option domainentry.PropertyOption) error {
	for _, existing := range store.opts[option.PropertyID] {
		if existing.OptionID == option.OptionID {
			return ErrDuplicateOptionID
		}
	}
	store.opts[option.PropertyID] = append(store.opts[option.PropertyID], option)
	return nil
}

func (store *memCatalogStore) SaveOptions(_ context.Context, options []domainentry.PropertyOption) error {
	for _, option := range options {
		rows := store.opts[option.PropertyID]
		replaced := false
		for index := range rows {
			if rows[index].OptionID == option.OptionID {
				rows[index] = option
				replaced = true
				break
			}
		}
		if !replaced {
			return ErrOptionNotFound
		}
	}
	return nil
}

// passthroughRunner는 TransactionRunner fake으로 tx 경계를 그대로 실행한다.
type passthroughRunner struct{}

func (passthroughRunner) WithinTx(ctx context.Context, fn func(context.Context) error) error {
	return fn(ctx)
}

// catalogSnapshot은 실패 후 상태 불변 검증을 위한 저장소 스냅샷이다.
type catalogSnapshot struct {
	defs map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition
	opts map[domainentry.PropertyID][]domainentry.PropertyOption
}

func snapshotStore(store *memCatalogStore) catalogSnapshot {
	frozen := catalogSnapshot{
		defs: make(map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition, len(store.defs)),
		opts: make(map[domainentry.PropertyID][]domainentry.PropertyOption, len(store.opts)),
	}
	for id, def := range store.defs {
		frozen.defs[id] = def
		frozen.opts[id] = append([]domainentry.PropertyOption(nil), store.opts[id]...)
	}
	return frozen
}

// mustEqualSnapshot은 두 스냅샷이 동일함을 단언한다. 거절된 mutation이 저장소를
// 전혀 바꾸지 않았음을 증명한다.
func mustEqualSnapshot(t *testing.T, want, got catalogSnapshot) {
	t.Helper()
	if len(want.defs) != len(got.defs) {
		t.Fatalf("definition count changed: want %d, got %d", len(want.defs), len(got.defs))
	}
	for id, wantDef := range want.defs {
		gotDef, ok := got.defs[id]
		if !ok || !reflect.DeepEqual(wantDef, gotDef) {
			t.Fatalf("definition %s changed after rejected mutation", id)
		}
		wantOpts, gotOpts := want.opts[id], got.opts[id]
		if len(wantOpts) != len(gotOpts) {
			t.Fatalf("option count for %s changed: want %d, got %d", id, len(wantOpts), len(gotOpts))
		}
		for index := range wantOpts {
			if wantOpts[index] != gotOpts[index] {
				t.Fatalf("option %d of %s changed after rejected mutation", index, id)
			}
		}
	}
}

// mustCatalogService는 테스트용 서비스를 만든다.
func mustCatalogService(t *testing.T, store *memCatalogStore) *CatalogService {
	t.Helper()
	service, err := NewCatalogService(store, passthroughRunner{})
	if err != nil {
		t.Fatal(err)
	}
	return service
}

// mustWorkspaceContext는 테스트용 typed workspace identity를 만든다.
func mustWorkspaceContext(t *testing.T) domainentry.WorkspaceContext {
	t.Helper()
	id, err := domainentry.NewWorkspaceID()
	if err != nil {
		t.Fatal(err)
	}
	return domainentry.WorkspaceContext{ID: id}
}

// mustCreatedDefinition은 select가 아닌 기본 정의 하나를 만들어 돌려준다.
func mustCreatedDefinition(t *testing.T, service *CatalogService, workspace domainentry.WorkspaceContext, key string) DefinitionView {
	t.Helper()
	view, err := service.CreateDefinition(context.Background(), workspace, CreateDefinitionInput{
		Key:         key,
		DisplayName: key + " display",
		ValueType:   domainentry.PropertyTypeText,
		Cardinality: domainentry.PropertyCardinalityOne,
	})
	if err != nil {
		t.Fatal(err)
	}
	return view
}

// mustCreatedSelectDefinition은 선택지 둘을 가진 select 정의를 만든다.
func mustCreatedSelectDefinition(t *testing.T, service *CatalogService, workspace domainentry.WorkspaceContext, key string) DefinitionView {
	t.Helper()
	view, err := service.CreateDefinition(context.Background(), workspace, CreateDefinitionInput{
		Key:          key,
		DisplayName:  key + " display",
		ValueType:    domainentry.PropertyTypeSelect,
		Cardinality:  domainentry.PropertyCardinalityOne,
		OptionLabels: []string{"first", "second"},
	})
	if err != nil {
		t.Fatal(err)
	}
	return view
}
