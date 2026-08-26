package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	sqlite "github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite"
	entryruntime "github.com/voyager-labs/voyager-app/apps/entry-core/internal/runtime"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// compositionStore는 fakeDaemonStore에 todo-10 조합 단계(preset 재조정, 서비스
// 조합)를 덧씌운 실패 주입 seam이다. openStore가 이 wrapper를 돌려주면 run()의
// 호출 순서와 실패 닫기 동작을 그대로 관찰할 수 있다.
type compositionStore struct {
	*fakeDaemonStore
	presetsErr error
	composeErr error
	runtime    *entryruntime.Runtime
}

func (s *compositionStore) openCompositionStore(context.Context, string) (daemonStore, error) {
	s.record("open")
	if s.openErr != nil {
		return nil, s.openErr
	}
	return s, nil
}

func (s *compositionStore) ValidateActiveCatalog(context.Context, domainentry.WorkspaceContext) (domainentry.PropertyCatalogSnapshot, error) {
	s.record("validate")
	if s.validateErr != nil {
		return domainentry.PropertyCatalogSnapshot{}, s.validateErr
	}
	return domainentry.PropertyCatalogSnapshot{}, nil
}

func (s *compositionStore) ApplyPropertyPresets(context.Context, domainentry.WorkspaceContext) error {
	s.record("presets")
	return s.presetsErr
}

func (s *compositionStore) ComposeServices(context.Context, domainentry.WorkspaceContext, domainentry.PropertyCatalogSnapshot) (*entryruntime.Runtime, error) {
	s.record("compose")
	return s.runtime, s.composeErr
}

// TestCompositionStartupOrderInstallsPresetsAndComposesBeforeReady는 DB 모드 기동이
// validate 뒤 preset 재조정과 서비스 조합을 마친 뒤에만 server를 만드는지 검증한다.
func TestCompositionStartupOrderInstallsPresetsAndComposesBeforeReady(t *testing.T) {
	parent := t.TempDir()
	store := &compositionStore{fakeDaemonStore: newFakeDaemonStore()}
	var captured *entryruntime.Runtime
	constructorCalled := false

	code := run(
		[]string{"--socket", filepath.Join(parent, "entry.sock"), "--database", filepath.Join(parent, "entry.db")},
		io.Discard,
		io.Discard,
		daemonDependencies{
			newServer: func(_ string, runtime *entryruntime.Runtime, _ *log.Logger) (daemonServer, error) {
				constructorCalled = true
				captured = runtime
				server := newFakeDaemonServer()
				server.serveErr = errors.New("accept failed")
				return server, nil
			},
			signalSource: inertSignalSource,
			openStore:    store.openCompositionStore,
		},
	)

	if code != 1 {
		t.Fatalf("run() = %d, want 1 (proceeded to serve then accept failed)", code)
	}
	if !constructorCalled {
		t.Fatal("server constructor was not called after composition")
	}
	if captured == nil {
		t.Fatal("composed runtime was not handed to the server constructor")
	}
	want := []string{"open", "migrate", "bootstrap", "seed", "validate", "presets", "compose", "close"}
	if got := store.callOrder(); !slices.Equal(got, want) {
		t.Fatalf("call order = %v, want %v", got, want)
	}
}

// TestCompositionPresetFailurePreventsReadiness는 preset 재조정 실패가 server 미구성,
// socket 미생성, store close, metadata-only stderr로 이어지는지 검증한다.
func TestCompositionPresetFailurePreventsReadiness(t *testing.T) {
	parent := t.TempDir()
	socketPath := filepath.Join(parent, "entry.sock")
	databasePath := filepath.Join(parent, "entry.db")
	store := &compositionStore{fakeDaemonStore: newFakeDaemonStore(), presetsErr: errors.New("preset reconcile failed")}
	constructorCalled := false
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(
		[]string{"--socket", socketPath, "--database", databasePath},
		&stdout,
		&stderr,
		daemonDependencies{
			newServer: func(string, *entryruntime.Runtime, *log.Logger) (daemonServer, error) {
				constructorCalled = true
				return nil, errors.New("unexpected constructor call")
			},
			signalSource: inertSignalSource,
			openStore:    store.openCompositionStore,
		},
	)

	if code != 1 {
		t.Fatalf("run() = %d, want 1", code)
	}
	if stdout.Len() != 0 || stderr.Len() == 0 {
		t.Fatalf("stdout = %q, stderr = %q", stdout.String(), stderr.String())
	}
	if !strings.Contains(stderr.String(), "startup failed") {
		t.Fatalf("stderr = %q, want startup failure", stderr.String())
	}
	if strings.Contains(stderr.String(), databasePath) || strings.Contains(stderr.String(), parent) {
		t.Fatalf("stderr %q must stay metadata-only", stderr.String())
	}
	if constructorCalled {
		t.Fatal("server constructed after preset failure")
	}
	if _, err := os.Lstat(socketPath); !os.IsNotExist(err) {
		t.Fatalf("socket created despite preset failure: %v", err)
	}
	if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "bootstrap", "seed", "validate", "presets", "close"}) {
		t.Fatalf("call order = %v, want [open migrate bootstrap seed validate presets close]", got)
	}
}

