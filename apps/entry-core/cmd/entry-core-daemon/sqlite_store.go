package main

import (
	"context"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	sqlite "github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite"
	entryruntime "github.com/voyager-labs/voyager-app/apps/entry-core/internal/runtime"
)

// sqliteDaemonStore adapts *sqlite.Store to the daemonStore seam. Migrate runs
// the embedded-migration runner over the store's shared connection; the other
// methods delegate to the store.
type sqliteDaemonStore struct {
	store *sqlite.Store
}

func (s sqliteDaemonStore) Migrate(ctx context.Context) error {
	return sqlite.MigrateUp(ctx, s.store.SQLDB())
}

func (s sqliteDaemonStore) BootstrapOrRestoreWorkspace(ctx context.Context) (domainentry.WorkspaceContext, error) {
	return s.store.BootstrapOrRestoreWorkspace(ctx)
}

func (s sqliteDaemonStore) ApplyCatalogSeed(ctx context.Context, wsctx domainentry.WorkspaceContext) error {
	return s.store.ApplyCatalogSeed(ctx, wsctx)
}

// ValidateActiveCatalog는 시드 적용 뒤 활성 카탈로그 전체를 기존
// PropertyCatalogRepository.Load 경로로 로드·검증한다. 고아 참조(ErrCatalogOrphanRef)나
// invalid 활성 스냅샷은 오류로 반환되어 기동이 실패 닫기된다. 검증을 통과한
// 스냅샷은 조합 단계에서 Entry 서비스 카탈로그로 재사용된다.
func (s sqliteDaemonStore) ValidateActiveCatalog(ctx context.Context, wsctx domainentry.WorkspaceContext) (domainentry.PropertyCatalogSnapshot, error) {
	loaded, err := sqlite.NewPropertyCatalogRepository(s.store).Load(ctx, wsctx)
	if err != nil {
		return domainentry.PropertyCatalogSnapshot{}, err
	}
	return loaded.Snapshot, nil
}

// ApplyPropertyPresets는 Status/Project/Priority preset을 멱등 재조정한다. 첫
// 실행은 누락 멤버를 만들고 이후 실행은 기존 행의 사용자 상태를 보존한다.
func (s sqliteDaemonStore) ApplyPropertyPresets(ctx context.Context, wsctx domainentry.WorkspaceContext) error {
	return s.store.ApplyPropertyPresets(ctx, wsctx)
}

// ComposeServices는 검증된 스냅샷으로 Property·Entry 서비스와 runtime을 조합한다.
func (s sqliteDaemonStore) ComposeServices(
	ctx context.Context,
	wsctx domainentry.WorkspaceContext,
	snapshot domainentry.PropertyCatalogSnapshot,
) (*entryruntime.Runtime, error) {
	return composeWorkspaceServices(s.store, wsctx, snapshot)
}

func (s sqliteDaemonStore) Close() error {
	return s.store.Close()
}
