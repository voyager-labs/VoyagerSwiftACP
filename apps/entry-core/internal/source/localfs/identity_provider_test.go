package localfs

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/testfixture"
)

type trackingIdentityProvider struct {
	mu      sync.Mutex
	records []trackedObject
	next    int
}

type trackedObject struct {
	info fs.FileInfo
	key  string
}

type objectIdentityProviderFunc func(string, fs.FileInfo) (ObjectIdentity, error)

func (function objectIdentityProviderFunc) Identify(relativePath string, info fs.FileInfo) (ObjectIdentity, error) {
	return function(relativePath, info)
}

func (provider *trackingIdentityProvider) Identify(_ string, info fs.FileInfo) (ObjectIdentity, error) {
	provider.mu.Lock()
	defer provider.mu.Unlock()
	for _, record := range provider.records {
		if os.SameFile(record.info, info) {
			return ObjectIdentity{ObjectKey: record.key, Strength: entry.IdentityStrengthObjectLifetime}, nil
		}
	}
	provider.next++
	identity := ObjectIdentity{ObjectKey: fmt.Sprintf("object-%d", provider.next), Strength: entry.IdentityStrengthObjectLifetime}
	provider.records = append(provider.records, trackedObject{info: info, key: identity.ObjectKey})
	return identity, nil
}

func TestStrongIdentityProvider(t *testing.T) {
	root := t.TempDir()
	testfixture.CopyFile(t, filepath.Join(root, "note.txt"), testfixture.PlainText)
	provider := &trackingIdentityProvider{}
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey(), IdentityProvider: provider})
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-local", "", nil))
	if err != nil || len(result.Items) != 1 {
		t.Fatalf("List() = %#v, %v", result, err)
	}
	if result.Items[0].Identity.EntryKey != "object-1" || result.Items[0].Identity.IdentityStrength != entry.IdentityStrengthObjectLifetime {
		t.Fatalf("identity = %#v", result.Items[0].Identity)
	}

	var typedNil *trackingIdentityProvider
	fallback := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey(), IdentityProvider: typedNil})
	fallbackResult, err := fallback.List(context.Background(), mustRequest(t, fallback.SourceIdentity(), "mount-local", "", nil))
	if err != nil || fallbackResult.Items[0].Identity.EntryKey != "note.txt" || fallbackResult.Items[0].Identity.IdentityStrength != entry.IdentityStrengthLocator {
		t.Fatalf("typed-nil fallback = %#v, %v", fallbackResult, err)
	}

	invalidProviders := []ObjectIdentityProvider{
		objectIdentityProviderFunc(func(string, fs.FileInfo) (ObjectIdentity, error) { return ObjectIdentity{}, nil }),
		objectIdentityProviderFunc(func(string, fs.FileInfo) (ObjectIdentity, error) {
			return ObjectIdentity{ObjectKey: "key", Strength: entry.IdentityStrength("inode")}, nil
		}),
		objectIdentityProviderFunc(func(string, fs.FileInfo) (ObjectIdentity, error) { return ObjectIdentity{}, source.ErrAdapterFailure }),
	}
	for _, invalidProvider := range invalidProviders {
		invalidAdapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey(), IdentityProvider: invalidProvider})
		if _, err := invalidAdapter.List(context.Background(), mustRequest(t, invalidAdapter.SourceIdentity(), "mount-local", "", nil)); !errors.Is(err, source.ErrAdapterFailure) {
			t.Fatalf("invalid provider error = %v", err)
		}
	}
}

func TestGenericLocalFSWeakIdentity(t *testing.T) {
	root := t.TempDir()
	oldPath := filepath.Join(root, "before.txt")
	newPath := filepath.Join(root, "after.txt")
	testfixture.CopyFile(t, oldPath, testfixture.PlainText)
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey()})
	before := onlyLocalItem(t, adapter, "")
	if err := os.Rename(oldPath, newPath); err != nil {
		t.Fatal(err)
	}
	after := onlyLocalItem(t, adapter, "")
	if before.Identity.EntryKey != "before.txt" || after.Identity.EntryKey != "after.txt" || before.Identity.IdentityStrength != entry.IdentityStrengthLocator || after.Identity.IdentityStrength != entry.IdentityStrengthLocator {
		t.Fatalf("generic identities = %#v %#v", before.Identity, after.Identity)
	}
}

func TestRenameMoveIdentity(t *testing.T) {
	root := t.TempDir()
	folder := filepath.Join(root, "folder")
	if err := os.Mkdir(folder, 0o700); err != nil {
		t.Fatal(err)
	}
	oldPath := filepath.Join(root, "note.txt")
	newPath := filepath.Join(folder, "renamed.txt")
	testfixture.CopyFile(t, oldPath, testfixture.PlainText)
	provider := &trackingIdentityProvider{}
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey(), IdentityProvider: provider})
	before := localItemByPath(t, adapter, "", "note.txt")
	if err := os.Rename(oldPath, newPath); err != nil {
		t.Fatal(err)
	}
	after := onlyLocalItem(t, adapter, "folder")
	if before.Identity != after.Identity || before.RelativePath == after.RelativePath {
		t.Fatalf("rename identities = %#v %#v", before, after)
	}
}

func TestDeleteRecreateIdentity(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "note.txt")
	testfixture.CopyFile(t, path, testfixture.PlainText)
	provider := &trackingIdentityProvider{}
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey(), IdentityProvider: provider})
	before := onlyLocalItem(t, adapter, "")
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	testfixture.CopyFile(t, path, testfixture.PlainText)
	after := onlyLocalItem(t, adapter, "")
	if before.Identity.EntryKey == after.Identity.EntryKey || before.Identity.IdentityStrength != entry.IdentityStrengthObjectLifetime || after.Identity.IdentityStrength != entry.IdentityStrengthObjectLifetime {
		t.Fatalf("recreated identities = %#v %#v", before.Identity, after.Identity)
	}
}

