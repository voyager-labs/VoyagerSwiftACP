package fakeexternal

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"reflect"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

const (
	pageSize             = 2
	minimumCursorKeySize = 32
	maximumGeneration    = 128
	maximumNamespace     = 256
	maximumFixtures      = 4096
	maximumCursor        = 4096
	cursorPayloadSize    = 4 + sha256.Size
	cursorTokenSize      = cursorPayloadSize + sha256.Size
)

type Fixture struct {
	Key              string
	RelativePath     string
	Name             string
	ResourceType     string
	SizeBytes        *int64
	ModifiedAt       *time.Time
	Properties       []entry.Property
	ProviderRevision *string
	Capabilities     entry.Capabilities
}

type Config struct {
	Namespace      string
	Generation     string
	CursorKey      []byte
	Fixtures       []Fixture
	Availability   entry.AvailabilityState
	ObservedAt     time.Time
	LastSyncAt     *time.Time
	StaleAfter     *time.Time
	CachedSnapshot bool
}

type Adapter struct {
	namespace    string
	generation   string
	cursorKey    []byte
	identity     entry.SourceIdentity
	fixtures     []Fixture
	availability entry.AvailabilityState
	observedAt   time.Time
	lastSyncAt   *time.Time
	staleAfter   *time.Time
	warningCode  source.WarningCode
}

type listRequest struct {
	SourceID, MountID, RelativePath string
	ChildCursor                     *string
}

func newListRequest(identity entry.SourceIdentity, mountID, relativePath string, childCursor *string) (listRequest, error) {
	request := listRequest{SourceID: identity.SourceID, MountID: mountID, RelativePath: relativePath, ChildCursor: cloneString(childCursor)}
	if identity.Validate() != nil || request.Validate() != nil {
		return listRequest{}, source.ErrInvalidRequest
	}
	return request, nil
}
func (request listRequest) Validate() error {
	if !validUTF8Bytes(request.SourceID, 1, 128) || !validUTF8Bytes(request.MountID, 1, 128) || !source.ValidateRelativePath(request.RelativePath) || request.ChildCursor != nil && !validUTF8Bytes(*request.ChildCursor, 1, maximumCursor) {
		return source.ErrInvalidRequest
	}
	return nil
}

type listResult struct {
	Items           []source.SourceItem
	NextChildCursor *string
	SourceRevision  entry.Revision
	Availability    entry.Availability
	Freshness       entry.Freshness
	SourceError     *source.SourceError
	Warnings        []source.Warning
}

