package integration

import (
	"bytes"
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	sqlite "github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite/seeds"
)

const (
	testAppVersion   = "9.8.7-test"
	appVersionSymbol = "github.com/voyager-labs/voyager-app/apps/entry-core/internal/runtime.AppVersion"
)

func TestDaemonProcessSmoke(t *testing.T) {
	moduleRoot := entryCoreModuleRoot(t)
	tempRoot, err := os.MkdirTemp("", "ec-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.RemoveAll(tempRoot); err != nil {
			t.Errorf("remove temporary process-smoke root: %v", err)
		}
	})
	if err := os.Chmod(tempRoot, 0o700); err != nil {
		t.Fatal(err)
	}

	cliPath := filepath.Join(tempRoot, "ec")
	daemonPath := filepath.Join(tempRoot, "ecd")
	socketPath := filepath.Join(tempRoot, "d.sock")
	buildBinary(t, moduleRoot, cliPath, "./cmd/entry-core")
	buildBinary(
		t,
		moduleRoot,
		daemonPath,
		"-ldflags",
		"-X "+appVersionSymbol+"="+testAppVersion,
		"./cmd/entry-core-daemon",
	)

	daemon := startDaemon(t, daemonPath, socketPath)
	waitForSocket(t, daemon, socketPath, 15*time.Second)

	assertCLIResult(t, cliPath, socketPath, "ping", "{\"message\":\"pong\"}\n")
	assertCLIResult(t, cliPath, socketPath, "health", "{\"status\":\"healthy\",\"state\":\"running\"}\n")
	assertCLIResult(
		t,
		cliPath,
		socketPath,
		"version",
		"{\"app_version\":\"9.8.7-test\"}\n",
	)

	sendMalformedRequest(t, socketPath)
	if err := syscall.Kill(daemon.cmd.Process.Pid, 0); err != nil {
		t.Fatalf("daemon is not alive after malformed request: %v", err)
	}
	assertCLIResult(t, cliPath, socketPath, "ping", "{\"message\":\"pong\"}\n")

	pid := daemon.cmd.Process.Pid
	if err := daemon.cmd.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatalf("send SIGTERM: %v", err)
	}
	if err := daemon.wait(5 * time.Second); err != nil {
		t.Fatalf("daemon did not exit successfully after SIGTERM: %v; stderr=%q", err, daemon.stderr.String())
	}
	if daemon.cmd.ProcessState == nil || !daemon.cmd.ProcessState.Exited() || daemon.cmd.ProcessState.ExitCode() != 0 {
		t.Fatalf("daemon process was not reaped with exit 0: state=%v", daemon.cmd.ProcessState)
	}
	if _, err := os.Lstat(socketPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("socket remains after daemon exit: %v", err)
	}
	if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
		t.Fatalf("daemon process residue remains after reap: %v", err)
	}
	assertMetadataOnlyLogs(t, daemon.stdout.String(), daemon.stderr.String(), socketOnlyAllowedLogLines())

	t.Run("persistence restart", func(t *testing.T) {
		dbPath := filepath.Join(tempRoot, "entry-core.db")

		firstBoot := startDaemonWithDatabase(t, daemonPath, socketPath, dbPath)
		waitForSocket(t, firstBoot, socketPath, 15*time.Second)
		assertCLIResult(t, cliPath, socketPath, "ping", "{\"message\":\"pong\"}\n")
		if err := firstBoot.cmd.Process.Signal(syscall.SIGTERM); err != nil {
			t.Fatalf("send SIGTERM to first boot: %v", err)
		}
		if err := firstBoot.wait(5 * time.Second); err != nil {
			t.Fatalf("first boot did not exit after SIGTERM: %v; stderr=%q", err, firstBoot.stderr.String())
		}
		if _, err := os.Lstat(socketPath); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("socket remains after first boot exit: %v", err)
		}
		assertMetadataOnlyLogs(
			t,
			firstBoot.stdout.String(),
			firstBoot.stderr.String(),
			map[string]bool{
				"entry-core-daemon: started in foreground":              true,
				"entry-core-daemon: received terminated; shutting down": true,
				"entry-core-daemon: stopped":                            true,
				"entry-core-daemon: workspace metadata initialized":     true,
			},
		)
		if !strings.Contains(firstBoot.stderr.String(), "workspace metadata initialized") {
			t.Fatalf("first boot stderr=%q, want workspace metadata initialized", firstBoot.stderr.String())
		}

		restart := startDaemonWithDatabase(t, daemonPath, socketPath, dbPath)
		waitForSocket(t, restart, socketPath, 15*time.Second)
		assertCLIResult(t, cliPath, socketPath, "ping", "{\"message\":\"pong\"}\n")
		if err := restart.cmd.Process.Signal(syscall.SIGTERM); err != nil {
			t.Fatalf("send SIGTERM to restart: %v", err)
		}
		if err := restart.wait(5 * time.Second); err != nil {
			t.Fatalf("restart did not exit after SIGTERM: %v; stderr=%q", err, restart.stderr.String())
		}
		if _, err := os.Lstat(socketPath); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("socket remains after restart exit: %v", err)
		}
		assertMetadataOnlyLogs(
			t,
			restart.stdout.String(),
			restart.stderr.String(),
			map[string]bool{
				"entry-core-daemon: started in foreground":              true,
				"entry-core-daemon: received terminated; shutting down": true,
				"entry-core-daemon: stopped":                            true,
				"entry-core-daemon: workspace metadata restored":        true,
			},
		)
		if !strings.Contains(restart.stderr.String(), "workspace metadata restored") {
			t.Fatalf("restart stderr=%q, want workspace metadata restored", restart.stderr.String())
		}
	})

	t.Run("corrupt database fails closed", func(t *testing.T) {
		corruptPath := filepath.Join(tempRoot, "corrupt.db")
		corruptData := make([]byte, 256)
		if _, err := rand.Read(corruptData); err != nil {
			t.Fatalf("read random corrupt bytes: %v", err)
		}
		if err := os.WriteFile(corruptPath, corruptData, 0o600); err != nil {
			t.Fatalf("write corrupt database file: %v", err)
		}

		daemon := startDaemonWithDatabase(t, daemonPath, socketPath, corruptPath)
		if !daemon.reaped(15 * time.Second) {
			t.Fatalf("daemon did not exit on corrupt database within 15s; stderr=%q", daemon.stderr.String())
		}
		if daemon.cmd.ProcessState == nil || !daemon.cmd.ProcessState.Exited() || daemon.cmd.ProcessState.ExitCode() != 1 {
			t.Fatalf("daemon exit = %v, want exit 1; stderr=%q", daemon.cmd.ProcessState, daemon.stderr.String())
		}
		if _, err := os.Lstat(socketPath); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("socket was created for corrupt database: %v", err)
		}
		if got := daemon.stdout.String(); got != "" {
			t.Fatalf("daemon stdout=%q, want empty", got)
		}
		stderr := daemon.stderr.String()
		if !strings.Contains(stderr, "startup failed: database open failed") {
			t.Fatalf("daemon stderr=%q, want startup failed: database open failed", stderr)
		}
		if strings.Contains(stderr, "started in foreground") {
			t.Fatalf("daemon stderr=%q, must not reach serve on corrupt database", stderr)
		}
	})

	t.Run("catalog fresh seed + restart no-op", func(t *testing.T) {
		dbPath := filepath.Join(tempRoot, "catalog.db")
		seed := seeds.Current()

		freshBoot := startDaemonWithDatabase(t, daemonPath, socketPath, dbPath)
		waitForSocket(t, freshBoot, socketPath, 15*time.Second)
		if err := freshBoot.cmd.Process.Signal(syscall.SIGTERM); err != nil {
			t.Fatalf("send SIGTERM to catalog fresh boot: %v", err)
		}
		if err := freshBoot.wait(5 * time.Second); err != nil {
			t.Fatalf("catalog fresh boot did not exit: %v; stderr=%q", err, freshBoot.stderr.String())
		}
		if !strings.Contains(freshBoot.stderr.String(), "workspace metadata initialized") {
			t.Fatalf("fresh boot stderr=%q, want workspace metadata initialized", freshBoot.stderr.String())
		}

		// Fresh seed must persist the full catalog (identity + counts + digest).
		counts, identity := inspectCatalogStore(t, dbPath)
		if counts["defs"] != seed.DefinitionCount || counts["descs"] != seed.DescriptorCount ||
			counts["bindings"] != seed.BindingCount || counts["terms"] != seed.TermCount {
			t.Fatalf("fresh seed counts=%v, want defs=%d descs=%d bindings=%d terms=%d",
				counts, seed.DefinitionCount, seed.DescriptorCount, seed.BindingCount, seed.TermCount)
		}
		if identity == "" {
			t.Fatal("workspace identity not persisted after fresh seed")
		}

		// Clean restart must no-op the seed and preserve identity/counts.
		restart := startDaemonWithDatabase(t, daemonPath, socketPath, dbPath)
		waitForSocket(t, restart, socketPath, 15*time.Second)
		if err := restart.cmd.Process.Signal(syscall.SIGTERM); err != nil {
			t.Fatalf("send SIGTERM to catalog restart: %v", err)
		}
		if err := restart.wait(5 * time.Second); err != nil {
			t.Fatalf("catalog restart did not exit: %v; stderr=%q", err, restart.stderr.String())
		}
		if !strings.Contains(restart.stderr.String(), "workspace metadata restored") {
			t.Fatalf("restart stderr=%q, want workspace metadata restored", restart.stderr.String())
		}

		countsAfter, identityAfter := inspectCatalogStore(t, dbPath)
		if countsAfter["defs"] != counts["defs"] || countsAfter["descs"] != counts["descs"] ||
			countsAfter["bindings"] != counts["bindings"] || countsAfter["terms"] != counts["terms"] {
			t.Fatalf("restart no-op changed counts: before=%v after=%v", counts, countsAfter)
		}
		if identityAfter != identity {
			t.Fatalf("restart changed persisted identity: before=%q after=%q", identity, identityAfter)
		}
	})

	t.Run("catalog drift fails closed", func(t *testing.T) {
		dbPath := filepath.Join(tempRoot, "catalog-drift.db")

		firstBoot := startDaemonWithDatabase(t, daemonPath, socketPath, dbPath)
		waitForSocket(t, firstBoot, socketPath, 15*time.Second)
		if err := firstBoot.cmd.Process.Signal(syscall.SIGTERM); err != nil {
			t.Fatalf("send SIGTERM to drift first boot: %v", err)
		}
		if err := firstBoot.wait(5 * time.Second); err != nil {
			t.Fatalf("drift first boot did not exit: %v; stderr=%q", err, firstBoot.stderr.String())
		}

		// Mutate a seed-owned definition row (digest-relevant) on a disposable DB.
		mutateCatalogSeedRow(t, dbPath)

		// Same-version drift must fail closed: exit 1, no socket.
		drifted := startDaemonWithDatabase(t, daemonPath, socketPath, dbPath)
		if !drifted.reaped(15 * time.Second) {
			t.Fatalf("drifted daemon did not exit within 15s; stderr=%q", drifted.stderr.String())
		}
		if drifted.cmd.ProcessState == nil || !drifted.cmd.ProcessState.Exited() || drifted.cmd.ProcessState.ExitCode() != 1 {
			t.Fatalf("drifted daemon exit = %v, want exit 1; stderr=%q", drifted.cmd.ProcessState, drifted.stderr.String())
		}
		if _, err := os.Lstat(socketPath); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("socket was created on catalog drift: %v", err)
		}
		if !strings.Contains(drifted.stderr.String(), "startup failed") {
			t.Fatalf("drifted daemon stderr=%q, want startup failed", drifted.stderr.String())
		}
	})
}

