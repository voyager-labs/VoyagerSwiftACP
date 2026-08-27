package localfs

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

const (
	pageSize                = 2
	maximumDirectoryEntries = 1024
	minimumCursorKeySize    = 32
	maximumGeneration       = 128
	maximumCursorLength     = 4096
	maximumLocalPathBytes   = 4096
	cursorPayloadSize       = 4 + sha256.Size
	cursorTokenSize         = cursorPayloadSize + sha256.Size
)

type Config struct {
	Root                    string
	Generation              string
	CursorKey               []byte
	IdentityProvider        ObjectIdentityProvider
	SourceNamespaceProvider LocalSourceNamespaceProvider
}

type Adapter struct {
	root             string
	identity         entry.SourceIdentity
	generation       string
	cursorKey        []byte
	identityProvider ObjectIdentityProvider
}

type listRequest struct {
	SourceID, MountID, RelativePath string
	ChildCursor                     *string
}

func (request listRequest) Validate() error {
	if !source.ValidateRelativePath(request.RelativePath) || !utf8.ValidString(request.SourceID) || len(request.SourceID) < 1 || !utf8.ValidString(request.MountID) || len(request.MountID) < 1 || len(request.MountID) > 128 || request.ChildCursor != nil && (!utf8.ValidString(*request.ChildCursor) || len(*request.ChildCursor) < 1 || len(*request.ChildCursor) > maximumCursorLength) {
		return source.ErrInvalidRequest
	}
	return nil
}

func newListRequest(identity entry.SourceIdentity, mountID, relativePath string, childCursor *string) (listRequest, error) {
	request := listRequest{SourceID: identity.SourceID, MountID: mountID, RelativePath: relativePath, ChildCursor: cloneString(childCursor)}
	if identity.Validate() != nil || !source.ValidateRelativePath(relativePath) || !utf8.ValidString(mountID) || len(mountID) < 1 || len(mountID) > 128 || request.ChildCursor != nil && (!utf8.ValidString(*request.ChildCursor) || len(*request.ChildCursor) < 1 || len(*request.ChildCursor) > maximumCursorLength) {
		return listRequest{}, source.ErrInvalidRequest
	}
	return request, nil
}

type listResult struct {
	Items           []source.SourceItem
	NextChildCursor *string
}

func newListResult(items []source.SourceItem, next *string) (listResult, error) {
	if len(items) > maximumDirectoryEntries || next != nil && (!utf8.ValidString(*next) || len(*next) < 1 || len(*next) > maximumCursorLength) {
		return listResult{}, source.ErrAdapterFailure
	}
	copyItems := append([]source.SourceItem(nil), items...)
	return listResult{Items: copyItems, NextChildCursor: cloneString(next)}, nil
}

type metadataProfile = source.MetadataProfile

func New(config Config) (*Adapter, error) {
	if config.Root == "" || !utf8.ValidString(config.Root) || !validGeneration(config.Generation) || len(config.CursorKey) < minimumCursorKeySize {
		return nil, source.ErrInvalidConfig
	}
	absolute, err := filepath.Abs(config.Root)
	if err != nil {
		return nil, source.ErrInvalidConfig
	}
	root := filepath.Clean(absolute)
	namespaceMaterial := root
	namespaceStrength := entry.IdentityStrengthLocator
	if provider := normalizeSourceNamespaceProvider(config.SourceNamespaceProvider); provider != nil {
		namespace, namespaceErr := provider.SourceNamespace(root)
		if namespaceErr != nil || namespace.Validate() != nil {
			return nil, source.ErrInvalidConfig
		}
		namespaceMaterial = namespace.Namespace
		namespaceStrength = namespace.Strength
	}
	identity, err := source.DeriveSourceIdentity("localfs", namespaceMaterial, namespaceStrength)
	if err != nil {
		return nil, source.ErrInvalidConfig
	}
	return &Adapter{
		root:             root,
		identity:         identity,
		generation:       config.Generation,
		cursorKey:        append([]byte(nil), config.CursorKey...),
		identityProvider: normalizeIdentityProvider(config.IdentityProvider),
	}, nil
}

