package unixsocket

import (
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	entryruntime "github.com/voyager-labs/voyager-app/apps/entry-core/internal/runtime"
)

func TestSocketPathPolicy(t *testing.T) {
	t.Run("absolute path required", func(t *testing.T) {
		if _, err := NewServer("relative.sock", entryruntime.New(), nil); err == nil {
			t.Fatal("NewServer() succeeded for relative path")
		}
	})

	t.Run("path length checked before filesystem mutation", func(t *testing.T) {
		root := shortTempDir(t)
		path := filepath.Join(root, strings.Repeat("x", len(syscall.RawSockaddrUnix{}.Path)))
		if _, err := NewServer(path, entryruntime.New(), nil); err == nil {
			t.Fatal("NewServer() succeeded for overlong path")
		}
		if _, err := os.Lstat(path); !os.IsNotExist(err) {
			t.Fatalf("destination Lstat error = %v, want not exist", err)
		}
	})

	t.Run("creates only missing direct parent as 0700", func(t *testing.T) {
		root := shortTempDir(t)
		parent := filepath.Join(root, "private")
		server := startServer(t, filepath.Join(parent, "entry.sock"), testDurations())
		info, err := os.Lstat(parent)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0o700 {
			t.Fatalf("parent mode = %o, want 700", info.Mode().Perm())
		}
		shutdownServer(t, server, nil)
	})

	t.Run("missing grandparent fails", func(t *testing.T) {
		root := shortTempDir(t)
		path := filepath.Join(root, "missing", "parent", "entry.sock")
		if _, err := NewServer(path, entryruntime.New(), nil); err == nil {
			t.Fatal("NewServer() succeeded with missing grandparent")
		}
		if _, err := os.Lstat(filepath.Join(root, "missing")); !os.IsNotExist(err) {
			t.Fatalf("grandparent Lstat error = %v, want not exist", err)
		}
	})

	t.Run("unsafe existing parents fail unchanged", func(t *testing.T) {
		root := shortTempDir(t)
		cases := []struct {
			name  string
			setup func(string) string
		}{
			{name: "permissive", setup: func(parent string) string {
				mustMkdir(t, parent, 0o755)
				return parent
			}},
			{name: "file", setup: func(parent string) string {
				mustWriteFile(t, parent, []byte("keep"), 0o600)
				return parent
			}},
			{name: "symlink", setup: func(parent string) string {
				target := parent + "-target"
				mustMkdir(t, target, 0o700)
				if err := os.Symlink(target, parent); err != nil {
					t.Fatal(err)
				}
				return parent
			}},
		}
		for _, test := range cases {
			t.Run(test.name, func(t *testing.T) {
				parent := test.setup(filepath.Join(root, test.name))
				before, err := os.Lstat(parent)
				if err != nil {
					t.Fatal(err)
				}
				if _, err := NewServer(filepath.Join(parent, "entry.sock"), entryruntime.New(), nil); err == nil {
					t.Fatal("NewServer() succeeded with unsafe parent")
				}
				after, err := os.Lstat(parent)
				if err != nil {
					t.Fatal(err)
				}
				if before.Mode() != after.Mode() {
					t.Fatalf("parent mode changed from %v to %v", before.Mode(), after.Mode())
				}
			})
		}
	})

	t.Run("effective owner required", func(t *testing.T) {
		root := shortTempDir(t)
		parent := filepath.Join(root, "private")
		mustMkdir(t, parent, 0o700)
		if _, err := validateSocketPath(filepath.Join(parent, "entry.sock"), os.Geteuid()+1); err == nil {
			t.Fatal("validateSocketPath() accepted parent owned by another effective UID")
		}
	})
}

func TestSocketDestinationTypesRemainUntouched(t *testing.T) {
	setups := []struct {
		name  string
		setup func(*testing.T, string)
	}{
		{name: "file", setup: func(t *testing.T, path string) { mustWriteFile(t, path, []byte("keep"), 0o600) }},
		{name: "directory", setup: func(t *testing.T, path string) { mustMkdir(t, path, 0o700) }},
		{name: "symlink", setup: func(t *testing.T, path string) {
			if err := os.Symlink("missing-target", path); err != nil {
				t.Fatal(err)
			}
		}},
		{name: "socket", setup: func(t *testing.T, path string) {
			listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
			if err != nil {
				t.Fatal(err)
			}
			listener.SetUnlinkOnClose(false)
			t.Cleanup(func() { _ = listener.Close() })
		}},
	}

	for _, test := range setups {
		t.Run(test.name, func(t *testing.T) {
			root := secureTempDir(t)
			path := filepath.Join(root, "entry.sock")
			test.setup(t, path)
			before, err := os.Lstat(path)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := NewServer(path, entryruntime.New(), nil); err == nil {
				t.Fatal("NewServer() succeeded for existing destination")
			}
			after, err := os.Lstat(path)
			if err != nil {
				t.Fatal(err)
			}
			if !os.SameFile(before, after) {
				t.Fatal("existing destination identity changed")
			}
		})
	}
}

