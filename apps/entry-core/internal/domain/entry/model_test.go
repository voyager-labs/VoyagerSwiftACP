package entry

import (
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"
)

const validSourceID = "src:8kHitBFXUPx-VG4Qf_M3LXM1kDu4jXaGZ1JTw9cUiyY"

func TestSourceIdentity(t *testing.T) {
	for _, strength := range []IdentityStrength{
		IdentityStrengthStable,
		IdentityStrengthLocator,
		IdentityStrengthEphemeral,
	} {
		t.Run(string(strength), func(t *testing.T) {
			identity, err := NewSourceIdentity(validSourceID, strength)
			if err != nil {
				t.Fatalf("NewSourceIdentity() error = %v", err)
			}
			if identity.SourceID != validSourceID || identity.IdentityStrength != strength {
				t.Fatalf("identity = %#v", identity)
			}
			if err := identity.Validate(); err != nil {
				t.Fatalf("Validate() error = %v", err)
			}
		})
	}

	tests := []struct {
		name     string
		identity SourceIdentity
		wantErr  error
	}{
		{name: "missing prefix", identity: SourceIdentity{SourceID: strings.TrimPrefix(validSourceID, "src:"), IdentityStrength: IdentityStrengthStable}, wantErr: ErrInvalidSourceIdentity},
		{name: "padded digest", identity: SourceIdentity{SourceID: validSourceID + "=", IdentityStrength: IdentityStrengthStable}, wantErr: ErrInvalidSourceIdentity},
		{name: "short digest", identity: SourceIdentity{SourceID: validSourceID[:len(validSourceID)-1], IdentityStrength: IdentityStrengthStable}, wantErr: ErrInvalidSourceIdentity},
		{name: "invalid base64url", identity: SourceIdentity{SourceID: validSourceID[:len(validSourceID)-1] + "+", IdentityStrength: IdentityStrengthStable}, wantErr: ErrInvalidSourceIdentity},
		{name: "unknown strength", identity: SourceIdentity{SourceID: validSourceID, IdentityStrength: IdentityStrength("durable")}, wantErr: ErrInvalidIdentityStrength},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if err := test.identity.Validate(); !errors.Is(err, test.wantErr) {
				t.Fatalf("Validate() error = %v, want %v", err, test.wantErr)
			}
		})
	}
}

func TestEntryIdentity(t *testing.T) {
	identity, err := NewEntryIdentity(validSourceID, "notes.txt", IdentityStrengthLocator)
	if err != nil {
		t.Fatalf("NewEntryIdentity() error = %v", err)
	}
	if identity.SourceID != validSourceID || identity.EntryKey != "notes.txt" {
		t.Fatalf("identity = %#v", identity)
	}
	if identity.IdentityStrength != IdentityStrengthLocator {
		t.Fatalf("local locator strength = %q, want %q", identity.IdentityStrength, IdentityStrengthLocator)
	}

	for _, test := range []struct {
		name     string
		identity EntryIdentity
		wantErr  error
	}{
		{name: "different valid source remains scoped", identity: EntryIdentity{SourceID: "src:m-KQdBGV6oTOo0uNavbxU6UH9heJBwQTseDcv_utLsE", EntryKey: "notes.txt", IdentityStrength: IdentityStrengthStable}},
		{name: "invalid source", identity: EntryIdentity{SourceID: "source", EntryKey: "notes.txt", IdentityStrength: IdentityStrengthStable}, wantErr: ErrInvalidEntryIdentity},
		{name: "empty key", identity: EntryIdentity{SourceID: validSourceID, IdentityStrength: IdentityStrengthLocator}, wantErr: ErrInvalidEntryIdentity},
		{name: "oversized key", identity: EntryIdentity{SourceID: validSourceID, EntryKey: strings.Repeat("x", 4097), IdentityStrength: IdentityStrengthLocator}, wantErr: ErrInvalidEntryIdentity},
		{name: "invalid UTF-8 key", identity: EntryIdentity{SourceID: validSourceID, EntryKey: string([]byte{0xff}), IdentityStrength: IdentityStrengthLocator}, wantErr: ErrInvalidEntryIdentity},
		{name: "unknown strength", identity: EntryIdentity{SourceID: validSourceID, EntryKey: "notes.txt", IdentityStrength: IdentityStrength("global")}, wantErr: ErrInvalidIdentityStrength},
	} {
		t.Run(test.name, func(t *testing.T) {
			err := test.identity.Validate()
			if test.wantErr == nil && err != nil {
				t.Fatalf("Validate() error = %v", err)
			}
			if test.wantErr != nil && !errors.Is(err, test.wantErr) {
				t.Fatalf("Validate() error = %v, want %v", err, test.wantErr)
			}
		})
	}
}

