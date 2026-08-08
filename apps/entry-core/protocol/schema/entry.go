package schema

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	applicationentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/entry"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

const (
	maximumVirtualPathBytes = 4096
	maximumPageTokenBytes   = 4096
	maximumRequestedProps   = 256
)

type EntryListParams struct {
	MountID             *string
	SourceInstanceID    *string
	VirtualPath         string
	ParentRef           *EntryRef
	PageSize            int
	PageToken           *string
	RequestedProperties []string
}

type EntryResolveParams struct {
	EntryRef            *EntryRef
	VirtualPath         *string
	MountID             *string
	RequestedProperties []string
}

func DecodeRequest(wire []byte) (Request, string, *ProtocolError) {
	if len(wire) > MaxWireBytes {
		return Request{}, "", newProtocolError(ErrorRequestTooLarge)
	}
	root, err := parseJSON(wire)
	if err != nil || root.kind != jsonObject {
		return Request{}, "", newProtocolError(ErrorInvalidRequest)
	}
	trustworthyID := extractTrustworthyID(root)
	fields, ok := objectFields(root, "request_id", "method", "params")
	if !ok || !validRequestID(fields["request_id"]) || fields["method"].kind != jsonString || fields["params"].kind != jsonObject {
		return Request{}, trustworthyID, newProtocolError(ErrorInvalidRequest)
	}
	method := Method(fields["method"].text)
	request := Request{RequestID: trustworthyID, Method: method, Params: EmptyParams{}}
	if !method.valid() {
		return request, trustworthyID, newProtocolError(ErrorUnknownMethod)
	}
	switch method {
	case MethodEntryList:
		params, code := decodeEntryListParams(fields["params"])
		if code != "" {
			return request, trustworthyID, newProtocolError(code)
		}
		request.EntryListParams = &params
	case MethodEntryResolve:
		params, code := decodeEntryResolveParams(fields["params"])
		if code != "" {
			return request, trustworthyID, newProtocolError(code)
		}
		request.EntryResolveParams = &params
	default:
		if !validEmptyParams(fields["params"]) {
			return request, trustworthyID, newProtocolError(ErrorInvalidRequest)
		}
	}
	return request, trustworthyID, nil
}

func decodeEntryListParams(value jsonValue) (EntryListParams, ErrorCode) {
	fields, ok := objectFieldsWithOptional(value, []string{"page_size", "requested_properties"}, []string{"mount_id", "source_instance_id", "virtual_path", "parent_ref", "page_token"})
	if !ok {
		return EntryListParams{}, ErrorInvalidRequest
	}
	pageSize, integer := lexicalInteger(fields["page_size"])
	if !integer || pageSize < 1 || pageSize > 256 {
		return EntryListParams{}, ErrorInvalidRequest
	}
	properties, ok := decodeRequestedProperties(fields["requested_properties"])
	if !ok {
		return EntryListParams{}, ErrorInvalidRequest
	}
	params := EntryListParams{PageSize: int(pageSize), RequestedProperties: properties}
	if field, exists := fields["mount_id"]; exists {
		if field.kind != jsonString || !validUTF8Bytes(field.text, 1, 64) {
			return EntryListParams{}, ErrorInvalidRequest
		}
		params.MountID = stringPointer(field.text)
	}
	if field, exists := fields["source_instance_id"]; exists {
		if field.kind != jsonString || !validSourceInstanceID(field.text) {
			return EntryListParams{}, ErrorInvalidRequest
		}
		params.SourceInstanceID = stringPointer(field.text)
	}
	if params.MountID != nil && params.SourceInstanceID != nil {
		return EntryListParams{}, ErrorInvalidSelector
	}
	if field, exists := fields["virtual_path"]; exists {
		if field.kind != jsonString || !validUTF8Bytes(field.text, 1, maximumVirtualPathBytes) {
			return EntryListParams{}, ErrorInvalidRequest
		}
		params.VirtualPath = field.text
	}
	if field, exists := fields["parent_ref"]; exists {
		ref, valid := decodeEntryRef(field)
		if !valid {
			return EntryListParams{}, ErrorInvalidRequest
		}
		params.ParentRef = &ref
	}
	if (params.VirtualPath == "") == (params.ParentRef == nil) {
		return EntryListParams{}, ErrorInvalidSelector
	}
	if field, exists := fields["page_token"]; exists {
		if field.kind != jsonString || !validOpaqueASCII(field.text, 1, maximumPageTokenBytes) {
			return EntryListParams{}, ErrorInvalidRequest
		}
		params.PageToken = stringPointer(field.text)
	}
	return params, ""
}

func decodeEntryResolveParams(value jsonValue) (EntryResolveParams, ErrorCode) {
	fields, ok := objectFieldsWithOptional(value, []string{"requested_properties"}, []string{"entry_ref", "virtual_path", "mount_id"})
	if !ok {
		return EntryResolveParams{}, ErrorInvalidRequest
	}
	properties, ok := decodeRequestedProperties(fields["requested_properties"])
	if !ok {
		return EntryResolveParams{}, ErrorInvalidRequest
	}
	params := EntryResolveParams{RequestedProperties: properties}
	if field, exists := fields["entry_ref"]; exists {
		ref, valid := decodeEntryRef(field)
		if !valid {
			return EntryResolveParams{}, ErrorInvalidRequest
		}
		params.EntryRef = &ref
	}
	if field, exists := fields["virtual_path"]; exists {
		if field.kind != jsonString || !validUTF8Bytes(field.text, 1, maximumVirtualPathBytes) {
			return EntryResolveParams{}, ErrorInvalidRequest
		}
		params.VirtualPath = stringPointer(field.text)
	}
	if field, exists := fields["mount_id"]; exists {
		if field.kind != jsonString || !validUTF8Bytes(field.text, 1, 64) {
			return EntryResolveParams{}, ErrorInvalidRequest
		}
		params.MountID = stringPointer(field.text)
	}
	if (params.EntryRef == nil) == (params.VirtualPath == nil) || (params.EntryRef != nil && params.MountID == nil) || (params.VirtualPath != nil && params.MountID != nil) {
		return EntryResolveParams{}, ErrorInvalidSelector
	}
	return params, ""
}

func decodeRequestedProperties(value jsonValue) ([]string, bool) {
	if value.kind != jsonArray || len(value.items) > maximumRequestedProps {
		return nil, false
	}
	result := make([]string, len(value.items))
	seen := make(map[string]struct{}, len(result))
	for index, item := range value.items {
		if item.kind != jsonString || !validUTF8Bytes(item.text, 1, 128) {
			return nil, false
		}
		if _, exists := seen[item.text]; exists || index > 0 && result[index-1] >= item.text {
			return nil, false
		}
		seen[item.text], result[index] = struct{}{}, item.text
	}
	return result, true
}

type EntryRef struct {
	EntryID          string `json:"entry_id"`
	SourceInstanceID string `json:"source_instance_id"`
	SourceObjectKey  string `json:"source_object_key"`
	ResourceType     string `json:"resource_type"`
	CanonicalLocator string `json:"canonical_locator"`
	IdentityStrength string `json:"identity_strength"`
}

