package schema

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

const (
	testSourceID = "src:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	testLocator  = "loc:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
)

func TestEntryListRequest(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		params string
		valid  bool
	}{
		{"virtual path", `{"virtual_path":"/","page_size":1,"requested_properties":[]}`, true},
		{"parent ref", `{"parent_ref":` + testEntryRefJSON() + `,"page_size":1,"requested_properties":[]}`, true},
		{"mount selector", `{"mount_id":"m","virtual_path":"/m","page_size":1,"requested_properties":[]}`, true},
		{"source selector", `{"source_instance_id":"` + testSourceID + `","virtual_path":"/","page_size":1,"requested_properties":[]}`, true},
		{"both selectors", `{"mount_id":"m","source_instance_id":"` + testSourceID + `","virtual_path":"/","page_size":1,"requested_properties":[]}`, false},
		{"both roots", `{"virtual_path":"/","parent_ref":` + testEntryRefJSON() + `,"page_size":1,"requested_properties":[]}`, false},
		{"neither root", `{"page_size":1,"requested_properties":[]}`, false},
		{"client has more", `{"virtual_path":"/","page_size":1,"requested_properties":[],"has_more":false}`, false},
		{"client total", `{"virtual_path":"/","page_size":1,"requested_properties":[],"total":0}`, false},
		{"null optional", `{"virtual_path":"/","page_size":1,"requested_properties":[],"page_token":null}`, false},
		{"duplicate", `{"virtual_path":"/","virtual_path":"/x","page_size":1,"requested_properties":[]}`, false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			wire := []byte(`{"request_id":"id","method":"entry.list","params":` + tc.params + `}`)
			_, _, protocolError := DecodeRequest(wire)
			if (protocolError == nil) != tc.valid {
				t.Fatalf("error=%#v valid=%t", protocolError, tc.valid)
			}
		})
	}
}

func TestEntryResolveStrictEntryRefSelector(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		params string
		valid  bool
	}{
		{`{"entry_ref":` + testEntryRefJSON() + `,"mount_id":"m","requested_properties":[]}`, true},
		{`{"entry_ref":` + testEntryRefJSON() + `,"requested_properties":[]}`, false},
		{`{"entry_ref":` + testEntryRefJSON() + `,"mount_id":"","requested_properties":[]}`, false},
		{`{"virtual_path":"/a","mount_id":"m","requested_properties":[]}`, false},
		{`{"virtual_path":"/a","requested_properties":null}`, false},
	} {
		wire := []byte(`{"request_id":"id","method":"entry.resolve","params":` + tc.params + `}`)
		_, _, err := DecodeRequest(wire)
		if (err == nil) != tc.valid {
			t.Fatalf("params=%s error=%#v", tc.params, err)
		}
	}
}

func TestRequestParserBoundaries(t *testing.T) {
	t.Parallel()
	deep := strings.Repeat("[", maxJSONDepth+1) + strings.Repeat("]", maxJSONDepth+1)
	invalidUTF8 := append([]byte(`{"request_id":"id","method":"entry.list","params":{"virtual_path":"/","page_size":1,"requested_properties":["`), 0xff)
	invalidUTF8 = append(invalidUTF8, []byte(`"]}}`)...)
	for _, wire := range [][]byte{
		[]byte(`{"request_id":"id","method":"entry.list","params":{"virtual_path":"/","page_size":1,"requested_properties":` + deep + `}}`),
		invalidUTF8,
	} {
		if _, _, err := DecodeRequest(wire); err == nil || err.Code != ErrorInvalidRequest {
			t.Fatalf("error=%#v", err)
		}
	}
}

func TestEntryListStrictResponse(t *testing.T) {
	t.Parallel()
	valid := emptyListResponse(false, "")
	response, err := DecodeResponse([]byte(valid), MethodEntryList)
	if err != nil || response.Result.(EntryListResult).Validate() != nil {
		t.Fatalf("valid response: %#v %v", response, err)
	}
	for _, wire := range []string{
		strings.Replace(valid, `"has_more":false`, `"has_more":true`, 1),
		strings.Replace(valid, `"warnings":[]`, `"warnings":null`, 1),
		strings.Replace(valid, `"entries":[]`, `"entries":null`, 1),
		strings.Replace(valid, `"has_more":false`, `"has_more":false,"has_more":false`, 1),
		strings.Replace(valid, `"warnings":[]`, `"warnings":[],"provider_cursor":"x"`, 1),
		strings.Replace(valid, `"warnings":[]`, `"warnings":[{"source_instance_id":"`+testSourceID+`","mount_id":"m","code":"future","message":"","retryable":false}]`, 1),
	} {
		if _, err := DecodeResponse([]byte(wire), MethodEntryList); err == nil {
			t.Fatalf("invalid response accepted: %s", wire)
		}
	}
	zeroScope := `{"request_id":"id","ok":true,"result":{"entries":[],"has_more":false,"observed_at":"2026-08-03T00:00:00Z","source_revision":[],"availability":[],"freshness":[],"warnings":[]}}`
	if _, err := DecodeResponse([]byte(zeroScope), MethodEntryList); err == nil {
		t.Fatal("zero-scope success accepted")
	}
}

func TestEntryResponseRejectsNonCanonicalVirtualPath(t *testing.T) {
	result := validLargeListResult()
	result.Entries = result.Entries[:1]
	for _, path := range []string{"relative/path", "//m/object", "/m/../object", "/m/./object", "/m/object/"} {
		result.Entries[0].AccessContext.VirtualPath = path
		if err := result.Validate(); err == nil {
			t.Fatalf("accepted virtual_path %q", path)
		}
	}
}