func New(config Config) (*Adapter, error) {
	configuredAvailability := config.Availability
	if configuredAvailability == "" {
		configuredAvailability = entry.AvailabilityStateAvailable
	}
	availability := configuredAvailability
	warningCode := source.WarningCode("")
	if config.CachedSnapshot && configuredAvailability == entry.AvailabilityStateOffline {
		availability = entry.AvailabilityStateStale
		warningCode = source.WarningCodeSourceOffline
	} else if config.CachedSnapshot && configuredAvailability == entry.AvailabilityStateLoading {
		availability = entry.AvailabilityStateStale
		warningCode = source.WarningCodeStaleSnapshot
	}
	observedAt := config.ObservedAt.Round(0).UTC()
	if config.ObservedAt.IsZero() {
		observedAt = time.Unix(0, 0).UTC()
	}
	if !validUTF8Bytes(config.Namespace, 1, maximumNamespace) || !validGeneration(config.Generation) || len(config.CursorKey) < minimumCursorKeySize || len(config.Fixtures) > maximumFixtures ||
		!validProviderAvailability(configuredAvailability) || !validOutcomeConfig(configuredAvailability, observedAt, config.LastSyncAt, config.StaleAfter, config.Fixtures, config.CachedSnapshot) {
		return nil, source.ErrInvalidConfig
	}
	identity, err := source.DeriveSourceIdentity("fakeexternal", config.Namespace, entry.IdentityStrengthStable)
	if err != nil {
		return nil, source.ErrInvalidConfig
	}

	fixtures := make([]Fixture, 0, len(config.Fixtures))
	keys := make(map[string]struct{}, len(config.Fixtures))
	paths := make(map[string]struct{}, len(config.Fixtures))
	for _, fixture := range config.Fixtures {
		if _, exists := keys[fixture.Key]; exists {
			return nil, source.ErrInvalidConfig
		}
		if _, exists := paths[fixture.RelativePath]; exists {
			return nil, source.ErrInvalidConfig
		}
		cloned, err := cloneFixture(identity, config.Namespace, fixture)
		if err != nil {
			return nil, source.ErrInvalidConfig
		}
		keys[cloned.Key] = struct{}{}
		paths[cloned.RelativePath] = struct{}{}
		fixtures = append(fixtures, cloned)
	}

	return &Adapter{
		namespace:    config.Namespace,
		generation:   config.Generation,
		cursorKey:    append([]byte(nil), config.CursorKey...),
		identity:     identity,
		fixtures:     fixtures,
		availability: availability,
		observedAt:   observedAt,
		lastSyncAt:   cloneTime(config.LastSyncAt),
		staleAfter:   cloneTime(config.StaleAfter),
		warningCode:  warningCode,
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
	if providerStateError(adapter.availability) != nil {
		result, err := adapter.outcomeResult([]source.SourceItem{}, nil)
		if err != nil {
			return listResult{}, source.ErrAdapterFailure
		}
		return result, providerStateError(adapter.availability)
	}

	fixtures := make([]Fixture, 0)
	for _, fixture := range adapter.fixtures {
		if parentPath(fixture.RelativePath) == request.RelativePath {
			fixtures = append(fixtures, fixture)
		}
	}
	sort.Slice(fixtures, func(left, right int) bool { return fixtures[left].RelativePath < fixtures[right].RelativePath })
	if offset < 0 || offset > len(fixtures) {
		return listResult{}, source.ErrInvalidCursor
	}

	end := offset + limit
	if end > len(fixtures) {
		end = len(fixtures)
	}
	items := make([]source.SourceItem, 0, end-offset)
	for _, fixture := range fixtures[offset:end] {
		item, err := adapter.makeItem(fixture)
		if err != nil {
			return listResult{}, source.ErrAdapterFailure
		}
		items = append(items, item)
	}
	var nextCursor *string
	if end < len(fixtures) {
		encoded := adapter.encodeCursor(end, request)
		nextCursor = &encoded
	}
	return adapter.outcomeResult(items, nextCursor)
}

func (adapter *Adapter) outcomeResult(items []source.SourceItem, nextCursor *string) (listResult, error) {
	revision, err := entry.NewRevision(entry.RevisionStrengthUnknown, nil)
	if err != nil {
		return listResult{}, source.ErrAdapterFailure
	}
	sourceRevision, err := entry.NewSourceRevision(revision)
	if err != nil {
		return listResult{}, source.ErrAdapterFailure
	}
	freshness, err := entry.NewFreshness(freshnessStateForAvailability(adapter.availability), adapter.observedAt, sourceRevision, adapter.lastSyncAt, adapter.staleAfter)
	if err != nil {
		return listResult{}, source.ErrAdapterFailure
	}
	availability, err := entry.NewAvailability(adapter.availability)
	if err != nil {
		return listResult{}, source.ErrAdapterFailure
	}
	warnings := []source.Warning{}
	var sourceError *source.SourceError
	if adapter.warningCode != "" {
		warnings = append(warnings, source.Warning{Code: adapter.warningCode})
	} else if adapter.availability == entry.AvailabilityStateStale {
		warnings = append(warnings, source.Warning{Code: source.WarningCodeStaleSnapshot})
	}
	if code := sourceErrorCode(adapter.availability); code != "" {
		sourceError, err = source.NewSourceError(code)
		if err != nil {
			return listResult{}, source.ErrAdapterFailure
		}
	}
	return newListResult(items, nextCursor, revision, availability, freshness, sourceError, warnings)
}

func validProviderAvailability(state entry.AvailabilityState) bool {
	switch state {
	case entry.AvailabilityStateAvailable, entry.AvailabilityStateReadOnly, entry.AvailabilityStateStale, entry.AvailabilityStateLoading, entry.AvailabilityStateOffline,
		entry.AvailabilityStatePermissionDenied, entry.AvailabilityStateSourceDeleted, entry.AvailabilityStateError:
		return true
	default:
		return false
	}
}

func validOutcomeConfig(state entry.AvailabilityState, observedAt time.Time, lastSyncAt, staleAfter *time.Time, fixtures []Fixture, cachedSnapshot bool) bool {
	if observedAt.Location() != time.UTC || observedAt.Year() < 0 || observedAt.Year() > 9999 {
		return false
	}
	switch state {
	case entry.AvailabilityStateAvailable, entry.AvailabilityStateReadOnly:
		if cachedSnapshot {
			return false
		}
	case entry.AvailabilityStateStale:
		if len(fixtures) == 0 && !cachedSnapshot {
			return false
		}
	case entry.AvailabilityStateLoading, entry.AvailabilityStateOffline:
		if !cachedSnapshot && len(fixtures) != 0 {
			return false
		}
	case entry.AvailabilityStatePermissionDenied, entry.AvailabilityStateSourceDeleted, entry.AvailabilityStateError:
		if cachedSnapshot || len(fixtures) != 0 {
			return false
		}
	default:
		return false
	}
	if lastSyncAt != nil {
		canonical := lastSyncAt.Round(0).UTC()
		if canonical.Year() < 0 || canonical.Year() > 9999 {
			return false
		}
	}
	if staleAfter != nil && staleAfter.Round(0).UTC().Before(observedAt) {
		return false
	}
	return true
}

func freshnessStateForAvailability(state entry.AvailabilityState) entry.FreshnessState {
	if state == entry.AvailabilityStateStale {
		return entry.FreshnessStateStale
	}
	if state == entry.AvailabilityStateAvailable || state == entry.AvailabilityStateReadOnly {
		return entry.FreshnessStateCurrent
	}
	return entry.FreshnessStateUnknown
}

func sourceErrorCode(state entry.AvailabilityState) source.SourceErrorCode {
	switch state {
	case entry.AvailabilityStateLoading, entry.AvailabilityStateOffline:
		return source.SourceErrorCodeSourceUnavailable
	case entry.AvailabilityStateError:
		return source.SourceErrorCodeAdapterFailure
	case entry.AvailabilityStatePermissionDenied:
		return source.SourceErrorCodePermissionDenied
	case entry.AvailabilityStateSourceDeleted:
		return source.SourceErrorCodeSourceDeleted
	default:
		return ""
	}
}

func providerStateError(state entry.AvailabilityState) error {
	switch state {
	case entry.AvailabilityStateLoading, entry.AvailabilityStateOffline:
		return source.ErrSourceUnavailable
	case entry.AvailabilityStateError:
		return source.ErrAdapterFailure
	case entry.AvailabilityStatePermissionDenied:
		return source.ErrPermissionDenied
	case entry.AvailabilityStateSourceDeleted:
		return source.ErrSourceDeleted
	default:
		return nil
	}
}

func (adapter *Adapter) makeItem(fixture Fixture) (source.SourceItem, error) {
	identity, err := entry.NewEntryIdentity(adapter.identity.SourceID, fixture.Key, entry.IdentityStrengthStable)
	if err != nil {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	revision, err := revisionFor(adapter.namespace, fixture)
	if err != nil {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	snapshot, err := entry.NewEntrySnapshot(
		fixture.Name,
		fixture.ResourceType,
		fixture.SizeBytes,
		fixture.ModifiedAt,
		fixture.Properties,
		revision,
		entry.Availability{State: adapter.availability},
		entry.Freshness{State: freshnessStateForAvailability(adapter.availability)},
		entry.OperationState{State: entry.OperationStateIdle},
	)
	if err != nil {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	backendLocator := []byte(adapter.namespace + "\x00" + fixture.Key)
	locator, err := source.NewSourceLocator(adapter.cursorKey, backendLocator)
	if err != nil || !source.ValidateSourceLocator(locator, adapter.cursorKey, backendLocator) {
		return source.SourceItem{}, source.ErrAdapterFailure
	}
	return source.NewSourceItem(fixture.RelativePath, identity, snapshot, locator, fixture.Capabilities)
}

func cloneFixture(identity entry.SourceIdentity, namespace string, fixture Fixture) (Fixture, error) {
	if fixture.RelativePath == "" || !source.ValidateRelativePath(fixture.RelativePath) {
		return Fixture{}, source.ErrInvalidConfig
	}
	if _, err := entry.NewEntryIdentity(identity.SourceID, fixture.Key, entry.IdentityStrengthStable); err != nil {
		return Fixture{}, source.ErrInvalidConfig
	}
	revision, err := revisionFor(namespace, fixture)
	if err != nil {
		return Fixture{}, source.ErrInvalidConfig
	}
	snapshot, err := entry.NewEntrySnapshot(
		fixture.Name,
		fixture.ResourceType,
		fixture.SizeBytes,
		fixture.ModifiedAt,
		fixture.Properties,
		revision,
		entry.Availability{State: entry.AvailabilityStateAvailable},
		entry.Freshness{State: entry.FreshnessStateCurrent},
		entry.OperationState{State: entry.OperationStateIdle},
	)
	if err != nil {
		return Fixture{}, source.ErrInvalidConfig
	}
	return Fixture{
		Key:              fixture.Key,
		RelativePath:     fixture.RelativePath,
		Name:             snapshot.Name,
		ResourceType:     snapshot.ResourceType,
		SizeBytes:        cloneInt64(snapshot.SizeBytes),
		ModifiedAt:       cloneTime(snapshot.ModifiedAt),
		Properties:       cloneProperties(snapshot.Properties),
		ProviderRevision: cloneString(fixture.ProviderRevision),
		Capabilities:     fixture.Capabilities,
	}, nil
}

func revisionFor(namespace string, fixture Fixture) (entry.Revision, error) {
	metadata := source.MetadataProfile{
		ProfileName:  "fake-external",
		Namespace:    namespace,
		EntryKey:     fixture.Key,
		ResourceType: fixture.ResourceType,
		Name:         fixture.Name,
		RelativePath: fixture.RelativePath,
		SizeBytes:    fixture.SizeBytes,
		ModifiedAt:   fixture.ModifiedAt,
		Properties:   fixture.Properties,
	}
	return revisionForMetadata(fixture.ProviderRevision, &metadata)
}

func revisionForMetadata(providerToken *string, metadata *source.MetadataProfile) (entry.Revision, error) {
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

func parentPath(relativePath string) string {
	separator := strings.LastIndexByte(relativePath, '/')
	if separator < 0 {
		return ""
	}
	return relativePath[:separator]
}

func cloneProperties(properties []entry.Property) []entry.Property {
	if properties == nil {
		return nil
	}
	cloned := make([]entry.Property, len(properties))
	for index, property := range properties {
		copy, err := entry.NewProperty(property.Key, property.Value)
		if err != nil {
			return nil
		}
		cloned[index] = copy
	}
	return cloned
}

func cloneString(value *string) *string {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}

func cloneInt64(value *int64) *int64 {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}

func cloneTime(value *time.Time) *time.Time {
	if value == nil {
		return nil
	}
	copy := value.Round(0)
	return &copy
}

func validGeneration(generation string) bool {
	return validUTF8Bytes(generation, 1, maximumGeneration)
}

func validUTF8Bytes(value string, minimum, maximum int) bool {
	return utf8.ValidString(value) && len(value) >= minimum && len(value) <= maximum
}

type providerClient interface {
	List(context.Context, source.AccessSession, *Adapter, listRequest, int) (listResult, error)
	Resolve(context.Context, source.AccessSession, *Adapter, source.AdapterResolveRequest) (*Fixture, error)
}

type fixtureProviderClient struct{}

func (fixtureProviderClient) List(ctx context.Context, session source.AccessSession, adapter *Adapter, request listRequest, limit int) (listResult, error) {
	if session.Validate() != nil || session.SourceInstanceID != adapter.identity.SourceID || session.Provider != "fakeexternal" {
		return listResult{}, source.ErrPermissionDenied
	}
	return adapter.listWithLimit(ctx, request, limit)
}

func (fixtureProviderClient) Resolve(ctx context.Context, session source.AccessSession, adapter *Adapter, request source.AdapterResolveRequest) (*Fixture, error) {
	if session.Validate() != nil || session.SourceInstanceID != adapter.identity.SourceID || session.Provider != "fakeexternal" {
		return nil, source.ErrPermissionDenied
	}
	if err := ctx.Err(); err != nil {
		return nil, source.ErrAdapterFailure
	}
	for index := range adapter.fixtures {
		candidate := &adapter.fixtures[index]
		if request.EntryRef != nil && candidate.Key == request.EntryRef.SourceObjectKey || request.RelativePath != nil && candidate.RelativePath == *request.RelativePath {
			copy := *candidate
			return &copy, nil
		}
	}
	return nil, nil
}

type ResourceAdapter struct {
	delegate *Adapter
	resolver source.ConnectionResolver
	client   providerClient
}

func NewResourceAdapter(adapter *Adapter) *ResourceAdapter {
	resolver, err := defaultConnectionResolver(adapter)
	if err != nil {
		return &ResourceAdapter{delegate: adapter}
	}
	return &ResourceAdapter{delegate: adapter, resolver: resolver, client: fixtureProviderClient{}}
}

func newResourceAdapterWithConnection(adapter *Adapter, resolver source.ConnectionResolver, client providerClient) (*ResourceAdapter, error) {
	if adapter == nil || nilConnectionResolver(resolver) || nilProviderClient(client) {
		return nil, source.ErrInvalidConfig
	}
	return &ResourceAdapter{delegate: adapter, resolver: resolver, client: client}, nil
}

func defaultConnectionResolver(adapter *Adapter) (source.ConnectionResolver, error) {
	if adapter == nil {
		return nil, source.ErrInvalidConfig
	}
	credential, err := source.NewCredentialRef("fake-credential-reference")
	if err != nil {
		return nil, err
	}
	connection, err := source.NewSourceConnection("fake-connection", "fakeexternal", adapter.identity.SourceID, source.AuthMethodOAuth2, source.ConnectionStatusConnected, &credential, []string{}, adapter.observedAt, nil)
	if err != nil {
		return nil, err
	}
	state := source.ConnectionResolutionConnected
	switch adapter.availability {
	case entry.AvailabilityStatePermissionDenied:
		state = source.ConnectionResolutionAuthRequired
	case entry.AvailabilityStateOffline, entry.AvailabilityStateLoading:
		state = source.ConnectionResolutionProviderUnavailable
	}
	return source.NewFakeConnectionResolver(connection, state, adapter.observedAt.Add(time.Hour))
}

func (adapter *ResourceAdapter) resolveConnection(ctx context.Context) (source.ConnectionResolution, error) {
	if adapter == nil || adapter.delegate == nil || nilConnectionResolver(adapter.resolver) || nilProviderClient(adapter.client) {
		return source.ConnectionResolution{}, source.ErrInvalidRequest
	}
	resolution, err := adapter.resolver.Resolve(ctx, adapter.delegate.identity.SourceID, "fakeexternal")
	if err != nil || resolution.Validate() != nil {
		return source.ConnectionResolution{}, source.ErrAdapterFailure
	}
	return resolution, nil
}

func (adapter *ResourceAdapter) List(ctx context.Context, request source.AdapterListRequest) (source.AdapterListResult, error) {
	if adapter == nil || adapter.delegate == nil || request.Validate() != nil || request.SourceRef.SourceInstanceID != adapter.delegate.identity.SourceID {
		return source.AdapterListResult{}, source.ErrInvalidRequest
	}
	resolution, err := adapter.resolveConnection(ctx)
	if err != nil {
		return source.AdapterListResult{}, err
	}
	if resolution.State != source.ConnectionResolutionConnected {
		return connectionListResult(resolution.State, adapter.delegate.observedAt)
	}
	if resolution.Session == nil {
		return source.AdapterListResult{}, source.ErrAdapterFailure
	}
	listRequest, err := newListRequest(adapter.delegate.identity, request.MountRef.MountID, request.RelativePath, request.ChildCursor)
	if err != nil {
		return source.AdapterListResult{}, err
	}
	listResult, listErr := adapter.client.List(ctx, *resolution.Session, adapter.delegate, listRequest, request.PageQuota)
	if listErr != nil && listResult.SourceError == nil {
		return source.AdapterListResult{}, listErr
	}
	items := make([]source.AdapterEntry, len(listResult.Items))
	for index, item := range listResult.Items {
		locatorRef, locatorErr := adapter.delegate.canonicalLocatorRef(item)
		if locatorErr != nil {
			return source.AdapterListResult{}, locatorErr
		}
		items[index], err = source.CanonicalizeSourceItemWithLocator(item, locatorRef, request.RequestedProperties, request.PropertyDefinitions, listResult.Freshness.ObservedAt, listResult.SourceRevision, listResult.Availability, listResult.Freshness, entry.PropertyProvenanceProviderDefined)
		if err != nil {
			return source.AdapterListResult{}, source.ErrAdapterFailure
		}
	}
	result := source.AdapterListResult{Items: items, NextChildCursor: cloneString(listResult.NextChildCursor), SourceRevision: listResult.SourceRevision, Availability: listResult.Availability, Freshness: listResult.Freshness, SourceError: cloneSourceError(listResult.SourceError), Warnings: cloneWarnings(listResult.Warnings)}
	if result.Validate(request.PageQuota) != nil {
		return source.AdapterListResult{}, source.ErrAdapterFailure
	}
	return result, nil
}

func (adapter *ResourceAdapter) Resolve(ctx context.Context, request source.AdapterResolveRequest) (source.AdapterResolveResult, error) {
	if adapter == nil || adapter.delegate == nil || request.Validate() != nil || request.SourceRef.SourceInstanceID != adapter.delegate.identity.SourceID {
		return source.AdapterResolveResult{}, source.ErrInvalidRequest
	}
	resolution, err := adapter.resolveConnection(ctx)
	if err != nil {
		return source.AdapterResolveResult{}, err
	}
	if resolution.State != source.ConnectionResolutionConnected {
		return connectionResolveResult(resolution.State, adapter.delegate.observedAt)
	}
	if resolution.Session == nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	sourceOutcome, outcomeErr := adapter.delegate.outcomeResult([]source.SourceItem{}, nil)
	if outcomeErr != nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	result := source.AdapterResolveResult{SourceRevision: sourceOutcome.SourceRevision, Availability: sourceOutcome.Availability, Freshness: sourceOutcome.Freshness, SourceError: cloneSourceError(sourceOutcome.SourceError), Warnings: cloneWarnings(sourceOutcome.Warnings)}
	if providerStateError(adapter.delegate.availability) != nil {
		if result.Validate() != nil {
			return source.AdapterResolveResult{}, source.ErrAdapterFailure
		}
		return result, nil
	}
	fixture, err := adapter.client.Resolve(ctx, *resolution.Session, adapter.delegate, request)
	if err != nil {
		return source.AdapterResolveResult{}, err
	}
	if fixture == nil {
		result.SourceError, _ = source.NewSourceError(source.SourceErrorCodeEntryNotFound)
		if result.Validate() != nil {
			return source.AdapterResolveResult{}, source.ErrAdapterFailure
		}
		return result, nil
	}
	sourceItem, err := adapter.delegate.makeItem(*fixture)
	if err != nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	result.SourceRevision = sourceItem.Snapshot.Revision
	sourceRevision, err := entry.NewSourceRevision(result.SourceRevision)
	if err != nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	result.Freshness, err = entry.NewFreshness(result.Freshness.State, result.Freshness.ObservedAt, sourceRevision, result.Freshness.LastSyncAt, result.Freshness.StaleAfter)
	if err != nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	locatorRef, err := adapter.delegate.canonicalLocatorRef(sourceItem)
	if err != nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	canonical, err := source.CanonicalizeSourceItemWithLocator(sourceItem, locatorRef, request.RequestedProperties, request.PropertyDefinitions, result.Freshness.ObservedAt, result.SourceRevision, result.Availability, result.Freshness, entry.PropertyProvenanceProviderDefined)
	if err != nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	result.Item = &canonical
	result.SourceError = nil
	if result.Validate() != nil {
		return source.AdapterResolveResult{}, source.ErrAdapterFailure
	}
	return result, nil
}

func connectionListResult(state source.ConnectionResolutionState, observedAt time.Time) (source.AdapterListResult, error) {
	availabilityState, errorCode := connectionOutcome(state)
	revision, _ := entry.NewRevision(entry.RevisionStrengthUnknown, nil)
	sourceRevision, _ := entry.NewSourceRevision(revision)
	freshness, _ := entry.NewFreshness(entry.FreshnessStateUnknown, observedAt.Round(0).UTC(), sourceRevision, nil, nil)
	availability, _ := entry.NewAvailability(availabilityState)
	sourceError, _ := source.NewSourceError(errorCode)
	result := source.AdapterListResult{Items: []source.AdapterEntry{}, SourceRevision: revision, Availability: availability, Freshness: freshness, SourceError: sourceError, Warnings: []source.Warning{}}
	return result, nil
}
func connectionResolveResult(state source.ConnectionResolutionState, observedAt time.Time) (source.AdapterResolveResult, error) {
	list, err := connectionListResult(state, observedAt)
	return source.AdapterResolveResult{SourceRevision: list.SourceRevision, Availability: list.Availability, Freshness: list.Freshness, SourceError: list.SourceError, Warnings: list.Warnings}, err
}
func connectionOutcome(state source.ConnectionResolutionState) (entry.AvailabilityState, source.SourceErrorCode) {
	switch state {
	case source.ConnectionResolutionAuthRequired, source.ConnectionResolutionAuthExpired, source.ConnectionResolutionAuthRevoked:
		return entry.AvailabilityStatePermissionDenied, source.SourceErrorCodePermissionDenied
	case source.ConnectionResolutionProviderUnavailable:
		return entry.AvailabilityStateOffline, source.SourceErrorCodeSourceUnavailable
	default:
		return entry.AvailabilityStateError, source.SourceErrorCodeAdapterFailure
	}
}
func nilConnectionResolver(value source.ConnectionResolver) bool { return nilInterfaceValue(value) }
func nilProviderClient(value providerClient) bool                { return nilInterfaceValue(value) }
func nilInterfaceValue(value any) bool {
	if value == nil {
		return true
	}
	ref := reflect.ValueOf(value)
	switch ref.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return ref.IsNil()
	}
	return false
}

func equalOptionalString(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}

func newListResult(items []source.SourceItem, next *string, revision entry.Revision, availability entry.Availability, freshness entry.Freshness, sourceError *source.SourceError, warnings []source.Warning) (listResult, error) {
	if len(items) > maximumFixtures || next != nil && !validUTF8Bytes(*next, 1, maximumCursor) || revision.Validate() != nil || availability.ValidateCanonical() != nil || freshness.ValidateCanonical() != nil || freshness.SourceRevision.Revision.Strength != revision.Strength || !equalOptionalString(freshness.SourceRevision.Revision.Token, revision.Token) || len(warnings) > 32 {
		return listResult{}, source.ErrAdapterFailure
	}
	for _, item := range items {
		if item.Validate() != nil {
			return listResult{}, source.ErrAdapterFailure
		}
	}
	for _, warning := range warnings {
		if warning.Validate() != nil {
			return listResult{}, source.ErrAdapterFailure
		}
	}
	if sourceError != nil && sourceError.Validate() != nil {
		return listResult{}, source.ErrAdapterFailure
	}
	return listResult{Items: append([]source.SourceItem{}, items...), NextChildCursor: cloneString(next), SourceRevision: revision, Availability: availability, Freshness: freshness, SourceError: cloneSourceError(sourceError), Warnings: cloneWarnings(warnings)}, nil
}

func cloneSourceError(value *source.SourceError) *source.SourceError {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}
func cloneWarnings(values []source.Warning) []source.Warning {
	if values == nil {
		return nil
	}
	return append([]source.Warning{}, values...)
}

func (adapter *Adapter) canonicalLocatorRef(item source.SourceItem) (entry.LocatorRef, error) {
	backendLocator := []byte(adapter.namespace + "\x00" + item.Identity.EntryKey)
	locator, err := source.NewCanonicalSourceLocator(adapter.cursorKey[:minimumCursorKeySize], "fakeexternal", adapter.identity.SourceID, backendLocator)
	if err != nil {
		return entry.LocatorRef{}, err
	}
	return locator.LocatorRef()
}
