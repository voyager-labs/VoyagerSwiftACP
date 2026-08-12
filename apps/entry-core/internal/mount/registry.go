package mount

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync"
	"unicode/utf8"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

var (
	ErrInvalidPath          = errors.New("invalid path")
	ErrInvalidMount         = errors.New("invalid mount")
	ErrDuplicateMountID     = errors.New("duplicate mount id")
	ErrDuplicateMountPrefix = errors.New("duplicate mount prefix")
	ErrMountNotFound        = errors.New("mount not found")
	ErrTooManyMounts        = errors.New("too many mounts")
)

const (
	maximumVirtualPathBytes = 4096
	maximumMountIDBytes     = 128
	maximumWorkspaceMounts  = 64
)

type Mount struct {
	ID            string
	Source        entry.SourceIdentity
	VirtualPrefix string
}

type Resolution struct {
	Source       entry.SourceIdentity
	MountID      string
	RelativePath string
}

type Registry struct {
	mu         sync.RWMutex
	mounts     []registeredMount
	byID       map[string]registeredMount
	canonical  []entry.MountRef
	generation uint64
}

type MountRegistrySnapshot struct {
	generation uint64
	mounts     []entry.MountRef
	byID       map[string]entry.MountRef
}

func (snapshot MountRegistrySnapshot) Generation() uint64 { return snapshot.generation }

func (snapshot MountRegistrySnapshot) ListMounts(workspaceID string) []entry.MountRef {
	if !validWorkspaceID(workspaceID) {
		return []entry.MountRef{}
	}
	result := make([]entry.MountRef, 0)
	for _, ref := range snapshot.mounts {
		if ref.WorkspaceID == workspaceID && ref.MountStatus.State != entry.AvailabilityStateUnmounted {
			result = append(result, ref)
		}
	}
	return append([]entry.MountRef(nil), result...)
}

func (snapshot MountRegistrySnapshot) ListAllMounts() []entry.MountRef {
	result := make([]entry.MountRef, 0, len(snapshot.mounts))
	for _, ref := range snapshot.mounts {
		if ref.MountStatus.State != entry.AvailabilityStateUnmounted {
			result = append(result, ref)
		}
	}
	return append([]entry.MountRef(nil), result...)
}

func (snapshot MountRegistrySnapshot) MountByID(workspaceID, mountID string) (entry.MountRef, error) {
	ref, ok := snapshot.byID[mountID]
	if !ok || ref.WorkspaceID != workspaceID || ref.MountStatus.State == entry.AvailabilityStateUnmounted {
		return entry.MountRef{}, ErrMountNotFound
	}
	return ref, nil
}

func (snapshot MountRegistrySnapshot) ResolveVirtualPath(workspaceID, raw string) (entry.MountRef, string, error) {
	virtualPath, err := NormalizeVirtualPath(raw)
	if err != nil {
		return entry.MountRef{}, "", err
	}
	value := virtualPath.String()
	var selected *entry.MountRef
	for index := range snapshot.mounts {
		candidate := &snapshot.mounts[index]
		if candidate.WorkspaceID != workspaceID || candidate.MountStatus.State == entry.AvailabilityStateUnmounted || !matchesPrefix(value, candidate.MountPoint.String()) {
			continue
		}
		if selected == nil || len(candidate.MountPoint.String()) > len(selected.MountPoint.String()) || len(candidate.MountPoint.String()) == len(selected.MountPoint.String()) && lessMountRef(*candidate, *selected) {
			copy := *candidate
			selected = &copy
		}
	}
	if selected == nil {
		return entry.MountRef{}, "", ErrMountNotFound
	}
	relative := relativeToPrefix(value, selected.MountPoint.String())
	if !validRelativePath(relative) {
		return entry.MountRef{}, "", ErrInvalidPath
	}
	return *selected, relative, nil
}

func (snapshot MountRegistrySnapshot) ReverseVirtualPath(mountID, relativePath string) (entry.VirtualPath, error) {
	selected, ok := snapshot.byID[mountID]
	if !ok {
		return entry.VirtualPath{}, ErrMountNotFound
	}
	if !validRelativePath(relativePath) {
		return entry.VirtualPath{}, ErrInvalidPath
	}
	value := selected.MountPoint.String()
	if relativePath != "" {
		if value == "/" {
			value += relativePath
		} else {
			value += "/" + relativePath
		}
	}
	return entry.NewResolvedVirtualPath(mountID, value, fmt.Sprintf("%d", snapshot.generation))
}