func TestRevisionFallback(t *testing.T) {
	provider := "provider-revision"
	metadata := "meta:d8Gf7-VJuNudFhh2KhmydZ3zHO9Nl-NSueKajhIG22s"
	for _, test := range []struct {
		name     string
		strength RevisionStrength
		token    *string
	}{
		{name: "provider", strength: RevisionStrengthProvider, token: &provider},
		{name: "metadata", strength: RevisionStrengthMetadata, token: &metadata},
		{name: "unknown", strength: RevisionStrengthUnknown},
	} {
		t.Run(test.name, func(t *testing.T) {
			revision, err := NewRevision(test.strength, test.token)
			if err != nil {
				t.Fatalf("NewRevision() error = %v", err)
			}
			if revision.Strength != test.strength {
				t.Fatalf("strength = %q, want %q", revision.Strength, test.strength)
			}
			if err := revision.Validate(); err != nil {
				t.Fatalf("Validate() error = %v", err)
			}
		})
	}

	maximumProvider := strings.Repeat("p", 128)
	if _, err := NewRevision(RevisionStrengthProvider, &maximumProvider); err != nil {
		t.Fatalf("128-byte provider revision error = %v", err)
	}
	oversizedProvider := strings.Repeat("p", 129)
	if _, err := NewRevision(RevisionStrengthProvider, &oversizedProvider); !errors.Is(err, ErrInvalidRevision) {
		t.Fatalf("129-byte provider revision error = %v, want %v", err, ErrInvalidRevision)
	}
	nonASCIIProvider := "révision"
	if _, err := NewRevision(RevisionStrengthProvider, &nonASCIIProvider); !errors.Is(err, ErrInvalidRevision) {
		t.Fatalf("non-ASCII provider revision error = %v, want %v", err, ErrInvalidRevision)
	}

	empty := ""
	oversized := strings.Repeat("x", 4097)
	invalidUTF8 := string([]byte{0xff})
	wrongMetadataPrefix := "provider-token"
	shortMetadataDigest := "meta:abc"
	paddedMetadataDigest := metadata + "="
	invalidMetadataDigest := metadata[:len(metadata)-1] + "+"
	for _, test := range []struct {
		name     string
		revision Revision
	}{
		{name: "provider missing token", revision: Revision{Strength: RevisionStrengthProvider}},
		{name: "metadata empty token", revision: Revision{Strength: RevisionStrengthMetadata, Token: &empty}},
		{name: "metadata oversized token", revision: Revision{Strength: RevisionStrengthMetadata, Token: &oversized}},
		{name: "provider invalid UTF-8 token", revision: Revision{Strength: RevisionStrengthProvider, Token: &invalidUTF8}},
		{name: "metadata wrong prefix", revision: Revision{Strength: RevisionStrengthMetadata, Token: &wrongMetadataPrefix}},
		{name: "metadata short digest", revision: Revision{Strength: RevisionStrengthMetadata, Token: &shortMetadataDigest}},
		{name: "metadata padded digest", revision: Revision{Strength: RevisionStrengthMetadata, Token: &paddedMetadataDigest}},
		{name: "metadata invalid base64url", revision: Revision{Strength: RevisionStrengthMetadata, Token: &invalidMetadataDigest}},
		{name: "unknown has token", revision: Revision{Strength: RevisionStrengthUnknown, Token: &provider}},
		{name: "unknown strength", revision: Revision{Strength: RevisionStrength("content")}},
	} {
		t.Run(test.name, func(t *testing.T) {
			if err := test.revision.Validate(); !errors.Is(err, ErrInvalidRevision) {
				t.Fatalf("Validate() error = %v, want %v", err, ErrInvalidRevision)
			}
		})
	}
}