func (adapter *Adapter) SourceIdentity() entry.SourceIdentity {
	return adapter.identity
}

func (adapter *Adapter) List(ctx context.Context, request listRequest) (listResult, error) {
	return adapter.listWithLimit(ctx, request, pageSize)
}

func (adapter *Adapter) listWithLimit(ctx context.Context, request listRequest, limit int) (listResult, error) {
	if err := request.Validate(); err != nil || request.SourceID != adapter.identity.SourceID {
		return listResult{}, source.ErrInvalidRequest
	}
	if err := ctx.Err(); err != nil {
		return listResult{}, source.ErrAdapterFailure
	}

	offset := 0
	if request.ChildCursor != nil {
		decoded, err := adapter.decodeCursor(*request.ChildCursor, request)
		if err != nil {
			return listResult{}, err
		}
		offset = decoded
	}

	root, err := openVerifiedRoot(adapter.root)
	if err != nil {
		return listResult{}, err
	}
	defer root.Close()
	directory, err := openDirectory(root, request.RelativePath)
	if err != nil {
		return listResult{}, err
	}
	defer directory.Close()
	entries, err := directory.ReadDir(maximumDirectoryEntries + 1)
	if err != nil && !errors.Is(err, io.EOF) {
		return listResult{}, source.ErrAdapterFailure
	}
	if len(entries) > maximumDirectoryEntries {
		return listResult{}, source.ErrAdapterFailure
	}
	sort.Slice(entries, func(left, right int) bool { return entries[left].Name() < entries[right].Name() })

	items := make([]source.SourceItem, 0, len(entries))
	for _, directoryEntry := range entries {
		if err := ctx.Err(); err != nil {
			return listResult{}, source.ErrAdapterFailure
		}
		if directoryEntry.Type()&os.ModeSymlink != 0 {
			continue
		}
		item, err := adapter.makeItem(request.RelativePath, directoryEntry)
		if err != nil {
			return listResult{}, err
		}
		items = append(items, item)
	}
	if offset < 0 || offset > len(items) {
		return listResult{}, source.ErrInvalidCursor
	}

	end := offset + limit
	if end > len(items) {
		end = len(items)
	}
	var nextCursor *string
	if end < len(items) {
		encoded := adapter.encodeCursor(end, request)
		nextCursor = &encoded
	}
	return newListResult(items[offset:end], nextCursor)
}

func openVerifiedRoot(path string) (*os.Root, error) {
	before, err := os.Lstat(path)
	if err != nil {
		return nil, localFilesystemError(err, source.ErrSourceDeleted)
	}
	if before.Mode()&os.ModeSymlink != 0 || !before.IsDir() {
		return nil, source.ErrPathEscape
	}
	root, err := os.OpenRoot(path)
	if err != nil {
		return nil, localFilesystemError(err, source.ErrSourceDeleted)
	}
	opened, err := root.Stat(".")
	if err != nil {
		_ = root.Close()
		return nil, source.ErrAdapterFailure
	}
	after, err := os.Lstat(path)
	if err != nil {
		_ = root.Close()
		return nil, localFilesystemError(err, source.ErrSourceDeleted)
	}
	if after.Mode()&os.ModeSymlink != 0 || !os.SameFile(before, opened) || !os.SameFile(after, opened) {
		_ = root.Close()
		return nil, source.ErrPathEscape
	}
	return root, nil
}

