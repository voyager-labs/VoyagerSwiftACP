package entry

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

var (
	ErrInvalidIdentityStrength = errors.New("invalid identity strength")
	ErrInvalidSourceIdentity   = errors.New("invalid source identity")
	ErrInvalidLocatorRef       = errors.New("invalid locator ref")
	ErrInvalidEntryRef         = errors.New("invalid entry ref")
	ErrInvalidSourceRef        = errors.New("invalid source ref")
	ErrInvalidMountRef         = errors.New("invalid mount ref")
	ErrInvalidCapabilities     = errors.New("invalid capabilities")
	ErrInvalidSourceRevision   = errors.New("invalid source revision")
	ErrInvalidObservedRevision = errors.New("invalid observed revision")
	ErrInvalidEntryIdentity    = errors.New("invalid entry identity")
	ErrInvalidRevision         = errors.New("invalid revision")
	ErrInvalidAvailability     = errors.New("invalid availability")
	ErrInvalidFreshness        = errors.New("invalid freshness")
	ErrInvalidOperationState   = errors.New("invalid operation state")
	ErrInvalidVirtualPath      = errors.New("invalid virtual path")
	ErrInvalidAccessContext    = errors.New("invalid access context")
	ErrInvalidPropertyValue    = errors.New("invalid property value")
	ErrInvalidProperty         = errors.New("invalid property")
	ErrDuplicatePropertyKey    = errors.New("duplicate property key")
	ErrInvalidEntrySnapshot    = errors.New("invalid entry snapshot")
	ErrInvalidEntry            = errors.New("invalid entry")
)

const (
	sourceIDPrefix         = "src:"
	entryIDPrefix          = "ent:"
	locatorRefPrefix       = "loc:"
	metadataRevisionPrefix = "meta:"
)

type IdentityStrength string

const (
	IdentityStrengthStable         IdentityStrength = "stable"
	IdentityStrengthObjectLifetime IdentityStrength = "object_lifetime"
	IdentityStrengthLocator        IdentityStrength = "locator"
	IdentityStrengthEphemeral      IdentityStrength = "ephemeral"
)

func (strength IdentityStrength) valid() bool {
	switch strength {
	case IdentityStrengthStable, IdentityStrengthObjectLifetime, IdentityStrengthLocator, IdentityStrengthEphemeral:
		return true
	default:
		return false
	}
}

type SourceIdentity struct {
	SourceID         string
	IdentityStrength IdentityStrength
}

func NewSourceIdentity(sourceID string, strength IdentityStrength) (SourceIdentity, error) {
	identity := SourceIdentity{
		SourceID:         sourceID,
		IdentityStrength: strength,
	}
	if err := identity.Validate(); err != nil {
		return SourceIdentity{}, err
	}
	return identity, nil
}

func (identity SourceIdentity) Validate() error {
	if !isValidSourceID(identity.SourceID) {
		return ErrInvalidSourceIdentity
	}
	if !identity.IdentityStrength.valid() {
		return ErrInvalidIdentityStrength
	}
	return nil
}

func isValidSourceID(sourceID string) bool {
	return validPrefixedDigest(sourceID, sourceIDPrefix)
}

func validPrefixedDigest(value, prefix string) bool {
	if len(value) != len(prefix)+43 || value[:len(prefix)] != prefix {
		return false
	}
	encoded := value[len(prefix):]
	digest, err := base64.RawURLEncoding.DecodeString(encoded)
	return err == nil && len(digest) == 32 && base64.RawURLEncoding.EncodeToString(digest) == encoded
}

type EntryIdentity struct {
	SourceID         string
	EntryKey         string
	IdentityStrength IdentityStrength
}

func NewEntryIdentity(sourceID, entryKey string, strength IdentityStrength) (EntryIdentity, error) {
	identity := EntryIdentity{SourceID: sourceID, EntryKey: entryKey, IdentityStrength: strength}
	if err := identity.Validate(); err != nil {
		return EntryIdentity{}, err
	}
	return identity, nil
}

func (identity EntryIdentity) Validate() error {
	if !isValidSourceID(identity.SourceID) || !validUTF8Bytes(identity.EntryKey, 1, 4096) {
		return ErrInvalidEntryIdentity
	}
	if !identity.IdentityStrength.valid() {
		return ErrInvalidIdentityStrength
	}
	return nil
}

type RevisionStrength string

const (
	RevisionStrengthProvider RevisionStrength = "provider"
	RevisionStrengthMetadata RevisionStrength = "metadata"
	RevisionStrengthObserved RevisionStrength = "observed"
	RevisionStrengthUnknown  RevisionStrength = "unknown"
)

func (strength RevisionStrength) valid() bool {
	switch strength {
	case RevisionStrengthProvider, RevisionStrengthMetadata, RevisionStrengthObserved, RevisionStrengthUnknown:
		return true
	default:
		return false
	}
}

type Revision struct {
	Strength RevisionStrength
	Token    *string
}

func NewRevision(strength RevisionStrength, token *string) (Revision, error) {
	revision := Revision{Strength: strength, Token: token}
	if err := revision.Validate(); err != nil {
		return Revision{}, err
	}
	revision.Token = cloneString(token)
	return revision, nil
}

func (revision Revision) Validate() error {
	if !revision.Strength.valid() {
		return ErrInvalidRevision
	}
	switch revision.Strength {
	case RevisionStrengthProvider:
		if revision.Token == nil || !validASCIIBytes(*revision.Token, 1, 128) {
			return ErrInvalidRevision
		}
	case RevisionStrengthMetadata:
		if revision.Token == nil || !validPrefixedDigest(*revision.Token, metadataRevisionPrefix) {
			return ErrInvalidRevision
		}
	case RevisionStrengthObserved:
		if revision.Token == nil || !validPositiveDecimal(*revision.Token) {
			return ErrInvalidRevision
		}
	case RevisionStrengthUnknown:
		if revision.Token != nil {
			return ErrInvalidRevision
		}
	}
	return nil
}

type AvailabilityState string