func TestIndependentStates(t *testing.T) {
	for _, state := range []AvailabilityState{AvailabilityStateAvailable, AvailabilityStateUnavailable, AvailabilityStateUnknown} {
		if err := (Availability{State: state}).Validate(); err != nil {
			t.Fatalf("availability %q: %v", state, err)
		}
	}
	for _, state := range []FreshnessState{FreshnessStateCurrent, FreshnessStateStale, FreshnessStateUnknown} {
		if err := (Freshness{State: state}).Validate(); err != nil {
			t.Fatalf("freshness %q: %v", state, err)
		}
	}
	for _, state := range []OperationStateValue{OperationStateIdle, OperationStateBusy, OperationStateFailed, OperationStateUnknown} {
		if err := (OperationState{State: state}).Validate(); err != nil {
			t.Fatalf("operation state %q: %v", state, err)
		}
	}
	if err := (Availability{State: AvailabilityState("busy")}).Validate(); !errors.Is(err, ErrInvalidAvailability) {
		t.Fatalf("availability error = %v", err)
	}
	if err := (Freshness{State: FreshnessState("available")}).Validate(); !errors.Is(err, ErrInvalidFreshness) {
		t.Fatalf("freshness error = %v", err)
	}
	canonicalFreshness := Freshness{State: FreshnessStateCurrent, ObservedAt: time.Now().UTC()}
	if err := canonicalFreshness.Validate(); !errors.Is(err, ErrInvalidFreshness) {
		t.Fatalf("legacy freshness accepted canonical fields: %v", err)
	}
	if err := (OperationState{State: OperationStateValue("current")}).Validate(); !errors.Is(err, ErrInvalidOperationState) {
		t.Fatalf("operation state error = %v", err)
	}

	virtualPath, err := NewVirtualPath("/local/notes.txt")
	if err != nil {
		t.Fatalf("NewVirtualPath() error = %v", err)
	}
	capabilities := Capabilities{ListChildren: false, ReadProperties: true}
	access, err := NewAccessContext(validSourceID, "mount-local", virtualPath, capabilities)
	if err != nil {
		t.Fatalf("NewAccessContext() error = %v", err)
	}
	if access.VirtualPath.String() != "/local/notes.txt" || access.Capabilities != capabilities {
		t.Fatalf("access context = %#v", access)
	}

	if _, err := NewVirtualPath(""); !errors.Is(err, ErrInvalidVirtualPath) {
		t.Fatalf("empty virtual path error = %v", err)
	}
	if _, err := NewVirtualPath(string([]byte{0xff})); !errors.Is(err, ErrInvalidVirtualPath) {
		t.Fatalf("invalid UTF-8 virtual path error = %v", err)
	}
	for _, value := range []string{"relative", "//team", "/team/", "/a/./b", "/a/../b", "/a\\b", "/a\x00b"} {
		if _, err := NewVirtualPath(value); !errors.Is(err, ErrInvalidVirtualPath) {
			t.Fatalf("NewVirtualPath(%q) error = %v", value, err)
		}
	}
	if root, err := NewVirtualPath("/"); err != nil || root.String() != "/" {
		t.Fatalf("root virtual path = %q, error = %v", root.String(), err)
	}
	if err := (AccessContext{SourceID: "bad", MountID: "mount", VirtualPath: virtualPath}).Validate(); !errors.Is(err, ErrInvalidAccessContext) {
		t.Fatalf("access source error = %v", err)
	}
	if err := (AccessContext{SourceID: validSourceID, MountID: "", VirtualPath: virtualPath}).Validate(); !errors.Is(err, ErrInvalidAccessContext) {
		t.Fatalf("access mount error = %v", err)
	}
	displayPath := "Local"
	if err := (AccessContext{SourceID: validSourceID, MountID: "mount", VirtualPath: virtualPath, DisplayPath: &displayPath}).Validate(); !errors.Is(err, ErrInvalidAccessContext) {
		t.Fatalf("legacy access accepted canonical display path: %v", err)
	}
}

func TestIndependentStatesEntryValidation(t *testing.T) {
	identity, err := NewEntryIdentity(validSourceID, "notes.txt", IdentityStrengthLocator)
	if err != nil {
		t.Fatal(err)
	}
	virtualPath, err := NewVirtualPath("/local/notes.txt")
	if err != nil {
		t.Fatal(err)
	}
	access, err := NewAccessContext(validSourceID, "mount-local", virtualPath, Capabilities{ReadProperties: true})
	if err != nil {
		t.Fatal(err)
	}
	revision, err := NewRevision(RevisionStrengthUnknown, nil)
	if err != nil {
		t.Fatal(err)
	}
	size := int64(12)
	modifiedAt := time.Date(2026, time.August, 2, 12, 0, 0, 0, time.UTC)
	propertyValue, err := NewStringPropertyValue("Notes")
	if err != nil {
		t.Fatal(err)
	}
	property, err := NewProperty("title", propertyValue)
	if err != nil {
		t.Fatal(err)
	}
	properties := []Property{property}
	snapshot, err := NewEntrySnapshot(
		"notes.txt",
		"file",
		&size,
		&modifiedAt,
		properties,
		revision,
		Availability{State: AvailabilityStateAvailable},
		Freshness{State: FreshnessStateStale},
		OperationState{State: OperationStateBusy},
	)
	if err != nil {
		t.Fatalf("NewEntrySnapshot() error = %v", err)
	}
	legacyHybrid := snapshot
	legacyHybrid.DisplayName = "canonical"
	if err := legacyHybrid.Validate(); !errors.Is(err, ErrInvalidEntrySnapshot) {
		t.Fatalf("legacy snapshot accepted canonical fields: %v", err)
	}
	properties[0].Key = "mutated"
	if snapshot.Properties[0].Key != "title" {
		t.Fatalf("snapshot properties alias constructor input: %#v", snapshot.Properties)
	}

	mismatchedAccess := access
	mismatchedAccess.SourceID = "src:m-KQdBGV6oTOo0uNavbxU6UH9heJBwQTseDcv_utLsE"
	if err := (Entry{Identity: identity, Snapshot: snapshot, AccessContext: mismatchedAccess}).Validate(); !errors.Is(err, ErrInvalidEntry) {
		t.Fatalf("source mismatch error = %v", err)
	}
	badSnapshot := snapshot
	badSnapshot.Name = ""
	if err := badSnapshot.Validate(); !errors.Is(err, ErrInvalidEntrySnapshot) {
		t.Fatalf("snapshot name error = %v", err)
	}
	negative := int64(-1)
	badSnapshot = snapshot
	badSnapshot.SizeBytes = &negative
	if err := badSnapshot.Validate(); !errors.Is(err, ErrInvalidEntrySnapshot) {
		t.Fatalf("snapshot size error = %v", err)
	}
	outOfRangeModifiedAt := time.Date(0, time.January, 1, 0, 0, 0, 0, time.FixedZone("plus-fourteen", 14*60*60))
	badSnapshot = snapshot
	badSnapshot.ModifiedAt = &outOfRangeModifiedAt
	if err := badSnapshot.Validate(); !errors.Is(err, ErrInvalidEntrySnapshot) {
		t.Fatalf("snapshot UTC timestamp error = %v", err)
	}

}

