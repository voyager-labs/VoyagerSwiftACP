package property

import (
	"context"
	"errors"
	"strings"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	schema "github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

type directTransactionRunner struct{}

func (directTransactionRunner) WithinTx(ctx context.Context, fn func(context.Context) error) error {
	return fn(ctx)
}

// rollbackTransactionRunner는 fn이 오류를 반환하면 가장 바깥 스냅샷으로 저장소를
// 되돌리는 테스트 전용 러너다. 실제 SQLite tx의 커밋/롤백 의미를 in-memory
// 저장소에서 재현한다.
type rollbackTransactionRunner struct {
	store *memCatalogStore
}

func (runner *rollbackTransactionRunner) WithinTx(_ context.Context, fn func(context.Context) error) error {
	saved := snapshotStore(runner.store)
	if err := fn(context.Background()); err != nil {
		runner.store.defs = saved.defs
		runner.store.opts = saved.opts
		return err
	}
	return nil
}

var _ TransactionRunner = directTransactionRunner{}

// 요청이 봉투에 들어도 발급 UUID와 상태 필드가 추가된 성공 응답은 65,536바이트를
// 넘을 수 있다. 초과 예상 생성은 커밋 전에 scope_too_large로 거절되고 쓰기는 0이다.
func TestCreateDefinitionRejectsEnvelopeOverflowBeforeCommit(t *testing.T) {
	store := newMemCatalogStore()
	service, err := NewCatalogService(store, directTransactionRunner{})
	if err != nil {
		t.Fatalf("NewCatalogService: %v", err)
	}
	workspace := mustWorkspaceContext(t)

	labels := make([]string, 256)
	for index := range labels {
		labels[index] = strings.Repeat("a", 200)
	}
	view, err := service.CreateDefinition(context.Background(), workspace, CreateDefinitionInput{
		Key:          "overflow",
		DisplayName:  "Overflow",
		ValueType:    domainentry.PropertyTypeSelect,
		Cardinality:  domainentry.PropertyCardinalityOne,
		OptionLabels: labels,
		RequestID:    "req-overflow-test",
	})
	if !errors.Is(err, ErrScopeTooLarge) {
		t.Fatalf("err = %v, want ErrScopeTooLarge", err)
	}
	if view.Definition.PropertyID != (domainentry.PropertyID{}) {
		t.Fatalf("view returned on overflow: %+v", view)
	}
	if len(store.defs) != 0 || len(store.opts) != 0 || len(store.opts) > 0 && false {
		t.Fatalf("overflow create must write nothing")
	}
	for _, def := range store.defs {
		t.Fatalf("definition persisted despite overflow: %+v", def)
	}
	for _, options := range store.opts {
		if len(options) != 0 {
			t.Fatalf("options persisted despite overflow: %d rows", len(options))
		}
	}
}

// 경계 내 생성은 여전히 성공하고, 같은 뷰의 인코딩이 protocol EncodedSuccessBytes
// 기준으로 실제 들어감을 함께 잠근다.
func TestCreateDefinitionWithinBudgetStillSucceeds(t *testing.T) {
	store := newMemCatalogStore()
	service, err := NewCatalogService(store, directTransactionRunner{})
	if err != nil {
		t.Fatalf("NewCatalogService: %v", err)
	}
	workspace := mustWorkspaceContext(t)

	view, err := service.CreateDefinition(context.Background(), workspace, CreateDefinitionInput{
		Key:          "compact",
		DisplayName:  "Compact",
		ValueType:    domainentry.PropertyTypeSelect,
		Cardinality:  domainentry.PropertyCardinalityOne,
		OptionLabels: []string{"only"},
		RequestID:    "req-compact-test",
	})
	if err != nil {
		t.Fatalf("CreateDefinition: %v", err)
	}
	wire, code := DefinitionViewToWire(view)
	if code != "" {
		t.Fatalf("wire mapping failed: %s", code)
	}
	if _, fits := schema.EncodedSuccessBytes("req-compact-test", schema.PropertyDefinitionResult{Definition: wire}); !fits {
		t.Fatalf("in-budget create response must fit the wire envelope")
	}
}

// 단일 정의 결과 봉투가 들어가도 최소 목록 페이지(ID 필터 page_size 1)는
// definitions 배열과 has_more 필드 때문에 더 크다. 커밋된 정의는 커밋 이후에도
// 최소 페이지로 조회 가능해야 하므로, 결과 봉투는 들어가지만 최소 목록 페이지가
// 초과하는 생성은 커밋 전에 scope_too_large로 거절되고 쓰기는 0이다.
func TestCreateDefinitionRejectsMinimalListEnvelopeOverflow(t *testing.T) {
	store := newMemCatalogStore()
	service, err := NewCatalogService(store, directTransactionRunner{})
	if err != nil {
		t.Fatalf("NewCatalogService: %v", err)
	}
	workspace := mustWorkspaceContext(t)

	labels := make([]string, 186)
	for index := range labels {
		labels[index] = strings.Repeat("a", 255)
	}
	view, err := service.CreateDefinition(context.Background(), workspace, CreateDefinitionInput{
		Key:          "k",
		DisplayName:  "n",
		ValueType:    domainentry.PropertyTypeSelect,
		Cardinality:  domainentry.PropertyCardinalityOne,
		OptionLabels: labels,
		RequestID:    strings.Repeat("r", 128),
	})
	if !errors.Is(err, ErrScopeTooLarge) {
		t.Fatalf("err = %v, want ErrScopeTooLarge", err)
	}
	if view.Definition.PropertyID != (domainentry.PropertyID{}) {
		t.Fatalf("view returned on overflow: %+v", view)
	}
	for _, def := range store.defs {
		t.Fatalf("definition persisted despite overflow: %+v", def)
	}
	for _, options := range store.opts {
		if len(options) != 0 {
			t.Fatalf("options persisted despite overflow: %d rows", len(options))
		}
	}
}

// 정의 안쪽 요청으로 만든 경계 부근의 카탈로그(220×200바이트 라벨)는 update나
// option mutation 같은 작은 후속 요청의 결과 뷰를 65,536바이트 넘게 만들 수
// 있다. 이때도 커밋 전에 scope_too_large로 실패 닫기하고 쓰기는 0이어야 한다.
func TestMutationsRejectEnvelopeOverflowBeforeCommit(t *testing.T) {
	store := newMemCatalogStore()
	service, err := NewCatalogService(store, &rollbackTransactionRunner{store: store})
	if err != nil {
		t.Fatalf("NewCatalogService: %v", err)
	}
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	labels := make([]string, 200)
	for index := range labels {
		labels[index] = strings.Repeat("a", 230)
	}
	created, err := service.CreateDefinition(ctx, workspace, CreateDefinitionInput{
		Key:          "edge",
		DisplayName:  "Edge",
		ValueType:    domainentry.PropertyTypeSelect,
		Cardinality:  domainentry.PropertyCardinalityOne,
		OptionLabels: labels,
		RequestID:    "req-edge",
	})
	if err != nil {
		t.Fatalf("in-budget create must succeed: %v", err)
	}
	propertyID := created.Definition.PropertyID

	before := snapshotStore(store)

	if _, err := service.UpdateDefinitionMetadata(ctx, workspace, propertyID, created.Definition.DefinitionRev,
		strings.Repeat("n", 128), strings.Repeat("b", 256)); !errors.Is(err, ErrScopeTooLarge) {
		t.Fatalf("update error = %v, want ErrScopeTooLarge", err)
	}
	mustEqualSnapshot(t, before, snapshotStore(store))

	if _, err := service.CreateOption(ctx, workspace, propertyID, created.Definition.DefinitionRev,
		"req-opt", strings.Repeat("c", 256)); !errors.Is(err, ErrScopeTooLarge) {
		t.Fatalf("create option error = %v, want ErrScopeTooLarge", err)
	}
	mustEqualSnapshot(t, before, snapshotStore(store))
}

// 예산 안의 동일 mutation은 그대로 성공해야 한다. 초과 거절이 우발적으로
// 모든 후속 mutation을 막는 회귀가 아님을 함께 잠근다.
func TestMutationsWithinBudgetStillSucceedAfterPreflight(t *testing.T) {
	store := newMemCatalogStore()
	service, err := NewCatalogService(store, directTransactionRunner{})
	if err != nil {
		t.Fatalf("NewCatalogService: %v", err)
	}
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	view := mustCreatedSelectDefinition(t, service, workspace, "preflight")
	propertyID := view.Definition.PropertyID

	updated, err := service.UpdateDefinitionMetadata(ctx, workspace, propertyID, view.Definition.DefinitionRev, "req-u", "Updated")
	if err != nil {
		t.Fatalf("update: %v", err)
	}
	if updated.Definition.DisplayName != "Updated" || updated.Definition.DefinitionRev != view.Definition.DefinitionRev+1 {
		t.Fatalf("update result unexpected: %+v", updated.Definition)
	}

	optioned, err := service.CreateOption(ctx, workspace, propertyID, updated.Definition.DefinitionRev, "req-o", "third")
	if err != nil {
		t.Fatalf("create option: %v", err)
	}
	if len(optioned.Options) != len(view.Options)+1 {
		t.Fatalf("options = %d, want %d", len(optioned.Options), len(view.Options)+1)
	}
}
