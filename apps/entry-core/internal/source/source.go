package source

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

var (
	ErrInvalidConfig         = errors.New("invalid source configuration")
	ErrInvalidRequest        = errors.New("invalid source request")
	ErrInvalidCursor         = errors.New("invalid cursor")
	ErrPathEscape            = errors.New("source path escapes root")
	ErrAdapterFailure        = errors.New("source adapter failure")
	ErrSourceUnavailable     = errors.New("source unavailable")
	ErrPermissionDenied      = errors.New("permission denied")
	ErrSourceDeleted         = errors.New("source deleted")
	ErrEntryNotFound         = errors.New("entry not found")
	errPropertyNotApplicable = errors.New("source property not applicable")
)

const (
	maximumSourceRelativePathBytes = 4096
	maximumMountIDBytes            = 128
	maximumCursorBytes             = 4096
	maximumResultItems             = 256
	maximumChildCursorBytes        = 256
	maximumRequestedProperties     = 256
)

type SourceLocator struct {
	digest []byte
}

func NewSourceLocator(ownerKey, backendLocator []byte) (SourceLocator, error) {
	if len(ownerKey) < 32 || len(backendLocator) == 0 {
		return SourceLocator{}, ErrAdapterFailure
	}
	mac := hmac.New(sha256.New, ownerKey)
	_, _ = mac.Write(backendLocator)
	return SourceLocator{digest: mac.Sum(nil)}, nil
}

func ValidateSourceLocator(locator SourceLocator, ownerKey, backendLocator []byte) bool {
	if !locator.valid() || len(ownerKey) < 32 || len(backendLocator) == 0 {
		return false
	}
	mac := hmac.New(sha256.New, ownerKey)
	_, _ = mac.Write(backendLocator)
	return hmac.Equal(locator.digest, mac.Sum(nil))
}

func (locator SourceLocator) valid() bool {
	return len(locator.digest) == sha256.Size
}

type SourceItem struct {
	RelativePath string
	Identity     entry.EntryIdentity
	Snapshot     entry.EntrySnapshot
	Locator      SourceLocator
	Capabilities entry.Capabilities
}

func NewSourceItem(
	relativePath string,
	identity entry.EntryIdentity,
	snapshot entry.EntrySnapshot,
	locator SourceLocator,
	capabilities entry.Capabilities,
) (SourceItem, error) {
	item := SourceItem{
		RelativePath: relativePath,
		Identity:     identity,
		Snapshot:     snapshot,
		Locator:      locator,
		Capabilities: capabilities,
	}
	if err := item.Validate(); err != nil {
		return SourceItem{}, err
	}
	return cloneSourceItem(item)
}

func (item SourceItem) Validate() error {
	if !ValidateRelativePath(item.RelativePath) || !item.Locator.valid() {
		return ErrAdapterFailure
	}
	if err := item.Identity.Validate(); err != nil {
		return ErrAdapterFailure
	}
	if err := item.Snapshot.Validate(); err != nil {
		return ErrAdapterFailure
	}
	return nil
}

type SourceErrorCode string

const (
	SourceErrorCodeEntryNotFound     SourceErrorCode = "entry_not_found"
	SourceErrorCodeSourceUnavailable SourceErrorCode = "source_unavailable"
	SourceErrorCodePermissionDenied  SourceErrorCode = "permission_denied"
	SourceErrorCodeSourceDeleted     SourceErrorCode = "source_deleted"
	SourceErrorCodeAdapterFailure    SourceErrorCode = "adapter_failure"
)

type SourceError struct {
	Code      SourceErrorCode
	Message   string
	Retryable bool
}

func NewSourceError(code SourceErrorCode) (*SourceError, error) {
	value := SourceError{Code: code, Message: sourceErrorMessage(code)}
	if err := value.Validate(); err != nil {
		return nil, err
	}
	return &value, nil
}

func (sourceError SourceError) Validate() error {
	if sourceError.Message == "" || sourceError.Message != sourceErrorMessage(sourceError.Code) {
		return ErrAdapterFailure
	}
	return nil
}

type WarningCode string

const (
	WarningCodeStaleSnapshot     WarningCode = "stale_snapshot"
	WarningCodeSourceOffline     WarningCode = "source_offline"
	WarningCodeSourceUnavailable WarningCode = "source_unavailable"
	WarningCodePermissionDenied  WarningCode = "permission_denied"
	WarningCodeSourceDeleted     WarningCode = "source_deleted"
	WarningCodeAdapterFailure    WarningCode = "adapter_failure"
	WarningCodePartialResult     WarningCode = "partial_result"
)

type Warning struct {
	Code      WarningCode
	Message   string
	Retryable bool
}

func (warning Warning) Validate() error {
	switch warning.Code {
	case WarningCodeStaleSnapshot, WarningCodeSourceOffline, WarningCodeSourceUnavailable, WarningCodePermissionDenied, WarningCodeSourceDeleted, WarningCodeAdapterFailure, WarningCodePartialResult:
	default:
		return ErrAdapterFailure
	}
	return nil
}

