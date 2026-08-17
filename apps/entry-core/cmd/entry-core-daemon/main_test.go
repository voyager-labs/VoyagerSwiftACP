package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

func TestDaemonUsageErrors(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{name: "missing socket", args: nil},
		{name: "empty socket", args: []string{"--socket", ""}},
		{name: "relative socket", args: []string{"--socket", "entry.sock"}},
		{name: "unknown flag", args: []string{"--unknown", "/tmp/entry.sock"}},
		{name: "extra positional", args: []string{"--socket", "/tmp/entry.sock", "extra"}},
		{name: "equals syntax", args: []string{"--socket=/tmp/entry.sock"}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var stdout bytes.Buffer
			var stderr bytes.Buffer
			constructorCalled := false
			dependencies := daemonDependencies{
				newServer: func(string, *log.Logger) (daemonServer, error) {
					constructorCalled = true
					return nil, errors.New("unexpected constructor call")
				},
				signalSource: inertSignalSource,
			}

			if code := run(test.args, &stdout, &stderr, dependencies); code != 2 {
				t.Fatalf("run() = %d, want 2", code)
			}
			if stdout.Len() != 0 {
				t.Fatalf("stdout = %q, want empty", stdout.String())
			}
			if stderr.Len() == 0 {
				t.Fatal("stderr is empty")
			}
			if constructorCalled {
				t.Fatal("server constructor called for invalid argv")
			}
		})
	}
}

func TestDaemonDatabaseArgs(t *testing.T) {
	acceptCases := []struct {
		name string
		args []string
	}{
		{name: "database after socket", args: []string{"--socket", "/tmp/entry.sock", "--database", "/tmp/entry.db"}},
		{name: "database before socket", args: []string{"--database", "/tmp/entry.db", "--socket", "/tmp/entry.sock"}},
		{name: "absent database still starts", args: []string{"--socket", "/tmp/entry.sock"}},
	}
	for _, test := range acceptCases {
		t.Run(test.name, func(t *testing.T) {
			store := newFakeDaemonStore()
			server := newFakeDaemonServer()
			server.serveErr = errors.New("accept failed")
			code := run(
				test.args,
				io.Discard,
				io.Discard,
				daemonDependencies{
					newServer:    func(string, *log.Logger) (daemonServer, error) { return server, nil },
					signalSource: inertSignalSource,
					openStore:    store.openStore,
				},
			)
			if code != 1 {
				t.Fatalf("run() = %d, want 1 (proceeded past parse to serve)", code)
			}
		})
	}

	rejectCases := []struct {
		name string
		args []string
	}{
		{name: "relative database", args: []string{"--socket", "/tmp/entry.sock", "--database", "relative.db"}},
		{name: "empty database", args: []string{"--socket", "/tmp/entry.sock", "--database", ""}},
		{name: "duplicate database", args: []string{"--socket", "/tmp/entry.sock", "--database", "/tmp/a.db", "--database", "/tmp/b.db"}},
	}
	for _, test := range rejectCases {
		t.Run(test.name, func(t *testing.T) {
			var stdout bytes.Buffer
			var stderr bytes.Buffer
			constructorCalled := false
			code := run(
				test.args,
				&stdout,
				&stderr,
				daemonDependencies{
					newServer: func(string, *log.Logger) (daemonServer, error) {
						constructorCalled = true
						return nil, errors.New("unexpected constructor call")
					},
					signalSource: inertSignalSource,
				},
			)
			if code != 2 {
				t.Fatalf("run() = %d, want 2", code)
			}
			if stdout.Len() != 0 {
				t.Fatalf("stdout = %q, want empty", stdout.String())
			}
			if stderr.Len() == 0 {
				t.Fatal("stderr is empty")
			}
			if constructorCalled {
				t.Fatal("server constructed for invalid --database")
			}
		})
	}
}

