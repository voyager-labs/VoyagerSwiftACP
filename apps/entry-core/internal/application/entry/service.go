package entry

import (
	"context"
	"errors"
	"reflect"
	"sort"
	"strings"
	"sync/atomic"
	"time"
	"unicode/utf8"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/mount"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

var (
	ErrInvalidService            = errors.New("invalid entry service")
	ErrDuplicateSourceID         = errors.New("duplicate adapter source id")
	ErrSourceNotFound            = errors.New("source not found")
	ErrAmbiguousPropertySelector = errors.New("ambiguous property selector")
	ErrUnregisteredPropertyID    = errors.New("unregistered property id")
)

type UnifiedService struct {
	mountRegistry MountRegistry
	adapters      map[string]ResourceAdapterBinding
	catalog       domainentry.PropertyCatalogSnapshot
	cursor        *compositeCursorCodec
	clock         func() time.Time
	observed      atomic.Uint64
}

type selectedScope struct {
	mount        domainentry.MountRef
	sourceRef    domainentry.SourceRef
	adapter      ResourceAdapter
	relativePath string
}

type scopePage struct {
	items        []CanonicalEntry
	revision     RevisionSummary
	availability SourceAvailability
	freshness    SourceFreshness
	warnings     []ScopeWarning
	state        paginationScopeState
	success      bool
	failure      error
}

func NewUnifiedService(registry MountRegistry, bindings []ResourceAdapterBinding, cursorKey []byte, clock func() time.Time) (*UnifiedService, error) {
	if registry == nil || len(bindings) == 0 || clock == nil {
		return nil, ErrInvalidService
	}
	codec, err := newCompositeCursorCodec(cursorKey)
	if err != nil {
		return nil, err
	}
	adapters := make(map[string]ResourceAdapterBinding, len(bindings))
	for _, binding := range bindings {
		if binding.SourceRef.Validate() != nil || nilResourceAdapter(binding.Adapter) {
			return nil, ErrInvalidService
		}
		if _, exists := adapters[binding.SourceRef.SourceInstanceID]; exists {
			return nil, ErrDuplicateSourceID
		}
		adapters[binding.SourceRef.SourceInstanceID] = binding
	}
	return &UnifiedService{mountRegistry: registry, adapters: adapters, cursor: codec, clock: clock}, nil
}

func NewUnifiedServiceWithCatalog(registry MountRegistry, bindings []ResourceAdapterBinding, catalog domainentry.PropertyCatalogSnapshot, cursorKey []byte, clock func() time.Time) (*UnifiedService, error) {
	if err := catalog.Validate(); err != nil {
		return nil, ErrInvalidService
	}
	service, err := NewUnifiedService(registry, bindings, cursorKey, clock)
	if err != nil {
		return nil, err
	}
	service.catalog = catalog
	return service, nil
}

func (service *UnifiedService) propertyDefinitions(requestedProperties []string) (map[string]domainentry.PropertyDefinition, error) {
	definitions := make(map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition, len(service.catalog.Definitions))
	for _, definition := range service.catalog.Definitions {
		definitions[definition.PropertyID] = definition
	}
	resolved := make(map[string]domainentry.PropertyDefinition, len(requestedProperties))
	for _, requested := range requestedProperties {
		catalogDefinition, found, resolveErr := service.catalogDefinitionFor(requested, definitions)
		if resolveErr != nil {
			message := "ambiguous_property_selector"
			if errors.Is(resolveErr, ErrUnregisteredPropertyID) {
				message = "unregistered_property_selector"
			}
			return nil, newApplicationError("invalid_request", message, resolveErr)
		}
		if !found {
			continue
		}
		propertyDefinition, err := domainentry.NewPropertyDefinition(domainentry.PropertyDefinition{
			PropertyID: catalogDefinition.PropertyID, IdentityScheme: catalogDefinition.IdentityScheme, Namespace: catalogDefinition.Namespace,
			Key: catalogDefinition.CanonicalKey, DisplayName: catalogDefinition.DisplayName, ValueType: catalogDefinition.ValueType,
			Cardinality: catalogDefinition.Cardinality, Editable: catalogDefinition.Editable, Provenance: catalogDefinition.Provenance,
			ValidationRules: []domainentry.ValidationRule{}, Unit: catalogDefinition.Unit,
		})
		if err == nil {
			resolved[requested] = propertyDefinition
		}
	}
	return resolved, nil
}

// catalogDefinitionFor는 요청 이름을 정확한 PropertyID 텍스트 → 용어(alias) → canonical key
// 순서로 검색하는 단일 해석 경로다. 정확한 PropertyID 텍스트는 단말 해석이다: 카탈로그
// 적중이면 그 정의를, 미등록이면 ErrUnregisteredPropertyID로 실패 닫기하고 alias/canonical
// 검색과 registry 재해싱을 시도하지 않는다. 같은 별칭이나 canonical key가 서로 다른
// PropertyID에 걸리면 순서 의존 첫 매칭 대신 ErrAmbiguousPropertySelector로 실패 닫기한다.
func (service *UnifiedService) catalogDefinitionFor(requested string, definitions map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition) (domainentry.WorkspacePropertyDefinition, bool, error) {
	if id, err := domainentry.ParsePropertyID(requested); err == nil {
		if definition, ok := definitions[id]; ok {
			return definition, true, nil
		}
		return domainentry.WorkspacePropertyDefinition{}, false, ErrUnregisteredPropertyID
	}
	matched := domainentry.WorkspacePropertyDefinition{}
	found := false
	for _, term := range service.catalog.Terms {
		if term.TermValue != requested {
			continue
		}
		definition, ok := definitions[term.PropertyID]
		if !ok {
			continue
		}
		if found && matched.PropertyID != term.PropertyID {
			return domainentry.WorkspacePropertyDefinition{}, false, ErrAmbiguousPropertySelector
		}
		matched, found = definition, true
	}
	if found {
		return matched, true, nil
	}
	for _, definition := range service.catalog.Definitions {
		if definition.CanonicalKey != requested {
			continue
		}
		if found && matched.PropertyID != definition.PropertyID {
			return domainentry.WorkspacePropertyDefinition{}, false, ErrAmbiguousPropertySelector
		}
		matched, found = definition, true
	}
	return matched, found, nil
}

func (service *UnifiedService) UnifiedList(ctx context.Context, request UnifiedListRequest) (UnifiedListResult, error) {
	if service == nil || ctx == nil || service.mountRegistry == nil || service.clock == nil || !validApplicationID(request.WorkspaceID, 64) ||
		(request.VirtualPath == nil) == (request.ParentRef == nil) || (request.MountID != nil && request.SourceInstanceID != nil) ||
		request.PageSize < 1 || request.PageSize > 256 || !validApplicationProperties(request.RequestedProperties) || !validOptionalToken(request.PageToken) {
		return UnifiedListResult{}, newApplicationError("invalid_request", "invalid_request", ErrInvalidRequest)
	}
	snapshot := service.mountRegistry.Snapshot()
	scopes, normalizedPath, err := service.selectScopes(request, snapshot)
	if err != nil {
		return UnifiedListResult{}, err
	}
	if len(scopes) > 8 {
		return UnifiedListResult{}, newApplicationError("scope_too_large", "scope_too_large", ErrScopeTooLarge)
	}
	if request.PageSize < len(scopes) {
		return UnifiedListResult{}, newApplicationError("invalid_request", "page_size_too_small", ErrInvalidRequest)
	}
	query := cursorQuery{WorkspaceID: request.WorkspaceID, VirtualPath: normalizedPath, PageSize: request.PageSize, RequestedProperties: append([]string(nil), request.RequestedProperties...)}
	if request.MountID != nil {
		query.MountID = *request.MountID
	}
	if request.SourceInstanceID != nil {
		query.SourceInstanceID = *request.SourceInstanceID
	}
	if request.ParentRef != nil {
		query.ParentEntryID = request.ParentRef.EntryID
		query.ParentSourceID = request.ParentRef.SourceInstanceID
		query.ParentObjectKey = request.ParentRef.SourceObjectKey
		query.ParentResourceType = request.ParentRef.ResourceType
		query.ParentLocator = request.ParentRef.CanonicalLocator.String()
		query.ParentStrength = string(request.ParentRef.IdentityStrength)
	}
	queryHash := hashCursorQuery(query)
	cursorScopes := make([]cursorScope, len(scopes))
	for index, scope := range scopes {
		cursorScopes[index] = cursorScope{WorkspaceID: scope.mount.WorkspaceID, MountID: scope.mount.MountID, SourceInstanceID: scope.sourceRef.SourceInstanceID}
	}
	scopeHash := hashCursorScopes(snapshot.Generation(), cursorScopes)
	states := make([]paginationScopeState, len(scopes))
	roundRobinStart := uint8(0)
	if request.PageToken == nil {
		for index := range states {
			states[index] = paginationScopeState{ScopeIndex: uint8(index), State: paginationStateInitial}
		}
	} else {
		decoded, decodeErr := service.cursor.decode(*request.PageToken, queryHash, scopeHash, len(scopes))
		if decodeErr != nil {
			return UnifiedListResult{}, newApplicationError("invalid_page_token", "invalid_page_token", ErrInvalidPageToken)
		}
		states = decoded.States
		roundRobinStart = decoded.RoundRobinStart
	}
	definitions, definitionsErr := service.propertyDefinitions(request.RequestedProperties)
	if definitionsErr != nil {
		return UnifiedListResult{}, definitionsErr
	}
	if request.ParentRef != nil {
		if resolveErr := service.resolveParentPaths(ctx, scopes, states, *request.ParentRef, request.RequestedProperties, definitions); resolveErr != nil {
			return UnifiedListResult{}, resolveErr
		}
	}
	active := activeScopeIndexes(states, int(roundRobinStart))
	if len(active) == 0 {
		return UnifiedListResult{}, newApplicationError("invalid_page_token", "invalid_page_token", ErrInvalidPageToken)
	}
	quotas, nextStart := fairQuotas(request.PageSize, active, int(roundRobinStart), len(scopes))
	pages := make([]scopePage, len(scopes))
	for index, scope := range scopes {
		if states[index].State == paginationStateExhausted {
			pages[index], err = restoreScopePage(scope, states[index])
			if err != nil {
				return UnifiedListResult{}, newApplicationError("invalid_page_token", "invalid_page_token", ErrInvalidPageToken)
			}
			continue
		}
		adapterRequest, requestErr := source.NewAdapterListRequest(scope.sourceRef, scope.mount, scope.relativePath, quotas[index], states[index].ChildCursor, request.RequestedProperties)
		if requestErr != nil {
			return UnifiedListResult{}, newApplicationError("internal_error", "internal_error", ErrApplicationAdapterFailure)
		}
		adapterRequest.PropertyDefinitions = clonePropertyDefinitions(definitions)
		adapterResult, adapterErr := scope.adapter.List(ctx, adapterRequest)
		if adapterErr != nil {
			if errors.Is(adapterErr, source.ErrInvalidCursor) {
				return UnifiedListResult{}, newApplicationError("invalid_page_token", "invalid_page_token", ErrInvalidPageToken)
			}
			adapterResult = adapterErrorListResult(adapterErr, service.clock())
		}
		pages[index], err = service.consumeScopePage(snapshot, scope, uint8(index), adapterResult, quotas[index], request.RequestedProperties, definitions)
		if err != nil {
			pages[index] = service.adapterFailureScope(snapshot, scope, uint8(index))
			pages[index].failure = err
		} else {
			pages[index].failure = adapterErr
		}
		if pages[index].state.State == paginationStateExhausted {
			pages[index].state.ExhaustedSnapshot = snapshotForPage(pages[index])
		}
	}
	entries := interleaveScopeEntries(pages, active)
	if len(entries) > request.PageSize {
		return UnifiedListResult{}, newApplicationError("internal_error", "internal_error", ErrApplicationAdapterFailure)
	}
	result := UnifiedListResult{Entries: entries, ObservedAt: service.clock().Round(0).UTC(), RevisionSummaries: make([]RevisionSummary, len(scopes)), Availabilities: make([]SourceAvailability, len(scopes)), Freshness: make([]SourceFreshness, len(scopes)), Warnings: []ScopeWarning{}}
	successes := 0
	nextStates := make([]paginationScopeState, len(scopes))
	for index := range pages {
		result.RevisionSummaries[index] = pages[index].revision
		result.Availabilities[index] = pages[index].availability
		result.Freshness[index] = pages[index].freshness
		result.Warnings = append(result.Warnings, pages[index].warnings...)
		nextStates[index] = pages[index].state
		if pages[index].success && states[index].State != paginationStateExhausted {
			successes++
		}
	}
	if successes == 0 {
		return UnifiedListResult{}, allFailedError(pages)
	}
	if len(scopes) > 1 {
		for index := range pages {
			if states[index].State != paginationStateExhausted && !pages[index].success {
				result.Warnings = append(result.Warnings, ScopeWarning{SourceInstanceID: scopes[index].sourceRef.SourceInstanceID, MountID: scopes[index].mount.MountID, Code: source.WarningCodePartialResult, Message: stableWarningMessage(source.WarningCodePartialResult)})
			}
		}
	}
	if len(result.Warnings) > 64 {
		result.Warnings = append([]ScopeWarning(nil), result.Warnings[:64]...)
	}
	if hasContinuingState(nextStates) {
		token, encodeErr := service.cursor.encode(queryHash, scopeHash, uint8(nextStart), nextStates)
		if encodeErr != nil {
			return UnifiedListResult{}, newApplicationError("internal_error", "internal_error", ErrApplicationAdapterFailure)
		}
		result.NextPageToken = &token
		result.HasMore = true
	}
	return result, nil
}

func (service *UnifiedService) ResolveEntry(ctx context.Context, request ResolveRequest) (ResolveResult, error) {
	if !validApplicationProperties(request.RequestedProperties) {
		return ResolveResult{}, newApplicationError("invalid_request", "invalid_request", ErrInvalidRequest)
	}
	if service == nil || ctx == nil || !validApplicationID(request.WorkspaceID, 64) || (request.EntryRef == nil) == (request.VirtualPath == nil) ||
		(request.EntryRef != nil && request.MountID == nil) || (request.VirtualPath != nil && request.MountID != nil) {
		return ResolveResult{}, newApplicationError("invalid_selector", "invalid_selector", ErrInvalidSelector)
	}
	snapshot := service.mountRegistry.Snapshot()
	var mountRef domainentry.MountRef
	var relativePath *string
	var entryRef *domainentry.EntryRef
	var err error
	if request.EntryRef != nil {
		if request.EntryRef.Validate() != nil {
			return ResolveResult{}, newApplicationError("invalid_selector", "invalid_selector", ErrInvalidSelector)
		}
		mountRef, err = snapshot.MountByID(request.WorkspaceID, *request.MountID)
		if err != nil {
			return ResolveResult{}, err
		}
		if mountRef.SourceInstanceID != request.EntryRef.SourceInstanceID {
			return ResolveResult{}, newApplicationError("context_mismatch", "context_mismatch", ErrContextMismatch)
		}
		copy := *request.EntryRef
		entryRef = &copy
	} else {
		var relative string
		var resolveErr error
		mountRef, relative, resolveErr = snapshot.ResolveVirtualPath(request.WorkspaceID, *request.VirtualPath)
		if resolveErr != nil {
			return ResolveResult{}, resolveErr
		}
		relativePath = &relative
	}
	binding, exists := service.adapters[mountRef.SourceInstanceID]
	if !exists {
		return ResolveResult{}, ErrSourceNotFound
	}
	adapterRequest, err := source.NewAdapterResolveRequest(binding.SourceRef, mountRef, entryRef, relativePath, request.RequestedProperties)
	if err != nil {
		return ResolveResult{}, newApplicationError("invalid_selector", "invalid_selector", ErrInvalidSelector)
	}
	definitions, definitionsErr := service.propertyDefinitions(request.RequestedProperties)
	if definitionsErr != nil {
		return ResolveResult{}, definitionsErr
	}
	adapterRequest.PropertyDefinitions = clonePropertyDefinitions(definitions)
	adapterResult, adapterErr := binding.Adapter.Resolve(ctx, adapterRequest)
	if adapterErr != nil {
		return ResolveResult{}, mapCanonicalAdapterError(adapterErr)
	}
	if adapterResult.Validate() != nil {
		return ResolveResult{}, newApplicationError("adapter_failure", "adapter_failure", ErrApplicationAdapterFailure)
	}
	if adapterResult.Item == nil {
		if adapterResult.SourceError != nil {
			return ResolveResult{}, sourceErrorToApplication(adapterResult.SourceError.Code)
		}
		return ResolveResult{}, newApplicationError("entry_not_found", "entry_not_found", ErrEntryNotFound)
	}
	item := *adapterResult.Item
	if relativePath != nil && item.RelativePath != *relativePath {
		return ResolveResult{}, newApplicationError("context_mismatch", "context_mismatch", ErrContextMismatch)
	}
	if item.EntryRef.SourceInstanceID != binding.SourceRef.SourceInstanceID || item.EntrySnapshot.EntryRef.SourceInstanceID != binding.SourceRef.SourceInstanceID {
		return ResolveResult{}, newApplicationError("context_mismatch", "context_mismatch", ErrContextMismatch)
	}
	if !propertiesWithinRequest(item.EntrySnapshot.CanonicalProperties, request.RequestedProperties, definitions) {
		return ResolveResult{}, newApplicationError("adapter_failure", "adapter_failure", ErrApplicationAdapterFailure)
	}
	if entryRef != nil && item.EntryRef.EntryID != entryRef.EntryID {
		return ResolveResult{}, newApplicationError("context_mismatch", "context_mismatch", ErrContextMismatch)
	}
	observedRevision, observedErr := domainentry.NewObservedRevision(service.observed.Add(1))
	if observedErr != nil {
		return ResolveResult{}, newApplicationError("adapter_failure", "adapter_failure", ErrApplicationAdapterFailure)
	}
	canonicalProperties := sortCanonicalProperties(item.EntrySnapshot.CanonicalProperties)
	canonicalSnapshot, snapshotErr := domainentry.NewCanonicalEntrySnapshot(item.EntryRef, item.EntrySnapshot.DisplayName, item.EntrySnapshot.ParentRef, canonicalProperties, item.EntrySnapshot.SourceRevision, observedRevision, item.EntrySnapshot.ObservedAt, item.EntrySnapshot.CanonicalModifiedAt, item.EntrySnapshot.Availability, item.EntrySnapshot.Freshness)
	if snapshotErr != nil {
		return ResolveResult{}, newApplicationError("adapter_failure", "adapter_failure", ErrApplicationAdapterFailure)
	}
	item.EntrySnapshot = canonicalSnapshot
	virtualPath, err := snapshot.ReverseVirtualPath(mountRef.MountID, item.RelativePath)
	if err != nil {
		return ResolveResult{}, err
	}
	access, err := domainentry.NewCanonicalAccessContext(item.EntryRef.SourceInstanceID, mountRef.MountID, virtualPath, nil, item.Capabilities)
	if err != nil {
		return ResolveResult{}, newApplicationError("adapter_failure", "adapter_failure", ErrApplicationAdapterFailure)
	}
	return ResolveResult{EntryRef: item.EntryRef, EntrySnapshot: item.EntrySnapshot, AccessContext: access, Capabilities: item.Capabilities, Availability: adapterResult.Availability, Freshness: adapterResult.Freshness, SourceRevision: adapterResult.SourceRevision}, nil
}

func (service *UnifiedService) SourceObjectToEntryRef(sourceRef domainentry.SourceRef, identity source.SourceObjectIdentity) (domainentry.EntryRef, error) {
	if sourceRef.Validate() != nil || identity.Validate() != nil {
		return domainentry.EntryRef{}, source.ErrInvalidRequest
	}
	return domainentry.NewEntryRef(domainentry.DeriveEntryID(sourceRef.SourceInstanceID, identity.ResourceType, identity.ObjectKey), sourceRef.SourceInstanceID, identity.ObjectKey, identity.ResourceType, identity.LocatorRef, identity.IdentityStrength)
}

func (service *UnifiedService) EntryRefToSourceObject(ref domainentry.EntryRef) (source.SourceObjectSelector, error) {
	if ref.Validate() != nil {
		return source.SourceObjectSelector{}, source.ErrInvalidRequest
	}
	selector := source.SourceObjectSelector{SourceInstanceID: ref.SourceInstanceID, SourceObjectKey: ref.SourceObjectKey}
	return selector, selector.Validate()
}

func (service *UnifiedService) VirtualPathToEntryRef(ctx context.Context, workspaceID, path string, requested []string) (domainentry.EntryRef, error) {
	result, err := service.ResolveEntry(ctx, ResolveRequest{WorkspaceID: workspaceID, VirtualPath: &path, RequestedProperties: requested})
	if err != nil {
		return domainentry.EntryRef{}, err
	}
	return result.EntryRef, nil
}

func (service *UnifiedService) EntryRefToVirtualPaths(ref domainentry.EntryRef) ([]domainentry.AccessContext, error) {
	if ref.Validate() != nil {
		return nil, source.ErrInvalidRequest
	}
	binding, exists := service.adapters[ref.SourceInstanceID]
	if !exists {
		return nil, ErrSourceNotFound
	}
	snapshot := service.mountRegistry.Snapshot()
	result := make([]domainentry.AccessContext, 0)
	for _, mountRef := range snapshot.ListAllMounts() {
		if mountRef.SourceInstanceID != ref.SourceInstanceID {
			continue
		}
		request, err := source.NewAdapterResolveRequest(binding.SourceRef, mountRef, &ref, nil, []string{})
		if err != nil {
			return nil, err
		}
		resolved, err := binding.Adapter.Resolve(context.Background(), request)
		if err != nil || resolved.Validate() != nil || resolved.Item == nil {
			continue
		}
		if resolved.Item.EntryRef.EntryID != ref.EntryID || resolved.Item.EntryRef.SourceInstanceID != ref.SourceInstanceID {
			return nil, newApplicationError("context_mismatch", "context_mismatch", ErrContextMismatch)
		}
		path, err := snapshot.ReverseVirtualPath(mountRef.MountID, resolved.Item.RelativePath)
		if err != nil {
			return nil, err
		}
		access, err := domainentry.NewCanonicalAccessContext(ref.SourceInstanceID, mountRef.MountID, path, nil, resolved.Item.Capabilities)
		if err != nil {
			return nil, err
		}
		result = append(result, access)
	}
	return result, nil
}

func (service *UnifiedService) resolveParentPaths(ctx context.Context, scopes []selectedScope, states []paginationScopeState, parent domainentry.EntryRef, requested []string, definitions map[string]domainentry.PropertyDefinition) error {
	for index := range scopes {
		if states[index].State == paginationStateExhausted {
			continue
		}
		request, err := source.NewAdapterResolveRequest(scopes[index].sourceRef, scopes[index].mount, &parent, nil, requested)
		if err != nil {
			return newApplicationError("invalid_selector", "invalid_selector", ErrInvalidSelector)
		}
		request.PropertyDefinitions = clonePropertyDefinitions(definitions)
		result, err := scopes[index].adapter.Resolve(ctx, request)
		if err != nil {
			return mapCanonicalAdapterError(err)
		}
		if result.Validate() != nil {
			return newApplicationError("adapter_failure", "adapter_failure", ErrApplicationAdapterFailure)
		}
		if result.Item == nil {
			if result.SourceError != nil {
				return sourceErrorToApplication(result.SourceError.Code)
			}
			return newApplicationError("entry_not_found", "entry_not_found", ErrEntryNotFound)
		}
		if result.Item.EntryRef.EntryID != parent.EntryID {
			return newApplicationError("context_mismatch", "context_mismatch", ErrContextMismatch)
		}
		scopes[index].relativePath = result.Item.RelativePath
	}
	return nil
}

func (service *UnifiedService) selectScopes(request UnifiedListRequest, snapshot mount.MountRegistrySnapshot) ([]selectedScope, string, error) {
	mountRefs := snapshot.ListMounts(request.WorkspaceID)
	if request.MountID != nil {
		mountRef, err := snapshot.MountByID(request.WorkspaceID, *request.MountID)
		if err != nil {
			return nil, "", err
		}
		mountRefs = []domainentry.MountRef{mountRef}
	}
	if request.SourceInstanceID != nil {
		filtered := mountRefs[:0]
		for _, ref := range mountRefs {
			if ref.SourceInstanceID == *request.SourceInstanceID {
				filtered = append(filtered, ref)
			}
		}
		mountRefs = filtered
		if len(mountRefs) == 0 {
			return nil, "", ErrSourceNotFound
		}
	}
	normalizedPath := ""
	if request.VirtualPath != nil {
		normalized, err := mount.NormalizeVirtualPath(*request.VirtualPath)
		if err != nil {
			return nil, "", err
		}
		normalizedPath = normalized.String()
		if request.MountID == nil && request.SourceInstanceID == nil && normalizedPath != "/" {
			resolved, _, resolveErr := snapshot.ResolveVirtualPath(request.WorkspaceID, normalizedPath)
			if resolveErr != nil {
				return nil, "", resolveErr
			}
			mountRefs = []domainentry.MountRef{resolved}
		} else if request.SourceInstanceID != nil && normalizedPath != "/" {
			best := longestMatchingMount(mountRefs, normalizedPath)
			if best == nil {
				return nil, "", newApplicationError("invalid_selector", "invalid_selector", ErrInvalidSelector)
			}
			mountRefs = []domainentry.MountRef{*best}
		}
	} else {
		if request.ParentRef.Validate() != nil {
			return nil, "", newApplicationError("invalid_selector", "invalid_selector", ErrInvalidSelector)
		}
		filtered := mountRefs[:0]
		for _, ref := range mountRefs {
			if ref.SourceInstanceID == request.ParentRef.SourceInstanceID {
				filtered = append(filtered, ref)
			}
		}
		mountRefs = filtered
		if len(mountRefs) == 0 {
			if request.MountID != nil || request.SourceInstanceID != nil {
				return nil, "", newApplicationError("invalid_selector", "invalid_selector", ErrInvalidSelector)
			}
			return nil, "", ErrSourceNotFound
		}
	}
	if len(mountRefs) == 0 {
		return nil, "", mount.ErrMountNotFound
	}
	if len(mountRefs) > 8 {
		return nil, "", ErrScopeTooLarge
	}
	scopes := make([]selectedScope, 0, len(mountRefs))
	for _, mountRef := range mountRefs {
		binding, exists := service.adapters[mountRef.SourceInstanceID]
		if !exists {
			return nil, "", ErrSourceNotFound
		}
		relative := ""
		if request.VirtualPath != nil {
			if normalizedPath == "/" && request.MountID == nil {
				relative = ""
			} else {
				if !pathWithinMount(normalizedPath, mountRef.MountPoint.String()) {
					return nil, "", newApplicationError("invalid_selector", "invalid_selector", ErrInvalidSelector)
				}
				relative = relativeForMount(normalizedPath, mountRef.MountPoint.String())
			}
		} else {
			relative = request.ParentRef.SourceObjectKey
		}
		scopes = append(scopes, selectedScope{mount: mountRef, sourceRef: binding.SourceRef, adapter: binding.Adapter, relativePath: relative})
	}
	sort.Slice(scopes, func(left, right int) bool {
		if scopes[left].mount.WorkspaceID != scopes[right].mount.WorkspaceID {
			return scopes[left].mount.WorkspaceID < scopes[right].mount.WorkspaceID
		}
		if scopes[left].mount.MountPoint.String() != scopes[right].mount.MountPoint.String() {
			return scopes[left].mount.MountPoint.String() < scopes[right].mount.MountPoint.String()
		}
		if scopes[left].mount.MountID != scopes[right].mount.MountID {
			return scopes[left].mount.MountID < scopes[right].mount.MountID
		}
		return scopes[left].sourceRef.SourceInstanceID < scopes[right].sourceRef.SourceInstanceID
	})
	return scopes, normalizedPath, nil
}

func (service *UnifiedService) consumeScopePage(snapshot mount.MountRegistrySnapshot, scope selectedScope, index uint8, result source.AdapterListResult, quota int, requestedProperties []string, definitions map[string]domainentry.PropertyDefinition) (scopePage, error) {
	if result.Validate(quota) != nil {
		return scopePage{}, source.ErrAdapterFailure
	}
	observedRevision, err := domainentry.NewObservedRevision(service.observed.Add(1))
	if err != nil {
		return scopePage{}, err
	}
	page := scopePage{items: make([]CanonicalEntry, 0, len(result.Items)), revision: RevisionSummary{SourceInstanceID: scope.sourceRef.SourceInstanceID, MountID: scope.mount.MountID, SourceRevision: cloneDomainRevision(result.SourceRevision), ObservedRevision: observedRevision}, availability: SourceAvailability{SourceInstanceID: scope.sourceRef.SourceInstanceID, MountID: scope.mount.MountID, State: result.Availability.State}, freshness: sourceFreshnessSummary(scope, result.Freshness), warnings: scopeWarnings(scope, result.Warnings), success: successfulAvailability(result.Availability.State)}
	if result.SourceError != nil {
		page.availability.Error = scopeError(scope, result.SourceError)
	}
	for _, item := range result.Items {
		if !propertiesWithinRequest(item.EntrySnapshot.CanonicalProperties, requestedProperties, definitions) {
			return scopePage{}, source.ErrAdapterFailure
		}
		if item.EntryRef.SourceInstanceID != scope.sourceRef.SourceInstanceID || item.EntrySnapshot.Availability != result.Availability || !equalCanonicalFreshnessEnvelope(item.EntrySnapshot.Freshness, result.Freshness) {
			return scopePage{}, source.ErrAdapterFailure
		}
		canonicalProperties := sortCanonicalProperties(item.EntrySnapshot.CanonicalProperties)
		canonicalSnapshot, snapshotErr := domainentry.NewCanonicalEntrySnapshot(item.EntryRef, item.EntrySnapshot.DisplayName, item.EntrySnapshot.ParentRef, canonicalProperties, item.EntrySnapshot.SourceRevision, observedRevision, item.EntrySnapshot.ObservedAt, item.EntrySnapshot.CanonicalModifiedAt, item.EntrySnapshot.Availability, item.EntrySnapshot.Freshness)
		if snapshotErr != nil {
			return scopePage{}, source.ErrAdapterFailure
		}
		path, reverseErr := snapshot.ReverseVirtualPath(scope.mount.MountID, item.RelativePath)
		if reverseErr != nil {
			return scopePage{}, reverseErr
		}
		access, accessErr := domainentry.NewCanonicalAccessContext(scope.sourceRef.SourceInstanceID, scope.mount.MountID, path, nil, item.Capabilities)
		if accessErr != nil {
			return scopePage{}, accessErr
		}
		page.items = append(page.items, CanonicalEntry{EntryRef: item.EntryRef, EntrySnapshot: canonicalSnapshot, AccessContext: access})
	}
	if !page.success {
		page.warnings = append(page.warnings, failureWarning(scope, result.Availability.State))
	}
	if result.NextChildCursor != nil {
		page.state = paginationScopeState{ScopeIndex: index, State: paginationStateContinuing, ChildCursor: cloneApplicationString(result.NextChildCursor)}
	} else {
		page.state = paginationScopeState{ScopeIndex: index, State: paginationStateExhausted, ExhaustedSnapshot: snapshotForPage(page)}
	}
	return page, nil
}

func (service *UnifiedService) adapterFailureScope(snapshot mount.MountRegistrySnapshot, scope selectedScope, index uint8) scopePage {
	result := adapterFailureListResult(service.clock())
	page, _ := service.consumeScopePage(snapshot, scope, index, result, 1, []string{}, nil)
	return page
}

func adapterErrorListResult(adapterErr error, observedAt time.Time) source.AdapterListResult {
	state := domainentry.AvailabilityStateError
	code := source.SourceErrorCodeAdapterFailure
	switch {
	case errors.Is(adapterErr, source.ErrPermissionDenied):
		state, code = domainentry.AvailabilityStatePermissionDenied, source.SourceErrorCodePermissionDenied
	case errors.Is(adapterErr, source.ErrSourceDeleted):
		state, code = domainentry.AvailabilityStateSourceDeleted, source.SourceErrorCodeSourceDeleted
	case errors.Is(adapterErr, source.ErrSourceUnavailable):
		state, code = domainentry.AvailabilityStateOffline, source.SourceErrorCodeSourceUnavailable
	}
	revision, _ := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := domainentry.NewSourceRevision(revision)
	freshness, _ := domainentry.NewFreshness(domainentry.FreshnessStateUnknown, observedAt.Round(0).UTC(), sourceRevision, nil, nil)
	availability, _ := domainentry.NewAvailability(state)
	sourceError, _ := source.NewSourceError(code)
	return source.AdapterListResult{Items: []source.AdapterEntry{}, SourceRevision: revision, Availability: availability, Freshness: freshness, SourceError: sourceError, Warnings: []source.Warning{}}
}

func adapterFailureListResult(observedAt time.Time) source.AdapterListResult {
	revision, _ := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := domainentry.NewSourceRevision(revision)
	freshness, _ := domainentry.NewFreshness(domainentry.FreshnessStateUnknown, observedAt.Round(0).UTC(), sourceRevision, nil, nil)
	availability, _ := domainentry.NewAvailability(domainentry.AvailabilityStateError)
	sourceError, _ := source.NewSourceError(source.SourceErrorCodeAdapterFailure)
	return source.AdapterListResult{Items: []source.AdapterEntry{}, SourceRevision: revision, Availability: availability, Freshness: freshness, SourceError: sourceError, Warnings: []source.Warning{}}
}

func restoreScopePage(scope selectedScope, state paginationScopeState) (scopePage, error) {
	if state.ExhaustedSnapshot == nil {
		return scopePage{}, ErrInvalidPageToken
	}
	snapshot := state.ExhaustedSnapshot
	observedRevision, err := domainentry.NewObservedRevision(snapshot.ObservedRevision)
	if err != nil {
		return scopePage{}, err
	}
	page := scopePage{revision: RevisionSummary{SourceInstanceID: scope.sourceRef.SourceInstanceID, MountID: scope.mount.MountID, SourceRevision: cloneDomainRevision(snapshot.SourceRevision), ObservedRevision: observedRevision}, availability: SourceAvailability{SourceInstanceID: scope.sourceRef.SourceInstanceID, MountID: scope.mount.MountID, State: snapshot.AvailabilityState}, freshness: SourceFreshness{SourceInstanceID: scope.sourceRef.SourceInstanceID, MountID: scope.mount.MountID, State: snapshot.FreshnessState, ObservedAt: snapshot.ObservedAt, SourceRevision: cloneDomainRevision(snapshot.SourceRevision), LastSyncAt: cloneTime(snapshot.LastSyncAt), StaleAfter: cloneTime(snapshot.StaleAfter)}, warnings: []ScopeWarning{}, state: state, success: successfulAvailability(snapshot.AvailabilityState)}
	if snapshot.SourceErrorCode != "" {
		page.availability.Error = scopeError(scope, &source.SourceError{Code: snapshot.SourceErrorCode, Message: stableSourceErrorMessage(snapshot.SourceErrorCode), Retryable: snapshot.SourceRetryable})
	}
	if snapshot.WarningCode != "" {
		page.warnings = append(page.warnings, ScopeWarning{SourceInstanceID: scope.sourceRef.SourceInstanceID, MountID: scope.mount.MountID, Code: snapshot.WarningCode, Message: stableWarningMessage(snapshot.WarningCode), Retryable: snapshot.WarningRetryable})
	}
	page.failure = sourceFailure(snapshot.FailureCode)
	return page, nil
}

func snapshotForPage(page scopePage) *exhaustedScopeSnapshot {
	snapshot := &exhaustedScopeSnapshot{SourceRevision: cloneDomainRevision(page.revision.SourceRevision), ObservedRevision: page.revision.ObservedRevision.Sequence, AvailabilityState: page.availability.State, FreshnessState: page.freshness.State, ObservedAt: page.freshness.ObservedAt, LastSyncAt: cloneTime(page.freshness.LastSyncAt), StaleAfter: cloneTime(page.freshness.StaleAfter)}
	if page.availability.Error != nil {
		snapshot.SourceErrorCode = page.availability.Error.Code
		snapshot.SourceRetryable = page.availability.Error.Retryable
	}
	snapshot.FailureCode = failureSourceErrorCode(page.failure)
	if len(page.warnings) > 0 {
		snapshot.WarningCode = page.warnings[0].Code
		snapshot.WarningRetryable = page.warnings[0].Retryable
	}
	return snapshot
}

func failureSourceErrorCode(err error) source.SourceErrorCode {
	switch {
	case errors.Is(err, source.ErrPermissionDenied):
		return source.SourceErrorCodePermissionDenied
	case errors.Is(err, source.ErrSourceDeleted):
		return source.SourceErrorCodeSourceDeleted
	case errors.Is(err, source.ErrSourceUnavailable):
		return source.SourceErrorCodeSourceUnavailable
	case errors.Is(err, source.ErrEntryNotFound):
		return source.SourceErrorCodeEntryNotFound
	case err != nil:
		return source.SourceErrorCodeAdapterFailure
	default:
		return ""
	}
}

func sourceFailure(code source.SourceErrorCode) error {
	switch code {
	case source.SourceErrorCodePermissionDenied:
		return source.ErrPermissionDenied
	case source.SourceErrorCodeSourceDeleted:
		return source.ErrSourceDeleted
	case source.SourceErrorCodeSourceUnavailable:
		return source.ErrSourceUnavailable
	case source.SourceErrorCodeEntryNotFound:
		return source.ErrEntryNotFound
	case source.SourceErrorCodeAdapterFailure:
		return source.ErrAdapterFailure
	default:
		return nil
	}
}

func activeScopeIndexes(states []paginationScopeState, start int) []int {
	result := make([]int, 0, len(states))
	for offset := range len(states) {
		index := (start + offset) % len(states)
		if states[index].State != paginationStateExhausted {
			result = append(result, index)
		}
	}
	return result
}

func fairQuotas(pageSize int, active []int, start, scopeCount int) (map[int]int, int) {
	quotas := make(map[int]int, len(active))
	base, remainder := pageSize/len(active), pageSize%len(active)
	for order, index := range active {
		quotas[index] = base
		if order < remainder {
			quotas[index]++
		}
	}
	if remainder == 0 {
		return quotas, start
	}
	return quotas, active[remainder%len(active)] % scopeCount
}

func interleaveScopeEntries(pages []scopePage, order []int) []CanonicalEntry {
	result := make([]CanonicalEntry, 0)
	for round := 0; ; round++ {
		added := false
		for _, index := range order {
			if round < len(pages[index].items) {
				result = append(result, pages[index].items[round])
				added = true
			}
		}
		if !added {
			return result
		}
	}
}

func hasContinuingState(states []paginationScopeState) bool {
	for _, state := range states {
		if state.State == paginationStateInitial || state.State == paginationStateContinuing {
			return true
		}
	}
	return false
}
func successfulAvailability(state domainentry.AvailabilityState) bool {
	return state == domainentry.AvailabilityStateAvailable || state == domainentry.AvailabilityStateReadOnly || state == domainentry.AvailabilityStateStale
}

func allFailedError(pages []scopePage) error {
	priority := []struct {
		code  source.SourceErrorCode
		cause error
	}{
		{source.SourceErrorCodePermissionDenied, source.ErrPermissionDenied},
		{source.SourceErrorCodeSourceDeleted, source.ErrSourceDeleted},
		{source.SourceErrorCodeSourceUnavailable, source.ErrSourceUnavailable},
		{source.SourceErrorCodeEntryNotFound, source.ErrEntryNotFound},
		{source.SourceErrorCodeAdapterFailure, source.ErrAdapterFailure},
	}
	for _, candidate := range priority {
		for _, page := range pages {
			if errors.Is(page.failure, candidate.cause) || (page.availability.Error != nil && page.availability.Error.Code == candidate.code) {
				return sourceErrorToApplication(candidate.code)
			}
		}
	}
	return newApplicationError("adapter_failure", "adapter_failure", ErrApplicationAdapterFailure)
}

func sourceErrorToApplication(code source.SourceErrorCode) error {
	switch code {
	case source.SourceErrorCodeEntryNotFound:
		return newApplicationError("entry_not_found", "entry_not_found", ErrEntryNotFound)
	case source.SourceErrorCodePermissionDenied:
		return newApplicationError("permission_denied", "permission_denied", ErrPermissionDenied)
	case source.SourceErrorCodeSourceDeleted:
		return newApplicationError("source_deleted", "source_deleted", ErrApplicationSourceDeleted)
	case source.SourceErrorCodeSourceUnavailable:
		return newApplicationError("source_unavailable", "source_unavailable", ErrApplicationSourceUnavailable)
	default:
		return newApplicationError("adapter_failure", "adapter_failure", ErrApplicationAdapterFailure)
	}
}

func mapCanonicalAdapterError(err error) error {
	switch {
	case errors.Is(err, source.ErrEntryNotFound):
		return sourceErrorToApplication(source.SourceErrorCodeEntryNotFound)
	case errors.Is(err, source.ErrPermissionDenied):
		return sourceErrorToApplication(source.SourceErrorCodePermissionDenied)
	case errors.Is(err, source.ErrSourceDeleted):
		return sourceErrorToApplication(source.SourceErrorCodeSourceDeleted)
	case errors.Is(err, source.ErrSourceUnavailable):
		return sourceErrorToApplication(source.SourceErrorCodeSourceUnavailable)
	default:
		return sourceErrorToApplication(source.SourceErrorCodeAdapterFailure)
	}
}

func sourceFreshnessSummary(scope selectedScope, freshness domainentry.Freshness) SourceFreshness {
	return SourceFreshness{SourceInstanceID: scope.sourceRef.SourceInstanceID, MountID: scope.mount.MountID, State: freshness.State, ObservedAt: freshness.ObservedAt, SourceRevision: cloneDomainRevision(freshness.SourceRevision.Revision), LastSyncAt: cloneTime(freshness.LastSyncAt), StaleAfter: cloneTime(freshness.StaleAfter)}
}
func scopeError(scope selectedScope, value *source.SourceError) *ScopeError {
	if value == nil {
		return nil
	}
	return &ScopeError{SourceInstanceID: scope.sourceRef.SourceInstanceID, MountID: scope.mount.MountID, Code: value.Code, Message: stableSourceErrorMessage(value.Code), Retryable: value.Retryable}
}
func scopeWarnings(scope selectedScope, values []source.Warning) []ScopeWarning {
	result := make([]ScopeWarning, 0, len(values))
	for _, value := range values {
		result = append(result, ScopeWarning{SourceInstanceID: scope.sourceRef.SourceInstanceID, MountID: scope.mount.MountID, Code: value.Code, Message: stableWarningMessage(value.Code), Retryable: value.Retryable})
	}
	return result
}
func failureWarning(scope selectedScope, state domainentry.AvailabilityState) ScopeWarning {
	code := source.WarningCodeAdapterFailure
	retryable := false
	switch state {
	case domainentry.AvailabilityStateLoading, domainentry.AvailabilityStateOffline, domainentry.AvailabilityStateUnmounted:
		code = source.WarningCodeSourceUnavailable
		retryable = true
	case domainentry.AvailabilityStatePermissionDenied:
		code = source.WarningCodePermissionDenied
	case domainentry.AvailabilityStateSourceDeleted:
		code = source.WarningCodeSourceDeleted
	}
	return ScopeWarning{SourceInstanceID: scope.sourceRef.SourceInstanceID, MountID: scope.mount.MountID, Code: code, Message: stableWarningMessage(code), Retryable: retryable}
}
func stableSourceErrorMessage(code source.SourceErrorCode) string {
	switch code {
	case source.SourceErrorCodeEntryNotFound:
		return "The entry was not found."
	case source.SourceErrorCodeSourceUnavailable:
		return "The source is unavailable."
	case source.SourceErrorCodePermissionDenied:
		return "Permission was denied."
	case source.SourceErrorCodeSourceDeleted:
		return "The source was deleted."
	default:
		return "The source adapter failed."
	}
}
func stableWarningMessage(code source.WarningCode) string {
	switch code {
	case source.WarningCodeStaleSnapshot:
		return "A stale snapshot was returned."
	case source.WarningCodeSourceOffline:
		return "The source is offline."
	case source.WarningCodeSourceUnavailable:
		return "The source is unavailable."
	case source.WarningCodePermissionDenied:
		return "Permission was denied."
	case source.WarningCodeSourceDeleted:
		return "The source was deleted."
	case source.WarningCodePartialResult:
		return "The result is partial."
	default:
		return "The source adapter failed."
	}
}
func cloneDomainRevision(value domainentry.Revision) domainentry.Revision {
	return domainentry.Revision{Strength: value.Strength, Token: cloneApplicationString(value.Token)}
}
func equalCanonicalFreshness(left, right domainentry.Freshness) bool {
	return left.State == right.State && left.ObservedAt.Equal(right.ObservedAt) && left.SourceRevision.Revision.Strength == right.SourceRevision.Revision.Strength && equalAppString(left.SourceRevision.Revision.Token, right.SourceRevision.Revision.Token)
}

func equalCanonicalFreshnessEnvelope(left, right domainentry.Freshness) bool {
	return left.State == right.State && left.ObservedAt.Equal(right.ObservedAt) && equalOptionalApplicationTime(left.LastSyncAt, right.LastSyncAt) && equalOptionalApplicationTime(left.StaleAfter, right.StaleAfter)
}

func equalOptionalApplicationTime(left, right *time.Time) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return left.Equal(*right)
}
func equalAppString(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}
func validApplicationID(value string, maximum int) bool {
	return utf8.ValidString(value) && len(value) >= 1 && len(value) <= maximum
}
func validApplicationProperties(values []string) bool {
	if values == nil || len(values) > 256 {
		return false
	}
	for index, value := range values {
		if !validApplicationID(value, 128) || index > 0 && values[index-1] >= value {
			return false
		}
	}
	return true
}
func validOptionalToken(value *string) bool { return value == nil || validOpaqueASCII(*value, 1, 4096) }
func pathWithinMount(path, point string) bool {
	return point == "/" || path == point || strings.HasPrefix(path, point+"/")
}
func relativeForMount(path, point string) string {
	if point == "/" {
		return strings.TrimPrefix(path, "/")
	}
	if path == point {
		return ""
	}
	return strings.TrimPrefix(path, point+"/")
}
func longestMatchingMount(mounts []domainentry.MountRef, path string) *domainentry.MountRef {
	var best *domainentry.MountRef
	for _, ref := range mounts {
		if pathWithinMount(path, ref.MountPoint.String()) && (best == nil || len(ref.MountPoint.String()) > len(best.MountPoint.String())) {
			copy := ref
			best = &copy
		}
	}
	return best
}