func TestEncodeResponseRejectsNonCanonicalSnapshotPropertyOrder(t *testing.T) {
	result := listResultWithUnsortedProperties()

	encoded := EncodeResponse(NewSuccessResponse("trusted", result))
	if !bytes.Contains(encoded, []byte(`"code":"internal_error"`)) {
		t.Fatalf("EncodeResponse() = %s, want internal_error fallback", encoded)
	}
}

func TestDecodeResponseRejectsNonCanonicalSnapshotPropertyOrder(t *testing.T) {
	result := listResultWithUnsortedProperties()
	wire, err := json.Marshal(successWire{RequestID: "trusted", OK: true, Result: result})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := DecodeResponse(wire, MethodEntryList); err == nil {
		t.Fatalf("DecodeResponse() accepted noncanonical properties: %s", wire)
	}
}

func TestEntryListEncodedSizeBoundary(t *testing.T) {
	t.Parallel()
	result := validLargeListResult()
	encoded := EncodeResponse(NewSuccessResponse("trusted", result))
	if !bytes.Contains(encoded, []byte(`"code":"internal_error"`)) || len(encoded) > MaxWireBytes {
		t.Fatalf("fallback=%s", encoded)
	}
	if entryListSuccessFitsWire("trusted", result) {
		t.Fatal("oversized response passed preflight")
	}
	result.Entries = result.Entries[:1]
	raw, err := json.Marshal(successWire{RequestID: "trusted", OK: true, Result: result})
	if err != nil || len(raw) > MaxWireBytes || wireSizeForEntryListSuccess("trusted", result) != len(raw) {
		t.Fatalf("small size err=%v len=%d", err, len(raw))
	}
}

var testEntryID = domainentry.DeriveEntryID(testSourceID, "file", "object")

func testEntryRefJSON() string {
	return `{"entry_id":"` + testEntryID + `","source_instance_id":"` + testSourceID + `","source_object_key":"object","resource_type":"file","canonical_locator":"` + testLocator + `","identity_strength":"locator"}`
}
func emptyListResponse(hasMore bool, token string) string {
	optional := ""
	if token != "" {
		optional = `,"next_page_token":"` + token + `"`
	}
	return `{"request_id":"id","ok":true,"result":{"entries":[]` + optional + `,"has_more":` + map[bool]string{true: "true", false: "false"}[hasMore] + `,"observed_at":"2026-08-03T00:00:00Z","source_revision":[{"source_instance_id":"` + testSourceID + `","mount_id":"m","source_revision":{"strength":"unknown"},"observed_revision":{"strength":"observed","token":"1"}}],"availability":[{"source_instance_id":"` + testSourceID + `","mount_id":"m","state":"available"}],"freshness":[{"source_instance_id":"` + testSourceID + `","mount_id":"m","state":"current","observed_at":"2026-08-03T00:00:00Z","source_revision":{"strength":"unknown"}}],"warnings":[]}}`
}
func validLargeListResult() EntryListResult {
	text := strings.Repeat("x", 16384)
	property := PropertyValue{PropertyID: "p", EntryID: testEntryID, ValueType: "text", Value: &PropertyPayload{kind: "text", one: text}, State: "value", Provenance: "system", ObservedAt: "2026-08-03T00:00:00Z", SourceRevision: Revision{Strength: "unknown"}, Validation: ValidationResult{Valid: true}, Cardinality: "one"}
	ref := EntryRef{testEntryID, testSourceID, "object", "file", testLocator, "locator"}
	fresh := Freshness{State: "current", ObservedAt: "2026-08-03T00:00:00Z", SourceRevision: Revision{Strength: "unknown"}}
	entry := Entry{EntryRef: ref, EntrySnapshot: EntrySnapshot{EntryRef: ref, DisplayName: "name", Properties: []PropertyValue{property}, SourceRevision: Revision{Strength: "unknown"}, ObservedRevision: Revision{Strength: "observed", Token: stringPointer("1")}, ObservedAt: "2026-08-03T00:00:00Z", Availability: Availability{State: "available"}, Freshness: fresh}, AccessContext: AccessContext{SourceInstanceID: testSourceID, MountID: "m", VirtualPath: "/m/object", Capabilities: Capabilities{Readable: true}}}
	entries := make([]Entry, 5)
	for i := range entries {
		entries[i] = entry
	}
	return EntryListResult{Entries: entries, HasMore: false, ObservedAt: "2026-08-03T00:00:00Z", SourceRevision: []RevisionSummary{{SourceInstanceID: testSourceID, MountID: "m", SourceRevision: Revision{Strength: "unknown"}, ObservedRevision: Revision{Strength: "observed", Token: stringPointer("1")}}}, Availability: []SourceAvailability{{SourceInstanceID: testSourceID, MountID: "m", State: "available"}}, Freshness: []SourceFreshness{{SourceInstanceID: testSourceID, MountID: "m", State: "current", ObservedAt: "2026-08-03T00:00:00Z", SourceRevision: Revision{Strength: "unknown"}}}, Warnings: []Warning{}}
}

func listResultWithUnsortedProperties() EntryListResult {
	result := validLargeListResult()
	result.Entries = result.Entries[:1]
	first := result.Entries[0].EntrySnapshot.Properties[0]
	first.PropertyID = "property.z"
	second := first
	second.PropertyID = "property.a"
	result.Entries[0].EntrySnapshot.Properties = []PropertyValue{first, second}
	return result
}
