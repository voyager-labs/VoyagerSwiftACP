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
// migrate, workspace bootstrap/restore, and close. Migration is invoked only
// through this seam, never around it.
type daemonStore interface {
	Migrate(ctx context.Context) error
	BootstrapOrRestoreWorkspace(ctx context.Context) (domainentry.WorkspaceContext, error)
	Close() error
}

type daemonDependencies struct {
	newServer    func(string, *log.Logger) (daemonServer, error)
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
		if _, err := store.BootstrapOrRestoreWorkspace(ctx); err != nil {
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

	server, err := dependencies.newServer(socketPath, logger)
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

func (s sqliteDaemonStore) Close() error {
	return s.store.Close()
}

func productionDependencies() daemonDependencies {
	return daemonDependencies{
		newServer: func(path string, logger *log.Logger) (daemonServer, error) {
			return unixsocket.NewServer(path, entryruntime.New(), logger)
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