type Revision struct {
	Strength string  `json:"strength"`
	Token    *string `json:"token,omitempty"`
}
type Availability struct {
	State string `json:"state"`
}
type Freshness struct {
	State          string   `json:"state"`
	ObservedAt     string   `json:"observed_at"`
	SourceRevision Revision `json:"source_revision"`
	LastSyncAt     *string  `json:"last_sync_at,omitempty"`
	StaleAfter     *string  `json:"stale_after,omitempty"`
}
type Capabilities struct {
	Readable         bool `json:"readable"`
	Writable         bool `json:"writable"`
	Searchable       bool `json:"searchable"`
	Commentable      bool `json:"commentable"`
	Movable          bool `json:"movable"`
	Copyable         bool `json:"copyable"`
	Deletable        bool `json:"deletable"`
	Watchable        bool `json:"watchable"`
	Streamable       bool `json:"streamable"`
	RequiresApproval bool `json:"requires_approval"`
}
type AccessContext struct {
	SourceInstanceID string       `json:"source_instance_id"`
	MountID          string       `json:"mount_id"`
	VirtualPath      string       `json:"virtual_path"`
	DisplayPath      *string      `json:"display_path,omitempty"`
	Capabilities     Capabilities `json:"capabilities"`
}
type ValidationResult struct {
	Valid      bool    `json:"valid"`
	ReasonCode *string `json:"reason_code,omitempty"`
	Message    *string `json:"message,omitempty"`
	RuleKind   *string `json:"rule_kind,omitempty"`
}
type PropertyDefinitionReference struct {
	PropertyID string `json:"property_id"`
}

type PropertyPayload struct {
	kind string
	one  any
	many any
}

func (payload PropertyPayload) MarshalJSON() ([]byte, error) {
	if payload.one != nil {
		return json.Marshal(payload.one)
	}
	if payload.many != nil {
		return json.Marshal(payload.many)
	}
	return nil, errors.New("invalid property payload")
}

type PropertyValue struct {
	PropertyID     string           `json:"property_id"`
	EntryID        string           `json:"entry_id"`
	ValueType      string           `json:"value_type"`
	Value          *PropertyPayload `json:"value,omitempty"`
	State          string           `json:"state"`
	Provenance     string           `json:"provenance"`
	ObservedAt     string           `json:"observed_at"`
	SourceRevision Revision         `json:"source_revision"`
	Editable       bool             `json:"editable"`
	Validation     ValidationResult `json:"validation"`
	Cardinality    string           `json:"cardinality"`
}
type EntrySnapshot struct {
	EntryRef         EntryRef        `json:"entry_ref"`
	DisplayName      string          `json:"display_name"`
	ParentRef        *EntryRef       `json:"parent_ref,omitempty"`
	Properties       []PropertyValue `json:"properties"`
	SourceRevision   Revision        `json:"source_revision"`
	ObservedRevision Revision        `json:"observed_revision"`
	ObservedAt       string          `json:"observed_at"`
	ModifiedAt       *string         `json:"modified_at,omitempty"`
	Availability     Availability    `json:"availability"`
	Freshness        Freshness       `json:"freshness"`
}
type Entry struct {
	EntryRef      EntryRef            `json:"entry_ref"`
	EntrySnapshot EntrySnapshot       `json:"entry_snapshot"`
	AccessContext AccessContext       `json:"access_context"`
	Identity      EntryIdentity       `json:"-"`
	Snapshot      LegacyEntrySnapshot `json:"-"`
}
type EntryIdentity struct {
	SourceID         string
	EntryKey         string
	IdentityStrength string
}
type LegacyEntrySnapshot struct{ Properties []Property }
type Property struct {
	Key   string
	Value LegacyPropertyValue
}
type LegacyPropertyValue struct {
	Type            string
	StringValue     *string
	Int64Value      *int64
	BoolValue       *bool
	TimestampValue  *string
	StringListValue *[]string
}

type RevisionSummary struct {
	SourceInstanceID string   `json:"source_instance_id"`
	MountID          string   `json:"mount_id"`
	SourceRevision   Revision `json:"source_revision"`
	ObservedRevision Revision `json:"observed_revision"`
}
type SourceError struct {
	SourceInstanceID string `json:"source_instance_id"`
	MountID          string `json:"mount_id"`
	Code             string `json:"code"`
	Message          string `json:"message"`
	Retryable        bool   `json:"retryable"`
}
type SourceAvailability struct {
	SourceInstanceID string       `json:"source_instance_id"`
	MountID          string       `json:"mount_id"`
	State            string       `json:"state"`
	Error            *SourceError `json:"error,omitempty"`
}
type SourceFreshness struct {
	SourceInstanceID string   `json:"source_instance_id"`
	MountID          string   `json:"mount_id"`
	State            string   `json:"state"`
	ObservedAt       string   `json:"observed_at"`
	SourceRevision   Revision `json:"source_revision"`
	LastSyncAt       *string  `json:"last_sync_at,omitempty"`
	StaleAfter       *string  `json:"stale_after,omitempty"`
}
type Warning struct {
	SourceInstanceID string `json:"source_instance_id"`
	MountID          string `json:"mount_id"`
	Code             string `json:"code"`
	Message          string `json:"message"`
	Retryable        bool   `json:"retryable"`
}

type EntryListResult struct {
	Entries        []Entry              `json:"entries"`
	NextPageToken  *string              `json:"next_page_token,omitempty"`
	HasMore        bool                 `json:"has_more"`
	ObservedAt     string               `json:"observed_at"`
	SourceRevision []RevisionSummary    `json:"source_revision"`
	Availability   []SourceAvailability `json:"availability"`
	Freshness      []SourceFreshness    `json:"freshness"`
	Warnings       []Warning            `json:"warnings"`
}

func (EntryListResult) isResult() {}

type EntryResolveResult struct {
	EntryRef       EntryRef      `json:"entry_ref"`
	EntrySnapshot  EntrySnapshot `json:"entry_snapshot"`
	AccessContext  AccessContext `json:"access_context"`
	Capabilities   Capabilities  `json:"capabilities"`
	Availability   Availability  `json:"availability"`
	Freshness      Freshness     `json:"freshness"`
	SourceRevision Revision      `json:"source_revision"`
}

func (EntryResolveResult) isResult() {}

func EntryListResultFromApplication(result applicationentry.UnifiedListResult) (EntryListResult, error) {
	wire := EntryListResult{Entries: make([]Entry, len(result.Entries)), NextPageToken: cloneWireString(result.NextPageToken), HasMore: result.NextPageToken != nil, ObservedAt: formatTime(result.ObservedAt), SourceRevision: make([]RevisionSummary, len(result.RevisionSummaries)), Availability: make([]SourceAvailability, len(result.Availabilities)), Freshness: make([]SourceFreshness, len(result.Freshness)), Warnings: make([]Warning, len(result.Warnings))}
	for index, item := range result.Entries {
		mapped, err := entryFromApplication(item)
		if err != nil {
			return EntryListResult{}, err
		}
		wire.Entries[index] = mapped
	}
	for index, value := range result.RevisionSummaries {
		wire.SourceRevision[index] = RevisionSummary{SourceInstanceID: value.SourceInstanceID, MountID: value.MountID, SourceRevision: revisionFromDomain(value.SourceRevision), ObservedRevision: Revision{Strength: "observed", Token: stringPointer(strconv.FormatUint(value.ObservedRevision.Sequence, 10))}}
	}
	for index, value := range result.Availabilities {
		mapped := SourceAvailability{SourceInstanceID: value.SourceInstanceID, MountID: value.MountID, State: string(value.State)}
		if value.Error != nil {
			mapped.Error = &SourceError{SourceInstanceID: value.Error.SourceInstanceID, MountID: value.Error.MountID, Code: string(value.Error.Code), Message: value.Error.Message, Retryable: value.Error.Retryable}
		}
		wire.Availability[index] = mapped
	}
	for index, value := range result.Freshness {
		wire.Freshness[index] = SourceFreshness{SourceInstanceID: value.SourceInstanceID, MountID: value.MountID, State: string(value.State), ObservedAt: formatTime(value.ObservedAt), SourceRevision: revisionFromDomain(value.SourceRevision), LastSyncAt: formatOptionalTime(value.LastSyncAt), StaleAfter: formatOptionalTime(value.StaleAfter)}
	}
	for index, value := range result.Warnings {
		wire.Warnings[index] = Warning{SourceInstanceID: value.SourceInstanceID, MountID: value.MountID, Code: string(value.Code), Message: value.Message, Retryable: value.Retryable}
	}
	if err := wire.Validate(); err != nil {
		return EntryListResult{}, err
	}
	return wire, nil
}