func sourceErrorCodeForAvailability(state entry.AvailabilityState) SourceErrorCode {
	switch state {
	case entry.AvailabilityStatePermissionDenied:
		return SourceErrorCodePermissionDenied
	case entry.AvailabilityStateSourceDeleted:
		return SourceErrorCodeSourceDeleted
	case entry.AvailabilityStateOffline, entry.AvailabilityStateUnmounted, entry.AvailabilityStateLoading:
		return SourceErrorCodeSourceUnavailable
	case entry.AvailabilityStateError:
		return SourceErrorCodeAdapterFailure
	default:
		return ""
	}
}

func sourceErrorMessage(code SourceErrorCode) string {
	switch code {
	case SourceErrorCodeEntryNotFound:
		return "The entry was not found."
	case SourceErrorCodeSourceUnavailable:
		return "The source is unavailable."
	case SourceErrorCodePermissionDenied:
		return "Permission was denied."
	case SourceErrorCodeSourceDeleted:
		return "The source was deleted."
	case SourceErrorCodeAdapterFailure:
		return "The source adapter failed."
	default:
		return ""
	}
}

func hasWarning(warnings []Warning, allowed ...WarningCode) bool {
	for _, warning := range warnings {
		for _, code := range allowed {
			if warning.Code == code {
				return true
			}
		}
	}
	return false
}

func cloneRevision(value entry.Revision) entry.Revision {
	return entry.Revision{Strength: value.Strength, Token: cloneString(value.Token)}
}

func cloneFreshness(value entry.Freshness) entry.Freshness {
	return entry.Freshness{
		State: value.State, ObservedAt: value.ObservedAt, SourceRevision: entry.SourceRevision{Revision: cloneRevision(value.SourceRevision.Revision)},
		LastSyncAt: cloneTime(value.LastSyncAt), StaleAfter: cloneTime(value.StaleAfter),
	}
}