func openDirectory(root *os.Root, relativePath string) (*os.File, error) {
	if !source.ValidateRelativePath(relativePath) {
		return nil, source.ErrInvalidRequest
	}
	current := root
	owned := false
	closeOwned := func() {
		if owned {
			_ = current.Close()
		}
	}
	if relativePath != "" {
		for _, component := range strings.Split(relativePath, "/") {
			before, err := current.Lstat(component)
			if err != nil {
				closeOwned()
				return nil, localFilesystemError(err, source.ErrEntryNotFound)
			}
			if before.Mode()&os.ModeSymlink != 0 || !before.IsDir() {
				closeOwned()
				return nil, source.ErrPathEscape
			}
			next, err := current.OpenRoot(component)
			if err != nil {
				closeOwned()
				return nil, localFilesystemError(err, source.ErrEntryNotFound)
			}
			opened, openedErr := next.Lstat(".")
			after, afterErr := current.Lstat(component)
			if openedErr != nil {
				_ = next.Close()
				closeOwned()
				return nil, source.ErrAdapterFailure
			}
			if afterErr != nil {
				_ = next.Close()
				closeOwned()
				return nil, localFilesystemError(afterErr, source.ErrEntryNotFound)
			}
			if after.Mode()&os.ModeSymlink != 0 || !os.SameFile(before, opened) || !os.SameFile(after, opened) {
				_ = next.Close()
				closeOwned()
				return nil, source.ErrPathEscape
			}
			closeOwned()
			current, owned = next, true
		}
	}
	before, err := current.Lstat(".")
	if err != nil {
		closeOwned()
		return nil, localFilesystemError(err, source.ErrEntryNotFound)
	}
	if before.Mode()&os.ModeSymlink != 0 || !before.IsDir() {
		closeOwned()
		return nil, source.ErrPathEscape
	}
	directory, err := current.Open(".")
	if err != nil {
		closeOwned()
		return nil, localFilesystemError(err, source.ErrEntryNotFound)
	}
	opened, openedErr := directory.Stat()
	after, afterErr := current.Lstat(".")
	closeOwned()
	if openedErr != nil {
		_ = directory.Close()
		return nil, source.ErrAdapterFailure
	}
	if afterErr != nil {
		_ = directory.Close()
		return nil, localFilesystemError(afterErr, source.ErrEntryNotFound)
	}
	if !opened.IsDir() || after.Mode()&os.ModeSymlink != 0 || !os.SameFile(before, opened) || !os.SameFile(after, opened) {
		_ = directory.Close()
		return nil, source.ErrPathEscape
	}
	return directory, nil
}

func localFilesystemError(err, notExist error) error {
	if errors.Is(err, fs.ErrNotExist) {
		return notExist
	}
	return source.ErrAdapterFailure
}

