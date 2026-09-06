package localfs

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

func TestLocalFSDeterministicPagination(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "zeta.txt"), "z")
	writeFile(t, filepath.Join(root, "alpha.txt"), "a")
	if err := os.Mkdir(filepath.Join(root, "docs"), 0o700); err != nil {
		t.Fatal(err)
	}

	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})
	request := mustRequest(t, adapter.SourceIdentity(), "mount-local", "", nil)
	first, err := adapter.List(context.Background(), request)
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if got := relativePaths(first.Items); !equalStrings(got, []string{"alpha.txt", "docs"}) {
		t.Fatalf("first paths = %v", got)
	}
	if first.NextChildCursor == nil || *first.NextChildCursor == "" {
		t.Fatal("first NextChildCursor is empty")
	}
	for _, item := range first.Items {
		if item.Identity.SourceID != adapter.SourceIdentity().SourceID || item.Identity.IdentityStrength != entry.IdentityStrengthLocator {
			t.Fatalf("identity = %#v", item.Identity)
		}
		if err := item.Snapshot.Validate(); err != nil {
			t.Fatalf("snapshot Validate() error = %v", err)
		}
		backendLocator := []byte(filepath.Join(root, filepath.FromSlash(item.RelativePath)))
		if !source.ValidateSourceLocator(item.Locator, adapter.cursorKey, backendLocator) {
			t.Fatal("local locator did not validate for its backend path")
		}
		if source.ValidateSourceLocator(item.Locator, bytes.Repeat([]byte{0x99}, 32), backendLocator) {
			t.Fatal("local locator validated with the wrong owner key")
		}
	}
	if !first.Items[1].Capabilities.ListChildren || !first.Items[1].Capabilities.ReadProperties {
		t.Fatalf("directory capabilities = %#v", first.Items[1].Capabilities)
	}

	secondRequest := mustRequest(t, adapter.SourceIdentity(), "mount-local", "", first.NextChildCursor)
	second, err := adapter.List(context.Background(), secondRequest)
	if err != nil {
		t.Fatalf("second List() error = %v", err)
	}
	if got := relativePaths(second.Items); !equalStrings(got, []string{"zeta.txt"}) || second.NextChildCursor != nil {
		t.Fatalf("second result = %#v", second)
	}

	repeat, err := adapter.List(context.Background(), request)
	if err != nil {
		t.Fatal(err)
	}
	if got := relativePaths(repeat.Items); !equalStrings(got, []string{"alpha.txt", "docs"}) {
		t.Fatalf("repeat paths = %v", got)
	}
}

func TestLocalFSIdentityUsesLexicalRoot(t *testing.T) {
	root := t.TempDir()
	configured := filepath.Join(root, "child", "..")
	adapter := mustAdapter(t, Config{Root: configured, Generation: "generation-1", CursorKey: testCursorKey()})
	absolute, err := filepath.Abs(configured)
	if err != nil {
		t.Fatal(err)
	}
	want, err := source.DeriveSourceIdentity("localfs", filepath.Clean(absolute), entry.IdentityStrengthLocator)
	if err != nil {
		t.Fatal(err)
	}
	if adapter.SourceIdentity() != want {
		t.Fatalf("SourceIdentity() = %#v, want %#v", adapter.SourceIdentity(), want)
	}

	frozen, err := source.DeriveSourceIdentity("localfs", "/tmp/voyager-local", entry.IdentityStrengthLocator)
	if err != nil {
		t.Fatal(err)
	}
	const expected = "src:8kHitBFXUPx-VG4Qf_M3LXM1kDu4jXaGZ1JTw9cUiyY"
	if frozen.SourceID != expected {
		t.Fatalf("frozen local source ID = %q, want %q", frozen.SourceID, expected)
	}
	if _, err := source.DeriveSourceIdentity("localfs", strings.Repeat("x", 4097), entry.IdentityStrengthLocator); err != nil {
		t.Fatalf("long lexical source material error = %v", err)
	}
}

