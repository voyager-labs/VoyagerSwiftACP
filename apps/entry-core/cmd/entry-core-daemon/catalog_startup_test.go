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

	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	sqlite "github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite"
)

// TestCatalogStartupOrder는 daemon이 DB startup 시
// open → migrate → bootstrap → seed → newServer 순서로 진행하는지 검증한다.
// seed는 bootstrap에서 얻은 workspace identity를 사용해 catalog를 적용하며,
// 그 전에 server constructor가 호출되면 안 된다.
func TestCatalogStartupOrder(t *testing.T) {
	parent := t.TempDir()
	databasePath := filepath.Join(parent, "entry.db")
	store := newFakeDaemonStore()
	server := newFakeDaemonServer()
	server.serveErr = errors.New("accept failed")
	constructorCalled := false
	var stderr bytes.Buffer

	code := run(
		[]string{"--socket", filepath.Join(parent, "entry.sock"), "--database", databasePath},
		io.Discard,
		&stderr,
		daemonDependencies{
			newServer: func(string, *log.Logger) (daemonServer, error) {
				constructorCalled = true
				return server, nil
			},
			signalSource: inertSignalSource,
			openStore:    store.openStore,
		},
	)
	if code != 1 {
		t.Fatalf("run() = %d, want 1 (proceeded to serve then accept failed)", code)
	}
	if !constructorCalled {
		t.Fatal("server constructor was not called after seed success")
	}
	if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "bootstrap", "seed", "validate", "close"}) {
		t.Fatalf("call order = %v, want [open migrate bootstrap seed validate close]", got)
	}
	if strings.Contains(stderr.String(), "startup failed") {
		t.Fatalf("stderr = %q, want no startup failure", stderr.String())
	}
}

// TestCatalogStartupSeedFailure는 seed 실패 시 exit 1, store close, metadata-only
// stderr, server 미구성, socket 미생성을 보장한다.
func TestCatalogStartupSeedFailure(t *testing.T) {
	parent := t.TempDir()
	databasePath := filepath.Join(parent, "entry.db")
	store := newFakeDaemonStore()
	store.seedErr = errors.New("catalog seed digest mismatch")
	constructorCalled := false
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(
		[]string{"--socket", filepath.Join(parent, "entry.sock"), "--database", databasePath},
		&stdout,
		&stderr,
		daemonDependencies{
			newServer: func(string, *log.Logger) (daemonServer, error) {
				constructorCalled = true
				return nil, errors.New("unexpected constructor call")
			},
			signalSource: inertSignalSource,
			openStore:    store.openStore,
		},
	)
	if code != 1 {
		t.Fatalf("run() = %d, want 1", code)
	}
	if stdout.Len() != 0 || stderr.Len() == 0 {
		t.Fatalf("stdout = %q, stderr = %q", stdout.String(), stderr.String())
	}
	if constructorCalled {
		t.Fatal("server constructed after seed failure")
	}
	if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "bootstrap", "seed", "close"}) {
		t.Fatalf("call order = %v, want [open migrate bootstrap seed close]", got)
	}
}

// TestCatalogStartupMigrateFailure는 migrate 실패 시 server 미구성, socket 미생성,
// stderr metadata-only를 보장한다. seed는 migrate 전이므로 호출되지 않는다.
func TestCatalogStartupMigrateFailure(t *testing.T) {
	parent := t.TempDir()
	databasePath := filepath.Join(parent, "entry.db")
	store := newFakeDaemonStore()
	store.migrateErr = errors.New("migration failed")
	constructorCalled := false
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(
		[]string{"--socket", filepath.Join(parent, "entry.sock"), "--database", databasePath},
		&stdout,
		&stderr,
		daemonDependencies{
			newServer: func(string, *log.Logger) (daemonServer, error) {
				constructorCalled = true
				return nil, errors.New("unexpected constructor call")
			},
			signalSource: inertSignalSource,
			openStore:    store.openStore,
		},
	)
	if code != 1 {
		t.Fatalf("run() = %d, want 1", code)
	}
	if stdout.Len() != 0 || stderr.Len() == 0 {
		t.Fatalf("stdout = %q, stderr = %q", stdout.String(), stderr.String())
	}
	if constructorCalled {
		t.Fatal("server constructed after migrate failure")
	}
	if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "close"}) {
		t.Fatalf("call order = %v, want [open migrate close]", got)
	}
}