func onlyLocalItem(t *testing.T, adapter *Adapter, relativePath string) source.SourceItem {
	t.Helper()
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-local", relativePath, nil))
	if err != nil || len(result.Items) != 1 {
		t.Fatalf("List(%q) = %#v, %v", relativePath, result, err)
	}
	return result.Items[0]
}

func localItemByPath(t *testing.T, adapter *Adapter, parent, relativePath string) source.SourceItem {
	t.Helper()
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount-local", parent, nil))
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range result.Items {
		if item.RelativePath == relativePath {
			return item
		}
	}
	t.Fatalf("item %q not found in %#v", relativePath, result.Items)
	return source.SourceItem{}
}

func TestStrongIdentityResourceAdapterResolveAfterRename(t *testing.T) {
	root := t.TempDir()
	oldPath := filepath.Join(root, "before.txt")
	newPath := filepath.Join(root, "after.txt")
	testfixture.CopyFile(t, oldPath, testfixture.PlainText)
	provider := &trackingIdentityProvider{}
	delegate := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: testCursorKey(), IdentityProvider: provider})
	adapter := NewResourceAdapter(delegate)
	sourceRef, mountRef := canonicalRefs(t, delegate.SourceIdentity(), "localfs", root, "mount-local", "/local")
	listRequest, err := source.NewAdapterListRequest(sourceRef, mountRef, "", 1, nil, []string{})
	if err != nil {
		t.Fatal(err)
	}
	listed, err := adapter.List(context.Background(), listRequest)
	if err != nil || len(listed.Items) != 1 {
		t.Fatalf("List() = %#v, %v", listed, err)
	}
	if err := os.Rename(oldPath, newPath); err != nil {
		t.Fatal(err)
	}
	resolveRequest, err := source.NewAdapterResolveRequest(sourceRef, mountRef, &listed.Items[0].EntryRef, nil, []string{})
	if err != nil {
		t.Fatal(err)
	}
	resolved, err := adapter.Resolve(context.Background(), resolveRequest)
	if err != nil || resolved.Item == nil || resolved.Item.RelativePath != "after.txt" || resolved.Item.EntryRef.EntryID != listed.Items[0].EntryRef.EntryID {
		t.Fatalf("Resolve() = %#v, %v", resolved, err)
	}
}

func TestLegacyLocatorCompatibilityWithLongKey(t *testing.T) {
	root := t.TempDir()
	testfixture.CopyFile(t, filepath.Join(root, "item"), testfixture.PlainText)
	key := bytes.Repeat([]byte{0x31}, 48)
	adapter := mustAdapter(t, Config{Root: root, Generation: "generation-1", CursorKey: key})
	result, err := adapter.List(context.Background(), mustRequest(t, adapter.SourceIdentity(), "mount", "", nil))
	if err != nil || len(result.Items) != 1 {
		t.Fatalf("List() = %#v, %v", result, err)
	}
	backend := []byte(filepath.Join(root, "item"))
	if !source.ValidateSourceLocator(result.Items[0].Locator, key, backend) {
		t.Fatal("legacy locator no longer validates")
	}
}

type sourceNamespaceProviderFunc func(string) (LocalSourceNamespace, error)

func (function sourceNamespaceProviderFunc) SourceNamespace(root string) (LocalSourceNamespace, error) {
	return function(root)
}

func TestStrongIdentityProviderSourceNamespace(t *testing.T) {
	provider := sourceNamespaceProviderFunc(func(string) (LocalSourceNamespace, error) {
		return LocalSourceNamespace{Namespace: "volume-object-lifetime-1", Strength: entry.IdentityStrengthObjectLifetime}, nil
	})
	firstRoot, secondRoot := t.TempDir(), t.TempDir()
	first := mustAdapter(t, Config{Root: firstRoot, Generation: "generation-1", CursorKey: testCursorKey(), SourceNamespaceProvider: provider})
	second := mustAdapter(t, Config{Root: secondRoot, Generation: "generation-1", CursorKey: testCursorKey(), SourceNamespaceProvider: provider})
	if first.SourceIdentity() != second.SourceIdentity() || first.SourceIdentity().IdentityStrength != entry.IdentityStrengthObjectLifetime {
		t.Fatalf("source identities = %#v %#v", first.SourceIdentity(), second.SourceIdentity())
	}
	generic := mustAdapter(t, Config{Root: firstRoot, Generation: "generation-1", CursorKey: testCursorKey()})
	if generic.SourceIdentity().IdentityStrength != entry.IdentityStrengthLocator || generic.SourceIdentity().SourceID == first.SourceIdentity().SourceID {
		t.Fatalf("generic source identity = %#v", generic.SourceIdentity())
	}
	var typedNil *trackingNamespaceProvider
	fallback := mustAdapter(t, Config{Root: firstRoot, Generation: "generation-1", CursorKey: testCursorKey(), SourceNamespaceProvider: typedNil})
	if fallback.SourceIdentity() != generic.SourceIdentity() {
		t.Fatal("typed nil namespace provider did not fall back to root locator")
	}
}

type trackingNamespaceProvider struct{}

func (*trackingNamespaceProvider) SourceNamespace(string) (LocalSourceNamespace, error) {
	return LocalSourceNamespace{Namespace: "unused", Strength: entry.IdentityStrengthObjectLifetime}, nil
}