func EntryResolveResultFromApplication(result applicationentry.ResolveResult) (EntryResolveResult, error) {
	entry, err := entryFromApplication(applicationentry.CanonicalEntry{EntryRef: result.EntryRef, EntrySnapshot: result.EntrySnapshot, AccessContext: result.AccessContext})
	if err != nil {
		return EntryResolveResult{}, err
	}
	wire := EntryResolveResult{EntryRef: entry.EntryRef, EntrySnapshot: entry.EntrySnapshot, AccessContext: entry.AccessContext, Capabilities: capabilitiesFromDomain(result.Capabilities), Availability: Availability{State: string(result.Availability.State)}, Freshness: freshnessFromDomain(result.Freshness), SourceRevision: revisionFromDomain(result.SourceRevision)}
	if err := wire.Validate(); err != nil {
		return EntryResolveResult{}, err
	}
	return wire, nil
}

func entryFromApplication(value applicationentry.CanonicalEntry) (Entry, error) {
	if value.EntryRef.Validate() != nil || value.EntrySnapshot.ValidateCanonical() != nil || value.AccessContext.ValidateCanonical() != nil || value.EntrySnapshot.EntryRef != value.EntryRef || value.AccessContext.SourceID != value.EntryRef.SourceInstanceID {
		return Entry{}, domainentry.ErrInvalidEntry
	}
	ref := entryRefFromDomain(value.EntryRef)
	snapshot, err := snapshotFromDomain(value.EntrySnapshot)
	if err != nil {
		return Entry{}, err
	}
	access := accessContextFromDomain(value.AccessContext)
	return Entry{EntryRef: ref, EntrySnapshot: snapshot, AccessContext: access, Identity: EntryIdentity{SourceID: ref.SourceInstanceID, EntryKey: ref.SourceObjectKey, IdentityStrength: ref.IdentityStrength}}, nil
}
func (ref EntryRef) Domain() (domainentry.EntryRef, error) {
	locator, err := domainentry.NewLocatorRef(ref.CanonicalLocator)
	if err != nil {
		return domainentry.EntryRef{}, err
	}
	return domainentry.NewEntryRef(ref.EntryID, ref.SourceInstanceID, ref.SourceObjectKey, ref.ResourceType, locator, domainentry.IdentityStrength(ref.IdentityStrength))
}

func entryRefFromDomain(value domainentry.EntryRef) EntryRef {
	return EntryRef{EntryID: value.EntryID, SourceInstanceID: value.SourceInstanceID, SourceObjectKey: value.SourceObjectKey, ResourceType: value.ResourceType, CanonicalLocator: value.CanonicalLocator.String(), IdentityStrength: string(value.IdentityStrength)}
}
func snapshotFromDomain(value domainentry.EntrySnapshot) (EntrySnapshot, error) {
	properties := make([]PropertyValue, len(value.CanonicalProperties))
	for i, p := range value.CanonicalProperties {
		mapped, err := propertyValueFromDomain(p)
		if err != nil {
			return EntrySnapshot{}, err
		}
		properties[i] = mapped
	}
	var parent *EntryRef
	if value.ParentRef != nil {
		mapped := entryRefFromDomain(*value.ParentRef)
		parent = &mapped
	}
	return EntrySnapshot{EntryRef: entryRefFromDomain(value.EntryRef), DisplayName: value.DisplayName, ParentRef: parent, Properties: properties, SourceRevision: revisionFromDomain(value.SourceRevision.Revision), ObservedRevision: Revision{Strength: "observed", Token: stringPointer(strconv.FormatUint(value.ObservedRevision.Sequence, 10))}, ObservedAt: formatTime(value.ObservedAt), ModifiedAt: formatOptionalTime(value.CanonicalModifiedAt), Availability: Availability{State: string(value.Availability.State)}, Freshness: freshnessFromDomain(value.Freshness)}, nil
}
func propertyValueFromDomain(value domainentry.PropertyValue) (PropertyValue, error) {
	if value.Validate() != nil {
		return PropertyValue{}, domainentry.ErrInvalidPropertyValue
	}
	var payload *PropertyPayload
	if value.State == domainentry.PropertyStateValue {
		p := PropertyPayload{kind: string(value.Type)}
		switch value.Type {
		case domainentry.PropertyTypeText:
			if value.Cardinality == domainentry.PropertyCardinalityOne {
				p.one = *value.Payload.Text
			} else {
				p.many = *value.Payload.TextMany
			}
		case domainentry.PropertyTypeNumber:
			if value.Cardinality == domainentry.PropertyCardinalityOne {
				p.one = *value.Payload.Number
			} else {
				p.many = *value.Payload.NumberMany
			}
		case domainentry.PropertyTypeDate:
			if value.Cardinality == domainentry.PropertyCardinalityOne {
				p.one = *value.Payload.Date
			} else {
				p.many = *value.Payload.DateMany
			}
		case domainentry.PropertyTypeDateTime:
			if value.Cardinality == domainentry.PropertyCardinalityOne {
				p.one = *value.Payload.DateTime
			} else {
				p.many = *value.Payload.DateTimeMany
			}
		case domainentry.PropertyTypeBoolean:
			if value.Cardinality == domainentry.PropertyCardinalityOne {
				p.one = *value.Payload.Boolean
			} else {
				p.many = *value.Payload.BooleanMany
			}
		case domainentry.PropertyTypeSelect:
			if value.Cardinality == domainentry.PropertyCardinalityOne {
				p.one = *value.Payload.Select
			} else {
				p.many = *value.Payload.SelectMany
			}
		default:
			return PropertyValue{}, domainentry.ErrInvalidPropertyValue
		}
		payload = &p
	}
	validation := ValidationResult{Valid: value.Validation.Valid}
	if !value.Validation.Valid {
		r, m := string(value.Validation.ReasonCode), value.Validation.Message
		validation.ReasonCode = &r
		validation.Message = &m
		if value.Validation.RuleKind != "" {
			k := string(value.Validation.RuleKind)
			validation.RuleKind = &k
		}
	}
	return PropertyValue{PropertyID: value.PropertyID, EntryID: value.EntryID, ValueType: string(value.Type), Value: payload, State: string(value.State), Provenance: string(value.Provenance), ObservedAt: formatTime(value.ObservedAt), SourceRevision: revisionFromDomain(value.SourceRevision.Revision), Editable: value.Editable, Validation: validation, Cardinality: string(value.Cardinality)}, nil
}
func revisionFromDomain(v domainentry.Revision) Revision {
	return Revision{Strength: string(v.Strength), Token: cloneWireString(v.Token)}
}
func freshnessFromDomain(v domainentry.Freshness) Freshness {
	return Freshness{State: string(v.State), ObservedAt: formatTime(v.ObservedAt), SourceRevision: revisionFromDomain(v.SourceRevision.Revision), LastSyncAt: formatOptionalTime(v.LastSyncAt), StaleAfter: formatOptionalTime(v.StaleAfter)}
}
func capabilitiesFromDomain(v domainentry.Capabilities) Capabilities {
	return Capabilities{v.Readable, v.Writable, v.Searchable, v.Commentable, v.Movable, v.Copyable, v.Deletable, v.Watchable, v.Streamable, v.RequiresApproval}
}
func accessContextFromDomain(v domainentry.AccessContext) AccessContext {
	return AccessContext{SourceInstanceID: v.SourceID, MountID: v.MountID, VirtualPath: v.VirtualPath.String(), DisplayPath: cloneWireString(v.DisplayPath), Capabilities: capabilitiesFromDomain(v.Capabilities)}
}

