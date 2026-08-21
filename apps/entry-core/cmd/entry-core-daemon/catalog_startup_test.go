package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log"
	"path/filepath"
	"slices"
	"strings"
	"testing"
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
	if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "bootstrap", "seed", "close"}) {
		t.Fatalf("call order = %v, want [open migrate bootstrap seed close]", got)
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