func (registry *Registry) Snapshot() MountRegistrySnapshot {
	if registry == nil {
		return MountRegistrySnapshot{mounts: []entry.MountRef{}, byID: map[string]entry.MountRef{}}
	}
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	mounts := append([]entry.MountRef(nil), registry.canonical...)
	byID := make(map[string]entry.MountRef, len(mounts))
	for _, ref := range mounts {
		byID[ref.MountID] = ref
	}
	return MountRegistrySnapshot{generation: registry.generation, mounts: mounts, byID: byID}
}

type registeredMount struct {
	id     string
	source entry.SourceIdentity
	prefix entry.VirtualPath
}

func NormalizeVirtualPath(raw string) (entry.VirtualPath, error) {
	if !validRawVirtualPath(raw) {
		return entry.VirtualPath{}, ErrInvalidPath
	}

	segments := make([]string, 0, strings.Count(raw, "/"))
	for _, segment := range strings.Split(raw[1:], "/") {
		if segment == "" {
			continue
		}
		if segment == "." || segment == ".." {
			return entry.VirtualPath{}, ErrInvalidPath
		}
		segments = append(segments, segment)
	}

	normalized := "/"
	if len(segments) > 0 {
		normalized += strings.Join(segments, "/")
	}
	if len(normalized) > maximumVirtualPathBytes {
		return entry.VirtualPath{}, ErrInvalidPath
	}

	virtualPath, err := entry.NewVirtualPath(normalized)
	if err != nil {
		return entry.VirtualPath{}, fmt.Errorf("%w: %w", ErrInvalidPath, err)
	}
	return virtualPath, nil
}

func NewRegistry(mounts []Mount) (*Registry, error) {
	registered := make([]registeredMount, 0, len(mounts))
	byID := make(map[string]registeredMount, len(mounts))
	prefixes := make(map[string]struct{}, len(mounts))

	for _, candidate := range mounts {
		if !validMountID(candidate.ID) {
			return nil, ErrInvalidMount
		}
		if err := candidate.Source.Validate(); err != nil {
			return nil, fmt.Errorf("%w: %w", ErrInvalidMount, err)
		}
		prefix, err := NormalizeVirtualPath(candidate.VirtualPrefix)
		if err != nil {
			return nil, err
		}
		if _, exists := byID[candidate.ID]; exists {
			return nil, ErrDuplicateMountID
		}
		if _, exists := prefixes[prefix.String()]; exists {
			return nil, ErrDuplicateMountPrefix
		}

		mount := registeredMount{id: candidate.ID, source: candidate.Source, prefix: prefix}
		registered = append(registered, mount)
		byID[mount.id] = mount
		prefixes[mount.prefix.String()] = struct{}{}
	}

	sort.Slice(registered, func(left, right int) bool {
		return len(registered[left].prefix.String()) > len(registered[right].prefix.String())
	})

	available, _ := entry.NewAvailability(entry.AvailabilityStateAvailable)
	canonical := make([]entry.MountRef, 0, len(registered))
	for _, mount := range registered {
		point, err := entry.NewResolvedVirtualPath(mount.id, mount.prefix.String(), "1")
		if err != nil {
			return nil, ErrInvalidMount
		}
		ref, err := entry.NewMountRef(mount.id, "legacy", mount.source.SourceID, point, available, entry.CachePolicyNone)
		if err != nil {
			return nil, ErrInvalidMount
		}
		canonical = append(canonical, ref)
	}
	sort.Slice(canonical, func(left, right int) bool { return lessMountRef(canonical[left], canonical[right]) })
	return &Registry{mounts: registered, byID: byID, canonical: canonical, generation: 1}, nil
}

func (registry *Registry) Resolve(raw string) (Resolution, error) {
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	virtualPath, err := NormalizeVirtualPath(raw)
	if err != nil {
		return Resolution{}, err
	}

	value := virtualPath.String()
	for _, mount := range registry.mounts {
		prefix := mount.prefix.String()
		if !matchesPrefix(value, prefix) {
			continue
		}

		relativePath := relativeToPrefix(value, prefix)
		if !validRelativePath(relativePath) {
			return Resolution{}, ErrInvalidPath
		}
		return Resolution{
			Source:       mount.source,
			MountID:      mount.id,
			RelativePath: relativePath,
		}, nil
	}
	return Resolution{}, ErrMountNotFound
}