const (
	AvailabilityStateAvailable        AvailabilityState = "available"
	AvailabilityStateLoading          AvailabilityState = "loading"
	AvailabilityStateStale            AvailabilityState = "stale"
	AvailabilityStateOffline          AvailabilityState = "offline"
	AvailabilityStatePermissionDenied AvailabilityState = "permission_denied"
	AvailabilityStateSourceDeleted    AvailabilityState = "source_deleted"
	AvailabilityStateUnmounted        AvailabilityState = "unmounted"
	AvailabilityStateReadOnly         AvailabilityState = "read_only"
	AvailabilityStateError            AvailabilityState = "error"
	AvailabilityStateUnavailable      AvailabilityState = "unavailable"
	AvailabilityStateUnknown          AvailabilityState = "unknown"
)

func (state AvailabilityState) valid() bool {
	switch state {
	case AvailabilityStateAvailable, AvailabilityStateLoading, AvailabilityStateStale, AvailabilityStateOffline, AvailabilityStatePermissionDenied, AvailabilityStateSourceDeleted, AvailabilityStateUnmounted, AvailabilityStateReadOnly, AvailabilityStateError, AvailabilityStateUnavailable, AvailabilityStateUnknown:
		return true
	default:
		return false
	}
}

type Availability struct {
	State AvailabilityState
}

func (availability Availability) Validate() error {
	if !availability.State.valid() {
		return ErrInvalidAvailability
	}
	return nil
}

type FreshnessState string

const (
	FreshnessStateCurrent FreshnessState = "current"
	FreshnessStateStale   FreshnessState = "stale"
	FreshnessStateUnknown FreshnessState = "unknown"
)

func (state FreshnessState) valid() bool {
	switch state {
	case FreshnessStateCurrent, FreshnessStateStale, FreshnessStateUnknown:
		return true
	default:
		return false
	}
}

type Freshness struct {
	State          FreshnessState
	ObservedAt     time.Time
	SourceRevision SourceRevision
	LastSyncAt     *time.Time
	StaleAfter     *time.Time
}

func (freshness Freshness) Validate() error {
	if !freshness.ObservedAt.IsZero() || freshness.SourceRevision.Revision.Strength != "" || freshness.SourceRevision.Revision.Token != nil || freshness.LastSyncAt != nil || freshness.StaleAfter != nil {
		return ErrInvalidFreshness
	}
	if !freshness.State.valid() {
		return ErrInvalidFreshness
	}
	return nil
}

type OperationStateValue string

const (
	OperationStateIdle    OperationStateValue = "idle"
	OperationStateBusy    OperationStateValue = "busy"
	OperationStateFailed  OperationStateValue = "failed"
	OperationStateUnknown OperationStateValue = "unknown"
)

func (state OperationStateValue) valid() bool {
	switch state {
	case OperationStateIdle, OperationStateBusy, OperationStateFailed, OperationStateUnknown:
		return true
	default:
		return false
	}
}

type OperationState struct {
	State OperationStateValue
}

func (operationState OperationState) Validate() error {
	if !operationState.State.valid() {
		return ErrInvalidOperationState
	}
	return nil
}

type Capabilities struct {
	Readable         bool
	Writable         bool
	Searchable       bool
	Commentable      bool
	Movable          bool
	Copyable         bool
	Deletable        bool
	Watchable        bool
	Streamable       bool
	RequiresApproval bool

	ListChildren   bool
	ReadProperties bool
}

type VirtualPath struct {
	value        string
	mountID      string
	parentPath   string
	pathRevision string
}

func NewVirtualPath(value string) (VirtualPath, error) {
	if !validCanonicalVirtualPath(value) {
		return VirtualPath{}, ErrInvalidVirtualPath
	}
	return VirtualPath{value: value}, nil
}

func (path VirtualPath) String() string {
	return path.value
}

func (path VirtualPath) Validate() error {
	if !validCanonicalVirtualPath(path.value) {
		return ErrInvalidVirtualPath
	}
	return nil
}

func validCanonicalVirtualPath(value string) bool {
	if !validUTF8Bytes(value, 1, 4096) || value[0] != '/' {
		return false
	}
	if value == "/" {
		return true
	}
	if value[len(value)-1] == '/' || strings.Contains(value, "//") || strings.ContainsRune(value, '\x00') || strings.ContainsRune(value, '\\') {
		return false
	}
	for _, segment := range strings.Split(value[1:], "/") {
		if segment == "." || segment == ".." {
			return false
		}
	}
	return true
}

type AccessContext struct {
	SourceID     string
	MountID      string
	VirtualPath  VirtualPath
	DisplayPath  *string
	Capabilities Capabilities
}

func NewAccessContext(sourceID, mountID string, virtualPath VirtualPath, capabilities Capabilities) (AccessContext, error) {
	context := AccessContext{
		SourceID:     sourceID,
		MountID:      mountID,
		VirtualPath:  virtualPath,
		Capabilities: capabilities,
	}
	if err := context.Validate(); err != nil {
		return AccessContext{}, err
	}
	return context, nil
}

func NewCanonicalAccessContext(sourceID, mountID string, virtualPath VirtualPath, displayPath *string, capabilities Capabilities) (AccessContext, error) {
	context := AccessContext{SourceID: sourceID, MountID: mountID, VirtualPath: virtualPath, DisplayPath: displayPath, Capabilities: capabilities}
	if err := context.ValidateCanonical(); err != nil {
		return AccessContext{}, err
	}
	context.DisplayPath = cloneString(displayPath)
	return context, nil
}

func (context AccessContext) ValidateCanonical() error {
	if !isValidSourceID(context.SourceID) || !validUTF8Bytes(context.MountID, 1, 64) || context.VirtualPath.ValidateCanonical() != nil ||
		context.VirtualPath.MountID() != context.MountID || context.Capabilities.ValidateCanonical() != nil {
		return ErrInvalidAccessContext
	}
	if context.DisplayPath != nil && !validUTF8Bytes(*context.DisplayPath, 1, 4096) {
		return ErrInvalidAccessContext
	}
	return nil
}

func (context AccessContext) Validate() error {
	if context.DisplayPath != nil || context.VirtualPath.MountID() != "" || context.VirtualPath.ParentPath() != "" || context.VirtualPath.PathRevision() != "" || context.Capabilities.hasCanonicalFields() {
		return ErrInvalidAccessContext
	}
	if !isValidSourceID(context.SourceID) || !validUTF8Bytes(context.MountID, 1, 128) {
		return ErrInvalidAccessContext
	}
	if err := context.VirtualPath.Validate(); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalidAccessContext, err)
	}
	return nil
}

type PropertyValueType string

