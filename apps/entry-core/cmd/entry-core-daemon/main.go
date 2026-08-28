package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	sqlite "github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite"
	entryruntime "github.com/voyager-labs/voyager-app/apps/entry-core/internal/runtime"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/transport/unixsocket"
)

const daemonUsage = "usage: entry-core-daemon --socket <absolute-path> [--database <absolute-path>]"

// errDatabasePathUnavailable is a metadata-only sentinel (no path embedded)
// returned when the database file cannot be inspected for a reason other than
// it not existing. The caller logs only this class, never the raw *os.PathError
// whose string form would embed the --database path.
var errDatabasePathUnavailable = errors.New("database path unavailable")

type daemonServer interface {
	Serve() error
	Shutdown(<-chan struct{}) error
}

// daemonStore is the seam through which the daemon drives store lifecycle:
// migrate, workspace bootstrap/restore, catalog seed apply, catalog validation,
// preset reconciliation, service composition, and close. Migration and seed
// apply are invoked only through this seam, never around it.
type daemonStore interface {
	Migrate(ctx context.Context) error
	BootstrapOrRestoreWorkspace(ctx context.Context) (domainentry.WorkspaceContext, error)
	ApplyCatalogSeed(ctx context.Context, wsctx domainentry.WorkspaceContext) error
	ValidateActiveCatalog(ctx context.Context, wsctx domainentry.WorkspaceContext) (domainentry.PropertyCatalogSnapshot, error)
	ApplyPropertyPresets(ctx context.Context, wsctx domainentry.WorkspaceContext) error
	ComposeServices(ctx context.Context, wsctx domainentry.WorkspaceContext, snapshot domainentry.PropertyCatalogSnapshot) (*entryruntime.Runtime, error)
	Close() error
}

type daemonDependencies struct {
	newServer    func(string, *entryruntime.Runtime, *log.Logger) (daemonServer, error)
	signalSource func() (<-chan os.Signal, func())
	openStore    func(context.Context, string) (daemonStore, error)
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, productionDependencies()))
}

func run(args []string, stdout io.Writer, stderr io.Writer, dependencies daemonDependencies) int {
	_ = stdout
	socketPath, databasePath, ok := parseDaemonArgs(args)
	if !ok {
		fmt.Fprintln(stderr, daemonUsage)
		return 2
	}

	logger := log.New(stderr, "entry-core-daemon: ", 0)
	signals, stopSignals := dependencies.signalSource()
	defer stopSignals()

	ctx := context.Background()
	var store daemonStore
	var runtime *entryruntime.Runtime
	if databasePath != "" {
		dbExisted, err := dbFileExists(databasePath)
		if err != nil {
			logger.Printf("startup failed: %v", err)
			return 1
		}
		store, err = dependencies.openStore(ctx, databasePath)
		if err != nil {
			logger.Printf("startup failed: %v", err)
			return 1
		}
		if err := store.Migrate(ctx); err != nil {
			logger.Printf("startup failed: %v", err)
			_ = store.Close()
			return 1
		}
		wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
		if err != nil {
			logger.Printf("startup failed: %v", err)
			_ = store.Close()
			return 1
		}
		if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
			logger.Printf("startup failed: %v", err)
			_ = store.Close()
			return 1
		}
		// 시드 트랜잭션 성공 뒤, 소켓 readiness 전에 활성 카탈로그 전체를 로드·검증한다.
		// 고아 참조나 invalid 스냅샷은 기동을 실패 닫기한다.
		snapshot, err := store.ValidateActiveCatalog(ctx, wsctx)
		if err != nil {
			logger.Printf("startup failed: %v", err)
			_ = store.Close()
			return 1
		}
		// 카탈로그 검증 뒤, readiness 전에 Status/Project/Priority preset을 멱등
		// 재조정한다. 사용자가 편집한 행은 절대 덮쓰지 않는다.
		if err := store.ApplyPropertyPresets(ctx, wsctx); err != nil {
			logger.Printf("startup failed: %v", err)
			_ = store.Close()
			return 1
		}
		// preset 조정이 새 DB에서 카탈로그를 바꿀 수 있으므로 조립 전 스냅샷을
		// 다시 로드한다. 이전 스냅샷으로 조립하면 프리셋 정의가 service.catalog에
		// 빠져 재시작 전까지 overlay가 그 ID를 거절한다(composition_test의
		// reconcile → load → compose 순서와 같다).
		snapshot, err = store.ValidateActiveCatalog(ctx, wsctx)
		if err != nil {
			logger.Printf("startup failed: %v", err)
			_ = store.Close()
			return 1
		}
		// 조합 실패는 빈 runtime 폴백 없이 readiness 전에 실패 닫기한다.
		runtime, err = store.ComposeServices(ctx, wsctx, snapshot)
		if err != nil {
			logger.Printf("startup failed: %v", err)
			_ = store.Close()
			return 1
		}
		if dbExisted {
			logger.Print("workspace metadata restored")
		} else {
			logger.Print("workspace metadata initialized")
		}
	}
	if runtime == nil {
		// --database 없음 계약: DB-less 모드는 기존과 동일하게 lifecycle 전용
		// runtime으로 구성된다(조합 실패 경로가 아니다).
		runtime = entryruntime.New()
	}

	server, err := dependencies.newServer(socketPath, runtime, logger)
	if err != nil {
		logger.Printf("startup failed: %v", err)
		if store != nil {
			_ = store.Close()
		}
		return 1
	}

	serveDone := make(chan error, 1)
	go func() {
		serveDone <- server.Serve()
	}()
	logger.Print("started in foreground")

	select {
	case serveErr := <-serveDone:
		if serveErr != nil {
			logger.Printf("serve failed: %v", serveErr)
		} else {
			logger.Print("serve stopped unexpectedly")
		}
		if shutdownErr := server.Shutdown(nil); shutdownErr != nil {
			logger.Printf("cleanup after serve failure failed: %v", shutdownErr)
		}
		if store != nil {
			if closeErr := store.Close(); closeErr != nil {
				logger.Printf("cleanup after serve failure failed: %v", closeErr)
			}
		}
		return 1
	case received := <-signals:
		logger.Printf("received %s; shutting down", received)
	}

	force := make(chan struct{})
	shutdownDone := make(chan error, 1)
	go func() {
		shutdownDone <- server.Shutdown(force)
	}()

	forceTriggered := false
	for {
		select {
		case received := <-signals:
			if !forceTriggered {
				close(force)
				forceTriggered = true
				logger.Printf("received second %s; forcing shutdown", received)
			}
		case shutdownErr := <-shutdownDone:
			serveErr := <-serveDone
			var closeErr error
			if store != nil {
				closeErr = store.Close()
			}
			if shutdownErr != nil {
				logger.Printf("shutdown failed: %v", shutdownErr)
			}
			if serveErr != nil {
				logger.Printf("serve failed during shutdown: %v", serveErr)
			}
			if closeErr != nil {
				logger.Printf("store close failed: %v", closeErr)
			}
			if shutdownErr != nil || serveErr != nil || closeErr != nil {
				return 1
			}
			logger.Print("stopped")
			return 0
		}
	}
}