func TestDaemonWorkspaceMetadataLog(t *testing.T) {
	tests := []struct {
		name      string
		precreate bool
		wantLog   string
	}{
		{name: "fresh database initializes", precreate: false, wantLog: "workspace metadata initialized"},
		{name: "existing database restores", precreate: true, wantLog: "workspace metadata restored"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			root := t.TempDir()
			dbPath := filepath.Join(root, "entry.db")
			if test.precreate {
				if err := os.WriteFile(dbPath, []byte("existing"), 0o600); err != nil {
					t.Fatal(err)
				}
			}
			store := newFakeDaemonStore()
			server := newFakeDaemonServer()
			server.serveErr = errors.New("accept failed")
			var stdout bytes.Buffer
			var stderr bytes.Buffer
			code := run(
				[]string{"--socket", "/tmp/entry.sock", "--database", dbPath},
				&stdout,
				&stderr,
				daemonDependencies{
					newServer:    func(string, *log.Logger) (daemonServer, error) { return server, nil },
					signalSource: inertSignalSource,
					openStore:    store.openStore,
				},
			)
			if code != 1 {
				t.Fatalf("run() = %d, want 1 (proceeded to serve)", code)
			}
			if !strings.Contains(stderr.String(), test.wantLog) {
				t.Fatalf("stderr = %q, want it to contain %q", stderr.String(), test.wantLog)
			}
			if strings.Contains(stderr.String(), "startup failed") {
				t.Fatalf("stderr = %q, want no startup failure", stderr.String())
			}
		})
	}
}

func TestDaemonDatabaseLifecycleLog(t *testing.T) {
	tests := []struct {
		name       string
		createFile bool
		wantLog    string
	}{
		{name: "fresh database initializes", createFile: false, wantLog: "workspace metadata initialized"},
		{name: "existing database restores", createFile: true, wantLog: "workspace metadata restored"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			parent := t.TempDir()
			databasePath := filepath.Join(parent, "entry.db")
			if test.createFile {
				if err := os.WriteFile(databasePath, nil, 0o600); err != nil {
					t.Fatal(err)
				}
			}

			store := newFakeDaemonStore()
			server := newFakeDaemonServer()
			server.serveErr = errors.New("accept failed")
			var stdout bytes.Buffer
			var stderr bytes.Buffer
			code := run(
				[]string{"--socket", filepath.Join(parent, "entry.sock"), "--database", databasePath},
				&stdout,
				&stderr,
				daemonDependencies{
					newServer:    func(string, *log.Logger) (daemonServer, error) { return server, nil },
					signalSource: inertSignalSource,
					openStore:    store.openStore,
				},
			)
			if code != 1 {
				t.Fatalf("run() = %d, want 1; stderr = %q", code, stderr.String())
			}
			if stdout.Len() != 0 {
				t.Fatalf("stdout = %q, want empty", stdout.String())
			}
			if !strings.Contains(stderr.String(), test.wantLog) {
				t.Fatalf("stderr = %q, want it to contain %q", stderr.String(), test.wantLog)
			}
			if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "bootstrap", "close"}) {
				t.Fatalf("call order = %v, want [open migrate bootstrap close]", got)
			}
		})
	}
}

func TestDaemonForegroundGracefulShutdown(t *testing.T) {
	signals := make(chan os.Signal, 2)
	server := newFakeDaemonServer()
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	result := make(chan int, 1)
	go func() {
		result <- run(
			[]string{"--socket", "/tmp/entry.sock"},
			&stdout,
			&stderr,
			daemonDependencies{
				newServer:    func(string, *log.Logger) (daemonServer, error) { return server, nil },
				signalSource: func() (<-chan os.Signal, func()) { return signals, func() {} },
			},
		)
	}()

	select {
	case <-server.serving:
	case <-time.After(time.Second):
		t.Fatal("Serve was not started")
	}
	signals <- syscall.SIGTERM

	select {
	case code := <-result:
		if code != 0 {
			t.Fatalf("run() = %d, want 0; stderr = %q", code, stderr.String())
		}
	case <-time.After(time.Second):
		t.Fatal("run did not return after shutdown")
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty", stdout.String())
	}
	if server.forceObserved() {
		t.Fatal("first signal unexpectedly forced shutdown")
	}
}

func TestDaemonSecondSignalClosesForceTrigger(t *testing.T) {
	signals := make(chan os.Signal, 2)
	server := newFakeDaemonServer()
	server.waitForForce = true
	result := make(chan int, 1)
	go func() {
		result <- run(
			[]string{"--socket", "/tmp/entry.sock"},
			io.Discard,
			io.Discard,
			daemonDependencies{
				newServer:    func(string, *log.Logger) (daemonServer, error) { return server, nil },
				signalSource: func() (<-chan os.Signal, func()) { return signals, func() {} },
			},
		)
	}()

	waitForSignal(t, server.serving, "Serve start")
	signals <- syscall.SIGTERM
	select {
	case <-server.shutdownStarted:
	case <-time.After(time.Second):
		t.Fatal("first signal did not start shutdown")
	}
	signals <- syscall.SIGINT

	select {
	case code := <-result:
		if code != 0 {
			t.Fatalf("run() = %d, want 0", code)
		}
	case <-time.After(time.Second):
		t.Fatal("second signal did not force shutdown")
	}
	if !server.forceObserved() {
		t.Fatal("force trigger was not closed")
	}
}