// clonePropertyDefinitions는 어댑터에 넘길 정의 맵을 깊은 복제한다. 어댑터가 맵이나
// 슬라이스·포인터 필드를 변조해도 권위 맵과 이후 요청이 영향을 받지 않는다.
func clonePropertyDefinitions(definitions map[string]domainentry.PropertyDefinition) map[string]domainentry.PropertyDefinition {
	cloned := make(map[string]domainentry.PropertyDefinition, len(definitions))
	for name, definition := range definitions {
		copied := definition
		copied.ValidationRules = make([]domainentry.ValidationRule, len(definition.ValidationRules))
		copy(copied.ValidationRules, definition.ValidationRules)
		if definition.Unit != nil {
			unit := *definition.Unit
			copied.Unit = &unit
		}
		cloned[name] = copied
	}
	return cloned
}

// propertiesWithinRequest는 어댑터 요청과 동일한 해석 결과로 출력을 검증한다.
// 카탈로그 바인딩 이름은 권위 정의로 ID·타입·cardinality까지 검증하고, 미바인딩 이름만
// registry 파생 ID 멤버십을 기대한다. 등록되지 않은 PropertyID 텍스트는 재해싱하지 않고
// 거부한다.
func propertiesWithinRequest(properties []domainentry.PropertyValue, requested []string, definitions map[string]domainentry.PropertyDefinition) bool {
	expected := make(map[domainentry.PropertyID]struct{}, len(requested))
	bound := make(map[domainentry.PropertyID]domainentry.PropertyDefinition, len(definitions))
	for _, name := range requested {
		definition, ok := definitions[name]
		if !ok {
			if _, err := domainentry.ParsePropertyID(name); err == nil {
				return false
			}
			id, err := domainentry.RegistryPropertyID(name)
			if err != nil {
				return false
			}
			expected[id] = struct{}{}
			continue
		}
		expected[definition.PropertyID] = struct{}{}
		bound[definition.PropertyID] = definition
	}
	seen := make(map[domainentry.PropertyID]struct{}, len(properties))
	for _, property := range properties {
		if _, ok := expected[property.PropertyID]; !ok {
			return false
		}
		if _, duplicate := seen[property.PropertyID]; duplicate {
			return false
		}
		seen[property.PropertyID] = struct{}{}
		if definition, ok := bound[property.PropertyID]; ok {
			if !property.ValidateAgainst(definition).Valid {
				return false
			}
		}
	}
	return true
}

func sortCanonicalProperties(properties []domainentry.PropertyValue) []domainentry.PropertyValue {
	if properties == nil {
		return nil
	}
	canonical := make([]domainentry.PropertyValue, len(properties))
	copy(canonical, properties)
	sort.Slice(canonical, func(left, right int) bool {
		return canonical[left].PropertyID.String() < canonical[right].PropertyID.String()
	})
	return canonical
}

func nilResourceAdapter(adapter ResourceAdapter) bool {
	if adapter == nil {
		return true
	}
	value := reflect.ValueOf(adapter)
	switch value.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return value.IsNil()
	}
	return false
}

func cloneTime(value *time.Time) *time.Time {
	if value == nil {
		return nil
	}
	copy := value.Round(0).UTC()
	return &copy
}

func cloneApplicationString(value *string) *string {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}