func TestPropertyValue(t *testing.T) {
	timestamp := time.Date(2026, time.August, 2, 12, 34, 56, 123456789, time.FixedZone("offset", 9*60*60))
	listInput := []string{"one", "one", ""}
	values := []PropertyValue{}
	constructors := []struct {
		name string
		make func() (PropertyValue, error)
	}{
		{name: "string", make: func() (PropertyValue, error) { return NewStringPropertyValue("") }},
		{name: "int64", make: func() (PropertyValue, error) { return NewInt64PropertyValue(0) }},
		{name: "bool", make: func() (PropertyValue, error) { return NewBoolPropertyValue(false) }},
		{name: "timestamp", make: func() (PropertyValue, error) { return NewTimestampPropertyValue(timestamp) }},
		{name: "string list", make: func() (PropertyValue, error) { return NewStringListPropertyValue(listInput) }},
		{name: "empty string list", make: func() (PropertyValue, error) { return NewStringListPropertyValue([]string{}) }},
	}
	for _, test := range constructors {
		t.Run(test.name, func(t *testing.T) {
			value, err := test.make()
			if err != nil {
				t.Fatalf("constructor error = %v", err)
			}
			if err := value.Validate(); err != nil {
				t.Fatalf("Validate() error = %v", err)
			}
			values = append(values, value)
		})
	}
	listInput[0] = "mutated"
	if got := (*values[4].StringListValue)[0]; got != "one" {
		t.Fatalf("string list aliases constructor input: %q", got)
	}
	if values[5].StringListValue == nil || len(*values[5].StringListValue) != 0 {
		t.Fatalf("empty string list = %#v", values[5].StringListValue)
	}

	stringValue := "value"
	boolValue := false
	int64Value := int64(7)
	underflowUTC := time.Date(0, time.January, 1, 0, 0, 0, 0, time.FixedZone("plus-fourteen", 14*60*60))
	overflowUTC := time.Date(9999, time.December, 31, 23, 59, 59, 0, time.FixedZone("minus-fourteen", -14*60*60))
	for _, test := range []struct {
		name  string
		value PropertyValue
	}{
		{name: "zero payloads", value: PropertyValue{Type: PropertyValueTypeString}},
		{name: "multiple payloads", value: PropertyValue{Type: PropertyValueTypeString, StringValue: &stringValue, BoolValue: &boolValue}},
		{name: "mismatched payload", value: PropertyValue{Type: PropertyValueTypeString, Int64Value: &int64Value}},
		{name: "unknown type", value: PropertyValue{Type: PropertyValueType("number"), Int64Value: &int64Value}},
		{name: "oversized string", value: mustStringPropertyValue(t, strings.Repeat("x", 16385))},
		{name: "invalid UTF-8 string", value: mustStringPropertyValue(t, string([]byte{0xff}))},
		{name: "too many list items", value: directStringListValue(make([]string, 257))},
		{name: "oversized list item", value: directStringListValue([]string{strings.Repeat("x", 4097)})},
		{name: "invalid UTF-8 list item", value: directStringListValue([]string{string([]byte{0xff})})},
		{name: "timestamp underflows UTC year", value: PropertyValue{Type: PropertyValueTypeTimestamp, TimestampValue: &underflowUTC}},
		{name: "timestamp overflows UTC year", value: PropertyValue{Type: PropertyValueTypeTimestamp, TimestampValue: &overflowUTC}},
	} {
		t.Run(test.name, func(t *testing.T) {
			if err := test.value.Validate(); !errors.Is(err, ErrInvalidPropertyValue) {
				t.Fatalf("Validate() error = %v, want %v", err, ErrInvalidPropertyValue)
			}
		})
	}
}