func (registry *Registry) Reverse(mountID, relativePath string) (entry.VirtualPath, error) {
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	mount, exists := registry.byID[mountID]
	if !exists {
		return entry.VirtualPath{}, ErrMountNotFound
	}
	if !validRelativePath(relativePath) {
		return entry.VirtualPath{}, ErrInvalidPath
	}

	prefix := mount.prefix.String()
	if relativePath == "" {
		return mount.prefix, nil
	}

	value := prefix + "/" + relativePath
	if prefix == "/" {
		value = "/" + relativePath
	}
	if len(value) > maximumVirtualPathBytes {
		return entry.VirtualPath{}, ErrInvalidPath
	}
	virtualPath, err := entry.NewVirtualPath(value)
	if err != nil {
		return entry.VirtualPath{}, fmt.Errorf("%w: %w", ErrInvalidPath, err)
	}
	return virtualPath, nil
}

func validRawVirtualPath(raw string) bool {
	return len(raw) >= 1 &&
		len(raw) <= maximumVirtualPathBytes &&
		utf8.ValidString(raw) &&
		raw[0] == '/' &&
		!strings.ContainsRune(raw, '\x00') &&
		!strings.ContainsRune(raw, '\\')
}

func validMountID(mountID string) bool {
	return len(mountID) >= 1 && len(mountID) <= maximumMountIDBytes && utf8.ValidString(mountID)
}

func validRelativePath(relativePath string) bool {
	if len(relativePath) > maximumVirtualPathBytes || !utf8.ValidString(relativePath) {
		return false
	}
	if relativePath == "" {
		return true
	}
	if relativePath[0] == '/' || strings.ContainsRune(relativePath, '\x00') || strings.ContainsRune(relativePath, '\\') {
		return false
	}
	for _, segment := range strings.Split(relativePath, "/") {
		if segment == "" || segment == "." || segment == ".." {
			return false
		}
	}
	return true
}

func matchesPrefix(virtualPath, prefix string) bool {
	if prefix == "/" {
		return true
	}
	return virtualPath == prefix || strings.HasPrefix(virtualPath, prefix+"/")
}

func relativeToPrefix(virtualPath, prefix string) string {
	if prefix == "/" {
		return strings.TrimPrefix(virtualPath, "/")
	}
	if virtualPath == prefix {
		return ""
	}
	return virtualPath[len(prefix)+1:]
}

func NewMountRegistry() *Registry {
	return &Registry{byID: make(map[string]registeredMount), generation: 1}
}

func (registry *Registry) Register(ref entry.MountRef) error {
	if registry == nil || ref.Validate() != nil {
		return ErrInvalidMount
	}
	registry.mu.Lock()
	defer registry.mu.Unlock()
	if _, exists := registry.byID[ref.MountID]; exists {
		return ErrDuplicateMountID
	}
	workspaceCount := 0
	sources := make(map[string]struct{})
	for _, existing := range registry.canonical {
		if existing.MountID == ref.MountID {
			return ErrDuplicateMountID
		}
		if existing.WorkspaceID != ref.WorkspaceID {
			continue
		}
		workspaceCount++
		sources[existing.SourceInstanceID] = struct{}{}
		if existing.MountPoint.String() == ref.MountPoint.String() {
			return ErrDuplicateMountPrefix
		}
	}
	if workspaceCount >= maximumWorkspaceMounts {
		return ErrTooManyMounts
	}
	sources[ref.SourceInstanceID] = struct{}{}
	if len(sources) > maximumWorkspaceMounts {
		return ErrTooManyMounts
	}
	canonical := append([]entry.MountRef(nil), registry.canonical...)
	canonical = append(canonical, ref)
	sort.Slice(canonical, func(left, right int) bool { return lessMountRef(canonical[left], canonical[right]) })
	registered := registeredMount{id: ref.MountID, source: entry.SourceIdentity{SourceID: ref.SourceInstanceID, IdentityStrength: entry.IdentityStrengthLocator}, prefix: ref.MountPoint}
	byID := make(map[string]registeredMount, len(registry.byID)+1)
	for id, mount := range registry.byID {
		byID[id] = mount
	}
	byID[ref.MountID] = registered
	mounts := append([]registeredMount(nil), registry.mounts...)
	mounts = append(mounts, registered)
	sort.Slice(mounts, func(left, right int) bool {
		return len(mounts[left].prefix.String()) > len(mounts[right].prefix.String())
	})
	registry.canonical = canonical
	registry.byID = byID
	registry.mounts = mounts
	registry.generation++
	return nil
}