func TestCursorMountScope(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"a", "b", "c"} {
		writeFile(t, filepath.Join(root, name), name)
	}
	key := testCursorKey()
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: key})
	first, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-a", "", nil))
	if err != nil || first.NextChildCursor == nil {
		t.Fatalf("first List() = %#v, error = %v", first, err)
	}

	assertInvalidCursor(t, adapter, mustRequest(t, adapter.SourceIdentity(), "mount-b", "", first.NextChildCursor))
	assertInvalidCursor(t, adapter, mustRequest(t, adapter.SourceIdentity(), "mount-a", "other", first.NextChildCursor))

	otherRoot := t.TempDir()
	other := mustAdapter(t, Config{Root: otherRoot, Generation: "generation-1", CursorKey: key})
	assertInvalidCursor(t, other, mustRequest(t, other.SourceIdentity(), "mount-a", "", first.NextChildCursor))

	nextGeneration := mustAdapter(t, Config{Root: root, Generation: "generation-2", CursorKey: key})
	assertInvalidCursor(t, nextGeneration, mustRequest(t, nextGeneration.SourceIdentity(), "mount-a", "", first.NextChildCursor))

	tampered := *first.NextChildCursor
	if tampered[0] == 'A' {
		tampered = "B" + tampered[1:]
	} else {
		tampered = "A" + tampered[1:]
	}
	assertInvalidCursor(t, adapter, mustRequest(t, adapter.SourceIdentity(), "mount-a", "", &tampered))
}

func TestRootConfinement(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	writeFile(t, filepath.Join(outside, "secret.txt"), "secret")
	if err := os.Symlink(outside, filepath.Join(root, "escape")); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(root, "visible.txt"), "visible")
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})

	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-local", "", nil))
	if err != nil {
		t.Fatal(err)
	}
	if got := relativePaths(result.Items); !equalStrings(got, []string{"visible.txt"}) {
		t.Fatalf("root paths = %v", got)
	}

	_, err = adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-local", "escape", nil))
	if !errors.Is(err, source.ErrPathEscape) {
		t.Fatalf("symlink List() error = %v, want %v", err, source.ErrPathEscape)
	}

	invalid := listRequest{SourceID: adapter.SourceIdentity().SourceID, MountID: "mount-local", RelativePath: "../escape"}
	if _, err := adapter.List(context.Background(), invalid); !errors.Is(err, source.ErrInvalidRequest) {
		t.Fatalf("traversal List() error = %v, want %v", err, source.ErrInvalidRequest)
	}

	handle, err := openVerifiedRoot(root)
	if err != nil {
		t.Fatal(err)
	}
	savedRoot := root + "-saved"
	if err := os.Rename(root, savedRoot); err != nil {
		t.Fatal(err)
	}
	replaced := true
	t.Cleanup(func() {
		_ = handle.Close()
		if replaced {
			_ = os.Remove(root)
			_ = os.Rename(savedRoot, root)
		}
	})
	if err := os.Symlink(outside, root); err != nil {
		t.Fatal(err)
	}
	opened, err := handle.Open(".")
	if err != nil {
		t.Fatal(err)
	}
	anchoredEntries, err := opened.ReadDir(-1)
	_ = opened.Close()
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range anchoredEntries {
		if item.Name() == "secret.txt" {
			t.Fatal("descriptor-rooted listing escaped to replacement symlink")
		}
	}
	if _, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-local", "", nil)); !errors.Is(err, source.ErrPathEscape) {
		t.Fatalf("replaced root List() error = %v, want %v", err, source.ErrPathEscape)
	}
	if err := os.Remove(root); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(savedRoot, root); err != nil {
		t.Fatal(err)
	}
	replaced = false
}