const (
	PropertyValueTypeString     PropertyValueType = "string"
	PropertyValueTypeInt64      PropertyValueType = "int64"
	PropertyValueTypeBool       PropertyValueType = "bool"
	PropertyValueTypeTimestamp  PropertyValueType = "timestamp"
	PropertyValueTypeStringList PropertyValueType = "string_list"
	PropertyTypeText            PropertyValueType = "text"
	PropertyTypeNumber          PropertyValueType = "number"
	PropertyTypeDate            PropertyValueType = "date"
	PropertyTypeDateTime        PropertyValueType = "datetime"
	PropertyTypeBoolean         PropertyValueType = "boolean"
	PropertyTypeSelect          PropertyValueType = "select"
)

func (valueType PropertyValueType) valid() bool {
	switch valueType {
	case PropertyValueTypeString, PropertyValueTypeInt64, PropertyValueTypeBool, PropertyValueTypeTimestamp, PropertyValueTypeStringList, PropertyTypeText, PropertyTypeNumber, PropertyTypeDate, PropertyTypeDateTime, PropertyTypeBoolean, PropertyTypeSelect:
		return true
	default:
		return false
	}
}

type PropertyValue struct {
	Type            PropertyValueType
	PropertyID      PropertyID
	EntryID         string
	Payload         PropertyPayload
	State           PropertyState
	Provenance      PropertyProvenance
	ObservedAt      time.Time
	SourceRevision  SourceRevision
	Editable        bool
	Validation      ValidationResult
	Cardinality     PropertyCardinality
	StringValue     *string
	Int64Value      *int64
	BoolValue       *bool
	TimestampValue  *time.Time
	StringListValue *[]string
}

func NewStringPropertyValue(value string) (PropertyValue, error) {
	propertyValue := PropertyValue{Type: PropertyValueTypeString, StringValue: &value}
	return validatedPropertyValue(propertyValue)
}

func NewInt64PropertyValue(value int64) (PropertyValue, error) {
	propertyValue := PropertyValue{Type: PropertyValueTypeInt64, Int64Value: &value}
	return validatedPropertyValue(propertyValue)
}

func NewBoolPropertyValue(value bool) (PropertyValue, error) {
	propertyValue := PropertyValue{Type: PropertyValueTypeBool, BoolValue: &value}
	return validatedPropertyValue(propertyValue)
}

func NewTimestampPropertyValue(value time.Time) (PropertyValue, error) {
	value = value.Round(0)
	propertyValue := PropertyValue{Type: PropertyValueTypeTimestamp, TimestampValue: &value}
	return validatedPropertyValue(propertyValue)
}

func NewStringListPropertyValue(value []string) (PropertyValue, error) {
	propertyValue := PropertyValue{Type: PropertyValueTypeStringList, StringListValue: &value}
	if err := propertyValue.Validate(); err != nil {
		return PropertyValue{}, err
	}
	copied := append([]string(nil), value...)
	propertyValue.StringListValue = &copied
	return propertyValue, nil
}

func validatedPropertyValue(value PropertyValue) (PropertyValue, error) {
	if err := value.Validate(); err != nil {
		return PropertyValue{}, err
	}
	return value, nil
}

func (value PropertyValue) Validate() error {
	if value.hasCanonicalFields() {
		return value.validateCanonicalShape()
	}
	if !value.Type.valid() || value.payloadCount() != 1 {
		return ErrInvalidPropertyValue
	}
	switch value.Type {
	case PropertyValueTypeString:
		if value.StringValue == nil || !validUTF8Bytes(*value.StringValue, 0, 16384) {
			return ErrInvalidPropertyValue
		}
	case PropertyValueTypeInt64:
		if value.Int64Value == nil {
			return ErrInvalidPropertyValue
		}
	case PropertyValueTypeBool:
		if value.BoolValue == nil {
			return ErrInvalidPropertyValue
		}
	case PropertyValueTypeTimestamp:
		if value.TimestampValue == nil || !validTimestamp(*value.TimestampValue) {
			return ErrInvalidPropertyValue
		}
	case PropertyValueTypeStringList:
		if value.StringListValue == nil || len(*value.StringListValue) > 256 {
			return ErrInvalidPropertyValue
		}
		for _, item := range *value.StringListValue {
			if !validUTF8Bytes(item, 0, 4096) {
				return ErrInvalidPropertyValue
			}
		}
	}
	if !value.payloadMatchesType() {
		return ErrInvalidPropertyValue
	}
	return nil
}

func (value PropertyValue) payloadCount() int {
	count := 0
	for _, present := range []bool{
		value.StringValue != nil,
		value.Int64Value != nil,
		value.BoolValue != nil,
		value.TimestampValue != nil,
		value.StringListValue != nil,
	} {
		if present {
			count++
		}
	}
	return count
}

func (value PropertyValue) payloadMatchesType() bool {
	switch value.Type {
	case PropertyValueTypeString:
		return value.StringValue != nil
	case PropertyValueTypeInt64:
		return value.Int64Value != nil
	case PropertyValueTypeBool:
		return value.BoolValue != nil
	case PropertyValueTypeTimestamp:
		return value.TimestampValue != nil
	case PropertyValueTypeStringList:
		return value.StringListValue != nil
	default:
		return false
	}
}

type Property struct {
	Key   string
	Value PropertyValue
}

func NewProperty(key string, value PropertyValue) (Property, error) {
	property := Property{Key: key, Value: value}
	if err := property.Validate(); err != nil {
		return Property{}, err
	}
	property.Value = clonePropertyValue(value)
	return property, nil
}

func (property Property) Validate() error {
	if property.Value.hasCanonicalFields() || !validUTF8Bytes(property.Key, 1, 128) {
		return ErrInvalidProperty
	}
	if err := property.Value.Validate(); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalidProperty, err)
	}
	return nil
}

func ValidateProperties(properties []Property) error {
	if len(properties) > 256 {
		return ErrInvalidProperty
	}
	keys := make(map[string]struct{}, len(properties))
	for _, property := range properties {
		if err := property.Validate(); err != nil {
			return err
		}
		if _, exists := keys[property.Key]; exists {
			return ErrDuplicatePropertyKey
		}
		keys[property.Key] = struct{}{}
	}
	return nil
}