func cloneSourceError(value *SourceError) *SourceError {
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

func equalOptionalString(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}

func ValidateRelativePath(relativePath string) bool {
	if len(relativePath) > maximumSourceRelativePathBytes || !utf8.ValidString(relativePath) {
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

func DeriveSourceIdentity(adapterKind, material string, strength entry.IdentityStrength) (entry.SourceIdentity, error) {
	if !validASCII(adapterKind, 1, 64) || material == "" || !utf8.ValidString(material) {
		return entry.SourceIdentity{}, ErrInvalidConfig
	}
	encoded := make([]byte, 0, 16+len(adapterKind)+len(material))
	encoded = appendLengthPrefixed(encoded, []byte(adapterKind))
	encoded = appendLengthPrefixed(encoded, []byte(material))
	digest := sha256.Sum256(encoded)
	sourceID := "src:" + base64.RawURLEncoding.EncodeToString(digest[:])
	identity, err := entry.NewSourceIdentity(sourceID, strength)
	if err != nil {
		return entry.SourceIdentity{}, ErrInvalidConfig
	}
	return identity, nil
}

type MetadataProfile struct {
	ProfileName  string
	Namespace    string
	EntryKey     string
	ResourceType string
	Name         string
	RelativePath string
	SizeBytes    *int64
	ModifiedAt   *time.Time
	Properties   []entry.Property
}

func ResolveRevision(providerToken *string, metadata *MetadataProfile) (entry.Revision, error) {
	if providerToken != nil && *providerToken != "" {
		revision, err := entry.NewRevision(entry.RevisionStrengthProvider, providerToken)
		if err != nil {
			return entry.Revision{}, ErrAdapterFailure
		}
		return revision, nil
	}
	if metadata == nil {
		return entry.NewRevision(entry.RevisionStrengthUnknown, nil)
	}
	token, ok := metadataFingerprint(*metadata)
	if !ok {
		return entry.NewRevision(entry.RevisionStrengthUnknown, nil)
	}
	revision, err := entry.NewRevision(entry.RevisionStrengthMetadata, &token)
	if err != nil {
		return entry.Revision{}, ErrAdapterFailure
	}
	return revision, nil
}

func metadataFingerprint(profile MetadataProfile) (string, bool) {
	if !validMetadataProfile(profile) {
		return "", false
	}
	payload := make([]byte, 0)
	payload = appendFrame(payload, 0x01, []byte(profile.ProfileName))
	if profile.ProfileName == "fake-external" {
		payload = appendFrame(payload, 0x02, []byte(profile.Namespace))
		payload = appendFrame(payload, 0x03, []byte(profile.EntryKey))
	}
	payload = appendFrame(payload, 0x04, []byte(profile.ResourceType))
	payload = appendFrame(payload, 0x05, []byte(profile.Name))
	payload = appendFrame(payload, 0x06, []byte(profile.RelativePath))
	if profile.SizeBytes == nil {
		payload = appendFrame(payload, 0x00, nil)
	} else {
		encoded := make([]byte, 8)
		binary.BigEndian.PutUint64(encoded, uint64(*profile.SizeBytes))
		payload = appendFrame(payload, 0x07, encoded)
	}
	if profile.ModifiedAt == nil {
		payload = appendFrame(payload, 0x00, nil)
	} else {
		encoded := []byte(profile.ModifiedAt.Round(0).UTC().Format(time.RFC3339Nano))
		payload = appendFrame(payload, 0x08, encoded)
	}
	properties, ok := encodeProperties(profile.Properties)
	if !ok {
		return "", false
	}
	payload = append(payload, properties...)
	complete := appendFrame(nil, 0x10, payload)
	digest := sha256.Sum256(complete)
	return "meta:" + base64.RawURLEncoding.EncodeToString(digest[:]), true
}

func validMetadataProfile(profile MetadataProfile) bool {
	if profile.ProfileName != "local" && profile.ProfileName != "fake-external" {
		return false
	}
	if !validUTF8Bytes(profile.ResourceType, 1, 128) || !validUTF8Bytes(profile.Name, 1, 1024) || !ValidateRelativePath(profile.RelativePath) {
		return false
	}
	if profile.ProfileName == "local" && (profile.Namespace != "" || profile.EntryKey != "") {
		return false
	}
	if profile.ProfileName == "fake-external" && (!validUTF8Bytes(profile.Namespace, 1, 256) || !validUTF8Bytes(profile.EntryKey, 1, 4096)) {
		return false
	}
	if profile.SizeBytes != nil && *profile.SizeBytes < 0 {
		return false
	}
	if profile.ModifiedAt != nil {
		canonical := profile.ModifiedAt.Round(0).UTC()
		if canonical.Year() < 0 || canonical.Year() > 9999 {
			return false
		}
	}
	return entry.ValidateProperties(profile.Properties) == nil
}

func encodeProperties(properties []entry.Property) ([]byte, bool) {
	if err := entry.ValidateProperties(properties); err != nil {
		return nil, false
	}
	sorted := append([]entry.Property(nil), properties...)
	sort.Slice(sorted, func(left, right int) bool { return sorted[left].Key < sorted[right].Key })
	payload := make([]byte, 8)
	binary.BigEndian.PutUint64(payload, uint64(len(sorted)))
	for _, property := range sorted {
		value, ok := encodePropertyValue(property.Value)
		if !ok {
			return nil, false
		}
		propertyPayload := appendFrame(nil, 0x21, []byte(property.Key))
		propertyPayload = append(propertyPayload, value...)
		payload = appendFrame(payload, 0x20, propertyPayload)
	}
	return appendFrame(nil, 0x09, payload), true
}

func encodePropertyValue(value entry.PropertyValue) ([]byte, bool) {
	if err := value.Validate(); err != nil {
		return nil, false
	}
	switch value.Type {
	case entry.PropertyValueTypeString:
		return appendFrame(nil, 0x30, []byte(*value.StringValue)), true
	case entry.PropertyValueTypeInt64:
		payload := make([]byte, 8)
		binary.BigEndian.PutUint64(payload, uint64(*value.Int64Value))
		return appendFrame(nil, 0x31, payload), true
	case entry.PropertyValueTypeBool:
		payload := byte(0)
		if *value.BoolValue {
			payload = 1
		}
		return appendFrame(nil, 0x32, []byte{payload}), true
	case entry.PropertyValueTypeTimestamp:
		payload := []byte(value.TimestampValue.Round(0).UTC().Format(time.RFC3339Nano))
		return appendFrame(nil, 0x33, payload), true
	case entry.PropertyValueTypeStringList:
		payload := make([]byte, 8)
		binary.BigEndian.PutUint64(payload, uint64(len(*value.StringListValue)))
		for _, item := range *value.StringListValue {
			payload = appendFrame(payload, 0x35, []byte(item))
		}
		return appendFrame(nil, 0x34, payload), true
	default:
		return nil, false
	}
}

func cloneSourceItem(item SourceItem) (SourceItem, error) {
	snapshot, err := entry.NewEntrySnapshot(
		item.Snapshot.Name,
		item.Snapshot.ResourceType,
		item.Snapshot.SizeBytes,
		item.Snapshot.ModifiedAt,
		item.Snapshot.Properties,
		item.Snapshot.Revision,
		item.Snapshot.Availability,
		item.Snapshot.Freshness,
		item.Snapshot.OperationState,
	)
	if err != nil {
		return SourceItem{}, ErrAdapterFailure
	}
	return SourceItem{
		RelativePath: item.RelativePath,
		Identity:     item.Identity,
		Snapshot:     snapshot,
		Locator:      item.Locator,
		Capabilities: item.Capabilities,
	}, nil
}

func appendFrame(destination []byte, tag byte, payload []byte) []byte {
	destination = append(destination, tag)
	return appendLengthPrefixed(destination, payload)
}

func appendLengthPrefixed(destination, value []byte) []byte {
	length := make([]byte, 8)
	binary.BigEndian.PutUint64(length, uint64(len(value)))
	destination = append(destination, length...)
	return append(destination, value...)
}

func validSourceID(sourceID string) bool {
	if len(sourceID) != len("src:")+43 || !strings.HasPrefix(sourceID, "src:") {
		return false
	}
	encoded := strings.TrimPrefix(sourceID, "src:")
	digest, err := base64.RawURLEncoding.DecodeString(encoded)
	return err == nil && len(digest) == sha256.Size && base64.RawURLEncoding.EncodeToString(digest) == encoded
}

func validASCII(value string, minimum, maximum int) bool {
	if len(value) < minimum || len(value) > maximum {
		return false
	}
	for _, character := range []byte(value) {
		if character > 0x7f {
			return false
		}
	}
	return true
}

func validUTF8Bytes(value string, minimum, maximum int) bool {
	return utf8.ValidString(value) && len(value) >= minimum && len(value) <= maximum
}

func cloneString(value *string) *string {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}

// AdapterListRequest is the provider-neutral executable list boundary.
type AdapterListRequest struct {
	SourceRef           entry.SourceRef
	MountRef            entry.MountRef
	RelativePath        string
	PageQuota           int
	ChildCursor         *string
	RequestedProperties []string
	PropertyDefinitions map[string]entry.PropertyDefinition
	SourceSelectors     map[string]entry.SourcePropertyDescriptor
	ReadTransforms      map[string]entry.PropertyBinding
}

func NewAdapterListRequest(sourceRef entry.SourceRef, mountRef entry.MountRef, relativePath string, pageQuota int, childCursor *string, requestedProperties []string) (AdapterListRequest, error) {
	request := AdapterListRequest{
		SourceRef: sourceRef, MountRef: mountRef, RelativePath: relativePath, PageQuota: pageQuota,
		ChildCursor: cloneString(childCursor), RequestedProperties: append([]string{}, requestedProperties...),
	}
	if err := request.Validate(); err != nil {
		return AdapterListRequest{}, err
	}
	return request, nil
}

func (request AdapterListRequest) Validate() error {
	if request.SourceRef.Validate() != nil || request.MountRef.Validate() != nil ||
		request.SourceRef.SourceInstanceID != request.MountRef.SourceInstanceID ||
		!ValidateRelativePath(request.RelativePath) || request.PageQuota < 1 || request.PageQuota > maximumResultItems ||
		!validChildCursor(request.ChildCursor) || !validRequestedProperties(request.RequestedProperties) {
		return ErrInvalidRequest
	}
	return nil
}

type SourceObjectIdentity struct {
	ObjectKey        string
	ResourceType     string
	LocatorRef       entry.LocatorRef
	IdentityStrength entry.IdentityStrength
}

func (identity SourceObjectIdentity) Validate() error {
	if !validUTF8Bytes(identity.ObjectKey, 1, 4096) || !validUTF8Bytes(identity.ResourceType, 1, 128) ||
		identity.LocatorRef.Validate() != nil {
		return ErrInvalidRequest
	}
	switch identity.IdentityStrength {
	case entry.IdentityStrengthStable, entry.IdentityStrengthObjectLifetime, entry.IdentityStrengthLocator, entry.IdentityStrengthEphemeral:
		return nil
	default:
		return ErrInvalidRequest
	}
}

type SourceObjectSelector struct {
	SourceInstanceID string
	SourceObjectKey  string
}

func (selector SourceObjectSelector) Validate() error {
	if !validSourceID(selector.SourceInstanceID) || !validUTF8Bytes(selector.SourceObjectKey, 1, 4096) {
		return ErrInvalidRequest
	}
	return nil
}

type AdapterEntry struct {
	RelativePath  string
	EntryRef      entry.EntryRef
	EntrySnapshot entry.EntrySnapshot
	Capabilities  entry.Capabilities
}

func (item AdapterEntry) Validate() error {
	if !ValidateRelativePath(item.RelativePath) || item.EntryRef.Validate() != nil || item.EntrySnapshot.ValidateCanonical() != nil ||
		item.EntrySnapshot.EntryRef != item.EntryRef || item.Capabilities.ValidateCanonical() != nil ||
		item.Capabilities.ValidateForAvailability(item.EntrySnapshot.Availability.State) != nil {
		return ErrAdapterFailure
	}
	return nil
}

type AdapterListResult struct {
	Items           []AdapterEntry
	NextChildCursor *string
	SourceRevision  entry.Revision
	Availability    entry.Availability
	Freshness       entry.Freshness
	SourceError     *SourceError
	Warnings        []Warning
}

func (result AdapterListResult) Validate(pageQuota int) error {
	if pageQuota < 1 || pageQuota > maximumResultItems || result.Items == nil || result.Warnings == nil || len(result.Items) > pageQuota ||
		!validChildCursor(result.NextChildCursor) || (len(result.Items) == 0 && result.NextChildCursor != nil) ||
		result.SourceRevision.Strength == entry.RevisionStrengthObserved || result.SourceRevision.Validate() != nil ||
		result.Availability.ValidateCanonical() != nil || result.Freshness.ValidateCanonical() != nil || len(result.Warnings) > 32 ||
		result.Freshness.SourceRevision.Revision.Strength != result.SourceRevision.Strength ||
		!equalOptionalString(result.Freshness.SourceRevision.Revision.Token, result.SourceRevision.Token) {
		return ErrAdapterFailure
	}
	relativePaths := make(map[string]struct{}, len(result.Items))
	for _, item := range result.Items {
		if _, duplicate := relativePaths[item.RelativePath]; duplicate {
			return ErrAdapterFailure
		}
		relativePaths[item.RelativePath] = struct{}{}
		if item.Validate() != nil || item.EntrySnapshot.Availability != result.Availability || !equalAdapterFreshnessEnvelope(item.EntrySnapshot.Freshness, result.Freshness) {
			return ErrAdapterFailure
		}
	}
	for _, warning := range result.Warnings {
		if warning.Validate() != nil {
			return ErrAdapterFailure
		}
	}
	if err := validateAdapterOutcome(len(result.Items), result.NextChildCursor, result.Availability, result.Freshness, result.SourceError, result.Warnings, false); err != nil {
		return err
	}
	return nil
}

type AdapterResolveRequest struct {
	SourceRef           entry.SourceRef
	MountRef            entry.MountRef
	EntryRef            *entry.EntryRef
	RelativePath        *string
	RequestedProperties []string
	PropertyDefinitions map[string]entry.PropertyDefinition
	SourceSelectors     map[string]entry.SourcePropertyDescriptor
	ReadTransforms      map[string]entry.PropertyBinding
}

func NewAdapterResolveRequest(sourceRef entry.SourceRef, mountRef entry.MountRef, entryRef *entry.EntryRef, relativePath *string, requestedProperties []string) (AdapterResolveRequest, error) {
	request := AdapterResolveRequest{
		SourceRef: sourceRef, MountRef: mountRef, EntryRef: cloneEntryRef(entryRef), RelativePath: cloneString(relativePath),
		RequestedProperties: append([]string{}, requestedProperties...),
	}
	if err := request.Validate(); err != nil {
		return AdapterResolveRequest{}, err
	}
	return request, nil
}

func (request AdapterResolveRequest) Validate() error {
	if request.SourceRef.Validate() != nil || request.MountRef.Validate() != nil || request.SourceRef.SourceInstanceID != request.MountRef.SourceInstanceID ||
		(request.EntryRef == nil) == (request.RelativePath == nil) || !validRequestedProperties(request.RequestedProperties) {
		return ErrInvalidRequest
	}
	if request.EntryRef != nil && (request.EntryRef.Validate() != nil || request.EntryRef.SourceInstanceID != request.SourceRef.SourceInstanceID) {
		return ErrInvalidRequest
	}
	if request.RelativePath != nil && !ValidateRelativePath(*request.RelativePath) {
		return ErrInvalidRequest
	}
	return nil
}

type AdapterResolveResult struct {
	Item           *AdapterEntry
	SourceRevision entry.Revision
	Availability   entry.Availability
	Freshness      entry.Freshness
	SourceError    *SourceError
	Warnings       []Warning
}

func (result AdapterResolveResult) Validate() error {
	count := 0
	if result.Item != nil {
		count = 1
		if result.Item.Validate() != nil || result.Item.EntrySnapshot.Availability != result.Availability || !equalAdapterFreshness(result.Item.EntrySnapshot.Freshness, result.Freshness) || !equalRevision(result.Item.EntrySnapshot.SourceRevision.Revision, result.SourceRevision) {
			return ErrAdapterFailure
		}
	}
	if result.Warnings == nil || result.SourceRevision.Strength == entry.RevisionStrengthObserved || result.SourceRevision.Validate() != nil ||
		result.Availability.ValidateCanonical() != nil || result.Freshness.ValidateCanonical() != nil || len(result.Warnings) > 32 ||
		result.Freshness.SourceRevision.Revision.Strength != result.SourceRevision.Strength ||
		!equalOptionalString(result.Freshness.SourceRevision.Revision.Token, result.SourceRevision.Token) {
		return ErrAdapterFailure
	}
	for _, warning := range result.Warnings {
		if warning.Validate() != nil {
			return ErrAdapterFailure
		}
	}
	return validateAdapterOutcome(count, nil, result.Availability, result.Freshness, result.SourceError, result.Warnings, true)
}

func validateAdapterOutcome(itemCount int, cursor *string, availability entry.Availability, freshness entry.Freshness, sourceError *SourceError, warnings []Warning, resolve bool) error {
	switch availability.State {
	case entry.AvailabilityStateAvailable, entry.AvailabilityStateReadOnly:
		if resolve && itemCount == 0 && sourceError != nil && sourceError.Code == SourceErrorCodeEntryNotFound && sourceError.Validate() == nil {
			return nil
		}
		if sourceError != nil || freshness.State == entry.FreshnessStateStale || (resolve && itemCount != 1) {
			return ErrAdapterFailure
		}
	case entry.AvailabilityStateStale:
		if sourceError != nil || freshness.State != entry.FreshnessStateStale || (resolve && itemCount != 1) || !hasWarning(warnings, WarningCodeStaleSnapshot, WarningCodeSourceOffline) {
			return ErrAdapterFailure
		}
	case entry.AvailabilityStateLoading, entry.AvailabilityStateOffline, entry.AvailabilityStatePermissionDenied,
		entry.AvailabilityStateSourceDeleted, entry.AvailabilityStateUnmounted, entry.AvailabilityStateError:
		if itemCount != 0 || cursor != nil || sourceError == nil || sourceError.Validate() != nil || sourceError.Code != sourceErrorCodeForAvailability(availability.State) {
			return ErrAdapterFailure
		}
	default:
		return ErrAdapterFailure
	}
	return nil
}

func equalRevision(left, right entry.Revision) bool {
	return left.Strength == right.Strength && equalOptionalString(left.Token, right.Token)
}

func equalAdapterFreshness(left, right entry.Freshness) bool {
	return left.State == right.State && left.ObservedAt.Equal(right.ObservedAt) && equalRevision(left.SourceRevision.Revision, right.SourceRevision.Revision) && equalOptionalTime(left.LastSyncAt, right.LastSyncAt) && equalOptionalTime(left.StaleAfter, right.StaleAfter)
}

func equalAdapterFreshnessEnvelope(left, right entry.Freshness) bool {
	return left.State == right.State && left.ObservedAt.Equal(right.ObservedAt) && equalOptionalTime(left.LastSyncAt, right.LastSyncAt) && equalOptionalTime(left.StaleAfter, right.StaleAfter)
}

func equalOptionalTime(left, right *time.Time) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return left.Equal(*right)
}

func validChildCursor(cursor *string) bool {
	return cursor == nil || validASCII(*cursor, 1, maximumChildCursorBytes)
}

func validRequestedProperties(properties []string) bool {
	if properties == nil || len(properties) > maximumRequestedProperties {
		return false
	}
	for index, property := range properties {
		if !validUTF8Bytes(property, 1, 128) || (index > 0 && properties[index-1] >= property) {
			return false
		}
	}
	return true
}

func cloneEntryRef(value *entry.EntryRef) *entry.EntryRef {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}

func (locator SourceLocator) LocatorRef() (entry.LocatorRef, error) {
	if !locator.valid() {
		return entry.LocatorRef{}, ErrAdapterFailure
	}
	value := "loc:" + base64.RawURLEncoding.EncodeToString(locator.digest)
	ref, err := entry.NewLocatorRef(value)
	if err != nil {
		return entry.LocatorRef{}, ErrAdapterFailure
	}
	return ref, nil
}

func CanonicalizeSourceItem(item SourceItem, requestedProperties []string, observedAt time.Time, sourceRevision entry.Revision, availability entry.Availability, freshness entry.Freshness, provenance entry.PropertyProvenance) (AdapterEntry, error) {
	if item.Validate() != nil || !validRequestedProperties(requestedProperties) || sourceRevision.Validate() != nil || availability.ValidateCanonical() != nil || freshness.ValidateCanonical() != nil {
		return AdapterEntry{}, ErrAdapterFailure
	}
	locatorRef, err := item.Locator.LocatorRef()
	if err != nil {
		return AdapterEntry{}, err
	}
	return CanonicalizeSourceItemWithLocator(item, locatorRef, requestedProperties, nil, nil, nil, observedAt, sourceRevision, availability, freshness, provenance)
}

// CanonicalizeSourceItemWithLocator는 소스 아이템을 canonical AdapterEntry로 투영한다.
// requestedProperties는 workspace 요청 문자열(canonical key/alias/정확한 PropertyID
// 텍스트)이고, sourceSelectors는 요청 이름을 네이티브 소스 키로 연결하고 readTransforms는
// 검토된 변환 계약을 전달한다. 두 맵에 없는 이름은 요청 문자열 자체를 네이티브 키로 쓴다.
func CanonicalizeSourceItemWithLocator(item SourceItem, locatorRef entry.LocatorRef, requestedProperties []string, propertyDefinitions map[string]entry.PropertyDefinition, sourceSelectors map[string]entry.SourcePropertyDescriptor, readTransforms map[string]entry.PropertyBinding, observedAt time.Time, sourceRevision entry.Revision, availability entry.Availability, freshness entry.Freshness, provenance entry.PropertyProvenance) (AdapterEntry, error) {
	if item.Validate() != nil || locatorRef.Validate() != nil || !validRequestedProperties(requestedProperties) || sourceRevision.Validate() != nil || availability.ValidateCanonical() != nil || freshness.ValidateCanonical() != nil {
		return AdapterEntry{}, ErrAdapterFailure
	}
	ref, err := entry.NewEntryRef(entry.DeriveEntryID(item.Identity.SourceID, item.Snapshot.ResourceType, item.Identity.EntryKey), item.Identity.SourceID, item.Identity.EntryKey, item.Snapshot.ResourceType, locatorRef, item.Identity.IdentityStrength)
	if err != nil {
		return AdapterEntry{}, ErrAdapterFailure
	}
	itemRevision := item.Snapshot.Revision
	sourceRevisionValue, err := entry.NewSourceRevision(itemRevision)
	if err != nil {
		return AdapterEntry{}, ErrAdapterFailure
	}
	itemFreshness, err := entry.NewFreshness(freshness.State, freshness.ObservedAt, sourceRevisionValue, freshness.LastSyncAt, freshness.StaleAfter)
	if err != nil {
		return AdapterEntry{}, ErrAdapterFailure
	}
	properties := make([]entry.PropertyValue, 0, len(requestedProperties))
	for _, requested := range requestedProperties {
		nativeKey := requested
		descriptor, bound := sourceSelectors[requested]
		if bound {
			nativeKey = descriptor.NativeKey
		}
		transform := "identity"
		if binding, ok := readTransforms[requested]; ok {
			transform = binding.ReadTransform
		}
		found := false
		for _, property := range item.Snapshot.Properties {
			if property.Key != nativeKey {
				continue
			}
			found = true
			if bound && !nativeValueMatchesDescriptor(property.Value, descriptor) {
				return AdapterEntry{}, ErrAdapterFailure
			}
			value, valueErr := canonicalPropertyValue(property, transform, propertyDefinitions[requested], ref.EntryID, observedAt, sourceRevisionValue, provenance)
			if errors.Is(valueErr, errPropertyNotApplicable) {
				break
			}
			if valueErr != nil {
				return AdapterEntry{}, valueErr
			}
			properties = append(properties, value)
			break
		}
		if bound && !found && propertyDefinitions[requested].Required {
			return AdapterEntry{}, ErrAdapterFailure
		}
	}
	observedRevision, _ := entry.NewObservedRevision(1)
	snapshot, err := entry.NewCanonicalEntrySnapshot(ref, item.Snapshot.Name, nil, properties, sourceRevisionValue, observedRevision, observedAt.Round(0).UTC(), item.Snapshot.ModifiedAt, availability, itemFreshness)
	if err != nil {
		return AdapterEntry{}, ErrAdapterFailure
	}
	capabilities := canonicalCapabilities(item.Capabilities)
	result := AdapterEntry{RelativePath: item.RelativePath, EntryRef: ref, EntrySnapshot: snapshot, Capabilities: capabilities}
	if result.Validate() != nil {
		return AdapterEntry{}, ErrAdapterFailure
	}
	return result, nil
}

func nativeValueMatchesDescriptor(value entry.PropertyValue, descriptor entry.SourcePropertyDescriptor) bool {
	if value.Validate() != nil {
		return false
	}
	cardinality := entry.PropertyCardinalityOne
	if value.Type == entry.PropertyValueTypeStringList {
		cardinality = entry.PropertyCardinalityMany
	}
	if descriptor.NativeCardinality != cardinality {
		return false
	}
	switch descriptor.NativeType {
	case "string", "categorical":
		return value.Type == entry.PropertyValueTypeString
	case "string_list":
		return value.Type == entry.PropertyValueTypeStringList
	case "number":
		return value.Type == entry.PropertyValueTypeInt64
	case "boolean":
		return value.Type == entry.PropertyValueTypeBool
	case "date", "datetime":
		return value.Type == entry.PropertyValueTypeTimestamp
	default:
		return false
	}
}

// canonicalPropertyValue는 네이티브 소스 프로퍼티를 canonical PropertyValue로 투영한다.
// transform은 검토된 읽기 변환(filename_extension, filename_stem, identity)만 허용하고,
// 그 외 값은 실패 닫기한다. 카탈로그 바인딩된 정의는 타입·cardinality 계약을 보존하며
// select 계약에는 text 네이티브 값을 select payload로 투영한다.
func canonicalPropertyValue(property entry.Property, transform string, definition entry.PropertyDefinition, entryID string, observedAt time.Time, sourceRevision entry.SourceRevision, provenance entry.PropertyProvenance) (entry.PropertyValue, error) {
	catalogBound := definition.PropertyID != (entry.PropertyID{})
	value := property.Value
	switch transform {
	case "", "identity":
	case "filename_extension":
		name, ok := stringValuePayload(value)
		if !ok {
			return entry.PropertyValue{}, ErrAdapterFailure
		}
		_, extension, hasExtension := foundationFilenameParts(name)
		if !hasExtension {
			return entry.PropertyValue{}, errPropertyNotApplicable
		}
		value = stringPropertyValue(extension)
	case "filename_stem":
		name, ok := stringValuePayload(value)
		if !ok {
			return entry.PropertyValue{}, ErrAdapterFailure
		}
		stem, _, _ := foundationFilenameParts(name)
		value = stringPropertyValue(stem)
	default:
		return entry.PropertyValue{}, ErrAdapterFailure
	}
	if !catalogBound {
		propertyID, err := entry.RegistryPropertyID(property.Key)
		if err != nil {
			return entry.PropertyValue{}, ErrAdapterFailure
		}
		definition = entry.PropertyDefinition{PropertyID: propertyID, IdentityScheme: entry.PropertyIdentitySchemeRegistryDerived, Namespace: "adapter", Key: property.Key, DisplayName: property.Key, Cardinality: entry.PropertyCardinalityOne, Provenance: provenance, ValidationRules: []entry.ValidationRule{}}
	}
	var valueType entry.PropertyType
	cardinality := entry.PropertyCardinalityOne
	var payload entry.PropertyPayload
	switch value.Type {
	case entry.PropertyValueTypeString:
		valueType = entry.PropertyTypeText
		payload = entry.TextPayload(*value.StringValue)
	case entry.PropertyValueTypeInt64:
		valueType = entry.PropertyTypeNumber
		payload = entry.NumberPayload(strconv.FormatInt(*value.Int64Value, 10))
	case entry.PropertyValueTypeBool:
		valueType = entry.PropertyTypeBoolean
		payload = entry.BooleanPayload(*value.BoolValue)
	case entry.PropertyValueTypeTimestamp:
		valueType = entry.PropertyTypeDateTime
		payload = entry.DateTimePayload(value.TimestampValue.Round(0).Format(time.RFC3339Nano))
	case entry.PropertyValueTypeStringList:
		valueType = entry.PropertyTypeText
		cardinality = entry.PropertyCardinalityMany
		payload = entry.TextManyPayload(*value.StringListValue)
	default:
		return entry.PropertyValue{}, ErrAdapterFailure
	}
	if catalogBound && definition.ValueType == entry.PropertyTypeSelect && valueType == entry.PropertyTypeText {
		switch cardinality {
		case entry.PropertyCardinalityOne:
			if payload.Text == nil {
				return entry.PropertyValue{}, ErrAdapterFailure
			}
			payload = entry.SelectPayload(*payload.Text)
		case entry.PropertyCardinalityMany:
			if payload.TextMany == nil {
				return entry.PropertyValue{}, ErrAdapterFailure
			}
			payload = entry.SelectManyPayload(*payload.TextMany)
		default:
			return entry.PropertyValue{}, ErrAdapterFailure
		}
		valueType = entry.PropertyTypeSelect
	}
	if catalogBound {
		// 카탈로그에 바인딩된 정의는 타입·cardinality 계약을 보존한다. adapter
		// payload가 계약과 다르면 값을 재타이핑하지 않고 실패 처리한다.
		if definition.ValueType != valueType || definition.Cardinality != cardinality {
			return entry.PropertyValue{}, ErrAdapterFailure
		}
	} else {
		definition.ValueType = valueType
		definition.Cardinality = cardinality
	}
	validated, err := entry.NewPropertyDefinition(definition)
	if err != nil {
		return entry.PropertyValue{}, ErrAdapterFailure
	}
	canonical, err := entry.NewPropertyValue(validated, entryID, entry.PropertyStateValue, provenance, observedAt.Round(0).UTC(), sourceRevision, false, payload)
	if err != nil {
		return entry.PropertyValue{}, ErrAdapterFailure
	}
	return canonical, nil
}

func foundationFilenameParts(name string) (stem string, extension string, hasExtension bool) {
	lastDot := strings.LastIndexByte(name, '.')
	if lastDot <= 0 || lastDot == len(name)-1 {
		return name, "", false
	}
	return name[:lastDot], name[lastDot+1:], true
}

func stringValuePayload(value entry.PropertyValue) (string, bool) {
	if value.Type == entry.PropertyValueTypeString && value.StringValue != nil {
		return *value.StringValue, true
	}
	return "", false
}

func stringPropertyValue(text string) entry.PropertyValue {
	return entry.PropertyValue{Type: entry.PropertyValueTypeString, StringValue: &text}
}

func canonicalCapabilities(value entry.Capabilities) entry.Capabilities {
	result := value
	if result.ListChildren || result.ReadProperties {
		result.Readable = true
	}
	result.ListChildren = false
	result.ReadProperties = false
	return result
}

func NewCanonicalSourceLocator(ownerKey []byte, adapterKind, sourceInstanceID string, backendLocator []byte) (SourceLocator, error) {
	if len(ownerKey) != sha256.Size || !validASCII(adapterKind, 1, 64) || !validSourceID(sourceInstanceID) || len(backendLocator) == 0 {
		return SourceLocator{}, ErrAdapterFailure
	}
	material := make([]byte, 0, len(adapterKind)+len(sourceInstanceID)+len(backendLocator)+24)
	material = appendLengthPrefixed(material, []byte(adapterKind))
	material = appendLengthPrefixed(material, []byte(sourceInstanceID))
	material = appendLengthPrefixed(material, backendLocator)
	mac := hmac.New(sha256.New, ownerKey)
	_, _ = mac.Write(material)
	return SourceLocator{digest: mac.Sum(nil)}, nil
}

func ValidateCanonicalSourceLocator(locator SourceLocator, ownerKey []byte, adapterKind, sourceInstanceID string, backendLocator []byte) bool {
	expected, err := NewCanonicalSourceLocator(ownerKey, adapterKind, sourceInstanceID, backendLocator)
	return err == nil && locator.valid() && hmac.Equal(locator.digest, expected.digest)
}
