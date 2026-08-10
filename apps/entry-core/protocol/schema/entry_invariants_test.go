package schema

import (
	"encoding/base64"
	"os"
	"strings"
	"testing"
)

func TestResponseArrayBoundsBeforeAllocation(t *testing.T) {
	source, err := os.ReadFile("entry.go")
	if err != nil {
		t.Fatal(err)
	}
	body := string(source)
	guard := strings.Index(body, "func decodeEntryListResult")
	makeSlice := strings.Index(body[guard:], "Entries: make([]Entry")
	bounds := strings.Index(body[guard:], "len(fields[\"entries\"].items) > 256")
	if makeSlice < 0 || bounds < 0 || bounds > makeSlice {
		t.Fatal("entry-list cardinality is not guarded before typed allocation")
	}
	snapshot := strings.Index(body, "func decodeEntrySnapshot")
	propertyMake := strings.Index(body[snapshot:], "Properties: make([]PropertyValue")
	propertyBound := strings.Index(body[snapshot:], "len(f[\"properties\"].items) > 256")
	if propertyMake < 0 || propertyBound < 0 || propertyBound > propertyMake {
		t.Fatal("property cardinality is not guarded before typed allocation")
	}
}

func TestMetadataRevisionDigest(t *testing.T) {
	valid := "meta:" + base64.RawURLEncoding.EncodeToString(make([]byte, 32))
	if !validRevision(Revision{Strength: "metadata", Token: &valid}) {
		t.Fatal("valid metadata digest rejected")
	}
	for _, token := range []string{"meta:" + base64.RawURLEncoding.EncodeToString(make([]byte, 31)), "meta:" + base64.RawURLEncoding.EncodeToString(make([]byte, 33)), valid + "=", "meta:" + strings.Repeat("!", 43)} {
		if validRevision(Revision{Strength: "metadata", Token: &token}) {
			t.Fatalf("invalid metadata digest accepted: %q", token)
		}
	}
}

func TestAvailabilitySourceErrorCorrespondence(t *testing.T) {
	cases := []struct {
		state, code     string
		hasError, valid bool
	}{
		{"available", "", false, true}, {"read_only", "", false, true}, {"stale", "", false, true},
		{"offline", "source_unavailable", true, true}, {"loading", "source_unavailable", true, true}, {"unmounted", "source_unavailable", true, true},
		{"permission_denied", "permission_denied", true, true}, {"source_deleted", "source_deleted", true, true}, {"error", "adapter_failure", true, true},
		{"offline", "permission_denied", true, false}, {"available", "source_unavailable", true, false},
	}
	for _, test := range cases {
		value := SourceAvailability{SourceInstanceID: testSourceID, MountID: "m", State: test.state}
		if test.hasError {
			value.Error = &SourceError{SourceInstanceID: testSourceID, MountID: "m", Code: test.code, Message: sourceErrorMessage(test.code)}
		}
		if got := validSourceAvailability(value); got != test.valid {
			t.Fatalf("state=%s code=%s got=%t", test.state, test.code, got)
		}
	}
}

func TestReadOnlyCapabilities(t *testing.T) {
	result := validLargeListResult()
	result.Entries = result.Entries[:1]
	result.Availability[0].State = "read_only"
	result.Entries[0].EntrySnapshot.Availability.State = "read_only"
	result.Entries[0].AccessContext.Capabilities = Capabilities{Readable: true, Writable: true, Movable: true, Copyable: true, Deletable: true, Commentable: true}
	if result.Validate() == nil {
		t.Fatal("read_only accepted mutation capabilities")
	}
}

func TestCanonicalEntryAPISurface(t *testing.T) {
	checks := map[string][]string{
		"entry.go":                                      {"EntryListResultFromDomain", "Cursor              *string", "NextCursor     *string"},
		"../../internal/domain/entry/model.go":          {"type EntryListResult struct", "NextCursor *string"},
		"../../internal/source/source.go":               {"type Adapter interface", "type ListRequest struct", "type SourceListResult struct", "NextCursor"},
		"../../internal/application/entry/service.go":   {"type Service struct", "func NewService(", "type ListRequest struct", "NextCursor"},
		"../../internal/source/localfs/adapter.go":      {"source.ListRequest", "source.SourceListResult", ".NextCursor"},
		"../../internal/source/fakeexternal/adapter.go": {"source.ListRequest", "source.SourceListResult", ".NextCursor"},
	}
	for path, forbiddenValues := range checks {
		source, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		for _, forbidden := range forbiddenValues {
			if strings.Contains(string(source), forbidden) {
				t.Fatalf("noncanonical API %s remains in %s", forbidden, path)
			}
		}
	}
}