func TestDaemonFailureExitMapping(t *testing.T) {
	t.Run("unsafe startup", func(t *testing.T) {
		parent := t.TempDir()
		if err := os.Chmod(parent, 0o755); err != nil {
			t.Fatal(err)
		}
		var stdout bytes.Buffer
		var stderr bytes.Buffer
		code := run(
			[]string{"--socket", filepath.Join(parent, "entry.sock")},
			&stdout,
			&stderr,
			productionDependencies(),
		)
		if code != 1 {
			t.Fatalf("run() = %d, want 1", code)
		}
		if stdout.Len() != 0 || stderr.Len() == 0 {
			t.Fatalf("stdout = %q, stderr = %q", stdout.String(), stderr.String())
		}
	})

	t.Run("serve failure", func(t *testing.T) {
		server := newFakeDaemonServer()
		server.serveErr = errors.New("accept failed")
		var stdout bytes.Buffer
		var stderr bytes.Buffer
		code := run(
			[]string{"--socket", "/tmp/entry.sock"},
			&stdout,
			&stderr,
			daemonDependencies{
				newServer:    func(string, *log.Logger) (daemonServer, error) { return server, nil },
				signalSource: inertSignalSource,
			},
		)
		if code != 1 {
			t.Fatalf("run() = %d, want 1", code)
		}
		if stdout.Len() != 0 || stderr.Len() == 0 {
			t.Fatalf("stdout = %q, stderr = %q", stdout.String(), stderr.String())
		}
		select {
		case <-server.shutdownStarted:
		default:
			t.Fatal("Shutdown was not called after Serve failure")
		}
	})

	for _, test := range []struct {
		name string
		err  error
	}{
		{name: "cleanup failure", err: errors.New("remove owned Unix socket")},
		{name: "unsatisfied final wait", err: errors.New("handlers did not stop")},
	} {
		t.Run(test.name, func(t *testing.T) {
			signals := make(chan os.Signal, 1)
			server := newFakeDaemonServer()
			server.shutdownErr = test.err
			result := make(chan int, 1)
			go func() {
				result <- run(
					[]string{"--socket", "/tmp/entry.sock"},
					io.Discard,
					io.Discard,
					daemonDependencies{
						newServer:    func(string, *log.Logger) (daemonServer, error) { return server, nil },
						signalSource: func() (<-chan os.Signal, func()) { return signals, func() {} },
					},
				)
			}()
			waitForSignal(t, server.serving, "Serve start")
			signals <- syscall.SIGTERM
			select {
			case code := <-result:
				if code != 1 {
					t.Fatalf("run() = %d, want 1", code)
				}
			case <-time.After(time.Second):
				t.Fatal("run did not return after shutdown failure")
			}
		})
	}

	t.Run("database open failure", func(t *testing.T) {
		store := newFakeDaemonStore()
		store.openErr = errors.New("database open failed")
		var stdout bytes.Buffer
		var stderr bytes.Buffer
		constructorCalled := false
		code := run(
			[]string{"--socket", "/tmp/entry.sock", "--database", "/tmp/entry.db"},
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
			t.Fatal("server constructed after open failure")
		}
		if got := store.callOrder(); !slices.Equal(got, []string{"open"}) {
			t.Fatalf("call order = %v, want [open]", got)
		}
	})

	t.Run("database migrate failure", func(t *testing.T) {
		store := newFakeDaemonStore()
		store.migrateErr = errors.New("migration failed")
		constructorCalled := false
		code := run(
			[]string{"--socket", "/tmp/entry.sock", "--database", "/tmp/entry.db"},
			io.Discard,
			io.Discard,
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
		if constructorCalled {
			t.Fatal("server constructed after migrate failure")
		}
		if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "close"}) {
			t.Fatalf("call order = %v, want [open migrate close]", got)
		}
	})

	t.Run("database bootstrap failure", func(t *testing.T) {
		store := newFakeDaemonStore()
		store.bootstrapErr = errors.New("workspace metadata")
		constructorCalled := false
		code := run(
			[]string{"--socket", "/tmp/entry.sock", "--database", "/tmp/entry.db"},
			io.Discard,
			io.Discard,
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
		if constructorCalled {
			t.Fatal("server constructed after bootstrap failure")
		}
		if got := store.callOrder(); !slices.Equal(got, []string{"open", "migrate", "bootstrap", "close"}) {
			t.Fatalf("call order = %v, want [open migrate bootstrap close]", got)
		}
	})
}
func TestDaemonSignalSubprocess(t *testing.T) {
	for _, signal := range []os.Signal{os.Interrupt, syscall.SIGTERM} {
		t.Run(signal.String(), func(t *testing.T) {
			process := startDaemonHelper(t)
			if err := process.command.Process.Signal(signal); err != nil {
				t.Fatal(err)
			}
			result := waitForDaemon(t, process, 3*time.Second)
			assertSuccessfulDaemonExit(t, process, result)
		})
	}
}