type EntrySnapshot struct {
	EntryRef            EntryRef
	DisplayName         string
	ParentRef           *EntryRef
	CanonicalProperties []PropertyValue
	SourceRevision      SourceRevision
	ObservedRevision    ObservedRevision
	ObservedAt          time.Time
	CanonicalModifiedAt *time.Time

	Name           string
	ResourceType   string
	SizeBytes      *int64
	ModifiedAt     *time.Time
	Properties     []Property
	Revision       Revision
	Availability   Availability
	Freshness      Freshness
	OperationState OperationState
}

func NewEntrySnapshot(
	name string,
	resourceType string,
	sizeBytes *int64,
	modifiedAt *time.Time,
	properties []Property,
	revision Revision,
	availability Availability,
	freshness Freshness,
	operationState OperationState,
) (EntrySnapshot, error) {
	snapshot := EntrySnapshot{
		Name:           name,
		ResourceType:   resourceType,
		SizeBytes:      sizeBytes,
		ModifiedAt:     modifiedAt,
		Properties:     properties,
		Revision:       revision,
		Availability:   availability,
		Freshness:      freshness,
		OperationState: operationState,
	}
	if err := snapshot.Validate(); err != nil {
		return EntrySnapshot{}, err
	}
	return cloneSnapshot(snapshot), nil
}

func (snapshot EntrySnapshot) Validate() error {
	if snapshot.hasCanonicalFields() {
		return ErrInvalidEntrySnapshot
	}
	if !validUTF8Bytes(snapshot.Name, 1, 1024) || !validUTF8Bytes(snapshot.ResourceType, 1, 128) {
		return ErrInvalidEntrySnapshot
	}
	if snapshot.SizeBytes != nil && *snapshot.SizeBytes < 0 {
		return ErrInvalidEntrySnapshot
	}
	if snapshot.ModifiedAt != nil && !validTimestamp(*snapshot.ModifiedAt) {
		return ErrInvalidEntrySnapshot
	}
	if len(snapshot.Properties) > 256 {
		return ErrInvalidEntrySnapshot
	}
	legacyBudget := 0
	for _, property := range snapshot.Properties {
		propertyBudget, ok := legacyPropertyBudget(property)
		if !ok || !addWithin(&legacyBudget, propertyBudget, maximumSnapshotPropertyBudget) {
			return ErrInvalidEntrySnapshot
		}
	}
	if err := ValidateProperties(snapshot.Properties); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalidEntrySnapshot, err)
	}
	if err := snapshot.Revision.Validate(); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalidEntrySnapshot, err)
	}
	if err := snapshot.Availability.Validate(); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalidEntrySnapshot, err)
	}
	if err := snapshot.Freshness.Validate(); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalidEntrySnapshot, err)
	}
	if err := snapshot.OperationState.Validate(); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalidEntrySnapshot, err)
	}
	return nil
}

type Entry struct {
	Identity      EntryIdentity
	Snapshot      EntrySnapshot
	AccessContext AccessContext
}

func NewEntry(identity EntryIdentity, snapshot EntrySnapshot, accessContext AccessContext) (Entry, error) {
	entry := Entry{Identity: identity, Snapshot: snapshot, AccessContext: accessContext}
	if err := entry.Validate(); err != nil {
		return Entry{}, err
	}
	entry.Snapshot = cloneSnapshot(snapshot)
	entry.AccessContext = cloneAccessContext(accessContext)
	return entry, nil
}

func (entry Entry) Validate() error {
	if err := entry.Identity.Validate(); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalidEntry, err)
	}
	if err := entry.Snapshot.Validate(); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalidEntry, err)
	}
	if err := entry.AccessContext.Validate(); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalidEntry, err)
	}
	if entry.Identity.SourceID != entry.AccessContext.SourceID {
		return ErrInvalidEntry
	}
	return nil
}

func validUTF8Bytes(value string, minimum, maximum int) bool {
	length := len(value)
	return length >= minimum && length <= maximum && utf8.ValidString(value)
}

func validTimestamp(value time.Time) bool {
	canonical := value.Round(0).UTC()
	if canonical.Year() < 0 || canonical.Year() > 9999 {
		return false
	}
	_, err := time.Parse(time.RFC3339Nano, canonical.Format(time.RFC3339Nano))
	return err == nil
}

func cloneString(value *string) *string {
	if value == nil {
		return nil
	}
	copied := *value
	return &copied
}

func cloneInt64(value *int64) *int64 {
	if value == nil {
		return nil
	}
	copied := *value
	return &copied
}

func cloneTime(value *time.Time) *time.Time {
	if value == nil {
		return nil
	}
	copied := value.Round(0)
	return &copied
}

func cloneRevision(revision Revision) Revision {
	return Revision{Strength: revision.Strength, Token: cloneString(revision.Token)}
}

func clonePropertyValue(value PropertyValue) PropertyValue {
	cloned := PropertyValue{
		Type:           value.Type,
		PropertyID:     value.PropertyID,
		EntryID:        value.EntryID,
		Payload:        clonePropertyPayload(value.Payload),
		State:          value.State,
		Provenance:     value.Provenance,
		ObservedAt:     value.ObservedAt,
		SourceRevision: cloneSourceRevision(value.SourceRevision),
		Editable:       value.Editable,
		Validation:     value.Validation,
		Cardinality:    value.Cardinality,

		StringValue:    cloneString(value.StringValue),
		Int64Value:     cloneInt64(value.Int64Value),
		TimestampValue: cloneTime(value.TimestampValue),
	}
	if value.BoolValue != nil {
		copied := *value.BoolValue
		cloned.BoolValue = &copied
	}
	if value.StringListValue != nil {
		copied := append([]string(nil), (*value.StringListValue)...)
		cloned.StringListValue = &copied
	}
	return cloned
}

func cloneProperties(properties []Property) []Property {
	if properties == nil {
		return nil
	}
	cloned := make([]Property, len(properties))
	for index, property := range properties {
		cloned[index] = Property{Key: property.Key, Value: clonePropertyValue(property.Value)}
	}
	return cloned
}