func TestLocalFSMissingDirectoryReturnsEntryNotFound(t *testing.T) {
	root := t.TempDir()
	delegate := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})
	adapter := NewResourceAdapter(delegate)
	sourceRef, mountRef := canonicalRefs(t, delegate.SourceIdentity(), "localfs", root, "mount-local", "/local")
	request, err := source.NewAdapterListRequest(sourceRef, mountRef, "missing", 1, nil, []string{})
	if err != nil {
		t.Fatal(err)
	}

	_, err = adapter.List(context.Background(), request)
	if !errors.Is(err, source.ErrEntryNotFound) {
		t.Fatalf("missing directory List() error = %v, want %v", err, source.ErrEntryNotFound)
	}
}

func TestLocalFSDeletedRootReturnsSourceDeleted(t *testing.T) {
	root := t.TempDir()
	delegate := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})
	adapter := NewResourceAdapter(delegate)
	sourceRef, mountRef := canonicalRefs(t, delegate.SourceIdentity(), "localfs", root, "mount-local", "/local")
	request, err := source.NewAdapterListRequest(sourceRef, mountRef, "", 1, nil, []string{})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(root); err != nil {
		t.Fatal(err)
	}

	_, err = adapter.List(context.Background(), request)
	if !errors.Is(err, source.ErrSourceDeleted) {
		t.Fatalf("deleted root List() error = %v, want %v", err, source.ErrSourceDeleted)
	}
}

func TestRootConfinementFinalComponentReplacement(t *testing.T) {
	root := t.TempDir()
	safe := filepath.Join(root, "safe")
	other := filepath.Join(root, "other")
	if err := os.Mkdir(safe, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(other, 0o700); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(safe, "visible.txt"), "visible")
	writeFile(t, filepath.Join(other, "secret.txt"), "secret")

	handle, err := openVerifiedRoot(root)
	if err != nil {
		t.Fatal(err)
	}
	defer handle.Close()
	directory, err := openDirectory(handle, "safe")
	if err != nil {
		t.Fatal(err)
	}
	defer directory.Close()

	saved := filepath.Join(root, "safe-saved")
	if err := os.Rename(safe, saved); err != nil {
		t.Fatal(err)
	}
	replaced := true
	t.Cleanup(func() {
		if replaced {
			_ = os.Remove(safe)
			_ = os.Rename(saved, safe)
		}
	})
	if err := os.Symlink("other", safe); err != nil {
		t.Fatal(err)
	}
	entries, err := directory.ReadDir(-1)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "visible.txt" {
		t.Fatalf("descriptor followed replacement: %v", entries)
	}
	if _, err := openDirectory(handle, "safe"); !errors.Is(err, source.ErrPathEscape) {
		t.Fatalf("replacement symlink open error = %v, want %v", err, source.ErrPathEscape)
	}
	if err := os.Remove(safe); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(saved, safe); err != nil {
		t.Fatal(err)
	}
	replaced = false
}

func TestLocalFSDirectoryBound(t *testing.T) {
	root := t.TempDir()
	for index := 0; index <= maximumDirectoryEntries; index++ {
		writeFile(t, filepath.Join(root, strconv.Itoa(index)), "x")
	}
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})
	_, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-local", "", nil))
	if !errors.Is(err, source.ErrAdapterFailure) {
		t.Fatalf("large directory List() error = %v, want %v", err, source.ErrAdapterFailure)
	}
}

func TestRevisionFallback(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "notes.txt")
	writeFile(t, path, "hello world\n")
	modifiedAt := time.Date(2026, time.August, 2, 12, 0, 0, 0, time.UTC)
	if err := os.Chtimes(path, modifiedAt, modifiedAt); err != nil {
		t.Fatal(err)
	}
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-local", "", nil))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Items) != 1 {
		t.Fatalf("items = %d", len(result.Items))
	}
	const wantMetadata = "meta:BXGuqq0B5ErK4vD-UY-oy6qHeA2q4Rsq91Mdwo5jDAE"
	revision := result.Items[0].Snapshot.Revision
	if revision.Strength != entry.RevisionStrengthMetadata || revision.Token == nil || *revision.Token != wantMetadata {
		t.Fatalf("revision = %#v", revision)
	}

	provider := "provider-revision"
	providerRevision, err := revisionFor(&provider, nil)
	if err != nil || providerRevision.Strength != entry.RevisionStrengthProvider || providerRevision.Token == nil || *providerRevision.Token != provider {
		t.Fatalf("provider revision = %#v, error = %v", providerRevision, err)
	}
	unknown, err := revisionFor(nil, nil)
	if err != nil || unknown.Strength != entry.RevisionStrengthUnknown || unknown.Token != nil {
		t.Fatalf("unknown revision = %#v, error = %v", unknown, err)
	}
}

