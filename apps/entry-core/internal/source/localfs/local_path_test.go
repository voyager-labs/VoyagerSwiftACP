package localfs

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/testfixture"
)

// TestResolveLocalPathResolvesCleanAbsoluteTarget는 clean 절대 경로 하나가
// locator 강도의 canonical EntryRef로 해석되고 반복 호출에서 동일한 EntryID를
// 반환하는지 증명한다.
func TestResolveLocalPathResolvesCleanAbsoluteTarget(t *testing.T) {
	root := t.TempDir()
	docs := filepath.Join(root, "docs")
	if err := os.Mkdir(docs, 0o700); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(docs, "notes.txt")
	testfixture.CopyFile(t, file, testfixture.PlainText)

	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})

	first, err := adapter.ResolveLocalPath(context.Background(), file)
	if err != nil {
		t.Fatalf("ResolveLocalPath() error = %v", err)
	}
	if err := first.Validate(); err != nil {
		t.Fatalf("resolved ref Validate() error = %v", err)
	}
	if first.IdentityStrength != entry.IdentityStrengthLocator {
		t.Fatalf("identity strength = %q, want %q", first.IdentityStrength, entry.IdentityStrengthLocator)
	}
	if first.SourceInstanceID != adapter.SourceIdentity().SourceID {
		t.Fatalf("source instance = %q, want %q", first.SourceInstanceID, adapter.SourceIdentity().SourceID)
	}
	if first.SourceObjectKey != "docs/notes.txt" {
		t.Fatalf("source object key = %q, want %q", first.SourceObjectKey, "docs/notes.txt")
	}
	if first.ResourceType != "file" {
		t.Fatalf("resource type = %q, want %q", first.ResourceType, "file")
	}
	wantEntryID := entry.DeriveEntryID(adapter.SourceIdentity().SourceID, "file", "docs/notes.txt")
	if first.EntryID != wantEntryID {
		t.Fatalf("entry id = %q, want %q", first.EntryID, wantEntryID)
	}

	second, err := adapter.ResolveLocalPath(context.Background(), file)
	if err != nil {
		t.Fatalf("repeat ResolveLocalPath() error = %v", err)
	}
	if second != first {
		t.Fatalf("repeat resolution is not stable: %#v vs %#v", second, first)
	}

	directory, err := adapter.ResolveLocalPath(context.Background(), docs)
	if err != nil {
		t.Fatalf("ResolveLocalPath(directory) error = %v", err)
	}
	if directory.ResourceType != "directory" || directory.EntryID == first.EntryID {
		t.Fatalf("directory target = %#v", directory)
	}
}

// TestResolveLocalPathRejectsMalformedPath는 상대, 비정규, NUL 포함, 크기 초과
// 경로가 typed source error로 거절되는지 테이블로 증명한다.
func TestResolveLocalPathRejectsMalformedPath(t *testing.T) {
	root := t.TempDir()
	testfixture.CopyFile(t, filepath.Join(root, "real.txt"), testfixture.PlainText)
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})

	cases := []struct {
		name string
		path string
		want error
	}{
		{name: "relative path", path: "real.txt", want: source.ErrInvalidRequest},
		{name: "double slash", path: root + "//real.txt", want: source.ErrInvalidRequest},
		{name: "dot segment", path: root + "/./real.txt", want: source.ErrInvalidRequest},
		{name: "dot-dot segment", path: root + "/../" + filepath.Base(root) + "/real.txt", want: source.ErrInvalidRequest},
		{name: "trailing slash on file", path: filepath.Join(root, "real.txt") + "/", want: source.ErrInvalidRequest},
		{name: "NUL byte", path: "/" + strings.Repeat("a", 8) + "\x00" + "b", want: source.ErrInvalidRequest},
		{name: "oversized 4097 bytes", path: "/" + strings.Repeat("x", 4096), want: source.ErrInvalidRequest},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			_, err := adapter.ResolveLocalPath(context.Background(), testCase.path)
			if !errors.Is(err, testCase.want) {
				t.Fatalf("ResolveLocalPath(%q) error = %v, want %v", testCase.path, err, testCase.want)
			}
		})
	}
}

// TestResolveLocalPathAcceptsBoundaryLengthPath는 정확히 4096바이트 clean 절대
// 경로가 형태 검증을 통과하고 존재 여부로 판정되는지 증명한다.
func TestResolveLocalPathAcceptsBoundaryLengthPath(t *testing.T) {
	root := t.TempDir()
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})

	prefix := filepath.Join(root, strings.Repeat("y", 4096-len(root)-1))
	if len(prefix) != 4096 {
		t.Skipf("fixture length mismatch: %d", len(prefix))
	}
	_, err := adapter.ResolveLocalPath(context.Background(), prefix)
	if !errors.Is(err, source.ErrEntryNotFound) {
		t.Fatalf("boundary-length missing path error = %v, want %v", err, source.ErrEntryNotFound)
	}
}