// inspectCatalogStore는 daemon 종료 후 DB를 열어 (workspace identity, seed row
// count, seed no-op digest)를 검증하고 counts map과 identity hex를 반환한다.
// digest는 Store.ApplyCatalogSeed no-op 성공으로 확인하므로 persistence
// state-machine 상세를 여기서 재구현하지 않는다.
func inspectCatalogStore(t *testing.T, dbPath string) (counts map[string]int, identity string) {
	t.Helper()
	ctx := context.Background()
	store, err := sqlite.Open(ctx, dbPath)
	if err != nil {
		t.Fatalf("open catalog store for verification: %v", err)
	}
	defer func() { _ = store.Close() }()

	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("read persisted workspace identity: %v", err)
	}
	if wsctx.ID == (domainentry.WorkspaceID{}) {
		t.Fatal("persisted workspace identity is zero")
	}
	identity = wsctx.ID.String()
	if err := store.ApplyCatalogSeed(ctx, wsctx); err != nil {
		t.Fatalf("ApplyCatalogSeed on seeded DB = %v, want nil no-op (digest verified)", err)
	}

	tables := []struct {
		name      string
		table     string
		lifecycle bool
	}{
		{name: "defs", table: "workspace_property_definitions", lifecycle: true},
		{name: "descs", table: "source_property_descriptors", lifecycle: true},
		{name: "bindings", table: "property_bindings", lifecycle: true},
		{name: "terms", table: "workspace_property_terms", lifecycle: false},
	}
	counts = make(map[string]int)
	for _, entry := range tables {
		query := "SELECT COUNT(*) FROM " + entry.table + " WHERE seed_owner = 'system_property_registry'"
		if entry.lifecycle {
			query += " AND lifecycle_state = 'active'"
		}
		var n int
		if err := store.SQLDB().QueryRow(query).Scan(&n); err != nil {
			t.Fatalf("count %s: %v", entry.table, err)
		}
		counts[entry.name] = n
	}
	return counts, identity
}