func TestLifecycleLockRejectsUnsafePreexistingFiles(t *testing.T) {
	setups := []struct {
		name  string
		setup func(*testing.T, string)
	}{
		{name: "permissive mode", setup: func(t *testing.T, path string) {
			mustWriteFile(t, path, []byte("keep"), 0o600)
			if err := os.Chmod(path, 0o644); err != nil {
				t.Fatal(err)
			}
		}},
		{name: "directory", setup: func(t *testing.T, path string) {
			mustMkdir(t, path, 0o600)
		}},
		{name: "symlink", setup: func(t *testing.T, path string) {
			target := path + "-target"
			mustWriteFile(t, target, []byte("keep"), 0o600)
			if err := os.Symlink(target, path); err != nil {
				t.Fatal(err)
			}
		}},
		{name: "multiple links", setup: func(t *testing.T, path string) {
			mustWriteFile(t, path, []byte("keep"), 0o600)
			if err := os.Link(path, path+"-alias"); err != nil {
				t.Fatal(err)
			}
		}},
	}

	for _, test := range setups {
		t.Run(test.name, func(t *testing.T) {
			root := secureTempDir(t)
			path := filepath.Join(root, "entry.sock")
			lockPath := path + ".lock"
			test.setup(t, lockPath)
			before, err := os.Lstat(lockPath)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := NewServer(path, entryruntime.New(), nil); err == nil {
				t.Fatal("NewServer() succeeded with unsafe lifecycle lock")
			}
			after, err := os.Lstat(lockPath)
			if err != nil {
				t.Fatal(err)
			}
			if !os.SameFile(before, after) || before.Mode() != after.Mode() {
				t.Fatal("unsafe lifecycle lock was replaced or changed")
			}
			if _, err := os.Lstat(path); !os.IsNotExist(err) {
				t.Fatalf("socket Lstat error = %v, want not exist", err)
			}
		})
	}
}

func TestLifecycleLockRequiresEffectiveOwner(t *testing.T) {
	path := filepath.Join(secureTempDir(t), "entry.sock.lock")
	lock, err := acquireLifecycleLock(path, os.Geteuid()+1)
	if lock != nil || err == nil {
		if lock != nil {
			_ = lock.Close()
		}
		t.Fatalf("acquireLifecycleLock() = %#v, %v, want owner rejection", lock, err)
	}
}

func TestSocketCreationFailsClosedUnderRestrictiveCallerUmask(t *testing.T) {
	path := filepath.Join(secureTempDir(t), "entry.sock")
	originalMask := syscall.Umask(0o777)
	defer syscall.Umask(originalMask)

	server, err := NewServer(path, entryruntime.New(), nil)
	observedMask := syscall.Umask(0o777)
	syscall.Umask(observedMask)
	if server != nil || err == nil {
		t.Fatalf("NewServer() = %#v, %v, want exact-mode startup failure", server, err)
	}
	if observedMask != 0o777 {
		t.Fatalf("caller umask after NewServer() = %03o, want 777", observedMask)
	}
	if _, err := os.Lstat(path); !os.IsNotExist(err) {
		t.Fatalf("socket Lstat after failed startup = %v, want not exist", err)
	}
	lockInfo, err := os.Lstat(path + ".lock")
	if err != nil {
		t.Fatal(err)
	}
	if !lockInfo.Mode().IsRegular() || lockInfo.Mode().Perm() != 0o600 {
		t.Fatalf("lifecycle lock mode = %v, want regular 0600", lockInfo.Mode())
	}
}

func TestSocketModeAndReplacementSafeCleanup(t *testing.T) {
	root := secureTempDir(t)
	path := filepath.Join(root, "entry.sock")
	server := startServer(t, path, testDurations())
	info, err := os.Lstat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 || info.Mode()&os.ModeSocket == 0 {
		t.Fatalf("socket mode = %v, want socket 0600", info.Mode())
	}

	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	mustWriteFile(t, path, []byte("replacement"), 0o600)
	replacement, err := os.Lstat(path)
	if err != nil {
		t.Fatal(err)
	}
	shutdownServer(t, server, nil)
	after, err := os.Lstat(path)
	if err != nil {
		t.Fatal(err)
	}
	if !os.SameFile(replacement, after) {
		t.Fatal("shutdown removed or replaced a non-owned destination")
	}
}