func mustAdapter(t *testing.T, config Config) *Adapter {
	t.Helper()
	adapter, err := New(config)
	if err != nil {
		t.Fatal(err)
	}
	return adapter
}

func mustRequest(t *testing.T, identity entry.SourceIdentity, mountID, relativePath string, cursor *string) listRequest {
	t.Helper()
	request, err := newListRequest(identity, mountID, relativePath, cursor)
	if err != nil {
		t.Fatal(err)
	}
	return request
}

func assertInvalidCursor(t *testing.T, adapter *Adapter, request listRequest) {
	t.Helper()
	if _, err := adapter.List(context.Background(), request); !errors.Is(err, source.ErrInvalidCursor) {
		t.Fatalf("List() error = %v, want %v", err, source.ErrInvalidCursor)
	}
}

func testCursorKey() []byte { return bytes.Repeat([]byte{0x42}, 32) }

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func relativePaths(items []source.SourceItem) []string {
	paths := make([]string, len(items))
	for index, item := range items {
		paths[index] = item.RelativePath
	}
	return paths
}

func equalStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

func TestResourceAdapterContractLocalFS(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"a", "b", "c"} {
		writeFile(t, filepath.Join(root, name), name)
	}
	delegate := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})
	adapter := NewResourceAdapter(delegate)
	sourceRef, mountRef := canonicalRefs(t, delegate.SourceIdentity(), "localfs", root, "mount-local", "/local")
	request, err := source.NewAdapterListRequest(sourceRef, mountRef, "", 1, nil, []string{})
	if err != nil {
		t.Fatal(err)
	}
	first, err := adapter.List(context.Background(), request)
	if err != nil || len(first.Items) != 1 || first.NextChildCursor == nil {
		t.Fatalf("List() = %#v, %v", first, err)
	}
	resolve, err := source.NewAdapterResolveRequest(sourceRef, mountRef, nil, stringPointer("a"), []string{})
	if err != nil {
		t.Fatal(err)
	}
	resolved, err := adapter.Resolve(context.Background(), resolve)
	if err != nil || resolved.Item == nil || resolved.Item.EntryRef.EntryID != first.Items[0].EntryRef.EntryID {
		t.Fatalf("Resolve() = %#v, %v", resolved, err)
	}
}

func canonicalRefs(t *testing.T, identity entry.SourceIdentity, providerType, account, mountID, point string) (entry.SourceRef, entry.MountRef) {
	t.Helper()
	available, _ := entry.NewAvailability(entry.AvailabilityStateAvailable)
	sourceRef, err := entry.NewSourceRef(identity.SourceID, providerType, account, available, identity.IdentityStrength)
	if err != nil {
		t.Fatal(err)
	}
	path, _ := entry.NewResolvedVirtualPath(mountID, point, "seed")
	mountRef, err := entry.NewMountRef(mountID, "workspace", identity.SourceID, path, available, entry.CachePolicyNone)
	if err != nil {
		t.Fatal(err)
	}
	return sourceRef, mountRef
}

func stringPointer(value string) *string { return &value }