func (adapter *Adapter) makeItem(parent string, directoryEntry os.DirEntry) (source.SourceItem, error) {
	info, err := directoryEntry.Info()
	if err != nil || info.Mode()&os.ModeSymlink != 0 {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	return adapter.makeItemFromInfo(parent, directoryEntry.Name(), info)
}

// makeItemFromInfo는 FileInfo에서 SourceItem을 만든다. symlink는 이미 걸러진
// 상태로 들어온다.
func (adapter *Adapter) makeItemFromInfo(parent, name string, info os.FileInfo) (source.SourceItem, error) {
	if !utf8.ValidString(name) {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	relativePath := name
	if parent != "" {
		relativePath = parent + "/" + name
	}
	if !source.ValidateRelativePath(relativePath) {
		return source.SourceItem{}, source.ErrAdapterFailure
	}

	resourceType := "other"
	capabilities := entry.Capabilities{ReadProperties: true}
	var sizeBytes *int64
	switch {
	case info.IsDir():
		resourceType = "directory"
		capabilities.ListChildren = true
	case info.Mode().IsRegular():
		resourceType = "file"
		size := info.Size()
		sizeBytes = &size
	}
	modifiedAt := info.ModTime().Round(0)
	properties := []entry.Property{}
	revision, err := revisionFor(nil, &metadataProfile{
		ProfileName:  "local",
		ResourceType: resourceType,
		Name:         name,
		RelativePath: relativePath,
		SizeBytes:    sizeBytes,
		ModifiedAt:   &modifiedAt,
		Properties:   properties,
	})
	if err != nil {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	objectIdentity, err := adapter.identityProvider.Identify(relativePath, info)
	if err != nil || objectIdentity.Validate() != nil {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	identity, err := entry.NewEntryIdentity(adapter.identity.SourceID, objectIdentity.ObjectKey, objectIdentity.Strength)
	if err != nil {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	snapshot, err := entry.NewEntrySnapshot(
		name,
		resourceType,
		sizeBytes,
		&modifiedAt,
		properties,
		revision,
		entry.Availability{State: entry.AvailabilityStateAvailable},
		entry.Freshness{State: entry.FreshnessStateCurrent},
		entry.OperationState{State: entry.OperationStateIdle},
	)
	if err != nil {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	backendLocator := []byte(filepath.Join(adapter.root, filepath.FromSlash(relativePath)))
	locator, err := source.NewSourceLocator(adapter.cursorKey, backendLocator)
	if err != nil || !source.ValidateSourceLocator(locator, adapter.cursorKey, backendLocator) {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	return source.NewSourceItem(relativePath, identity, snapshot, locator, capabilities)
}

func revisionFor(providerToken *string, metadata *metadataProfile) (entry.Revision, error) {
	return source.ResolveRevision(providerToken, metadata)
}

func (adapter *Adapter) encodeCursor(offset int, request listRequest) string {
	payload := make([]byte, cursorPayloadSize)
	binary.BigEndian.PutUint32(payload[:4], uint32(offset))
	digest := cursorScopeDigest(request.SourceID, request.MountID, request.RelativePath, adapter.generation)
	copy(payload[4:], digest[:])
	mac := hmac.New(sha256.New, adapter.cursorKey)
	_, _ = mac.Write(payload)
	return base64.RawURLEncoding.EncodeToString(append(payload, mac.Sum(nil)...))
}

func (adapter *Adapter) decodeCursor(token string, request listRequest) (int, error) {
	decoded, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(decoded) != cursorTokenSize {
		return 0, source.ErrInvalidCursor
	}
	payload := decoded[:cursorPayloadSize]
	mac := hmac.New(sha256.New, adapter.cursorKey)
	_, _ = mac.Write(payload)
	if !hmac.Equal(decoded[cursorPayloadSize:], mac.Sum(nil)) {
		return 0, source.ErrInvalidCursor
	}
	digest := cursorScopeDigest(request.SourceID, request.MountID, request.RelativePath, adapter.generation)
	if !hmac.Equal(payload[4:], digest[:]) {
		return 0, source.ErrInvalidCursor
	}
	return int(binary.BigEndian.Uint32(payload[:4])), nil
}

func cursorScopeDigest(sourceID, mountID, relativePath, generation string) [sha256.Size]byte {
	var payload bytes.Buffer
	for _, value := range []string{sourceID, mountID, relativePath, generation} {
		_ = binary.Write(&payload, binary.BigEndian, uint64(len(value)))
		_, _ = payload.WriteString(value)
	}
	return sha256.Sum256(payload.Bytes())
}

func validGeneration(generation string) bool {
	return utf8.ValidString(generation) && len(generation) >= 1 && len(generation) <= maximumGeneration
}

type ResourceAdapter struct{ delegate *Adapter }

func NewResourceAdapter(adapter *Adapter) *ResourceAdapter {
	return &ResourceAdapter{delegate: adapter}
}

func (adapter *ResourceAdapter) List(ctx context.Context, request source.AdapterListRequest) (source.AdapterListResult, error) {
	if adapter == nil || adapter.delegate == nil || request.Validate() != nil || request.SourceRef.SourceInstanceID != adapter.delegate.identity.SourceID {
		return source.AdapterListResult{}, source.ErrInvalidRequest
	}
	listRequest, err := newListRequest(adapter.delegate.identity, request.MountRef.MountID, request.RelativePath, request.ChildCursor)
	if err != nil {
		return source.AdapterListResult{}, err
	}
	listResult, err := adapter.delegate.listWithLimit(ctx, listRequest, request.PageQuota)
	if err != nil {
		return source.AdapterListResult{}, err
	}
	observedAt := timeNowUTC()
	revision, _ := entry.NewRevision(entry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := entry.NewSourceRevision(revision)
	freshness, _ := entry.NewFreshness(entry.FreshnessStateCurrent, observedAt, sourceRevision, nil, nil)
	available, _ := entry.NewAvailability(entry.AvailabilityStateAvailable)
	items := make([]source.AdapterEntry, len(listResult.Items))
	for index, item := range listResult.Items {
		locatorRef, locatorErr := adapter.delegate.canonicalLocatorRef(item)
		if locatorErr != nil {
			return source.AdapterListResult{}, locatorErr
		}
		items[index], err = source.CanonicalizeSourceItemWithLocator(item, locatorRef, request.RequestedProperties, request.PropertyDefinitions, request.SourceSelectors, request.ReadTransforms, observedAt, revision, available, freshness, entry.PropertyProvenanceFilesystem)
		if err != nil {
			return source.AdapterListResult{}, source.ErrAdapterFailure
		}
	}
	result := source.AdapterListResult{Items: items, NextChildCursor: cloneString(listResult.NextChildCursor), SourceRevision: revision, Availability: available, Freshness: freshness, Warnings: []source.Warning{}}
	if result.Validate(request.PageQuota) != nil {
		return source.AdapterListResult{}, source.ErrAdapterFailure
	}
	return result, nil
}

func (adapter *ResourceAdapter) Resolve(ctx context.Context, request source.AdapterResolveRequest) (source.AdapterResolveResult, error) {
	if adapter == nil || adapter.delegate == nil || request.Validate() != nil || request.SourceRef.SourceInstanceID != adapter.delegate.identity.SourceID {
		return source.AdapterResolveResult{}, source.ErrInvalidRequest
	}
	var item source.SourceItem
	var found bool
	var err error
	if request.RelativePath != nil {
		item, found, err = adapter.delegate.resolveItem(ctx, *request.RelativePath)
	} else if request.EntryRef.IdentityStrength == entry.IdentityStrengthLocator && source.ValidateRelativePath(request.EntryRef.SourceObjectKey) {
		item, found, err = adapter.delegate.resolveItem(ctx, request.EntryRef.SourceObjectKey)
	} else {
		item, found, err = adapter.delegate.resolveObjectKey(ctx, request.EntryRef.SourceObjectKey)
	}
	if err != nil {
		return source.AdapterResolveResult{}, err
	}
	observedAt := timeNowUTC()
	revision, _ := entry.NewRevision(entry.RevisionStrengthUnknown, nil)
	if found {
		revision = item.Snapshot.Revision
	}
	sourceRevision, _ := entry.NewSourceRevision(revision)
	freshness, _ := entry.NewFreshness(entry.FreshnessStateCurrent, observedAt, sourceRevision, nil, nil)
	available, _ := entry.NewAvailability(entry.AvailabilityStateAvailable)
	result := source.AdapterResolveResult{SourceRevision: revision, Availability: available, Freshness: freshness, Warnings: []source.Warning{}}
	if !found {
		result.SourceError, _ = source.NewSourceError(source.SourceErrorCodeEntryNotFound)
		if result.Validate() != nil {
			return source.AdapterResolveResult{}, source.ErrAdapterFailure
		}
		return result, nil
	}
	locatorRef, err := adapter.delegate.canonicalLocatorRef(item)
	if err != nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	canonical, err := source.CanonicalizeSourceItemWithLocator(item, locatorRef, request.RequestedProperties, request.PropertyDefinitions, request.SourceSelectors, request.ReadTransforms, observedAt, revision, available, freshness, entry.PropertyProvenanceFilesystem)
	if err != nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	if request.EntryRef != nil && canonical.EntryRef.EntryID != request.EntryRef.EntryID {
		result.SourceError, _ = source.NewSourceError(source.SourceErrorCodeEntryNotFound)
		return result, nil
	}
	result.Item = &canonical
	if result.Validate() != nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	return result, nil
}

func (adapter *Adapter) resolveItem(ctx context.Context, relativePath string) (source.SourceItem, bool, error) {
	if !source.ValidateRelativePath(relativePath) || relativePath == "" {
		return source.SourceItem{}, false, nil
	}
	if err := ctx.Err(); err != nil {
		return source.SourceItem{}, false, source.ErrAdapterFailure
	}
	root, err := openVerifiedRoot(adapter.root)
	if err != nil {
		return source.SourceItem{}, false, err
	}
	defer root.Close()
	parent, name := filepath.Split(relativePath)
	parent = filepath.ToSlash(filepath.Clean(parent))
	if parent == "." {
		parent = ""
	}
	parent = strings.TrimSuffix(parent, "/")
	directory, err := openDirectory(root, parent)
	if err != nil {
		return source.SourceItem{}, false, err
	}
	defer directory.Close()
	// 단일 대상 해석은 부모를 열거하지 않는다. 목록 API의 디렉터리 예산
	// (1,024)을 여기 전파하면 큰 폴더의 존재하는 파일을 ErrAdapterFailure로
	// 거절한다. Lstat 직접 조회로 이름을 찾고 symlink는 목록 경로와 동일하게
	// 부재로 취급한다.
	info, statErr := os.Lstat(filepath.Join(root.Name(), filepath.FromSlash(relativePath)))
	if statErr != nil {
		// 부재와 이름 길이 초과(4,096 경계 경로)는 목록 경로와 동일하게
		// 부재로 취급한다. 나머지 오류만 접근 실패로 실패 닫기한다.
		if errors.Is(statErr, fs.ErrNotExist) || errors.Is(statErr, syscall.ENAMETOOLONG) {
			return source.SourceItem{}, false, nil
		}
		return source.SourceItem{}, false, source.ErrAdapterFailure
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return source.SourceItem{}, false, nil
	}
	item, makeErr := adapter.makeItemFromInfo(parent, name, info)
	return item, makeErr == nil, makeErr
}

func (adapter *Adapter) canonicalLocatorRef(item source.SourceItem) (entry.LocatorRef, error) {
	backendLocator := []byte(filepath.Join(adapter.root, filepath.FromSlash(item.RelativePath)))
	locator, err := source.NewCanonicalSourceLocator(adapter.cursorKey[:minimumCursorKeySize], "localfs", adapter.identity.SourceID, backendLocator)
	if err != nil {
		return entry.LocatorRef{}, err
	}
	return locator.LocatorRef()
}

// ResolveLocalPath는 소스 루트 기준 clean 절대 UTF-8 경로 하나를 canonical
// EntryRef로 해석한다. 원시 경로는 identity 재구성 입력으로만 쓰고 결과에는
// locator 유도 값만 남으며 rename/move 연속성은 보장하지 않는다.
func (adapter *Adapter) ResolveLocalPath(ctx context.Context, localPath string) (entry.EntryRef, error) {
	if err := ctx.Err(); err != nil {
		return entry.EntryRef{}, source.ErrAdapterFailure
	}
	if !utf8.ValidString(localPath) || len(localPath) < 1 || len(localPath) > maximumLocalPathBytes ||
		strings.ContainsRune(localPath, '\x00') || !filepath.IsAbs(localPath) || filepath.Clean(localPath) != localPath {
		return entry.EntryRef{}, source.ErrInvalidRequest
	}
	relativePath, err := filepath.Rel(adapter.root, localPath)
	if err != nil {
		return entry.EntryRef{}, source.ErrPathEscape
	}
	relativePath = filepath.ToSlash(relativePath)
	if relativePath == "." {
		// 소스 루트 자체는 assignment 대상 entry가 아니다.
		return entry.EntryRef{}, source.ErrInvalidRequest
	}
	if !source.ValidateRelativePath(relativePath) {
		return entry.EntryRef{}, source.ErrPathEscape
	}
	item, found, err := adapter.resolveItem(ctx, relativePath)
	if err != nil {
		return entry.EntryRef{}, err
	}
	if !found {
		return entry.EntryRef{}, classifyMissingLocalPath(localPath)
	}
	if err := verifyLocalPathAccessible(adapter.root, relativePath); err != nil {
		return entry.EntryRef{}, err
	}
	locatorRef, err := adapter.canonicalLocatorRef(item)
	if err != nil {
		return entry.EntryRef{}, source.ErrAdapterFailure
	}
	entryID := entry.DeriveEntryID(adapter.identity.SourceID, item.Snapshot.ResourceType, item.Identity.EntryKey)
	ref, err := entry.NewEntryRef(entryID, adapter.identity.SourceID, item.Identity.EntryKey, item.Snapshot.ResourceType, locatorRef, item.Identity.IdentityStrength)
	if err != nil {
		return entry.EntryRef{}, source.ErrAdapterFailure
	}
	return ref, nil
}

// classifyMissingLocalPath는 walk가 대상을 찾지 못한 원인을 존재·권한·어댑터가
// 다루지 않는 대상(symlink 등)으로 분류한다.
func classifyMissingLocalPath(localPath string) error {
	_, statErr := os.Lstat(localPath)
	switch {
	case statErr == nil:
		return source.ErrPathEscape
	case errors.Is(statErr, fs.ErrPermission):
		return source.ErrPermissionDenied
	default:
		return source.ErrEntryNotFound
	}
}

// verifyLocalPathAccessible은 최종 대상을 실제로 열어 접근 가능함을 확인한다.
// ponytail: 부모 순회 중간의 권한 오류는 openDirectory가 ErrAdapterFailure로
// 닫는다. 경로별 권한 정밀 분류가 필요해지면 openDirectory에 cause 매핑을 추가한다.
func verifyLocalPathAccessible(rootPath, relativePath string) error {
	root, err := os.OpenRoot(rootPath)
	if err != nil {
		return source.ErrAdapterFailure
	}
	defer root.Close()
	probe, err := root.Open(relativePath)
	if err != nil {
		if errors.Is(err, fs.ErrPermission) {
			return source.ErrPermissionDenied
		}
		return source.ErrAdapterFailure
	}
	return probe.Close()
}

func (adapter *Adapter) resolveObjectKey(ctx context.Context, objectKey string) (source.SourceItem, bool, error) {
	if objectKey == "" {
		return source.SourceItem{}, false, nil
	}
	root, err := openVerifiedRoot(adapter.root)
	if err != nil {
		return source.SourceItem{}, false, err
	}
	defer root.Close()
	queue := []string{""}
	visited := 0
	for len(queue) > 0 {
		if err := ctx.Err(); err != nil {
			return source.SourceItem{}, false, source.ErrAdapterFailure
		}
		parent := queue[0]
		queue = queue[1:]
		directory, openErr := openDirectory(root, parent)
		if openErr != nil {
			return source.SourceItem{}, false, openErr
		}
		entries, readErr := directory.ReadDir(maximumDirectoryEntries + 1)
		_ = directory.Close()
		if readErr != nil && !errors.Is(readErr, io.EOF) {
			return source.SourceItem{}, false, source.ErrAdapterFailure
		}
		sort.Slice(entries, func(left, right int) bool { return entries[left].Name() < entries[right].Name() })
		for _, candidate := range entries {
			if candidate.Type()&os.ModeSymlink != 0 {
				continue
			}
			visited++
			if visited > maximumDirectoryEntries {
				return source.SourceItem{}, false, source.ErrAdapterFailure
			}
			item, makeErr := adapter.makeItem(parent, candidate)
			if makeErr != nil {
				return source.SourceItem{}, false, makeErr
			}
			if item.Identity.EntryKey == objectKey {
				return item, true, nil
			}
			if item.Capabilities.ListChildren {
				queue = append(queue, item.RelativePath)
			}
		}
	}
	return source.SourceItem{}, false, nil
}

func cloneString(value *string) *string {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}
func timeNowUTC() time.Time { return time.Now().Round(0).UTC() }