func cloneSnapshot(snapshot EntrySnapshot) EntrySnapshot {
	return EntrySnapshot{
		EntryRef:            snapshot.EntryRef,
		DisplayName:         snapshot.DisplayName,
		ParentRef:           cloneEntryRef(snapshot.ParentRef),
		CanonicalProperties: cloneCanonicalPropertyValues(snapshot.CanonicalProperties),
		SourceRevision:      cloneSourceRevision(snapshot.SourceRevision),
		ObservedRevision:    snapshot.ObservedRevision,
		ObservedAt:          snapshot.ObservedAt,
		CanonicalModifiedAt: cloneTimeUTC(snapshot.CanonicalModifiedAt),
		Name:                snapshot.Name,
		ResourceType:        snapshot.ResourceType,
		SizeBytes:           cloneInt64(snapshot.SizeBytes),
		ModifiedAt:          cloneTime(snapshot.ModifiedAt),
		Properties:          cloneProperties(snapshot.Properties),
		Revision:            cloneRevision(snapshot.Revision),
		Availability:        snapshot.Availability,
		Freshness:           cloneFreshness(snapshot.Freshness),
		OperationState:      snapshot.OperationState,
	}
}

func cloneAccessContext(value AccessContext) AccessContext {
	value.DisplayPath = cloneString(value.DisplayPath)
	return value
}

type LocatorRef struct{ value string }

func NewLocatorRef(value string) (LocatorRef, error) {
	ref := LocatorRef{value: value}
	if err := ref.Validate(); err != nil {
		return LocatorRef{}, err
	}
	return ref, nil
}

func (ref LocatorRef) String() string { return ref.value }

func (ref LocatorRef) Validate() error {
	if !validPrefixedDigest(ref.value, locatorRefPrefix) {
		return ErrInvalidLocatorRef
	}
	return nil
}

type EntryRef struct {
	EntryID          string
	SourceInstanceID string
	SourceObjectKey  string
	ResourceType     string
	CanonicalLocator LocatorRef
	IdentityStrength IdentityStrength
}

func NewEntryRef(entryID, sourceInstanceID, sourceObjectKey, resourceType string, locator LocatorRef, strength IdentityStrength) (EntryRef, error) {
	ref := EntryRef{
		EntryID: entryID, SourceInstanceID: sourceInstanceID, SourceObjectKey: sourceObjectKey,
		ResourceType: resourceType, CanonicalLocator: locator, IdentityStrength: strength,
	}
	if err := ref.Validate(); err != nil {
		return EntryRef{}, err
	}
	return ref, nil
}

func (ref EntryRef) Validate() error {
	if !validPrefixedDigest(ref.EntryID, entryIDPrefix) || !isValidSourceID(ref.SourceInstanceID) ||
		!validUTF8Bytes(ref.SourceObjectKey, 1, 4096) || !validUTF8Bytes(ref.ResourceType, 1, 128) ||
		ref.EntryID != DeriveEntryID(ref.SourceInstanceID, ref.ResourceType, ref.SourceObjectKey) ||
		ref.CanonicalLocator.Validate() != nil || !ref.IdentityStrength.valid() {
		return ErrInvalidEntryRef
	}
	return nil
}

func DeriveEntryID(sourceInstanceID, resourceType, sourceObjectKey string) string {
	material := make([]byte, 0, 24+len(sourceInstanceID)+len(resourceType)+len(sourceObjectKey))
	for _, value := range []string{sourceInstanceID, resourceType, sourceObjectKey} {
		length := make([]byte, 8)
		binary.BigEndian.PutUint64(length, uint64(len(value)))
		material = append(material, length...)
		material = append(material, value...)
	}
	digest := sha256.Sum256(material)
	return entryIDPrefix + base64.RawURLEncoding.EncodeToString(digest[:])
}

type SourceRef struct {
	SourceInstanceID      string
	ProviderType          string
	AccountOrWorkspaceKey string
	SourceStatus          Availability
	IdentityStrength      IdentityStrength
}

func NewSourceRef(sourceInstanceID, providerType, accountOrWorkspaceKey string, status Availability, strength IdentityStrength) (SourceRef, error) {
	ref := SourceRef{
		SourceInstanceID: sourceInstanceID, ProviderType: providerType,
		AccountOrWorkspaceKey: accountOrWorkspaceKey, SourceStatus: status, IdentityStrength: strength,
	}
	if err := ref.Validate(); err != nil {
		return SourceRef{}, err
	}
	return ref, nil
}

func (ref SourceRef) Validate() error {
	if !isValidSourceID(ref.SourceInstanceID) || !validASCIIBytes(ref.ProviderType, 1, 64) ||
		!validUTF8Bytes(ref.AccountOrWorkspaceKey, 1, 256) || !ref.IdentityStrength.valid() ||
		ref.SourceStatus.ValidateCanonical() != nil {
		return ErrInvalidSourceRef
	}
	return nil
}

type CachePolicy string

const (
	CachePolicyNone                CachePolicy = "none"
	CachePolicyLazyRebuildable     CachePolicy = "lazy_rebuildable"
	CachePolicySnapshotRebuildable CachePolicy = "snapshot_rebuildable"
)

func (policy CachePolicy) valid() bool {
	return policy == CachePolicyNone || policy == CachePolicyLazyRebuildable || policy == CachePolicySnapshotRebuildable
}

type MountRef struct {
	MountID          string
	WorkspaceID      string
	SourceInstanceID string
	MountPoint       VirtualPath
	MountStatus      Availability
	CachePolicy      CachePolicy
}

func NewMountRef(mountID, workspaceID, sourceInstanceID string, mountPoint VirtualPath, status Availability, policy CachePolicy) (MountRef, error) {
	ref := MountRef{
		MountID: mountID, WorkspaceID: workspaceID, SourceInstanceID: sourceInstanceID,
		MountPoint: mountPoint, MountStatus: status, CachePolicy: policy,
	}
	if err := ref.Validate(); err != nil {
		return MountRef{}, err
	}
	return ref, nil
}

func (ref MountRef) Validate() error {
	if !validUTF8Bytes(ref.MountID, 1, 64) || !validUTF8Bytes(ref.WorkspaceID, 1, 64) ||
		!isValidSourceID(ref.SourceInstanceID) || ref.MountPoint.ValidateCanonical() != nil ||
		ref.MountPoint.MountID() != ref.MountID || ref.MountStatus.ValidateCanonical() != nil || !ref.CachePolicy.valid() {
		return ErrInvalidMountRef
	}
	return nil
}