func (result EntryListResult) Validate() error {
	if result.Entries == nil || len(result.Entries) > 256 || len(result.SourceRevision) < 1 || len(result.SourceRevision) > 8 || result.Availability == nil || result.Freshness == nil || result.Warnings == nil || len(result.Warnings) > 64 || !validOptionalOpaque(result.NextPageToken) || result.HasMore != (result.NextPageToken != nil) || !canonicalTimestamp(result.ObservedAt) || len(result.SourceRevision) != len(result.Availability) || len(result.SourceRevision) != len(result.Freshness) {
		return ErrInvalidResponse
	}
	scopes := make(map[string]struct{}, len(result.SourceRevision))
	for i := range result.SourceRevision {
		r, a, f := result.SourceRevision[i], result.Availability[i], result.Freshness[i]
		scopeKey := r.SourceInstanceID + "\x00" + r.MountID
		if _, duplicate := scopes[scopeKey]; duplicate {
			return ErrInvalidResponse
		}
		scopes[scopeKey] = struct{}{}
		if !validSourceInstanceID(r.SourceInstanceID) || !validUTF8Bytes(r.MountID, 1, 64) || r.SourceInstanceID != a.SourceInstanceID || r.MountID != a.MountID || r.SourceInstanceID != f.SourceInstanceID || r.MountID != f.MountID || !validRevision(r.SourceRevision) || !validObservedRevision(r.ObservedRevision) || !validSourceAvailability(a) || !validSourceFreshness(f) || !equalRevision(r.SourceRevision, f.SourceRevision) {
			return ErrInvalidResponse
		}
	}
	for _, entry := range result.Entries {
		if !validEntry(entry) {
			return ErrInvalidResponse
		}
		matched := false
		for i, a := range result.Availability {
			if a.SourceInstanceID == entry.AccessContext.SourceInstanceID && a.MountID == entry.AccessContext.MountID {
				matched = true
				if entry.EntrySnapshot.Availability.State != a.State || !equalFreshnessEnvelope(entry.EntrySnapshot.Freshness, result.Freshness[i]) {
					return ErrInvalidResponse
				}
				break
			}
		}
		if !matched {
			return ErrInvalidResponse
		}
	}
	for _, warning := range result.Warnings {
		if !validWarning(warning) {
			return ErrInvalidResponse
		}
		if _, exists := scopes[warning.SourceInstanceID+"\x00"+warning.MountID]; !exists {
			return ErrInvalidResponse
		}
	}
	return nil
}
func (result EntryResolveResult) Validate() error {
	entry := Entry{EntryRef: result.EntryRef, EntrySnapshot: result.EntrySnapshot, AccessContext: result.AccessContext}
	if !validEntry(entry) || result.Capabilities != result.AccessContext.Capabilities || result.Availability != result.EntrySnapshot.Availability || !equalFreshnessWire(result.Freshness, result.EntrySnapshot.Freshness) || !equalRevision(result.SourceRevision, result.EntrySnapshot.SourceRevision) {
		return ErrInvalidResponse
	}
	return nil
}