func TestPropertyValueDuplicateKeyRejection(t *testing.T) {
	value, err := NewStringPropertyValue("value")
	if err != nil {
		t.Fatal(err)
	}
	first, err := NewProperty("title", value)
	if err != nil {
		t.Fatal(err)
	}
	second, err := NewProperty("title", value)
	if err != nil {
		t.Fatal(err)
	}
	if err := ValidateProperties([]Property{first, second}); !errors.Is(err, ErrDuplicatePropertyKey) {
		t.Fatalf("ValidateProperties() error = %v, want %v", err, ErrDuplicatePropertyKey)
	}
	if _, err := NewProperty("", value); !errors.Is(err, ErrInvalidProperty) {
		t.Fatalf("empty key error = %v", err)
	}
	if _, err := NewProperty(strings.Repeat("x", 129), value); !errors.Is(err, ErrInvalidProperty) {
		t.Fatalf("oversized key error = %v", err)
	}
	if _, err := NewProperty(string([]byte{0xff}), value); !errors.Is(err, ErrInvalidProperty) {
		t.Fatalf("invalid UTF-8 key error = %v", err)
	}
}

func mustStringPropertyValue(t *testing.T, value string) PropertyValue {
	t.Helper()
	return PropertyValue{Type: PropertyValueTypeString, StringValue: &value}
}

func directStringListValue(items []string) PropertyValue {
	return PropertyValue{Type: PropertyValueTypeStringList, StringListValue: &items}
}

func TestLocatorRefCanonical(t *testing.T) {
	valid := "loc:8kHitBFXUPx-VG4Qf_M3LXM1kDu4jXaGZ1JTw9cUiyY"
	ref, err := NewLocatorRef(valid)
	if err != nil || ref.String() != valid {
		t.Fatalf("NewLocatorRef() = %q, %v", ref.String(), err)
	}
	for _, invalid := range []string{"", valid + "=", strings.Replace(valid, "-", "+", 1), "src:" + valid[4:]} {
		if _, err := NewLocatorRef(invalid); !errors.Is(err, ErrInvalidLocatorRef) {
			t.Fatalf("NewLocatorRef(%q) error = %v", invalid, err)
		}
	}
}

func TestEntryRefCanonical(t *testing.T) {
	locator := mustLocatorRef(t)
	entryID := DeriveEntryID(validSourceID, "file", "object-1")
	ref, err := NewEntryRef(entryID, validSourceID, "object-1", "file", locator, IdentityStrengthObjectLifetime)
	if err != nil {
		t.Fatal(err)
	}
	if ref.SourceObjectKey != "object-1" || ref.CanonicalLocator != locator {
		t.Fatalf("entry ref = %#v", ref)
	}
	changedLocator, _ := NewLocatorRef("loc:m-KQdBGV6oTOo0uNavbxU6UH9heJBwQTseDcv_utLsE")
	projectionChanged, err := NewEntryRef(entryID, validSourceID, "object-1", "file", changedLocator, IdentityStrengthObjectLifetime)
	if err != nil || projectionChanged.EntryID != ref.EntryID {
		t.Fatalf("locator projection changed identity: %#v, %v", projectionChanged, err)
	}
	if _, err := NewEntryRef(entryID, validSourceID, "", "file", locator, IdentityStrengthStable); !errors.Is(err, ErrInvalidEntryRef) {
		t.Fatalf("empty source object key error = %v", err)
	}
	if _, err := NewEntryRef(entryID, validSourceID, "object-2", "file", locator, IdentityStrengthStable); !errors.Is(err, ErrInvalidEntryRef) {
		t.Fatalf("identity material mismatch error = %v", err)
	}
}

func TestSourceRefCanonical(t *testing.T) {
	status := mustAvailability(t, AvailabilityStateAvailable)
	ref, err := NewSourceRef(validSourceID, "localfs", "/fixture", status, IdentityStrengthLocator)
	if err != nil {
		t.Fatal(err)
	}
	if ref.ProviderType != "localfs" || ref.SourceStatus.State != AvailabilityStateAvailable {
		t.Fatalf("source ref = %#v", ref)
	}
	if _, err := NewSourceRef(validSourceID, "로컬", "key", status, IdentityStrengthLocator); !errors.Is(err, ErrInvalidSourceRef) {
		t.Fatalf("non-ASCII provider error = %v", err)
	}
}