func NewResolvedVirtualPath(mountID, value, pathRevision string) (VirtualPath, error) {
	if !validUTF8Bytes(mountID, 1, 64) || !validUTF8Bytes(pathRevision, 1, 256) || !validCanonicalVirtualPath(value) {
		return VirtualPath{}, ErrInvalidVirtualPath
	}
	parent := ""
	if value != "/" {
		separator := strings.LastIndexByte(value, '/')
		if separator == 0 {
			parent = "/"
		} else {
			parent = value[:separator]
		}
	}
	return VirtualPath{value: value, mountID: mountID, parentPath: parent, pathRevision: pathRevision}, nil
}

func (path VirtualPath) MountID() string      { return path.mountID }
func (path VirtualPath) ParentPath() string   { return path.parentPath }
func (path VirtualPath) PathRevision() string { return path.pathRevision }

func (path VirtualPath) ValidateCanonical() error {
	if path.Validate() != nil || !validUTF8Bytes(path.mountID, 1, 64) || !validUTF8Bytes(path.pathRevision, 1, 256) {
		return ErrInvalidVirtualPath
	}
	expectedParent := ""
	if path.value != "/" {
		separator := strings.LastIndexByte(path.value, '/')
		if separator == 0 {
			expectedParent = "/"
		} else {
			expectedParent = path.value[:separator]
		}
	}
	if path.parentPath != expectedParent {
		return ErrInvalidVirtualPath
	}
	return nil
}

func (capabilities Capabilities) hasCanonicalFields() bool {
	return capabilities.Readable || capabilities.Writable || capabilities.Searchable || capabilities.Commentable ||
		capabilities.Movable || capabilities.Copyable || capabilities.Deletable || capabilities.Watchable ||
		capabilities.Streamable || capabilities.RequiresApproval
}

func (capabilities Capabilities) ValidateCanonical() error {
	if capabilities.ListChildren || capabilities.ReadProperties {
		return ErrInvalidCapabilities
	}
	if capabilities.RequiresApproval && !(capabilities.Writable || capabilities.Commentable || capabilities.Movable || capabilities.Copyable || capabilities.Deletable) {
		return ErrInvalidCapabilities
	}
	return nil
}

func (capabilities Capabilities) ValidateForAvailability(state AvailabilityState) error {
	if err := capabilities.ValidateCanonical(); err != nil {
		return err
	}
	if state == AvailabilityStateReadOnly && (capabilities.Writable || capabilities.Commentable || capabilities.Movable || capabilities.Copyable || capabilities.Deletable || capabilities.RequiresApproval) {
		return ErrInvalidCapabilities
	}
	return nil
}

func NewAvailability(state AvailabilityState) (Availability, error) {
	availability := Availability{State: state}
	if err := availability.ValidateCanonical(); err != nil {
		return Availability{}, err
	}
	return availability, nil
}

func (availability Availability) ValidateCanonical() error {
	switch availability.State {
	case AvailabilityStateAvailable, AvailabilityStateLoading, AvailabilityStateStale, AvailabilityStateOffline,
		AvailabilityStatePermissionDenied, AvailabilityStateSourceDeleted, AvailabilityStateUnmounted,
		AvailabilityStateReadOnly, AvailabilityStateError:
		return nil
	default:
		return ErrInvalidAvailability
	}
}

type SourceRevision struct {
	Revision Revision
}

func NewSourceRevision(revision Revision) (SourceRevision, error) {
	value := SourceRevision{Revision: revision}
	if err := value.Validate(); err != nil {
		return SourceRevision{}, err
	}
	value.Revision = cloneRevision(revision)
	return value, nil
}

func (revision SourceRevision) Validate() error {
	if revision.Revision.Strength == RevisionStrengthObserved || revision.Revision.Validate() != nil {
		return ErrInvalidSourceRevision
	}
	return nil
}

type ObservedRevision struct {
	Sequence uint64
}

func NewObservedRevision(sequence uint64) (ObservedRevision, error) {
	revision := ObservedRevision{Sequence: sequence}
	if err := revision.Validate(); err != nil {
		return ObservedRevision{}, err
	}
	return revision, nil
}

func (revision ObservedRevision) Validate() error {
	if revision.Sequence == 0 {
		return ErrInvalidObservedRevision
	}
	return nil
}

func NewFreshness(state FreshnessState, observedAt time.Time, sourceRevision SourceRevision, lastSyncAt, staleAfter *time.Time) (Freshness, error) {
	if sourceRevision.Validate() != nil {
		return Freshness{}, ErrInvalidFreshness
	}
	freshness := Freshness{
		State: state, ObservedAt: observedAt.Round(0).UTC(), SourceRevision: sourceRevision,
		LastSyncAt: cloneTimeUTC(lastSyncAt), StaleAfter: cloneTimeUTC(staleAfter),
	}
	if err := freshness.ValidateCanonical(); err != nil {
		return Freshness{}, err
	}
	freshness.SourceRevision = cloneSourceRevision(sourceRevision)
	return freshness, nil
}

func (freshness Freshness) ValidateCanonical() error {
	if !freshness.State.valid() || !validUTCTimestamp(freshness.ObservedAt) || freshness.SourceRevision.Validate() != nil {
		return ErrInvalidFreshness
	}
	if freshness.LastSyncAt != nil && !validUTCTimestamp(*freshness.LastSyncAt) {
		return ErrInvalidFreshness
	}
	if freshness.StaleAfter != nil && (!validUTCTimestamp(*freshness.StaleAfter) || freshness.StaleAfter.Before(freshness.ObservedAt)) {
		return ErrInvalidFreshness
	}
	return nil
}

func NewCanonicalEntrySnapshot(
	ref EntryRef,
	displayName string,
	parentRef *EntryRef,
	properties []PropertyValue,
	sourceRevision SourceRevision,
	observedRevision ObservedRevision,
	observedAt time.Time,
	modifiedAt *time.Time,
	availability Availability,
	freshness Freshness,
) (EntrySnapshot, error) {
	snapshot := EntrySnapshot{
		EntryRef: ref, DisplayName: displayName, ParentRef: parentRef, CanonicalProperties: properties,
		SourceRevision: sourceRevision, ObservedRevision: observedRevision, ObservedAt: observedAt.Round(0).UTC(),
		CanonicalModifiedAt: cloneTimeUTC(modifiedAt), Availability: availability, Freshness: freshness,
	}
	if err := snapshot.ValidateCanonical(); err != nil {
		return EntrySnapshot{}, err
	}
	return cloneSnapshot(snapshot), nil
}

