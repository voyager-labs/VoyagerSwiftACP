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