func TestMountRefCanonical(t *testing.T) {
	path, err := NewResolvedVirtualPath("mount-local", "/local", "path-rev-1")
	if err != nil {
		t.Fatal(err)
	}
	mount, err := NewMountRef("mount-local", "workspace", validSourceID, path, mustAvailability(t, AvailabilityStateAvailable), CachePolicyLazyRebuildable)
	if err != nil {
		t.Fatal(err)
	}
	if mount.MountPoint.ParentPath() != "/" || mount.MountPoint.MountID() != "mount-local" {
		t.Fatalf("mount path metadata = %#v", mount.MountPoint)
	}
	if _, err := NewMountRef("mount-local", "workspace", validSourceID, path, mustAvailability(t, AvailabilityStateAvailable), CachePolicy("durable")); !errors.Is(err, ErrInvalidMountRef) {
		t.Fatalf("cache policy error = %v", err)
	}
}

func TestCapabilityCanonical(t *testing.T) {
	valid := Capabilities{Readable: true, Writable: true, Searchable: true, Commentable: true, Movable: true, Copyable: true, Deletable: true, Watchable: true, Streamable: true, RequiresApproval: true}
	if err := valid.ValidateCanonical(); err != nil {
		t.Fatal(err)
	}
	invalid := Capabilities{Readable: true, RequiresApproval: true}
	if err := invalid.ValidateCanonical(); !errors.Is(err, ErrInvalidCapabilities) {
		t.Fatalf("approval without mutation error = %v", err)
	}
	legacy := Capabilities{ListChildren: true}
	if err := legacy.ValidateCanonical(); !errors.Is(err, ErrInvalidCapabilities) {
		t.Fatalf("legacy capability accepted by canonical validation: %v", err)
	}
	readOnlyMutations := []Capabilities{
		{Readable: true, Writable: true}, {Readable: true, Commentable: true}, {Readable: true, Movable: true},
		{Readable: true, Copyable: true}, {Readable: true, Deletable: true}, {Readable: true, Writable: true, RequiresApproval: true},
	}
	for _, readOnly := range readOnlyMutations {
		if err := readOnly.ValidateForAvailability(AvailabilityStateReadOnly); !errors.Is(err, ErrInvalidCapabilities) {
			t.Fatalf("read-only capability error = %v for %#v", err, readOnly)
		}
	}
}

func TestAvailabilityCanonical(t *testing.T) {
	states := []AvailabilityState{AvailabilityStateAvailable, AvailabilityStateLoading, AvailabilityStateStale, AvailabilityStateOffline, AvailabilityStatePermissionDenied, AvailabilityStateSourceDeleted, AvailabilityStateUnmounted, AvailabilityStateReadOnly, AvailabilityStateError}
	for _, state := range states {
		if _, err := NewAvailability(state); err != nil {
			t.Fatalf("NewAvailability(%q): %v", state, err)
		}
	}
	if _, err := NewAvailability(AvailabilityStateUnavailable); !errors.Is(err, ErrInvalidAvailability) {
		t.Fatalf("legacy state accepted by canonical constructor: %v", err)
	}
}

func TestFreshnessCanonical(t *testing.T) {
	observed := time.Date(2026, time.August, 3, 1, 2, 3, 4, time.UTC)
	for _, state := range []FreshnessState{FreshnessStateCurrent, FreshnessStateStale, FreshnessStateUnknown} {
		if _, err := NewFreshness(state, observed, mustSourceRevision(t), nil, nil); err != nil {
			t.Fatalf("NewFreshness(%q): %v", state, err)
		}
	}
	lastSync := observed.Add(time.Minute)
	staleAfter := observed.Add(time.Hour)
	freshness, err := NewFreshness(FreshnessStateCurrent, observed, mustSourceRevision(t), &lastSync, &staleAfter)
	if err != nil {
		t.Fatal(err)
	}
	lastSync = lastSync.Add(time.Hour)
	if freshness.LastSyncAt == nil || freshness.LastSyncAt.Equal(lastSync) {
		t.Fatal("freshness aliases timestamp input")
	}
	before := observed.Add(-time.Nanosecond)
	if _, err := NewFreshness(FreshnessStateStale, observed, mustSourceRevision(t), nil, &before); !errors.Is(err, ErrInvalidFreshness) {
		t.Fatalf("stale_after before observed_at error = %v", err)
	}
}

func TestRevisionValidateBeforeClone(t *testing.T) {
	oversized := strings.Repeat("x", 16*1024*1024)
	if _, err := NewRevision(RevisionStrengthProvider, &oversized); !errors.Is(err, ErrInvalidRevision) {
		t.Fatalf("oversized revision error = %v", err)
	}
	direct := Revision{Strength: RevisionStrengthProvider, Token: &oversized}
	if _, err := NewSourceRevision(direct); !errors.Is(err, ErrInvalidSourceRevision) {
		t.Fatalf("oversized source revision error = %v", err)
	}
}