func (snapshot EntrySnapshot) ValidateCanonical() error {
	if snapshot.Name != "" || snapshot.ResourceType != "" || snapshot.SizeBytes != nil || snapshot.ModifiedAt != nil ||
		snapshot.Properties != nil || snapshot.Revision.Strength != "" || snapshot.Revision.Token != nil || snapshot.OperationState.State != "" {
		return ErrInvalidEntrySnapshot
	}
	if snapshot.EntryRef.Validate() != nil || !validUTF8Bytes(snapshot.DisplayName, 1, 1024) || snapshot.CanonicalProperties == nil || len(snapshot.CanonicalProperties) > 256 ||
		snapshot.SourceRevision.Validate() != nil || snapshot.ObservedRevision.Validate() != nil || !validUTCTimestamp(snapshot.ObservedAt) ||
		snapshot.Availability.ValidateCanonical() != nil || snapshot.Freshness.ValidateCanonical() != nil ||
		snapshot.Freshness.ObservedAt != snapshot.ObservedAt || snapshot.Freshness.SourceRevision.Revision.Strength != snapshot.SourceRevision.Revision.Strength ||
		!equalOptionalString(snapshot.Freshness.SourceRevision.Revision.Token, snapshot.SourceRevision.Revision.Token) {
		return ErrInvalidEntrySnapshot
	}
	if snapshot.CanonicalModifiedAt != nil && !validUTCTimestamp(*snapshot.CanonicalModifiedAt) {
		return ErrInvalidEntrySnapshot
	}
	if snapshot.ParentRef != nil {
		if snapshot.ParentRef.Validate() != nil || snapshot.ParentRef.SourceInstanceID != snapshot.EntryRef.SourceInstanceID {
			return ErrInvalidEntrySnapshot
		}
	}
	seen := make(map[PropertyID]struct{}, len(snapshot.CanonicalProperties))
	propertyBudget := 0
	for _, property := range snapshot.CanonicalProperties {
		valueBudget, ok := canonicalPropertyValueBudget(property)
		if !ok || !addWithin(&propertyBudget, valueBudget, maximumSnapshotPropertyBudget) {
			return ErrInvalidEntrySnapshot
		}
		if property.EntryID != snapshot.EntryRef.EntryID || property.Validate() != nil {
			return ErrInvalidEntrySnapshot
		}
		if _, exists := seen[property.PropertyID]; exists {
			return ErrInvalidEntrySnapshot
		}
		seen[property.PropertyID] = struct{}{}
	}
	switch snapshot.Availability.State {
	case AvailabilityStateAvailable, AvailabilityStateReadOnly:
		if snapshot.Freshness.State == FreshnessStateStale {
			return ErrInvalidEntrySnapshot
		}
	case AvailabilityStateStale:
		if snapshot.Freshness.State != FreshnessStateStale {
			return ErrInvalidEntrySnapshot
		}
	default:
		return ErrInvalidEntrySnapshot
	}
	return nil
}

func validASCIIBytes(value string, minimum, maximum int) bool {
	if len(value) < minimum || len(value) > maximum {
		return false
	}
	for index := range len(value) {
		if value[index] > 0x7f {
			return false
		}
	}
	return true
}

func validPositiveDecimal(value string) bool {
	if value == "" || len(value) > 20 || value[0] == '0' {
		return false
	}
	for index := range len(value) {
		if value[index] < '0' || value[index] > '9' {
			return false
		}
	}
	_, err := strconv.ParseUint(value, 10, 64)
	return err == nil
}

func validUTCTimestamp(value time.Time) bool {
	return validTimestamp(value) && value.Location() == time.UTC
}

func cloneTimeUTC(value *time.Time) *time.Time {
	if value == nil {
		return nil
	}
	copied := value.Round(0).UTC()
	return &copied
}

func cloneFreshness(value Freshness) Freshness {
	return Freshness{
		State:          value.State,
		ObservedAt:     value.ObservedAt,
		SourceRevision: cloneSourceRevision(value.SourceRevision),
		LastSyncAt:     cloneTimeUTC(value.LastSyncAt),
		StaleAfter:     cloneTimeUTC(value.StaleAfter),
	}
}

func cloneSourceRevision(value SourceRevision) SourceRevision {
	return SourceRevision{Revision: cloneRevision(value.Revision)}
}

func cloneEntryRef(value *EntryRef) *EntryRef {
	if value == nil {
		return nil
	}
	copied := *value
	return &copied
}

func cloneCanonicalPropertyValues(values []PropertyValue) []PropertyValue {
	if values == nil {
		return nil
	}
	cloned := make([]PropertyValue, len(values))
	for index, value := range values {
		cloned[index] = clonePropertyValue(value)
	}
	return cloned
}

func (value PropertyValue) hasCanonicalFields() bool {
	return value.PropertyID != (PropertyID{}) || value.EntryID != "" || value.Payload.payloadCount() != 0 || value.State != "" ||
		value.Provenance != "" || !value.ObservedAt.IsZero() || value.SourceRevision.Revision.Strength != "" ||
		value.SourceRevision.Revision.Token != nil || value.Editable || value.Validation != (ValidationResult{}) || value.Cardinality != ""
}

func (snapshot EntrySnapshot) hasCanonicalFields() bool {
	return snapshot.EntryRef.EntryID != "" || snapshot.EntryRef.SourceInstanceID != "" || snapshot.EntryRef.SourceObjectKey != "" ||
		snapshot.EntryRef.ResourceType != "" || snapshot.EntryRef.CanonicalLocator.String() != "" || snapshot.EntryRef.IdentityStrength != "" ||
		snapshot.DisplayName != "" || snapshot.ParentRef != nil || snapshot.CanonicalProperties != nil ||
		snapshot.SourceRevision.Revision.Strength != "" || snapshot.SourceRevision.Revision.Token != nil ||
		snapshot.ObservedRevision.Sequence != 0 || !snapshot.ObservedAt.IsZero() || snapshot.CanonicalModifiedAt != nil
}

const (
	maximumSnapshotPropertyBudget = 5 * 1024 * 1024
	maximumEntryListBudget        = 16 * 1024 * 1024
)