// mutateCatalogSeedRow는 disposable DB의 seed-owned active definition 한 행의
// digest-relevant field를 drift시켜 same-version digest mismatch를 유발한다.
// persistence state-machine을 재구현하지 않고 raw row mutation만 수행한다.
func mutateCatalogSeedRow(t *testing.T, dbPath string) {
	t.Helper()
	ctx := context.Background()
	store, err := sqlite.Open(ctx, dbPath)
	if err != nil {
		t.Fatalf("open catalog store for mutation: %v", err)
	}
	defer func() { _ = store.Close() }()

	if _, err := store.SQLDB().Exec(
		"UPDATE workspace_property_definitions SET canonical_key = canonical_key || '-drifted' WHERE seed_owner = 'system_property_registry' AND lifecycle_state = 'active' AND property_id IN (SELECT property_id FROM workspace_property_definitions WHERE seed_owner = 'system_property_registry' AND lifecycle_state = 'active' LIMIT 1)",
	); err != nil {
		t.Fatalf("mutate seed-owned definition row: %v", err)
	}
}

func socketOnlyAllowedLogLines() map[string]bool {
	return map[string]bool{
		"entry-core-daemon: started in foreground":              true,
		"entry-core-daemon: received terminated; shutting down": true,
		"entry-core-daemon: stopped":                            true,
	}
}