func TestRevisionAxesCanonical(t *testing.T) {
	source := mustSourceRevision(t)
	observed, err := NewObservedRevision(7)
	if err != nil {
		t.Fatal(err)
	}
	if source.Revision.Strength == RevisionStrengthObserved || observed.Sequence != 7 {
		t.Fatalf("revision axes collapsed: %#v %#v", source, observed)
	}
	if _, err := NewObservedRevision(0); !errors.Is(err, ErrInvalidObservedRevision) {
		t.Fatalf("zero observed revision error = %v", err)
	}
	maximumObserved := "18446744073709551615"
	if _, err := NewRevision(RevisionStrengthObserved, &maximumObserved); err != nil {
		t.Fatalf("maximum observed token error = %v", err)
	}
	overflowObserved := "18446744073709551616"
	if _, err := NewRevision(RevisionStrengthObserved, &overflowObserved); !errors.Is(err, ErrInvalidRevision) {
		t.Fatalf("overflow observed token error = %v", err)
	}
	if _, err := NewSourceRevision(Revision{Strength: RevisionStrengthObserved, Token: stringPointer("1")}); !errors.Is(err, ErrInvalidSourceRevision) {
		t.Fatalf("observed accepted as source revision: %v", err)
	}
}

func TestEntrySnapshotCanonical(t *testing.T) {
	ref := mustEntryRef(t)
	observedAt := time.Date(2026, time.August, 3, 1, 2, 3, 4, time.UTC)
	definition := validTextDefinition()
	value := mustCanonicalPropertyValue(t, definition, ref.EntryID, TextPayload("title"))
	properties := []PropertyValue{value}
	snapshot, err := NewCanonicalEntrySnapshot(ref, "notes.txt", nil, properties, mustSourceRevision(t), ObservedRevision{Sequence: 1}, observedAt, nil, mustAvailability(t, AvailabilityStateAvailable), mustFreshness(t, observedAt))
	if err != nil {
		t.Fatal(err)
	}
	properties[0].PropertyID = "mutated"
	if snapshot.CanonicalProperties[0].PropertyID != definition.PropertyID {
		t.Fatal("snapshot aliases property input")
	}
	legacyHybrid := snapshot
	legacyHybrid.Name = "legacy"
	if err := legacyHybrid.ValidateCanonical(); !errors.Is(err, ErrInvalidEntrySnapshot) {
		t.Fatalf("canonical snapshot accepted legacy fields: %v", err)
	}
	nonUTC := observedAt.In(time.FixedZone("offset", 9*60*60))
	nonUTCSnapshot := snapshot
	nonUTCSnapshot.CanonicalModifiedAt = &nonUTC
	if err := nonUTCSnapshot.ValidateCanonical(); !errors.Is(err, ErrInvalidEntrySnapshot) {
		t.Fatalf("canonical snapshot accepted non-UTC timestamp: %v", err)
	}
	mismatchedProperties := cloneCanonicalPropertyValues(snapshot.CanonicalProperties)
	mismatchedProperties[0].EntryID = "ent:m-KQdBGV6oTOo0uNavbxU6UH9heJBwQTseDcv_utLsE"
	if _, err := NewCanonicalEntrySnapshot(ref, "notes.txt", nil, mismatchedProperties, mustSourceRevision(t), ObservedRevision{Sequence: 1}, observedAt, nil, mustAvailability(t, AvailabilityStateAvailable), mustFreshness(t, observedAt)); !errors.Is(err, ErrInvalidEntrySnapshot) {
		t.Fatalf("snapshot consistency error = %v", err)
	}
}

func TestCanonicalAccessContext(t *testing.T) {
	path, err := NewResolvedVirtualPath("mount-local", "/local/notes.txt", "path-rev-1")
	if err != nil {
		t.Fatal(err)
	}
	display := "Local/Notes"
	context, err := NewCanonicalAccessContext(validSourceID, "mount-local", path, &display, Capabilities{Readable: true})
	if err != nil {
		t.Fatal(err)
	}
	display = "mutated"
	if context.DisplayPath == nil || *context.DisplayPath != "Local/Notes" {
		t.Fatalf("display path alias: %#v", context.DisplayPath)
	}
	if _, err := NewCanonicalAccessContext(validSourceID, "other", path, nil, Capabilities{Readable: true}); !errors.Is(err, ErrInvalidAccessContext) {
		t.Fatalf("mount mismatch error = %v", err)
	}
}

func TestEntrySnapshotAggregateBudget(t *testing.T) {
	ref := mustEntryRef(t)
	definition := validTextDefinition()
	definition.Cardinality = PropertyCardinalityMany
	items := make([]string, 256)
	for index := range items {
		items[index] = strings.Repeat("x", 16384)
	}
	first := mustCanonicalPropertyValue(t, definition, ref.EntryID, TextManyPayload(items))
	secondDefinition := definition
	secondDefinition.PropertyID = "property.second"
	secondDefinition.Key = "second"
	second := mustCanonicalPropertyValue(t, secondDefinition, ref.EntryID, TextManyPayload(items))
	observedAt := time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC)
	if _, err := NewCanonicalEntrySnapshot(ref, "large", nil, []PropertyValue{first, second}, mustSourceRevision(t), ObservedRevision{Sequence: 1}, observedAt, nil, mustAvailability(t, AvailabilityStateAvailable), mustFreshness(t, observedAt)); !errors.Is(err, ErrInvalidEntrySnapshot) {
		t.Fatalf("aggregate snapshot budget error = %v", err)
	}
}