// TestCatalogStartupWorkspaceFailure는 workspace bootstrap 실패 시 server 미구성,
// socket 미생성, stderr metadata-only를 보장한다. seed는 bootstrap 후이므로
// 호출되지 않는다.
func TestCatalogStartupWorkspaceFailure(t *testing.T) {
	parent := t.TempDir()
	databasePath := filepath.Join(parent, "entry.db")
	store := newFakeDaemonStore()
	store.bootstrapErr = errors.New("workspace identity corrupt")
	constructorCalled := false
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(
		[]string{"--socket", filepath.Join(parent, "entry.sock"), "--database", databasePath},
		&stdout,
		&stderr,
		daemonDependencies{
			newServer: func(string, *log.Logger) (daemonServer, error) {
				constructorCalled = true
				return nil, errors.New("unexpected constructor call")
			},
			signalSource: inertSignalSource,
			openStore:    store.openStore,
		},
	)
	if code != 1 {
		t.Fatalf("run() = %d, want 1", code)
	}
	if stdout.Len() != 0 || stderr.Len() == 0 {
		t.Fatalf("stdout = %q, stderr = %q", stdout.String(), stderr.String())
	}
	if constructorCalled {
		t.Fatal("server constructed after workspace failure")
	}
	if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "bootstrap", "close"}) {
		t.Fatalf("call order = %v, want [open migrate bootstrap close]", got)
	}
}

// TestCatalogStartupValidateFailureFailsClosed는 seed 성공 뒤 활성 카탈로그 검증이
// 실패하면 exit 1, server 미구성, metadata-only stderr를 보장한다.
func TestCatalogStartupValidateFailureFailsClosed(t *testing.T) {
	parent := t.TempDir()
	databasePath := filepath.Join(parent, "entry.db")
	store := newFakeDaemonStore()
	store.validateErr = sqlite.ErrCatalogOrphanRef
	constructorCalled := false
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(
		[]string{"--socket", filepath.Join(parent, "entry.sock"), "--database", databasePath},
		&stdout,
		&stderr,
		daemonDependencies{
			newServer: func(string, *log.Logger) (daemonServer, error) {
				constructorCalled = true
				return nil, errors.New("unexpected constructor call")
			},
			signalSource: inertSignalSource,
			openStore:    store.openStore,
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
	if constructorCalled {
		t.Fatal("server constructed after catalog validation failure")
	}
	if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "bootstrap", "seed", "validate", "close"}) {
		t.Fatalf("call order = %v, want [open migrate bootstrap seed validate close]", got)
	}
}

// prepareCatalogDatabase는 실제 sqlite store로 DB를 열어 migrate → workspace
// bootstrap → seed 적용까지 수행하고 닫는다. run()은 이어서 같은 파일을 연다.
// sqlite.Open은 DB 부모 디렉터리에 정확한 0700 모드를 요구하므로 umask 영향 없이
// 명시적으로 보정한다.
func prepareCatalogDatabase(t *testing.T, databasePath string) domainentry.WorkspaceContext {
	t.Helper()
	requireParentMode(t, databasePath)
	ctx := context.Background()
	store, err := sqlite.Open(ctx, databasePath)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = store.Close() }()
	if err := sqlite.MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatal(err)
	}
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatal(err)
	}
	return wsctx
}

// requireParentMode는 DB 파일 부모 디렉터리가 store 경로 계약(비심볼릭 링크,
// 유효 사용자 소유, 정확히 0700)을 만족하게 강제한다. t.TempDir()의 중간 디렉터리는
// 모드가 다를 수 있어 테스트 전용 data 디렉터리를 만들어 사용한다.
func requireParentMode(t *testing.T, databasePath string) {
	t.Helper()
	parent := filepath.Dir(databasePath)
	if err := os.MkdirAll(parent, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(parent, 0700); err != nil {
		t.Fatal(err)
	}
}

func openInjectedDatabase(t *testing.T, databasePath string, mutate func(tx *gorm.DB) error) {
	t.Helper()
	ctx := context.Background()
	store, err := sqlite.Open(ctx, databasePath)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = store.Close() }()
	if err := store.WithinTx(ctx, mutate); err != nil {
		t.Fatal(err)
	}
}