func entryCoreModuleRoot(t *testing.T) string {
	t.Helper()
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve smoke test source path")
	}
	return filepath.Dir(filepath.Dir(filename))
}

func buildBinary(t *testing.T, moduleRoot, output string, args ...string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	buildArgs := append([]string{"build", "-o", output}, args...)
	command := exec.CommandContext(ctx, "go", buildArgs...)
	command.Dir = moduleRoot
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		t.Fatalf("build real binary %q: %v; stdout=%q stderr=%q", args[len(args)-1], err, stdout.String(), stderr.String())
	}
	if ctx.Err() != nil {
		t.Fatalf("build real binary %q: %v", args[len(args)-1], ctx.Err())
	}
}

type daemonProcess struct {
	cmd    *exec.Cmd
	stdout bytes.Buffer
	stderr bytes.Buffer
	done   chan struct{}
	mu     sync.Mutex
	err    error
}

func startDaemon(t *testing.T, daemonPath, socketPath string) *daemonProcess {
	t.Helper()
	return launchDaemon(t, daemonPath, "--socket", socketPath)
}

func startDaemonWithDatabase(t *testing.T, daemonPath, socketPath, dbPath string) *daemonProcess {
	t.Helper()
	return launchDaemon(t, daemonPath, "--socket", socketPath, "--database", dbPath)
}

func launchDaemon(t *testing.T, daemonPath string, argv ...string) *daemonProcess {
	t.Helper()
	process := &daemonProcess{
		cmd:  exec.Command(daemonPath, argv...),
		done: make(chan struct{}),
	}
	process.cmd.Stdout = &process.stdout
	process.cmd.Stderr = &process.stderr
	if err := process.cmd.Start(); err != nil {
		t.Fatalf("start real daemon binary: %v", err)
	}
	go func() {
		err := process.cmd.Wait()
		process.mu.Lock()
		process.err = err
		process.mu.Unlock()
		close(process.done)
	}()
	t.Cleanup(func() {
		select {
		case <-process.done:
			return
		default:
		}
		_ = process.cmd.Process.Kill()
		select {
		case <-process.done:
		case <-time.After(3 * time.Second):
			t.Errorf("daemon cleanup did not reap child process")
		}
	})
	return process
}

