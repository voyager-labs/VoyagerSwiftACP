package main

import (
	"context"
	"crypto/rand"
	"time"

	applicationentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/entry"
	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/mount"
	sqlite "github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite"
	entryruntime "github.com/voyager-labs/voyager-app/apps/entry-core/internal/runtime"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source/localfs"
)

// 이 파일은 todo 10의 데몬 조합 seam이다. 워크스페이스 복원·카탈로그 검증·
// preset 재조정이 끝난 뒤에만 호출되어 root-/ localfs resolver, Property
// 저장소·서비스, Entry overlay를 조합하고 두 서비스가 주입된 runtime을
// 돌려준다. 어떤 단계든 실패하면 readiness 전에 실패 닫기한다.

// propertyService는 정의·선택지 명령과 prepare/execute 변경을 하나의 runtime
// 서비스 경계로 묶는 조합 composite다. 두 서비스는 메서드 집합이 겹치지 않는다.
type propertyService struct {
	*applicationproperty.CatalogService
	*applicationproperty.ChangeService
}

// localfsTargetResolver는 localfs.Adapter.ResolveLocalPath(entry.EntryRef 반환)를
// applicationproperty.LocalPathResolver 포트(ResolvedTarget 반환)에 맞추는
// source→application 방향의 최소 adapter다. 의존성 방향을 지키기 위해 cmd에 둔다.
type localfsTargetResolver struct {
	adapter *localfs.Adapter
}

// ResolveLocalPath는 clean 절대 경로 하나를 locator 유도 대상으로 해석한다.
func (r localfsTargetResolver) ResolveLocalPath(ctx context.Context, localPath string) (applicationproperty.ResolvedTarget, error) {
	ref, err := r.adapter.ResolveLocalPath(ctx, localPath)
	if err != nil {
		return applicationproperty.ResolvedTarget{}, err
	}
	return applicationproperty.ResolvedTarget{
		EntryRef:       ref,
		Classification: applicationproperty.TargetClassificationLocatorDerived,
	}, nil
}

// composeWorkspaceServices는 열린 store와 검증된 활성 카탈로그 스냅샷으로
// root-/ localfs resolver, Property 저장소·서비스, Entry overlay를 조합해 두
// 서비스가 주입된 runtime을 만든다. ponytail: mount registry는 비워 둔다 — 이
// 슬라이스에는 mount 구성이 없고 entry.list는 typed 실패로 실패 닫기된다.
// mount 구성은 Entry production wiring 슬라이스에서 온다.
func composeWorkspaceServices(
	store *sqlite.Store,
	wsctx domainentry.WorkspaceContext,
	snapshot domainentry.PropertyCatalogSnapshot,
) (*entryruntime.Runtime, error) {
	cursorKey := make([]byte, 32)
	if _, err := rand.Read(cursorKey); err != nil {
		return nil, err
	}
	resolver, err := localfs.New(localfs.Config{
		Root:       "/",
		Generation: "entry-core-daemon",
		CursorKey:  cursorKey,
	})
	if err != nil {
		return nil, err
	}
	catalogStore, err := sqlite.NewPropertyCatalogStore(store, wsctx)
	if err != nil {
		return nil, err
	}
	facts := sqlite.NewEntryPropertyFactStore(store)
	runner := sqlite.NewStoreTransactionRunner(store)
	catalogService, err := applicationproperty.NewCatalogService(catalogStore, runner)
	if err != nil {
		return nil, err
	}
	changeService, err := applicationproperty.NewChangeService(catalogStore, facts, localfsTargetResolver{adapter: resolver}, runner)
	if err != nil {
		return nil, err
	}
	available, err := domainentry.NewAvailability(domainentry.AvailabilityStateAvailable)
	if err != nil {
		return nil, err
	}
	sourceRef, err := domainentry.NewSourceRef(
		resolver.SourceIdentity().SourceID, "localfs", "local",
		available, resolver.SourceIdentity().IdentityStrength,
	)
	if err != nil {
		return nil, err
	}
	entryService, err := applicationentry.NewUnifiedServiceWithCatalog(
		mount.NewMountRegistry(),
		[]applicationentry.ResourceAdapterBinding{
			{SourceRef: sourceRef, Adapter: localfs.NewResourceAdapter(resolver)},
		},
		snapshot,
		cursorKey,
		time.Now,
		applicationentry.WithPropertyOverlayLoader(propertyOverlayStore{catalog: catalogStore, facts: facts}),
	)
	if err != nil {
		return nil, err
	}
	service := &propertyService{CatalogService: catalogService, ChangeService: changeService}
	return entryruntime.NewWithServices(wsctx.ID.String(), entryService, service), nil
}