// TestDaemonStartupFailsClosedOnNonSystemActiveOrphan는 실제 시드 DB에 non-system
// 소유 active 바인딩이 tombstoned/부재 정의를 가리킬 때 기동이 소켓 생성 전에 실패
// 닫기함을 보장한다.
func TestDaemonStartupFailsClosedOnNonSystemActiveOrphan(t *testing.T) {
	parent := t.TempDir()
	databasePath := filepath.Join(parent, "entry.db")
	socketPath := filepath.Join(parent, "entry.sock")
	wsctx := prepareCatalogDatabase(t, databasePath)
	// FK가 binding→definition 참조 무결성을 강제하므로 orphan은 유효한 active
	// user 바인딩을 만든 뒤 참조된 정의를 tombstoned로 전환해 표현한다.
	openInjectedDatabase(t, databasePath, func(tx *gorm.DB) error {
		userDefID := domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12399")
		definition := sqlite.WorkspacePropertyDefinitionRow{
			WorkspaceID: wsctx.ID.Bytes(), PropertyID: userDefID.Bytes(),
			Origin: "user_defined", IdentityScheme: "voyager_issued",
			Namespace: "user", CanonicalKey: "user.orphan.title", DisplayName: "Orphan Title",
			ValueType: "text", Cardinality: "one", Provenance: "user_defined", LifecycleState: "active",
		}
		if err := tx.Create(&definition).Error; err != nil {
			return err
		}
		var seeded sqlite.SourcePropertyDescriptorRow
		if err := tx.First(&seeded).Error; err != nil {
			return err
		}
		descriptor := sqlite.SourcePropertyDescriptorRow{
			WorkspaceID: wsctx.ID.Bytes(),
			ProviderID:  "user.provider", SourceInstanceID: seeded.SourceInstanceID,
			ScopeKind: "workspace", ScopeExternalID: "workspace", ExternalPropertyID: "user.orphan.external",
			AuthorityKind: "provider", NativeType: "string", NativeCardinality: "one",
			SourceReadable: true, LifecycleState: "active",
		}
		if err := tx.Create(&descriptor).Error; err != nil {
			return err
		}
		binding := sqlite.PropertyBindingRow{
			WorkspaceID: wsctx.ID.Bytes(), PropertyID: userDefID.Bytes(),
			ProviderID: descriptor.ProviderID, SourceInstanceID: descriptor.SourceInstanceID,
			ScopeKind: descriptor.ScopeKind, ScopeExternalID: descriptor.ScopeExternalID,
			ExternalPropertyID: descriptor.ExternalPropertyID,
			ReadTransform:      "identity", Direction: "read", EffectiveReadable: true,
			MappingProvenance: "user_defined", ApprovalState: "approved", LifecycleState: "active",
		}
		if err := tx.Create(&binding).Error; err != nil {
			return err
		}
		return tx.Model(&sqlite.WorkspacePropertyDefinitionRow{}).
			Where("workspace_id = ? AND property_id = ?", wsctx.ID.Bytes(), userDefID.Bytes()).
			Update("lifecycle_state", "tombstoned").Error
	})
	constructorCalled := false

	deps := productionDependencies()
	deps.newServer = func(string, *log.Logger) (daemonServer, error) {
		constructorCalled = true
		server := newFakeDaemonServer()
		server.serveErr = errors.New("accept failed")
		return server, nil
	}
	deps.signalSource = inertSignalSource
	var stderr bytes.Buffer
	code := run([]string{"--socket", socketPath, "--database", databasePath}, io.Discard, &stderr, deps)

	if code != 1 {
		t.Fatalf("run() = %d, want 1; stderr=%q", code, stderr.String())
	}
	if constructorCalled {
		t.Fatal("server constructed despite orphaned active user binding")
	}
	if !strings.Contains(stderr.String(), "startup failed") {
		t.Fatalf("stderr = %q, want startup failure", stderr.String())
	}
}