func TestDaemonSecondSignalSubprocessSkipsGrace(t *testing.T) {
	process := startDaemonHelper(t)
	connection, err := net.DialTimeout("unix", process.socketPath, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	secret := "UNIQUE-REQUEST-PAYLOAD-SECRET"
	if _, err := connection.Write([]byte(`{"request_id":"raw-id","params":{"secret":"` + secret)); err != nil {
		t.Fatal(err)
	}
	defer connection.Close()

	started := time.Now()
	if err := process.command.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	time.Sleep(100 * time.Millisecond)
	if err := process.command.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	result := waitForDaemon(t, process, 3*time.Second)
	if elapsed := time.Since(started); elapsed >= 3*time.Second {
		t.Fatalf("forced shutdown took %v", elapsed)
	}
	assertSuccessfulDaemonExit(t, process, result)
	for _, forbidden := range []string{secret, "params", "raw-id"} {
		if strings.Contains(process.stderr.String(), forbidden) {
			t.Fatalf("stderr contains request data %q: %q", forbidden, process.stderr.String())
		}
	}
}

func TestDaemonProcessHelper(t *testing.T) {
	if os.Getenv("ENTRY_CORE_DAEMON_TEST_HELPER") != "1" {
		return
	}
	separator := -1
	for index, argument := range os.Args {
		if argument == "--" {
			separator = index
			break
		}
	}
	if separator < 0 {
		os.Exit(2)
	}
	os.Exit(run(os.Args[separator+1:], os.Stdout, os.Stderr, productionDependencies()))
}

type fakeDaemonServer struct {
	serving         chan struct{}
	shutdownStarted chan struct{}
	serveDone       chan struct{}
	serveOnce       sync.Once
	shutdownOnce    sync.Once
	mu              sync.Mutex
	forced          bool
	waitForForce    bool
	serveErr        error
	shutdownErr     error
}

func newFakeDaemonServer() *fakeDaemonServer {
	return &fakeDaemonServer{
		serving:         make(chan struct{}),
		shutdownStarted: make(chan struct{}),
		serveDone:       make(chan struct{}),
	}
}

func (server *fakeDaemonServer) Serve() error {
	server.serveOnce.Do(func() { close(server.serving) })
	if server.serveErr != nil {
		return server.serveErr
	}
	<-server.serveDone
	return nil
}

func (server *fakeDaemonServer) Shutdown(force <-chan struct{}) error {
	server.shutdownOnce.Do(func() { close(server.shutdownStarted) })
	if server.waitForForce {
		<-force
		server.mu.Lock()
		server.forced = true
		server.mu.Unlock()
	} else {
		select {
		case <-force:
			server.mu.Lock()
			server.forced = true
			server.mu.Unlock()
		default:
		}
	}
	close(server.serveDone)
	return server.shutdownErr
}

func (server *fakeDaemonServer) forceObserved() bool {
	server.mu.Lock()
	defer server.mu.Unlock()
	return server.forced
}

func inertSignalSource() (<-chan os.Signal, func()) {
	return make(chan os.Signal), func() {}
}

// fakeDaemonStore is the named seam for all store failure injections. It
// records its call order (open, migrate, bootstrap, close) so tests can assert
// the daemon's startup/shutdown ordering exactly.
type fakeDaemonStore struct {
	mu           sync.Mutex
	calls        []string
	openErr      error
	migrateErr   error
	bootstrapErr error
	closeErr     error
}

func newFakeDaemonStore() *fakeDaemonStore {
	return &fakeDaemonStore{}
}

func (f *fakeDaemonStore) record(call string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, call)
}

