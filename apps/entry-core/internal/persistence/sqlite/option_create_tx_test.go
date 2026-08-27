package sqlite

import (
	"context"
	"testing"
	"time"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

func mustWorkspaceContext(t *testing.T) domainentry.WorkspaceContext {
	t.Helper()
	id, err := domainentry.NewWorkspaceID()
	if err != nil {
		t.Fatalf("NewWorkspaceID: %v", err)
	}
	return domainentry.WorkspaceContext{ID: id}
}

// CreateOption이 정의 revision 갱신과 같은 트랜잭션에 참여함을 실제 단일 연결
// store로 증명한다. tx 스코프 밖 공유 연결 조회는 SetMaxOpenConns(1) 정책
// 아래 열린 트랜잭션과 교착되므로, 회귀 시 ctx 만료 실패로 드러난다.
func TestCreateOptionParticipatesInDefinitionTransaction(t *testing.T) {
	ctx := context.Background()
	store, err := Open(ctx, tempDBPath(t))
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp: %v", err)
	}

	workspace := mustWorkspaceContext(t)
	if _, err := store.SQLDB().ExecContext(ctx,
		`INSERT INTO workspace_metadata (singleton, workspace_id, created_at, updated_at)
		 VALUES (1, ?, datetime('now'), datetime('now'))`, workspace.ID.Bytes()); err != nil {
		t.Fatalf("seed workspace: %v", err)
	}

	catalogStore, err := NewPropertyCatalogStore(store, workspace)
	if err != nil {
		t.Fatalf("NewPropertyCatalogStore: %v", err)
	}
	service, err := applicationproperty.NewCatalogService(catalogStore, NewStoreTransactionRunner(store))
	if err != nil {
		t.Fatalf("NewCatalogService: %v", err)
	}

	view, err := service.CreateDefinition(ctx, workspace, applicationproperty.CreateDefinitionInput{
		Key:          "status_tx_test",
		DisplayName:  "Status",
		ValueType:    domainentry.PropertyTypeSelect,
		Cardinality:  domainentry.PropertyCardinalityOne,
		OptionLabels: []string{"todo"},
		RequestID:    "req-option-tx-test",
	})
	if err != nil {
		t.Fatalf("CreateDefinition: %v", err)
	}

	txCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	updated, err := service.CreateOption(txCtx, workspace, view.Definition.PropertyID, view.Definition.DefinitionRev, "done")
	if err != nil {
		t.Fatalf("CreateOption: %v", err)
	}
	if len(updated.Options) != 2 {
		t.Fatalf("options = %d, want 2", len(updated.Options))
	}
	if updated.Definition.DefinitionRev != view.Definition.DefinitionRev+1 {
		t.Fatalf("revision = %d, want %d", updated.Definition.DefinitionRev, view.Definition.DefinitionRev+1)
	}
}