// TestDaemonStartupAcceptsValidMixedOwnerCatalog는 시드(system) 행과 참조 일관성이
// 있는 user 소유 정의·디스크립터·바인딩이 공존할 때 기동이 계속됨을 보장한다.
func TestDaemonStartupAcceptsValidMixedOwnerCatalog(t *testing.T) {
	parent := t.TempDir()
	databasePath := filepath.Join(parent, "entry.db")
	socketPath := filepath.Join(parent, "entry.sock")
	wsctx := prepareCatalogDatabase(t, databasePath)
	openInjectedDatabase(t, databasePath, func(tx *gorm.DB) error {
		userDefID := domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12398")
		definition := sqlite.WorkspacePropertyDefinitionRow{
			WorkspaceID: wsctx.ID.Bytes(), PropertyID: userDefID.Bytes(),
			Origin: "user_defined", IdentityScheme: "voyager_issued",
			Namespace: "user", CanonicalKey: "user.custom.title", DisplayName: "Custom Title",
			ValueType: "text", Cardinality: "one", Provenance: "user_defined", LifecycleState: "active",
		}
		if err := tx.Create(&definition).Error; err != nil {
			return err
		}
		var seeded sqlite.SourcePropertyDescriptorRow
		if err := tx.First(&seeded).Error; err != nil {
			return err
		}
		descriptor := sqlite.SourcePropertyDescriptorRow{
			WorkspaceID: wsctx.ID.Bytes(),
			ProviderID:  "user.provider", SourceInstanceID: seeded.SourceInstanceID,
			ScopeKind: "workspace", ScopeExternalID: "workspace", ExternalPropertyID: "user.custom.external",
			AuthorityKind: "provider", NativeType: "string", NativeCardinality: "one",
			SourceReadable: true, LifecycleState: "active",
		}
		if err := tx.Create(&descriptor).Error; err != nil {
			return err
		}
		binding := sqlite.PropertyBindingRow{
			WorkspaceID: wsctx.ID.Bytes(), PropertyID: userDefID.Bytes(),
			ProviderID: descriptor.ProviderID, SourceInstanceID: descriptor.SourceInstanceID,
			ScopeKind: descriptor.ScopeKind, ScopeExternalID: descriptor.ScopeExternalID,
			ExternalPropertyID: descriptor.ExternalPropertyID,
			ReadTransform:      "identity", Direction: "read", EffectiveReadable: true,
			MappingProvenance: "user", ApprovalState: "approved", LifecycleState: "active",
		}
		return tx.Create(&binding).Error
	})
	constructorCalled := false

	deps := productionDependencies()
	deps.newServer = func(string, *log.Logger) (daemonServer, error) {
		constructorCalled = true
		server := newFakeDaemonServer()
		server.serveErr = errors.New("accept failed")
		return server, nil
	}
	deps.signalSource = inertSignalSource
	var stderr bytes.Buffer
	code := run([]string{"--socket", socketPath, "--database", databasePath}, io.Discard, &stderr, deps)

	if strings.Contains(stderr.String(), "startup failed") {
		t.Fatalf("stderr = %q, want clean mixed-owner startup", stderr.String())
	}
	if !constructorCalled || code != 1 {
		t.Fatalf("run() = %d constructor=%v, want proceed to serve then accept failure", code, constructorCalled)
	}
}

// TestCatalogStartupDBLessNoStore는 --database 없이 실행하면 store/seed가 전혀
// 열리지 않고 server만 구성됨을 보장한다.
func TestCatalogStartupDBLessNoStore(t *testing.T) {
	server := newFakeDaemonServer()
	server.serveErr = errors.New("accept failed")
	storeOpened := false

	code := run(
		[]string{"--socket", "/tmp/entry.sock"},
		io.Discard,
		io.Discard,
		daemonDependencies{
			newServer:    func(string, *log.Logger) (daemonServer, error) { return server, nil },
			signalSource: inertSignalSource,
			openStore: func(ctx context.Context, _ string) (daemonStore, error) {
				storeOpened = true
				return nil, errors.New("store must not open without --database")
			},
		},
	)
	if code != 1 {
		t.Fatalf("run() = %d, want 1 (proceeded to serve then accept failed)", code)
	}
	if storeOpened {
		t.Fatal("store opened without --database")
	}
}