func TestSocketOwnedCleanup(t *testing.T) {
	root := secureTempDir(t)
	path := filepath.Join(root, "entry.sock")
	server := startServer(t, path, testDurations())
	lockBefore, err := os.Lstat(path + ".lock")
	if err != nil {
		t.Fatal(err)
	}
	shutdownServer(t, server, nil)
	if _, err := os.Lstat(path); !os.IsNotExist(err) {
		t.Fatalf("socket Lstat after shutdown = %v, want not exist", err)
	}
	lockAfter, err := os.Lstat(path + ".lock")
	if err != nil {
		t.Fatal(err)
	}
	if !os.SameFile(lockBefore, lockAfter) {
		t.Fatal("shutdown removed or replaced the persistent lifecycle lock file")
	}
}

func TestSocketStartupRollback(t *testing.T) {
	t.Run("removes owned socket and closes listener", func(t *testing.T) {
		path := filepath.Join(secureTempDir(t), "entry.sock")
		server, err := newServerWithHooks(
			path,
			entryruntime.New(),
			nil,
			testDurations(),
			serverStartupHooks{afterBind: func(string, os.FileInfo) error {
				return errors.New("injected post-bind failure")
			}},
		)
		if err == nil || server != nil {
			t.Fatalf("newServerWithHooks() = %#v, %v, want startup failure", server, err)
		}
		if _, err := os.Lstat(path); !os.IsNotExist(err) {
			t.Fatalf("owned socket Lstat after rollback = %v, want not exist", err)
		}
		fresh, err := newServer(path, entryruntime.New(), nil, testDurations())
		if err != nil {
			t.Fatalf("lifecycle lock remained held after rollback: %v", err)
		}
		go func() { _ = fresh.Serve() }()
		shutdownServer(t, fresh, nil)
	})

	t.Run("preserves replacement identity and mode without pathname chmod", func(t *testing.T) {
		path := filepath.Join(secureTempDir(t), "entry.sock")
		content := []byte("replacement")
		var replacement os.FileInfo
		server, err := newServerWithHooks(
			path,
			entryruntime.New(),
			nil,
			testDurations(),
			serverStartupHooks{afterBind: func(path string, _ os.FileInfo) error {
				if err := os.Remove(path); err != nil {
					return err
				}
				if err := os.WriteFile(path, content, 0o644); err != nil {
					return err
				}
				if err := os.Chmod(path, 0o644); err != nil {
					return err
				}
				var err error
				replacement, err = os.Lstat(path)
				return err
			}},
		)
		if err == nil || server != nil {
			t.Fatalf("newServerWithHooks() = %#v, %v, want startup failure", server, err)
		}
		current, err := os.Lstat(path)
		if err != nil {
			t.Fatal(err)
		}
		if replacement == nil || !os.SameFile(replacement, current) {
			t.Fatal("startup rollback removed or replaced non-owned destination")
		}
		if current.Mode().Perm() != 0o644 {
			t.Fatalf("replacement mode = %o, want 644", current.Mode().Perm())
		}
		got, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if string(got) != string(content) {
			t.Fatalf("replacement content = %q, want %q", got, content)
		}
	})

	t.Run("preserves replacement identity", func(t *testing.T) {
		path := filepath.Join(secureTempDir(t), "entry.sock")
		var replacement os.FileInfo
		server, err := newServerWithHooks(
			path,
			entryruntime.New(),
			nil,
			testDurations(),
			serverStartupHooks{afterBind: func(path string, _ os.FileInfo) error {
				if err := os.Remove(path); err != nil {
					return err
				}
				if err := os.WriteFile(path, []byte("replacement"), 0o600); err != nil {
					return err
				}
				var err error
				replacement, err = os.Lstat(path)
				if err != nil {
					return err
				}
				return errors.New("injected post-bind failure")
			}},
		)
		if err == nil || server != nil {
			t.Fatalf("newServerWithHooks() = %#v, %v, want startup failure", server, err)
		}
		current, err := os.Lstat(path)
		if err != nil {
			t.Fatal(err)
		}
		if replacement == nil || !os.SameFile(replacement, current) {
			t.Fatal("startup rollback removed or replaced non-owned destination")
		}
	})
}

func shortTempDir(t *testing.T) string {
	t.Helper()
	root, err := os.MkdirTemp("", "ec-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(root) })
	return root
}

func secureTempDir(t *testing.T) string {
	t.Helper()
	root := shortTempDir(t)
	if err := os.Chmod(root, 0o700); err != nil {
		t.Fatal(err)
	}
	return root
}

func mustMkdir(t *testing.T, path string, mode os.FileMode) {
	t.Helper()
	if err := os.Mkdir(path, mode); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, mode); err != nil {
		t.Fatal(err)
	}
}

func mustWriteFile(t *testing.T, path string, content []byte, mode os.FileMode) {
	t.Helper()
	if err := os.WriteFile(path, content, mode); err != nil {
		t.Fatal(err)
	}
}

func testDurations() serverDurations {
	return serverDurations{
		readTimeout:  200 * time.Millisecond,
		writeTimeout: 200 * time.Millisecond,
		graceTimeout: 100 * time.Millisecond,
		finalTimeout: 100 * time.Millisecond,
	}
}