func TestFilesystemRevisionPreservedPerEntry(t *testing.T) {
	root := t.TempDir()
	for index, name := range []string{"a", "b"} {
		path := filepath.Join(root, name)
		writeFile(t, path, strings.Repeat(name, index+1))
		modified := time.Date(2026, time.August, 2, 12+index, 0, 0, 0, time.UTC)
		if err := os.Chtimes(path, modified, modified); err != nil {
			t.Fatal(err)
		}
	}
	delegate := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})
	adapter := NewResourceAdapter(delegate)
	sourceRef, mountRef := canonicalRefs(t, delegate.SourceIdentity(), "localfs", root, "mount-local", "/local")
	request, _ := source.NewAdapterListRequest(sourceRef, mountRef, "", 2, nil, []string{})
	result, err := adapter.List(context.Background(), request)
	if err != nil || len(result.Items) != 2 {
		t.Fatalf("result=%#v err=%v", result, err)
	}
	first, second := result.Items[0].EntrySnapshot.SourceRevision.Revision, result.Items[1].EntrySnapshot.SourceRevision.Revision
	if first.Strength != entry.RevisionStrengthMetadata || second.Strength != entry.RevisionStrengthMetadata || first.Token == nil || second.Token == nil || *first.Token == *second.Token {
		t.Fatalf("revisions=%#v %#v", first, second)
	}
	if result.SourceRevision.Strength != entry.RevisionStrengthUnknown {
		t.Fatalf("scope revision=%#v", result.SourceRevision)
	}
}

func TestIntermediateSymlinkTraversalRejected(t *testing.T) {
	for _, test := range []struct {
		name     string
		external bool
	}{{name: "internal"}, {name: "external", external: true}} {
		t.Run(test.name, func(t *testing.T) {
			root := t.TempDir()
			target := filepath.Join(root, "real")
			if test.external {
				target = t.TempDir()
			}
			if err := os.MkdirAll(filepath.Join(target, "nested"), 0o755); err != nil {
				t.Fatal(err)
			}
			writeFile(t, filepath.Join(target, "nested", "secret.txt"), "secret")
			if err := os.Symlink(target, filepath.Join(root, "link")); err != nil {
				t.Fatal(err)
			}
			adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})
			_, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "link/nested", nil))
			if !errors.Is(err, source.ErrPathEscape) {
				t.Fatalf("intermediate symlink error = %v", err)
			}
		})
	}
}

// TestOpenVerifiedDirectoryScopeContract는 walk가 반환하는 scope의 계약을
// 고정한다. 단일 대상 조회(resolveItem)와 디렉터리 열거(openDirectory)가 같은
// 검증 사슬을 공유하므로, scope는 부모 컴포넌트 symlink 치환을 거절하고 누수
// 없는 소유 규약을 유지해야 한다.
func TestOpenVerifiedDirectoryScopeContract(t *testing.T) {
	rootPath := t.TempDir()
	if err := os.MkdirAll(filepath.Join(rootPath, "nested"), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(rootPath, "nested", "leaf.txt"), "leaf")
	root, err := os.OpenRoot(rootPath)
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()

	if scope, owned, err := openVerifiedDirectoryScope(root, ""); err != nil || scope != root || owned {
		t.Fatalf("empty parent scope = (%v, %v, %v), want (root, false, nil)", scope, owned, err)
	}

	scope, owned, err := openVerifiedDirectoryScope(root, "nested")
	if err != nil {
		t.Fatal(err)
	}
	if !owned || scope == root {
		t.Fatalf("nested scope must be owned and distinct: owned=%v", owned)
	}
	if _, err := scope.Lstat("leaf.txt"); err != nil {
		t.Fatalf("scope must reach the leaf without re-traversal: %v", err)
	}
	scope.Close()

	if err := os.Symlink(rootPath, filepath.Join(rootPath, "escape")); err != nil {
		t.Fatal(err)
	}
	if _, _, err := openVerifiedDirectoryScope(root, "escape/nested"); !errors.Is(err, source.ErrPathEscape) {
		t.Fatalf("symlink component error = %v, want ErrPathEscape", err)
	}
	if _, _, err := openVerifiedDirectoryScope(root, "missing/leaf.txt"); !errors.Is(err, source.ErrEntryNotFound) {
		t.Fatalf("missing component error = %v, want ErrEntryNotFound", err)
	}
}