func decodeEntryListResult(value jsonValue) (EntryListResult, bool) {
	fields, ok := objectFieldsWithOptional(value, []string{"entries", "has_more", "observed_at", "source_revision", "availability", "freshness", "warnings"}, []string{"next_page_token"})
	if !ok || fields["entries"].kind != jsonArray || fields["has_more"].kind != jsonBool || fields["observed_at"].kind != jsonString || fields["source_revision"].kind != jsonArray || fields["availability"].kind != jsonArray || fields["freshness"].kind != jsonArray || fields["warnings"].kind != jsonArray {
		return EntryListResult{}, false
	}
	entryCount := len(fields["entries"].items)
	revisionCount := len(fields["source_revision"].items)
	availabilityCount := len(fields["availability"].items)
	freshnessCount := len(fields["freshness"].items)
	warningCount := len(fields["warnings"].items)
	if len(fields["entries"].items) > 256 || revisionCount < 1 || revisionCount > 8 || availabilityCount < 1 || availabilityCount > 8 || freshnessCount < 1 || freshnessCount > 8 || revisionCount != availabilityCount || revisionCount != freshnessCount || warningCount > 64 {
		return EntryListResult{}, false
	}
	r := EntryListResult{Entries: make([]Entry, entryCount), HasMore: fields["has_more"].boolean, ObservedAt: fields["observed_at"].text, SourceRevision: make([]RevisionSummary, len(fields["source_revision"].items)), Availability: make([]SourceAvailability, len(fields["availability"].items)), Freshness: make([]SourceFreshness, len(fields["freshness"].items)), Warnings: make([]Warning, len(fields["warnings"].items))}
	if token, exists := fields["next_page_token"]; exists {
		if token.kind != jsonString || !validOpaqueASCII(token.text, 1, maximumPageTokenBytes) {
			return EntryListResult{}, false
		}
		r.NextPageToken = stringPointer(token.text)
	}
	for i, v := range fields["entries"].items {
		e, valid := decodeEntry(v)
		if !valid {
			return EntryListResult{}, false
		}
		r.Entries[i] = e
	}
	for i, v := range fields["source_revision"].items {
		x, valid := decodeRevisionSummary(v)
		if !valid {
			return EntryListResult{}, false
		}
		r.SourceRevision[i] = x
	}
	for i, v := range fields["availability"].items {
		x, valid := decodeSourceAvailability(v)
		if !valid {
			return EntryListResult{}, false
		}
		r.Availability[i] = x
	}
	for i, v := range fields["freshness"].items {
		x, valid := decodeSourceFreshness(v)
		if !valid {
			return EntryListResult{}, false
		}
		r.Freshness[i] = x
	}
	for i, v := range fields["warnings"].items {
		x, valid := decodeWarning(v)
		if !valid {
			return EntryListResult{}, false
		}
		r.Warnings[i] = x
	}
	return r, r.Validate() == nil
}
func decodeEntryResolveResult(value jsonValue) (EntryResolveResult, bool) {
	fields, ok := objectFields(value, "entry_ref", "entry_snapshot", "access_context", "capabilities", "availability", "freshness", "source_revision")
	if !ok {
		return EntryResolveResult{}, false
	}
	ref, a := decodeEntryRef(fields["entry_ref"])
	snapshot, b := decodeEntrySnapshot(fields["entry_snapshot"])
	access, c := decodeAccessContext(fields["access_context"])
	caps, d := decodeCapabilities(fields["capabilities"])
	availability, e := decodeAvailability(fields["availability"])
	freshness, f := decodeFreshness(fields["freshness"])
	revision, g := decodeRevision(fields["source_revision"])
	r := EntryResolveResult{ref, snapshot, access, caps, availability, freshness, revision}
	return r, a && b && c && d && e && f && g && r.Validate() == nil
}
func decodeEntry(value jsonValue) (Entry, bool) {
	fields, ok := objectFields(value, "entry_ref", "entry_snapshot", "access_context")
	if !ok {
		return Entry{}, false
	}
	ref, a := decodeEntryRef(fields["entry_ref"])
	snapshot, b := decodeEntrySnapshot(fields["entry_snapshot"])
	access, c := decodeAccessContext(fields["access_context"])
	e := Entry{EntryRef: ref, EntrySnapshot: snapshot, AccessContext: access}
	return e, a && b && c && validEntry(e)
}
func decodeEntryRef(value jsonValue) (EntryRef, bool) {
	f, ok := objectFields(value, "entry_id", "source_instance_id", "source_object_key", "resource_type", "canonical_locator", "identity_strength")
	if !ok || !allStrings(f, "entry_id", "source_instance_id", "source_object_key", "resource_type", "canonical_locator", "identity_strength") {
		return EntryRef{}, false
	}
	r := EntryRef{f["entry_id"].text, f["source_instance_id"].text, f["source_object_key"].text, f["resource_type"].text, f["canonical_locator"].text, f["identity_strength"].text}
	return r, validEntryRef(r)
}
func decodeEntrySnapshot(value jsonValue) (EntrySnapshot, bool) {
	f, ok := objectFieldsWithOptional(value, []string{"entry_ref", "display_name", "properties", "source_revision", "observed_revision", "observed_at", "availability", "freshness"}, []string{"parent_ref", "modified_at"})
	if !ok || f["display_name"].kind != jsonString || f["properties"].kind != jsonArray || f["observed_at"].kind != jsonString || len(f["properties"].items) > 256 {
		return EntrySnapshot{}, false
	}
	ref, a := decodeEntryRef(f["entry_ref"])
	sr, b := decodeRevision(f["source_revision"])
	or, c := decodeRevision(f["observed_revision"])
	av, d := decodeAvailability(f["availability"])
	fr, e := decodeFreshness(f["freshness"])
	s := EntrySnapshot{EntryRef: ref, DisplayName: f["display_name"].text, Properties: make([]PropertyValue, len(f["properties"].items)), SourceRevision: sr, ObservedRevision: or, ObservedAt: f["observed_at"].text, Availability: av, Freshness: fr}
	if !a || !b || !c || !d || !e {
		return EntrySnapshot{}, false
	}
	if x, exists := f["parent_ref"]; exists {
		p, valid := decodeEntryRef(x)
		if !valid {
			return EntrySnapshot{}, false
		}
		s.ParentRef = &p
	}
	if x, exists := f["modified_at"]; exists {
		if x.kind != jsonString {
			return EntrySnapshot{}, false
		}
		s.ModifiedAt = stringPointer(x.text)
	}
	for i, x := range f["properties"].items {
		p, valid := decodePropertyValue(x)
		if !valid {
			return EntrySnapshot{}, false
		}
		s.Properties[i] = p
	}
	return s, validSnapshot(s)
}
func decodePropertyValue(value jsonValue) (PropertyValue, bool) {
	f, ok := objectFieldsWithOptional(value, []string{"property_id", "entry_id", "value_type", "state", "provenance", "observed_at", "source_revision", "editable", "validation", "cardinality"}, []string{"value"})
	if !ok || !allStrings(f, "property_id", "entry_id", "value_type", "state", "provenance", "observed_at", "cardinality") || f["editable"].kind != jsonBool {
		return PropertyValue{}, false
	}
	revision, a := decodeRevision(f["source_revision"])
	validation, b := decodeValidation(f["validation"])
	p := PropertyValue{PropertyID: f["property_id"].text, EntryID: f["entry_id"].text, ValueType: f["value_type"].text, State: f["state"].text, Provenance: f["provenance"].text, ObservedAt: f["observed_at"].text, SourceRevision: revision, Editable: f["editable"].boolean, Validation: validation, Cardinality: f["cardinality"].text}
	if x, exists := f["value"]; exists {
		payload, valid := decodePropertyPayload(x, p.ValueType, p.Cardinality)
		if !valid {
			return PropertyValue{}, false
		}
		p.Value = &payload
	}
	return p, a && b && validPropertyValue(p)
}
func decodePropertyPayload(v jsonValue, kind, cardinality string) (PropertyPayload, bool) {
	p := PropertyPayload{kind: kind}
	if cardinality == "one" {
		switch kind {
		case "text", "number", "date", "datetime", "select":
			if v.kind != jsonString {
				return p, false
			}
			p.one = v.text
		case "boolean":
			if v.kind != jsonBool {
				return p, false
			}
			p.one = v.boolean
		default:
			return p, false
		}
		return p, true
	}
	if cardinality != "many" || v.kind != jsonArray || len(v.items) > 256 {
		return p, false
	}
	switch kind {
	case "boolean":
		items := make([]bool, len(v.items))
		for i, x := range v.items {
			if x.kind != jsonBool {
				return p, false
			}
			items[i] = x.boolean
		}
		p.many = items
	case "text", "number", "date", "datetime", "select":
		items := make([]string, len(v.items))
		for i, x := range v.items {
			if x.kind != jsonString {
				return p, false
			}
			items[i] = x.text
		}
		p.many = items
	default:
		return p, false
	}
	return p, true
}
func decodeValidation(v jsonValue) (ValidationResult, bool) {
	f, ok := objectFieldsWithOptional(v, []string{"valid"}, []string{"reason_code", "message", "rule_kind"})
	if !ok || f["valid"].kind != jsonBool {
		return ValidationResult{}, false
	}
	r := ValidationResult{Valid: f["valid"].boolean}
	for name, target := range map[string]**string{"reason_code": &r.ReasonCode, "message": &r.Message, "rule_kind": &r.RuleKind} {
		if x, exists := f[name]; exists {
			if x.kind != jsonString {
				return ValidationResult{}, false
			}
			*target = stringPointer(x.text)
		}
	}
	return r, validValidation(r)
}
func decodeRevision(v jsonValue) (Revision, bool) {
	f, ok := objectFieldsWithOptional(v, []string{"strength"}, []string{"token"})
	if !ok || f["strength"].kind != jsonString {
		return Revision{}, false
	}
	r := Revision{Strength: f["strength"].text}
	if x, exists := f["token"]; exists {
		if x.kind != jsonString {
			return Revision{}, false
		}
		r.Token = stringPointer(x.text)
	}
	return r, validRevision(r) || validObservedRevision(r)
}
func decodeAvailability(v jsonValue) (Availability, bool) {
	f, ok := objectFields(v, "state")
	if !ok || f["state"].kind != jsonString {
		return Availability{}, false
	}
	a := Availability{f["state"].text}
	return a, validAvailability(a.State)
}
func decodeFreshness(v jsonValue) (Freshness, bool) {
	f, ok := objectFieldsWithOptional(v, []string{"state", "observed_at", "source_revision"}, []string{"last_sync_at", "stale_after"})
	if !ok || !allStrings(f, "state", "observed_at") {
		return Freshness{}, false
	}
	r, valid := decodeRevision(f["source_revision"])
	x := Freshness{State: f["state"].text, ObservedAt: f["observed_at"].text, SourceRevision: r}
	for name, target := range map[string]**string{"last_sync_at": &x.LastSyncAt, "stale_after": &x.StaleAfter} {
		if field, exists := f[name]; exists {
			if field.kind != jsonString {
				return Freshness{}, false
			}
			*target = stringPointer(field.text)
		}
	}
	return x, valid && validFreshness(x)
}
func decodeCapabilities(v jsonValue) (Capabilities, bool) {
	f, ok := objectFields(v, "readable", "writable", "searchable", "commentable", "movable", "copyable", "deletable", "watchable", "streamable", "requires_approval")
	if !ok {
		return Capabilities{}, false
	}
	for _, x := range f {
		if x.kind != jsonBool {
			return Capabilities{}, false
		}
	}
	return Capabilities{f["readable"].boolean, f["writable"].boolean, f["searchable"].boolean, f["commentable"].boolean, f["movable"].boolean, f["copyable"].boolean, f["deletable"].boolean, f["watchable"].boolean, f["streamable"].boolean, f["requires_approval"].boolean}, true
}
func decodeAccessContext(v jsonValue) (AccessContext, bool) {
	f, ok := objectFieldsWithOptional(v, []string{"source_instance_id", "mount_id", "virtual_path", "capabilities"}, []string{"display_path"})
	if !ok || !allStrings(f, "source_instance_id", "mount_id", "virtual_path") {
		return AccessContext{}, false
	}
	caps, valid := decodeCapabilities(f["capabilities"])
	x := AccessContext{SourceInstanceID: f["source_instance_id"].text, MountID: f["mount_id"].text, VirtualPath: f["virtual_path"].text, Capabilities: caps}
	if d, exists := f["display_path"]; exists {
		if d.kind != jsonString {
			return AccessContext{}, false
		}
		x.DisplayPath = stringPointer(d.text)
	}
	return x, valid && validAccessContext(x)
}
func decodeRevisionSummary(v jsonValue) (RevisionSummary, bool) {
	f, ok := objectFields(v, "source_instance_id", "mount_id", "source_revision", "observed_revision")
	if !ok || !allStrings(f, "source_instance_id", "mount_id") {
		return RevisionSummary{}, false
	}
	s, a := decodeRevision(f["source_revision"])
	o, b := decodeRevision(f["observed_revision"])
	r := RevisionSummary{f["source_instance_id"].text, f["mount_id"].text, s, o}
	return r, a && b
}
func decodeSourceError(v jsonValue) (SourceError, bool) {
	f, ok := objectFields(v, "source_instance_id", "mount_id", "code", "message", "retryable")
	if !ok || !allStrings(f, "source_instance_id", "mount_id", "code", "message") || f["retryable"].kind != jsonBool {
		return SourceError{}, false
	}
	x := SourceError{f["source_instance_id"].text, f["mount_id"].text, f["code"].text, f["message"].text, f["retryable"].boolean}
	return x, validSourceError(x)
}
func decodeSourceAvailability(v jsonValue) (SourceAvailability, bool) {
	f, ok := objectFieldsWithOptional(v, []string{"source_instance_id", "mount_id", "state"}, []string{"error"})
	if !ok || !allStrings(f, "source_instance_id", "mount_id", "state") {
		return SourceAvailability{}, false
	}
	x := SourceAvailability{SourceInstanceID: f["source_instance_id"].text, MountID: f["mount_id"].text, State: f["state"].text}
	if e, exists := f["error"]; exists {
		mapped, valid := decodeSourceError(e)
		if !valid {
			return SourceAvailability{}, false
		}
		x.Error = &mapped
	}
	return x, validSourceAvailability(x)
}
func decodeSourceFreshness(v jsonValue) (SourceFreshness, bool) {
	f, ok := objectFieldsWithOptional(v, []string{"source_instance_id", "mount_id", "state", "observed_at", "source_revision"}, []string{"last_sync_at", "stale_after"})
	if !ok || !allStrings(f, "source_instance_id", "mount_id", "state", "observed_at") {
		return SourceFreshness{}, false
	}
	r, valid := decodeRevision(f["source_revision"])
	x := SourceFreshness{SourceInstanceID: f["source_instance_id"].text, MountID: f["mount_id"].text, State: f["state"].text, ObservedAt: f["observed_at"].text, SourceRevision: r}
	for name, target := range map[string]**string{"last_sync_at": &x.LastSyncAt, "stale_after": &x.StaleAfter} {
		if z, exists := f[name]; exists {
			if z.kind != jsonString {
				return SourceFreshness{}, false
			}
			*target = stringPointer(z.text)
		}
	}
	return x, valid && validSourceFreshness(x)
}
func decodeWarning(v jsonValue) (Warning, bool) {
	f, ok := objectFields(v, "source_instance_id", "mount_id", "code", "message", "retryable")
	if !ok || !allStrings(f, "source_instance_id", "mount_id", "code", "message") || f["retryable"].kind != jsonBool {
		return Warning{}, false
	}
	x := Warning{f["source_instance_id"].text, f["mount_id"].text, f["code"].text, f["message"].text, f["retryable"].boolean}
	return x, validWarning(x)
}