func (process *daemonProcess) wait(timeout time.Duration) error {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case <-process.done:
		process.mu.Lock()
		defer process.mu.Unlock()
		return process.err
	case <-timer.C:
		return fmt.Errorf("timed out after %s", timeout)
	}
}

// reaped reports whether the process has been reaped (waited on) within the
// timeout, regardless of its exit code.
func (process *daemonProcess) reaped(timeout time.Duration) bool {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case <-process.done:
		return true
	case <-timer.C:
		return false
	}
}

func waitForSocket(t *testing.T, process *daemonProcess, socketPath string, timeout time.Duration) {
	t.Helper()
	deadline := time.NewTimer(timeout)
	defer deadline.Stop()
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-process.done:
			process.mu.Lock()
			err := process.err
			process.mu.Unlock()
			t.Fatalf("daemon exited before readiness: %v; stdout=%q stderr=%q", err, process.stdout.String(), process.stderr.String())
		case <-ticker.C:
			info, err := os.Lstat(socketPath)
			if err == nil && info.Mode()&os.ModeSocket != 0 {
				return
			}
			if err != nil && !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("inspect daemon socket readiness: %v", err)
			}
		case <-deadline.C:
			t.Fatalf("daemon socket was not ready within %s; stdout=%q stderr=%q", timeout, process.stdout.String(), process.stderr.String())
		}
	}
}

func assertCLIResult(t *testing.T, cliPath, socketPath, method, expectedStdout string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, cliPath, "--socket", socketPath, method)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		t.Fatalf("real CLI %s failed: %v; stdout=%q stderr=%q", method, err, stdout.String(), stderr.String())
	}
	if ctx.Err() != nil {
		t.Fatalf("real CLI %s exceeded process bound: %v", method, ctx.Err())
	}
	if stdout.String() != expectedStdout {
		t.Fatalf("real CLI %s stdout=%q, want %q", method, stdout.String(), expectedStdout)
	}
	if stderr.Len() != 0 {
		t.Fatalf("real CLI %s stderr=%q, want empty", method, stderr.String())
	}
}

func sendMalformedRequest(t *testing.T, socketPath string) {
	t.Helper()
	connection, err := net.DialTimeout("unix", socketPath, time.Second)
	if err != nil {
		t.Fatalf("dial daemon for malformed request: %v", err)
	}
	defer connection.Close()
	if err := connection.SetDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatalf("bound malformed request connection: %v", err)
	}
	unixConnection, ok := connection.(*net.UnixConn)
	if !ok {
		t.Fatal("malformed request connection is not Unix")
	}
	const malformed = `{"request_id":"malformed-raw-id","method":"ping","params":{"marker":"sensitive-payload-marker"}`
	if _, err := io.WriteString(connection, malformed); err != nil {
		t.Fatalf("write malformed request: %v", err)
	}
	if err := unixConnection.CloseWrite(); err != nil {
		t.Fatalf("finish malformed request write: %v", err)
	}
	if _, err := io.ReadAll(connection); err != nil {
		t.Fatalf("read malformed request response: %v", err)
	}
}

func assertMetadataOnlyLogs(t *testing.T, stdout, stderr string, allowed map[string]bool) {
	t.Helper()
	if stdout != "" {
		t.Fatalf("daemon stdout=%q, want empty", stdout)
	}
	for _, sensitive := range []string{"sensitive-payload-marker", "malformed-raw-id", "request_id", "params"} {
		if strings.Contains(stderr, sensitive) {
			t.Fatal("daemon stderr leaked malformed request data")
		}
	}
	lines := strings.Split(strings.TrimSuffix(stderr, "\n"), "\n")
	if len(lines) != len(allowed) {
		t.Fatalf("daemon stderr contains non-lifecycle output: %q", stderr)
	}
	for _, line := range lines {
		if !allowed[line] {
			t.Fatalf("daemon stderr contains non-metadata line: %q", line)
		}
	}
}