// TestResolveLocalPathMapsMissingInaccessibleAndSymlinkTargets는 미존재,
// 접근 불가, symlink 대상의 typed error 매핑을 증명한다.
func TestResolveLocalPathMapsMissingInaccessibleAndSymlinkTargets(t *testing.T) {
	root := t.TempDir()
	hidden := filepath.Join(root, "hidden")
	if err := os.Mkdir(hidden, 0o700); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(hidden, "secret.txt")
	testfixture.CopyFile(t, target, testfixture.PlainText)
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})

	t.Run("missing file", func(t *testing.T) {
		_, err := adapter.ResolveLocalPath(context.Background(), filepath.Join(root, "absent.txt"))
		if !errors.Is(err, source.ErrEntryNotFound) {
			t.Fatalf("missing file error = %v, want %v", err, source.ErrEntryNotFound)
		}
	})
	t.Run("missing parent directory", func(t *testing.T) {
		_, err := adapter.ResolveLocalPath(context.Background(), filepath.Join(root, "absent-dir", "child.txt"))
		if !errors.Is(err, source.ErrEntryNotFound) {
			t.Fatalf("missing parent error = %v, want %v", err, source.ErrEntryNotFound)
		}
	})
	t.Run("inaccessible final target", func(t *testing.T) {
		if os.Geteuid() == 0 {
			t.Skip("root bypasses permission checks")
		}
		if err := os.Chmod(target, 0o000); err != nil {
			t.Fatal(err)
		}
		defer func() { _ = os.Chmod(target, 0o600) }()
		_, err := adapter.ResolveLocalPath(context.Background(), target)
		if !errors.Is(err, source.ErrPermissionDenied) {
			t.Fatalf("inaccessible target error = %v, want %v", err, source.ErrPermissionDenied)
		}
	})
	t.Run("symlink final component", func(t *testing.T) {
		link := filepath.Join(root, "alias.txt")
		if err := os.Symlink(target, link); err != nil {
			t.Fatal(err)
		}
		defer func() { _ = os.Remove(link) }()
		_, err := adapter.ResolveLocalPath(context.Background(), link)
		if !errors.Is(err, source.ErrPathEscape) {
			t.Fatalf("symlink target error = %v, want %v", err, source.ErrPathEscape)
		}
	})
	t.Run("symlink directory component", func(t *testing.T) {
		link := filepath.Join(root, "alias-dir")
		if err := os.Symlink(hidden, link); err != nil {
			t.Fatal(err)
		}
		defer func() { _ = os.Remove(link) }()
		_, err := adapter.ResolveLocalPath(context.Background(), filepath.Join(link, "secret.txt"))
		if !errors.Is(err, source.ErrPathEscape) {
			t.Fatalf("symlink component error = %v, want %v", err, source.ErrPathEscape)
		}
	})
}

// TestResolveLocalPathRejectsOutsideRoot는 루트 밖 절대 경로가 escape으로
// 거절되고 취소된 컨텍스트가 실패로 닫히는지 증명한다.
func TestResolveLocalPathRejectsOutsideRootAndCanceledContext(t *testing.T) {
	root := t.TempDir()
	outsideParent := filepath.Dir(root)
	outside := filepath.Join(outsideParent, "voyager-localpath-outside.txt")
	testfixture.CopyFile(t, outside, testfixture.PlainText)
	defer func() { _ = os.Remove(outside) }()

	adapter := mustAdapter(t, Config{Root: filepath.Join(root, "scope"), Generation: "generation-1", CursorKey: testCursorKey()})
	if err := os.Mkdir(filepath.Join(root, "scope"), 0o700); err != nil {
		t.Fatal(err)
	}

	if _, err := adapter.ResolveLocalPath(context.Background(), outside); !errors.Is(err, source.ErrPathEscape) {
		t.Fatalf("outside-root path error = %v, want %v", err, source.ErrPathEscape)
	}

	canceled, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := adapter.ResolveLocalPath(canceled, filepath.Join(root, "scope")); !errors.Is(err, source.ErrAdapterFailure) {
		t.Fatalf("canceled context error = %v, want %v", err, source.ErrAdapterFailure)
	}
}