// parseDaemonArgs accepts --socket and an optional --database in either order,
// each at most once. --socket is required and must be absolute; --database,
// when present, must be non-empty and absolute. Usage violations return ok
// false (exit 2). An absent --database keeps the DB-less behavior.
func parseDaemonArgs(args []string) (socketPath, databasePath string, ok bool) {
	var socketSeen, databaseSeen bool
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--socket":
			if socketSeen {
				return "", "", false
			}
			socketSeen = true
			if i+1 >= len(args) {
				return "", "", false
			}
			i++
			socketPath = args[i]
		case "--database":
			if databaseSeen {
				return "", "", false
			}
			databaseSeen = true
			if i+1 >= len(args) {
				return "", "", false
			}
			i++
			databasePath = args[i]
		default:
			return "", "", false
		}
	}
	if !socketSeen || socketPath == "" || !filepath.IsAbs(socketPath) {
		return "", "", false
	}
	if databaseSeen && (databasePath == "" || !filepath.IsAbs(databasePath)) {
		return "", "", false
	}
	return socketPath, databasePath, true
}

// dbFileExists reports whether the database file already exists, so the daemon
// can distinguish a fresh initialize from a restore on an existing database.
func dbFileExists(path string) (bool, error) {
	_, err := os.Lstat(path)
	if err == nil {
		return true, nil
	}
	if os.IsNotExist(err) {
		return false, nil
	}
	return false, errDatabasePathUnavailable
}

func productionDependencies() daemonDependencies {
	return daemonDependencies{
		newServer: func(path string, runtime *entryruntime.Runtime, logger *log.Logger) (daemonServer, error) {
			return unixsocket.NewServer(path, runtime, logger)
		},
		signalSource: func() (<-chan os.Signal, func()) {
			signals := make(chan os.Signal, 2)
			signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
			return signals, func() { signal.Stop(signals) }
		},
		openStore: func(ctx context.Context, path string) (daemonStore, error) {
			store, err := sqlite.Open(ctx, path)
			if err != nil {
				return nil, err
			}
			return sqliteDaemonStore{store: store}, nil
		},
	}
}