func legacyPropertyBudget(property Property) (int, bool) {
	budget := len(property.Key)
	switch property.Value.Type {
	case PropertyValueTypeString:
		if property.Value.StringValue != nil && !addWithin(&budget, len(*property.Value.StringValue), maximumSnapshotPropertyBudget) {
			return 0, false
		}
	case PropertyValueTypeTimestamp, PropertyValueTypeInt64, PropertyValueTypeBool:
		if !addWithin(&budget, 32, maximumSnapshotPropertyBudget) {
			return 0, false
		}
	case PropertyValueTypeStringList:
		if property.Value.StringListValue != nil {
			if len(*property.Value.StringListValue) > 256 {
				return 0, false
			}
			for _, item := range *property.Value.StringListValue {
				if !addWithin(&budget, len(item), maximumSnapshotPropertyBudget) {
					return 0, false
				}
			}
		}
	}
	return budget, true
}

func canonicalPropertyValueBudget(value PropertyValue) (int, bool) {
	budget := 0
	for _, length := range []int{
		len(value.PropertyID.String()), len(value.EntryID), len(value.Type), len(value.State), len(value.Provenance), len(value.Cardinality),
		len(value.Validation.ReasonCode), len(value.Validation.Message), len(value.Validation.RuleKind),
	} {
		if !addWithin(&budget, length, maximumSnapshotPropertyBudget) {
			return 0, false
		}
	}
	if value.SourceRevision.Revision.Token != nil && !addWithin(&budget, len(*value.SourceRevision.Revision.Token), maximumSnapshotPropertyBudget) {
		return 0, false
	}
	if value.Payload.payloadCount() > 1 || payloadItemCount(value.Payload) > maximumPropertyItems {
		return 0, false
	}
	for _, scalar := range []*string{value.Payload.Text, value.Payload.Number, value.Payload.Date, value.Payload.DateTime, value.Payload.Select} {
		if scalar != nil && !addWithin(&budget, len(*scalar), maximumSnapshotPropertyBudget) {
			return 0, false
		}
	}
	for _, list := range []*[]string{value.Payload.TextMany, value.Payload.NumberMany, value.Payload.DateMany, value.Payload.DateTimeMany, value.Payload.SelectMany} {
		if list == nil {
			continue
		}
		for _, item := range *list {
			if !addWithin(&budget, len(item), maximumSnapshotPropertyBudget) {
				return 0, false
			}
		}
	}
	if value.Payload.Boolean != nil && !addWithin(&budget, 1, maximumSnapshotPropertyBudget) {
		return 0, false
	}
	if value.Payload.BooleanMany != nil && !addWithin(&budget, len(*value.Payload.BooleanMany), maximumSnapshotPropertyBudget) {
		return 0, false
	}
	return budget, true
}

func entryRefBudget(value EntryRef, maximum int) (int, bool) {
	budget := 0
	for _, length := range []int{len(value.EntryID), len(value.SourceInstanceID), len(value.SourceObjectKey), len(value.ResourceType), len(value.CanonicalLocator.String()), len(value.IdentityStrength)} {
		if !addWithin(&budget, length, maximum) {
			return 0, false
		}
	}
	return budget, true
}

func freshnessBudget(value Freshness, maximum int) (int, bool) {
	budget := len(value.State) + 64
	if budget > maximum {
		return 0, false
	}
	if value.SourceRevision.Revision.Token != nil && !addWithin(&budget, len(*value.SourceRevision.Revision.Token), maximum) {
		return 0, false
	}
	return budget, true
}

func snapshotBudget(snapshot EntrySnapshot, maximum int) (int, bool) {
	if len(snapshot.Properties) > 256 || len(snapshot.CanonicalProperties) > 256 {
		return 0, false
	}
	budget := 0
	for _, length := range []int{len(snapshot.Name), len(snapshot.ResourceType), len(snapshot.DisplayName), 256} {
		if !addWithin(&budget, length, maximum) {
			return 0, false
		}
	}
	refBudget, ok := entryRefBudget(snapshot.EntryRef, maximum-budget)
	if !ok || !addWithin(&budget, refBudget, maximum) {
		return 0, false
	}
	freshBudget, ok := freshnessBudget(snapshot.Freshness, maximum-budget)
	if !ok || !addWithin(&budget, freshBudget, maximum) {
		return 0, false
	}
	if snapshot.ParentRef != nil {
		parentBudget, valid := entryRefBudget(*snapshot.ParentRef, maximum-budget)
		if !valid || !addWithin(&budget, parentBudget, maximum) {
			return 0, false
		}
	}
	if snapshot.SourceRevision.Revision.Token != nil && !addWithin(&budget, len(*snapshot.SourceRevision.Revision.Token), maximum) {
		return 0, false
	}
	if snapshot.Revision.Token != nil && !addWithin(&budget, len(*snapshot.Revision.Token), maximum) {
		return 0, false
	}
	for _, property := range snapshot.Properties {
		propertyBudget, valid := legacyPropertyBudget(property)
		if !valid || !addWithin(&budget, propertyBudget, maximum) {
			return 0, false
		}
	}
	for _, property := range snapshot.CanonicalProperties {
		propertyBudget, valid := canonicalPropertyValueBudget(property)
		if !valid || !addWithin(&budget, propertyBudget, maximum) {
			return 0, false
		}
	}
	return budget, true
}

func accessContextBudget(value AccessContext, maximum int) (int, bool) {
	budget := 0
	for _, length := range []int{len(value.SourceID), len(value.MountID), len(value.VirtualPath.String()), len(value.VirtualPath.MountID()), len(value.VirtualPath.ParentPath()), len(value.VirtualPath.PathRevision())} {
		if !addWithin(&budget, length, maximum) {
			return 0, false
		}
	}
	if value.DisplayPath != nil && !addWithin(&budget, len(*value.DisplayPath), maximum) {
		return 0, false
	}
	return budget, true
}

func entryBudget(value Entry) (int, bool) {
	budget := 0
	for _, length := range []int{len(value.Identity.SourceID), len(value.Identity.EntryKey)} {
		if !addWithin(&budget, length, maximumEntryListBudget) {
			return 0, false
		}
	}
	accessBudget, ok := accessContextBudget(value.AccessContext, maximumEntryListBudget-budget)
	if !ok || !addWithin(&budget, accessBudget, maximumEntryListBudget) {
		return 0, false
	}
	snapshotSize, ok := snapshotBudget(value.Snapshot, maximumEntryListBudget-budget)
	if !ok || !addWithin(&budget, snapshotSize, maximumEntryListBudget) {
		return 0, false
	}
	return budget, true
}

func equalOptionalString(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}