// openStore is the openStore-seam fake: it records "open" and returns the
// store (or the injectable openErr) without touching the filesystem.
func (f *fakeDaemonStore) openStore(context.Context, string) (daemonStore, error) {
	f.record("open")
	if f.openErr != nil {
		return nil, f.openErr
	}
	return f, nil
}

func (f *fakeDaemonStore) Migrate(context.Context) error {
	f.record("migrate")
	return f.migrateErr
}

func (f *fakeDaemonStore) BootstrapOrRestoreWorkspace(context.Context) (domainentry.WorkspaceContext, error) {
	f.record("bootstrap")
	if f.bootstrapErr != nil {
		return domainentry.WorkspaceContext{}, f.bootstrapErr
	}
	return domainentry.WorkspaceContext{}, nil
}

func (f *fakeDaemonStore) Close() error {
	f.record("close")
	return f.closeErr
}

func (f *fakeDaemonStore) callOrder() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.calls...)
}

type daemonProcess struct {
	command    *exec.Cmd
	socketPath string
	stdout     bytes.Buffer
	stderr     bytes.Buffer
	wait       <-chan error
}

func startDaemonHelper(t *testing.T) *daemonProcess {
	t.Helper()
	root, err := os.MkdirTemp("/tmp", "ec6-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(root) })

	process := &daemonProcess{socketPath: filepath.Join(root, "d.sock")}
	process.command = exec.Command(
		os.Args[0],
		"-test.run=^TestDaemonProcessHelper$",
		"--",
		"--socket",
		process.socketPath,
	)
	process.command.Env = append(os.Environ(), "ENTRY_CORE_DAEMON_TEST_HELPER=1")
	process.command.Stdout = &process.stdout
	process.command.Stderr = &process.stderr
	if err := process.command.Start(); err != nil {
		t.Fatal(err)
	}
	wait := make(chan error, 1)
	process.wait = wait
	go func() { wait <- process.command.Wait() }()
	t.Cleanup(func() {
		if process.command.ProcessState == nil {
			_ = process.command.Process.Kill()
			select {
			case <-process.wait:
			case <-time.After(time.Second):
			}
		}
	})

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		info, statErr := os.Lstat(process.socketPath)
		if statErr == nil && info.Mode()&os.ModeSocket != 0 {
			return process
		}
		select {
		case waitErr := <-process.wait:
			t.Fatalf("daemon exited before readiness: %v; stderr = %q", waitErr, process.stderr.String())
		default:
		}
		time.Sleep(10 * time.Millisecond)
	}
	_ = process.command.Process.Kill()
	select {
	case <-process.wait:
	case <-time.After(time.Second):
		t.Fatal("daemon could not be reaped after readiness timeout")
	}
	t.Fatalf("daemon socket was not ready; stderr = %q", process.stderr.String())
	return nil
}

func waitForSignal(t *testing.T, signal <-chan struct{}, name string) {
	t.Helper()
	select {
	case <-signal:
	case <-time.After(time.Second):
		t.Fatalf("timed out waiting for %s", name)
	}
}

func waitForDaemon(t *testing.T, process *daemonProcess, timeout time.Duration) error {
	t.Helper()
	select {
	case err := <-process.wait:
		return err
	case <-time.After(timeout):
		_ = process.command.Process.Kill()
		select {
		case <-process.wait:
		case <-time.After(time.Second):
			t.Fatal("daemon could not be reaped after exit timeout")
		}
		t.Fatal("daemon did not exit within bound")
		return nil
	}
}

func assertSuccessfulDaemonExit(t *testing.T, process *daemonProcess, waitErr error) {
	t.Helper()
	if waitErr != nil {
		t.Fatalf("daemon exit = %v; stderr = %q", waitErr, process.stderr.String())
	}
	if process.stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty", process.stdout.String())
	}
	if _, err := os.Lstat(process.socketPath); !os.IsNotExist(err) {
		t.Fatalf("socket remains after exit: %v", err)
	}
}