func (registry *Registry) Unmount(mountID string) error {
	if registry == nil || !validMountID(mountID) {
		return ErrMountNotFound
	}
	registry.mu.Lock()
	defer registry.mu.Unlock()
	found := false
	canonical := make([]entry.MountRef, 0, len(registry.canonical))
	for _, ref := range registry.canonical {
		if ref.MountID == mountID {
			found = true
			continue
		}
		canonical = append(canonical, ref)
	}
	if !found {
		return ErrMountNotFound
	}
	byID := make(map[string]registeredMount, len(registry.byID)-1)
	for id, item := range registry.byID {
		if id != mountID {
			byID[id] = item
		}
	}
	mounts := make([]registeredMount, 0, len(registry.mounts)-1)
	for _, item := range registry.mounts {
		if item.id != mountID {
			mounts = append(mounts, item)
		}
	}
	registry.canonical = canonical
	registry.byID = byID
	registry.mounts = mounts
	registry.generation++
	return nil
}

func (registry *Registry) ListMounts(workspaceID string) []entry.MountRef {
	if registry == nil || !validWorkspaceID(workspaceID) {
		return []entry.MountRef{}
	}
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	result := make([]entry.MountRef, 0)
	for _, ref := range registry.canonical {
		if ref.WorkspaceID == workspaceID && ref.MountStatus.State != entry.AvailabilityStateUnmounted {
			result = append(result, ref)
		}
	}
	return result
}

func (registry *Registry) ResolveVirtualPath(workspaceID, raw string) (entry.MountRef, string, error) {
	virtualPath, err := NormalizeVirtualPath(raw)
	if err != nil {
		return entry.MountRef{}, "", err
	}
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	value := virtualPath.String()
	var selected *entry.MountRef
	for index := range registry.canonical {
		candidate := &registry.canonical[index]
		if candidate.WorkspaceID != workspaceID || candidate.MountStatus.State == entry.AvailabilityStateUnmounted || !matchesPrefix(value, candidate.MountPoint.String()) {
			continue
		}
		if selected == nil || len(candidate.MountPoint.String()) > len(selected.MountPoint.String()) ||
			(len(candidate.MountPoint.String()) == len(selected.MountPoint.String()) && lessMountRef(*candidate, *selected)) {
			copy := *candidate
			selected = &copy
		}
	}
	if selected == nil {
		return entry.MountRef{}, "", ErrMountNotFound
	}
	relative := relativeToPrefix(value, selected.MountPoint.String())
	if !validRelativePath(relative) {
		return entry.MountRef{}, "", ErrInvalidPath
	}
	return *selected, relative, nil
}

func (registry *Registry) ReverseVirtualPath(mountID, relativePath string) (entry.VirtualPath, error) {
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	var selected *entry.MountRef
	for index := range registry.canonical {
		if registry.canonical[index].MountID == mountID {
			copy := registry.canonical[index]
			selected = &copy
			break
		}
	}
	if selected == nil {
		return entry.VirtualPath{}, ErrMountNotFound
	}
	if !validRelativePath(relativePath) {
		return entry.VirtualPath{}, ErrInvalidPath
	}
	value := selected.MountPoint.String()
	if relativePath != "" {
		if value == "/" {
			value += relativePath
		} else {
			value += "/" + relativePath
		}
	}
	return entry.NewResolvedVirtualPath(mountID, value, fmt.Sprintf("%d", registry.generation))
}

func (registry *Registry) MountByID(workspaceID, mountID string) (entry.MountRef, error) {
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	for _, ref := range registry.canonical {
		if ref.WorkspaceID == workspaceID && ref.MountID == mountID && ref.MountStatus.State != entry.AvailabilityStateUnmounted {
			return ref, nil
		}
	}
	return entry.MountRef{}, ErrMountNotFound
}

func (registry *Registry) Generation() uint64 {
	if registry == nil {
		return 0
	}
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	return registry.generation
}

func lessMountRef(left, right entry.MountRef) bool {
	if left.WorkspaceID != right.WorkspaceID {
		return left.WorkspaceID < right.WorkspaceID
	}
	if left.MountPoint.String() != right.MountPoint.String() {
		return left.MountPoint.String() < right.MountPoint.String()
	}
	if left.MountID != right.MountID {
		return left.MountID < right.MountID
	}
	return left.SourceInstanceID < right.SourceInstanceID
}

func validWorkspaceID(value string) bool {
	return utf8.ValidString(value) && len(value) >= 1 && len(value) <= 64
}

func (registry *Registry) ListAllMounts() []entry.MountRef {
	if registry == nil {
		return []entry.MountRef{}
	}
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	result := make([]entry.MountRef, 0, len(registry.canonical))
	for _, ref := range registry.canonical {
		if ref.MountStatus.State != entry.AvailabilityStateUnmounted {
			result = append(result, ref)
		}
	}
	return result
}