func TestEntrySnapshotNestedBudgetWithinCanonicalRevisionLimit(t *testing.T) {
	ref := mustEntryRef(t)
	observedAt := time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC)
	token := strings.Repeat("r", 128)
	revision, err := NewRevision(RevisionStrengthProvider, &token)
	if err != nil {
		t.Fatal(err)
	}
	sourceRevision, err := NewSourceRevision(revision)
	if err != nil {
		t.Fatal(err)
	}
	properties := make([]PropertyValue, 256)
	for index := range properties {
		definition := validTextDefinition()
		definition.PropertyID = fmt.Sprintf("property.%03d", index)
		definition.Key = fmt.Sprintf("p%03d", index)
		properties[index], err = NewPropertyValue(definition, ref.EntryID, PropertyStateValue, PropertyProvenanceSystem, observedAt, sourceRevision, false, TextPayload(strings.Repeat("x", 16384)))
		if err != nil {
			t.Fatal(err)
		}
	}
	freshness, err := NewFreshness(FreshnessStateCurrent, observedAt, sourceRevision, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := NewCanonicalEntrySnapshot(ref, "large", nil, properties, sourceRevision, ObservedRevision{Sequence: 1}, observedAt, nil, mustAvailability(t, AvailabilityStateAvailable), freshness); err != nil {
		t.Fatalf("canonical nested budget error = %v", err)
	}
}

func TestEntrySnapshotFreshnessDefensiveCopy(t *testing.T) {
	ref := mustEntryRef(t)
	observedAt := time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC)
	token := "provider-revision"
	revision, err := NewRevision(RevisionStrengthProvider, &token)
	if err != nil {
		t.Fatal(err)
	}
	sourceRevision, err := NewSourceRevision(revision)
	if err != nil {
		t.Fatal(err)
	}
	lastSync := observedAt
	staleAfter := observedAt.Add(time.Hour)
	freshness, err := NewFreshness(FreshnessStateCurrent, observedAt, sourceRevision, &lastSync, &staleAfter)
	if err != nil {
		t.Fatal(err)
	}
	property := mustCanonicalPropertyValue(t, validTextDefinition(), ref.EntryID, TextPayload("title"))
	snapshot, err := NewCanonicalEntrySnapshot(ref, "notes.txt", nil, []PropertyValue{property}, sourceRevision, ObservedRevision{Sequence: 1}, observedAt, nil, mustAvailability(t, AvailabilityStateAvailable), freshness)
	if err != nil {
		t.Fatal(err)
	}
	*freshness.LastSyncAt = freshness.LastSyncAt.Add(time.Hour)
	*freshness.StaleAfter = freshness.StaleAfter.Add(time.Hour)
	*freshness.SourceRevision.Revision.Token = "mutated"
	if snapshot.Freshness.LastSyncAt.Equal(*freshness.LastSyncAt) || snapshot.Freshness.StaleAfter.Equal(*freshness.StaleAfter) || *snapshot.Freshness.SourceRevision.Revision.Token != "provider-revision" {
		t.Fatalf("snapshot freshness aliases input: %#v", snapshot.Freshness)
	}
}

const validEntryID = "ent:8kHitBFXUPx-VG4Qf_M3LXM1kDu4jXaGZ1JTw9cUiyY"

func mustLocatorRef(t *testing.T) LocatorRef {
	t.Helper()
	value, err := NewLocatorRef("loc:8kHitBFXUPx-VG4Qf_M3LXM1kDu4jXaGZ1JTw9cUiyY")
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func mustEntryRef(t *testing.T) EntryRef {
	t.Helper()
	entryID := DeriveEntryID(validSourceID, "file", "object-1")
	value, err := NewEntryRef(entryID, validSourceID, "object-1", "file", mustLocatorRef(t), IdentityStrengthStable)
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func mustAvailability(t *testing.T, state AvailabilityState) Availability {
	t.Helper()
	value, err := NewAvailability(state)
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func mustSourceRevision(t *testing.T) SourceRevision {
	t.Helper()
	token := "provider-revision"
	revision, err := NewRevision(RevisionStrengthProvider, &token)
	if err != nil {
		t.Fatal(err)
	}
	value, err := NewSourceRevision(revision)
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func mustFreshness(t *testing.T, observedAt time.Time) Freshness {
	t.Helper()
	value, err := NewFreshness(FreshnessStateCurrent, observedAt, mustSourceRevision(t), nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func stringPointer(value string) *string { return &value }