func validEntry(e Entry) bool {
	return validEntryRef(e.EntryRef) && validSnapshot(e.EntrySnapshot) && validAccessContext(e.AccessContext) && e.EntryRef == e.EntrySnapshot.EntryRef && e.EntryRef.SourceInstanceID == e.AccessContext.SourceInstanceID && validCapabilitiesForAvailability(e.AccessContext.Capabilities, e.EntrySnapshot.Availability.State)
}

func validCapabilitiesForAvailability(value Capabilities, availability string) bool {
	if availability != "read_only" {
		return true
	}
	return !value.Writable && !value.Movable && !value.Copyable && !value.Deletable && !value.Commentable
}
func validEntryRef(r EntryRef) bool {
	locator, err := domainentry.NewLocatorRef(r.CanonicalLocator)
	if err != nil {
		return false
	}
	ref, err := domainentry.NewEntryRef(r.EntryID, r.SourceInstanceID, r.SourceObjectKey, r.ResourceType, locator, domainentry.IdentityStrength(r.IdentityStrength))
	return err == nil && ref.Validate() == nil
}
func validSnapshot(s EntrySnapshot) bool {
	if !oneOf(s.Availability.State, "available", "read_only", "stale") || (s.Availability.State == "stale") != (s.Freshness.State == "stale") || !validEntryRef(s.EntryRef) || !validUTF8Bytes(s.DisplayName, 1, 1024) || s.Properties == nil || len(s.Properties) > 256 || !validRevision(s.SourceRevision) || !validObservedRevision(s.ObservedRevision) || !canonicalTimestamp(s.ObservedAt) || !validAvailability(s.Availability.State) || !validFreshness(s.Freshness) || !equalRevision(s.SourceRevision, s.Freshness.SourceRevision) || s.ObservedAt != s.Freshness.ObservedAt {
		return false
	}
	if s.ModifiedAt != nil && !canonicalTimestamp(*s.ModifiedAt) {
		return false
	}
	if s.ParentRef != nil && (!validEntryRef(*s.ParentRef) || s.ParentRef.SourceInstanceID != s.EntryRef.SourceInstanceID) {
		return false
	}
	for index, p := range s.Properties {
		if !validPropertyValue(p) || p.EntryID != s.EntryRef.EntryID {
			return false
		}
		if index > 0 && s.Properties[index-1].PropertyID >= p.PropertyID {
			return false
		}
	}
	return true
}
func validPropertyValue(v PropertyValue) bool {
	if !validUTF8Bytes(v.PropertyID, 1, 128) || !validEntryID(v.EntryID) || !oneOf(v.ValueType, "text", "number", "date", "datetime", "boolean", "select") || !oneOf(v.State, "value", "null", "unknown", "error", "not_applicable") || !oneOf(v.Provenance, "system", "filesystem", "spotlight", "extracted", "user_defined", "provider_defined", "agent_generated") || !canonicalTimestamp(v.ObservedAt) || !validRevision(v.SourceRevision) || !oneOf(v.Cardinality, "one", "many") || !validValidation(v.Validation) {
		return false
	}
	if (v.State == "value") != (v.Value != nil) {
		return false
	}
	return v.Value == nil || validWirePropertyPayload(*v.Value, v.ValueType, v.Cardinality)
}
func validValidation(v ValidationResult) bool {
	if v.Valid {
		return v.ReasonCode == nil && v.Message == nil && v.RuleKind == nil
	}
	if v.ReasonCode == nil || v.Message == nil {
		return false
	}
	expectedMessage := validationMessage(*v.ReasonCode)
	if expectedMessage == "" || *v.Message != expectedMessage {
		return false
	}
	expectedRule := map[string]string{"min_number": "min_number", "max_number": "max_number", "min_length": "min_length", "max_length": "max_length", "regex_mismatch": "regex", "option_not_allowed": "allowed_options", "max_items": "max_items"}[*v.ReasonCode]
	if expectedRule == "" {
		return v.RuleKind == nil
	}
	return v.RuleKind != nil && *v.RuleKind == expectedRule
}
func validationMessage(code string) string {
	return map[string]string{
		"type_mismatch": "The property value has an invalid type.", "cardinality_mismatch": "The property value has invalid cardinality.",
		"required_missing": "A required property value is missing.", "null_not_allowed": "The property does not allow null.",
		"min_number": "The property value is below the minimum.", "max_number": "The property value is above the maximum.",
		"min_length": "The property value is shorter than allowed.", "max_length": "The property value is longer than allowed.",
		"regex_mismatch": "The property value does not match the required pattern.", "option_not_allowed": "The selected option is not allowed.",
		"max_items": "The property value has too many items.", "invalid_definition": "The property definition is invalid.",
	}[code]
}
func validWirePropertyPayload(payload PropertyPayload, valueType, cardinality string) bool {
	validateString := func(value string) bool {
		switch valueType {
		case "text":
			return validUTF8Bytes(value, 0, 16384)
		case "number":
			return validCanonicalDecimal(value)
		case "date":
			parsed, err := time.Parse("2006-01-02", value)
			return err == nil && parsed.Format("2006-01-02") == value
		case "datetime":
			return canonicalTimestamp(value)
		case "select":
			return validUTF8Bytes(value, 1, 256)
		default:
			return false
		}
	}
	if cardinality == "one" {
		if valueType == "boolean" {
			_, ok := payload.one.(bool)
			return ok
		}
		value, ok := payload.one.(string)
		return ok && validateString(value)
	}
	if cardinality != "many" {
		return false
	}
	if valueType == "boolean" {
		values, ok := payload.many.([]bool)
		return ok && len(values) <= 256
	}
	values, ok := payload.many.([]string)
	if !ok || len(values) > 256 {
		return false
	}
	for _, value := range values {
		if !validateString(value) {
			return false
		}
	}
	return true
}
func validCanonicalDecimal(value string) bool {
	if len(value) < 1 || len(value) > 64 || strings.ContainsAny(value, "+eE \\t\\n\\r") {
		return false
	}
	index, negative := 0, false
	if value[0] == '-' {
		negative, index = true, 1
		if index == len(value) {
			return false
		}
	}
	integerStart := index
	if value[index] == '0' {
		index++
		if index < len(value) && value[index] >= '0' && value[index] <= '9' {
			return false
		}
	} else {
		if value[index] < '1' || value[index] > '9' {
			return false
		}
		for index < len(value) && value[index] >= '0' && value[index] <= '9' {
			index++
		}
	}
	integerDigits, fractionalDigits := index-integerStart, 0
	if index < len(value) {
		if value[index] != '.' {
			return false
		}
		index++
		start := index
		for index < len(value) && value[index] >= '0' && value[index] <= '9' {
			index++
		}
		fractionalDigits = index - start
		if fractionalDigits < 1 || fractionalDigits > 18 || value[index-1] == '0' {
			return false
		}
	}
	if index != len(value) || integerDigits+fractionalDigits > 38 {
		return false
	}
	return !(negative && integerDigits == 1 && value[integerStart] == '0' && fractionalDigits == 0)
}
func validAccessContext(v AccessContext) bool {
	if !validSourceInstanceID(v.SourceInstanceID) || !validUTF8Bytes(v.MountID, 1, 64) || !validUTF8Bytes(v.VirtualPath, 1, 4096) || (v.DisplayPath != nil && !validUTF8Bytes(*v.DisplayPath, 1, 4096)) {
		return false
	}
	path, err := domainentry.NewResolvedVirtualPath(v.MountID, v.VirtualPath, "wire")
	return err == nil && path.String() == v.VirtualPath
}
func validRevision(v Revision) bool {
	switch v.Strength {
	case "provider":
		return v.Token != nil && validOpaqueASCII(*v.Token, 1, 128)
	case "metadata":
		if v.Token == nil || !strings.HasPrefix(*v.Token, "meta:") {
			return false
		}
		encoded := strings.TrimPrefix(*v.Token, "meta:")
		digest, err := base64.RawURLEncoding.DecodeString(encoded)
		return err == nil && len(digest) == 32 && base64.RawURLEncoding.EncodeToString(digest) == encoded
	case "unknown":
		return v.Token == nil
	default:
		return false
	}
}
func validObservedRevision(v Revision) bool {
	if v.Strength != "observed" || v.Token == nil {
		return false
	}
	n, err := strconv.ParseUint(*v.Token, 10, 64)
	return err == nil && n > 0 && strconv.FormatUint(n, 10) == *v.Token
}
func validAvailability(v string) bool {
	return oneOf(v, "available", "loading", "stale", "offline", "permission_denied", "source_deleted", "unmounted", "read_only", "error")
}
func validFreshness(v Freshness) bool {
	if !oneOf(v.State, "current", "stale", "unknown") || !canonicalTimestamp(v.ObservedAt) || !validRevision(v.SourceRevision) {
		return false
	}
	if v.LastSyncAt != nil && !canonicalTimestamp(*v.LastSyncAt) {
		return false
	}
	if v.StaleAfter != nil {
		a, ok := parseCanonicalTime(*v.StaleAfter)
		b, bok := parseCanonicalTime(v.ObservedAt)
		if !ok || !bok || a.Before(b) {
			return false
		}
	}
	return true
}
func validSourceAvailability(v SourceAvailability) bool {
	if !validSourceInstanceID(v.SourceInstanceID) || !validUTF8Bytes(v.MountID, 1, 64) || !validAvailability(v.State) {
		return false
	}
	expectedCode := ""
	switch v.State {
	case "loading", "offline", "unmounted":
		expectedCode = "source_unavailable"
	case "permission_denied":
		expectedCode = "permission_denied"
	case "source_deleted":
		expectedCode = "source_deleted"
	case "error":
		expectedCode = "adapter_failure"
	}
	if expectedCode == "" {
		return v.Error == nil
	}
	return v.Error != nil && v.Error.Code == expectedCode && validSourceError(*v.Error) && v.Error.SourceInstanceID == v.SourceInstanceID && v.Error.MountID == v.MountID
}
func validSourceFreshness(v SourceFreshness) bool {
	return validSourceInstanceID(v.SourceInstanceID) && validUTF8Bytes(v.MountID, 1, 64) && validFreshness(Freshness{v.State, v.ObservedAt, v.SourceRevision, v.LastSyncAt, v.StaleAfter})
}
func validSourceError(v SourceError) bool {
	expected := sourceErrorMessage(v.Code)
	return expected != "" && validSourceInstanceID(v.SourceInstanceID) && validUTF8Bytes(v.MountID, 1, 64) && v.Message == expected
}
func sourceErrorMessage(code string) string {
	return map[string]string{"entry_not_found": "The entry was not found.", "source_unavailable": "The source is unavailable.", "permission_denied": "Permission was denied.", "source_deleted": "The source was deleted.", "adapter_failure": "The source adapter failed."}[code]
}
func validWarning(v Warning) bool {
	expected := warningMessage(v.Code)
	return expected != "" && validSourceInstanceID(v.SourceInstanceID) && validUTF8Bytes(v.MountID, 1, 64) && v.Message == expected
}
func warningMessage(code string) string {
	return map[string]string{"stale_snapshot": "A stale snapshot was returned.", "source_offline": "The source is offline.", "source_unavailable": "The source is unavailable.", "permission_denied": "Permission was denied.", "source_deleted": "The source was deleted.", "adapter_failure": "The source adapter failed.", "partial_result": "The result is partial."}[code]
}
func equalRevision(a, b Revision) bool {
	return a.Strength == b.Strength && equalOptionalString(a.Token, b.Token)
}
func equalFreshnessWire(a, b Freshness) bool {
	return a.State == b.State && a.ObservedAt == b.ObservedAt && equalRevision(a.SourceRevision, b.SourceRevision) && equalOptionalString(a.LastSyncAt, b.LastSyncAt) && equalOptionalString(a.StaleAfter, b.StaleAfter)
}
func equalFreshness(a Freshness, b SourceFreshness) bool {
	return a.State == b.State && a.ObservedAt == b.ObservedAt && equalRevision(a.SourceRevision, b.SourceRevision) && equalOptionalString(a.LastSyncAt, b.LastSyncAt) && equalOptionalString(a.StaleAfter, b.StaleAfter)
}
func equalFreshnessEnvelope(a Freshness, b SourceFreshness) bool {
	return a.State == b.State && a.ObservedAt == b.ObservedAt && equalOptionalString(a.LastSyncAt, b.LastSyncAt) && equalOptionalString(a.StaleAfter, b.StaleAfter)
}
func validSourceInstanceID(v string) bool {
	identity, err := domainentry.NewSourceIdentity(v, domainentry.IdentityStrengthLocator)
	return err == nil && identity.Validate() == nil
}
func validEntryID(v string) bool { return validPrefixedDigestValue(v, "ent:") }
func validPrefixedDigestValue(value, prefix string) bool {
	if len(value) != len(prefix)+43 || !strings.HasPrefix(value, prefix) {
		return false
	}
	encoded := strings.TrimPrefix(value, prefix)
	digest, err := base64.RawURLEncoding.DecodeString(encoded)
	return err == nil && len(digest) == 32 && base64.RawURLEncoding.EncodeToString(digest) == encoded
}
func validOpaqueASCII(v string, min, max int) bool {
	if len(v) < min || len(v) > max {
		return false
	}
	for i := range len(v) {
		if v[i] > 0x7f {
			return false
		}
	}
	return true
}
func validOptionalOpaque(v *string) bool {
	return v == nil || validOpaqueASCII(*v, 1, maximumPageTokenBytes)
}
func canonicalTimestamp(v string) bool { _, ok := parseCanonicalTime(v); return ok }
func parseCanonicalTime(v string) (time.Time, bool) {
	if !validUTF8Bytes(v, 1, 64) {
		return time.Time{}, false
	}
	t, err := time.Parse(time.RFC3339Nano, v)
	return t, err == nil && t.Location() == time.UTC && t.Format(time.RFC3339Nano) == v
}
func oneOf(v string, values ...string) bool {
	for _, x := range values {
		if v == x {
			return true
		}
	}
	return false
}
func equalOptionalString(a, b *string) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}
func formatTime(v time.Time) string { return v.Round(0).UTC().Format(time.RFC3339Nano) }
func formatOptionalTime(v *time.Time) *string {
	if v == nil {
		return nil
	}
	s := formatTime(*v)
	return &s
}
func validUTF8Bytes(v string, min, max int) bool {
	return utf8.ValidString(v) && len(v) >= min && len(v) <= max
}
func allStrings(fields map[string]jsonValue, names ...string) bool {
	for _, n := range names {
		if fields[n].kind != jsonString {
			return false
		}
	}
	return true
}
func objectFieldsWithOptional(value jsonValue, required, optional []string) (map[string]jsonValue, bool) {
	if value.kind != jsonObject || value.hasDuplicateObjectKey() {
		return nil, false
	}
	allowed := map[string]struct{}{}
	for _, n := range append(append([]string{}, required...), optional...) {
		allowed[n] = struct{}{}
	}
	fields := map[string]jsonValue{}
	for _, m := range value.members {
		if _, ok := allowed[m.name]; !ok {
			return nil, false
		}
		fields[m.name] = m.value
	}
	for _, n := range required {
		if _, ok := fields[n]; !ok {
			return nil, false
		}
	}
	return fields, true
}
func stringPointer(v string) *string { return &v }
func cloneWireString(v *string) *string {
	if v == nil {
		return nil
	}
	return stringPointer(*v)
}

func successFitsWire(requestID string, result Result) bool {
	counter := &limitedBuffer{limit: MaxWireBytes + 1}
	encoder := json.NewEncoder(counter)
	err := encoder.Encode(successWire{RequestID: requestID, OK: true, Result: result})
	return err == nil && counter.size-1 <= MaxWireBytes
}

type limitedBuffer struct{ size, limit int }

func (w *limitedBuffer) Write(p []byte) (int, error) {
	if len(p) > w.limit-w.size {
		w.size = w.limit
		return 0, errors.New("wire limit exceeded")
	}
	w.size += len(p)
	return len(p), nil
}
func entryListSuccessFitsWire(requestID string, result EntryListResult) bool {
	return successFitsWire(requestID, result)
}
func wireSizeForEntryListSuccess(requestID string, result EntryListResult) int {
	raw, err := json.Marshal(successWire{RequestID: requestID, OK: true, Result: result})
	if err != nil {
		return MaxWireBytes + 1
	}
	return len(raw)
}