// TestCompositionComposeFailurePreventsReadiness는 서비스 조합 실패가 readiness 전에
// 실패 닫기됨을 검증한다. 빈 runtime 폴백은 금지다.
func TestCompositionComposeFailurePreventsReadiness(t *testing.T) {
	parent := t.TempDir()
	socketPath := filepath.Join(parent, "entry.sock")
	store := &compositionStore{fakeDaemonStore: newFakeDaemonStore(), composeErr: errors.New("property service composition failed")}
	constructorCalled := false
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(
		[]string{"--socket", socketPath, "--database", filepath.Join(parent, "entry.db")},
		&stdout,
		&stderr,
		daemonDependencies{
			newServer: func(string, *entryruntime.Runtime, *log.Logger) (daemonServer, error) {
				constructorCalled = true
				return nil, errors.New("unexpected constructor call")
			},
			signalSource: inertSignalSource,
			openStore:    store.openCompositionStore,
		},
	)

	if code != 1 {
		t.Fatalf("run() = %d, want 1", code)
	}
	if constructorCalled {
		t.Fatal("server constructed after composition failure")
	}
	if _, err := os.Lstat(socketPath); !os.IsNotExist(err) {
		t.Fatalf("socket created despite composition failure: %v", err)
	}
	if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "bootstrap", "seed", "validate", "presets", "compose", "close"}) {
		t.Fatalf("call order = %v, want [open migrate bootstrap seed validate presets compose close]", got)
	}
}

// TestComposeWorkspaceServicesExposesPropertyMethodsAndLifecycle는 실제 시드 DB 위에서
// 조합된 runtime이 lifecycle 메서드와 Property 메서드를 모두 노출하는지 검증한다.
func TestComposeWorkspaceServicesExposesPropertyMethodsAndLifecycle(t *testing.T) {
	parent := t.TempDir()
	databasePath := filepath.Join(parent, "entry.db")
	wsctx := prepareCatalogDatabase(t, databasePath)
	ctx := context.Background()
	store, err := sqlite.Open(ctx, databasePath)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = store.Close() }()
	if err := store.ApplyPropertyPresets(ctx, wsctx); err != nil {
		t.Fatal(err)
	}
	loaded, err := sqlite.NewPropertyCatalogRepository(store).Load(ctx, wsctx)
	if err != nil {
		t.Fatal(err)
	}

	runtime, err := composeWorkspaceServices(store, wsctx, loaded.Snapshot)
	if err != nil {
		t.Fatalf("composeWorkspaceServices() error = %v", err)
	}

	lifecycleRequests := []schema.Request{
		{RequestID: "p", Method: schema.MethodPing},
		{RequestID: "h", Method: schema.MethodHealth},
		{RequestID: "v", Method: schema.MethodVersion},
	}
	for _, request := range lifecycleRequests {
		if response := runtime.Dispatch(ctx, request); !response.OK {
			t.Fatalf("%s dispatch error = %+v, want success", request.Method, response.Error)
		}
	}

	listResponse := runtime.Dispatch(ctx, schema.Request{
		RequestID:                    "l",
		Method:                       schema.MethodPropertyDefinitionList,
		PropertyDefinitionListParams: &schema.PropertyDefinitionListParams{PageSize: 256, RequestedPropertyIDs: []string{}},
	})
	if !listResponse.OK {
		t.Fatalf("property.definition.list dispatch error = %+v, want success", listResponse.Error)
	}
	list, ok := listResponse.Result.(schema.PropertyDefinitionListResult)
	if !ok {
		t.Fatalf("result type = %T, want PropertyDefinitionListResult", listResponse.Result)
	}
	presetFound := false
	for _, definition := range list.Definitions {
		if definition.Key == "status" && definition.ValueType == "select" && len(definition.Options) == 5 {
			presetFound = true
		}
	}
	if !presetFound {
		t.Fatalf("preset status definition missing from %d definitions", len(list.Definitions))
	}

	// UnifiedList 계약상 VirtualPath와 ParentRef 중 정확히 하나가 필요하다. 이
	// 슬라이스에는 mount 구성이 없으므로 게이트를 통과한 entry.list가 typed
	// mount_not_found로 실패 닫기되는 것이 정확한 관찰이다.
	entryResponse := runtime.Dispatch(ctx, schema.Request{
		RequestID:       "e",
		Method:          schema.MethodEntryList,
		EntryListParams: &schema.EntryListParams{PageSize: 10, VirtualPath: "/"},
	})
	if entryResponse.OK || entryResponse.Error == nil || entryResponse.Error.Code != schema.ErrorMountNotFound {
		t.Fatalf("entry.list dispatch = %+v, want typed mount_not_found fail-closed", entryResponse)
	}
}
