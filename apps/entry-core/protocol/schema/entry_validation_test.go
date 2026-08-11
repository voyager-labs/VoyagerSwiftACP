package schema

import (
	"bytes"
	"strings"
	"testing"
)

func TestRequiredPageSize(t *testing.T) {
	t.Parallel()
	valid := `{"request_id":"id","method":"entry.list","params":{"virtual_path":"/","page_size":2,"requested_properties":[]}}`
	request, _, protocolError := DecodeRequest([]byte(valid))
	if protocolError != nil || request.EntryListParams == nil || request.EntryListParams.PageSize != 2 {
		t.Fatalf("request=%#v error=%#v", request, protocolError)
	}
	for _, params := range []string{
		`{"virtual_path":"/","requested_properties":[]}`,
		`{"virtual_path":"/","page_size":0,"requested_properties":[]}`,
		`{"virtual_path":"/","page_size":257,"requested_properties":[]}`,
		`{"virtual_path":"/","page_size":1.0,"requested_properties":[]}`,
		`{"virtual_path":"/","page_size":null,"requested_properties":[]}`,
	} {
		_, _, err := DecodeRequest([]byte(`{"request_id":"id","method":"entry.list","params":` + params + `}`))
		if err == nil || err.Code != ErrorInvalidRequest {
			t.Fatalf("accepted params %s: %#v", params, err)
		}
	}
}

func TestOpaquePageToken(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		token string
		valid bool
	}{
		{`"opaque-token"`, true}, {`""`, false}, {`null`, false}, {`"` + strings.Repeat("x", 4097) + `"`, false},
	} {
		wire := []byte(`{"request_id":"id","method":"entry.list","params":{"virtual_path":"/","page_size":1,"page_token":` + tc.token + `,"requested_properties":[]}}`)
		_, _, err := DecodeRequest(wire)
		if (err == nil) != tc.valid {
			t.Fatalf("token %s error=%#v", tc.token, err)
		}
	}
}

func TestRequestedProperties(t *testing.T) {
	t.Parallel()
	request, _, err := DecodeRequest([]byte(`{"request_id":"id","method":"entry.list","params":{"virtual_path":"/","page_size":1,"requested_properties":["a","z"]}}`))
	if err != nil || request.EntryListParams == nil || len(request.EntryListParams.RequestedProperties) != 2 || request.EntryListParams.RequestedProperties[0] != "a" {
		t.Fatalf("request=%#v error=%#v", request, err)
	}
	for _, properties := range []string{`null`, `["z","a"]`, `["a","a"]`, `[""]`, `[null]`} {
		wire := []byte(`{"request_id":"id","method":"entry.list","params":{"virtual_path":"/","page_size":1,"requested_properties":` + properties + `}}`)
		_, _, protocolError := DecodeRequest(wire)
		if protocolError == nil || protocolError.Code != ErrorInvalidRequest {
			t.Fatalf("accepted %s", properties)
		}
	}
}

func TestEntryResolveRequest(t *testing.T) {
	t.Parallel()
	valid := `{"request_id":"id","method":"entry.resolve","params":{"virtual_path":"/local/a","requested_properties":[]}}`
	request, _, err := DecodeRequest([]byte(valid))
	if err != nil || request.EntryResolveParams == nil || request.EntryResolveParams.VirtualPath == nil {
		t.Fatalf("request=%#v error=%#v", request, err)
	}
	for _, params := range []string{
		`{"requested_properties":[]}`,
		`{"virtual_path":"/a","mount_id":"m","requested_properties":[]}`,
		`{"virtual_path":"/a","entry_ref":{},"requested_properties":[]}`,
	} {
		_, _, protocolError := DecodeRequest([]byte(`{"request_id":"id","method":"entry.resolve","params":` + params + `}`))
		if protocolError == nil {
			t.Fatalf("accepted resolve params %s", params)
		}
	}
}

func TestSelectorErrorsUseInvalidSelector(t *testing.T) {
	t.Parallel()
	for _, request := range []string{
		`{"request_id":"id","method":"entry.list","params":{"virtual_path":"/","parent_ref":` + testEntryRefJSON() + `,"page_size":1,"requested_properties":[]}}`,
		`{"request_id":"id","method":"entry.list","params":{"mount_id":"m","source_instance_id":"` + testSourceID + `","virtual_path":"/","page_size":1,"requested_properties":[]}}`,
		`{"request_id":"id","method":"entry.resolve","params":{"virtual_path":"/","mount_id":"m","requested_properties":[]}}`,
		`{"request_id":"id","method":"entry.resolve","params":{"entry_ref":` + testEntryRefJSON() + `,"requested_properties":[]}}`,
	} {
		_, _, protocolError := DecodeRequest([]byte(request))
		if protocolError == nil || protocolError.Code != ErrorInvalidSelector {
			t.Fatalf("error=%#v request=%s", protocolError, request)
		}
	}
}

func TestDerivedHasMore(t *testing.T) {
	t.Parallel()
	base := emptyListResponse(false, "")
	if _, err := DecodeResponse([]byte(base), MethodEntryList); err != nil {
		t.Fatalf("valid empty result: %v", err)
	}
	contradictory := strings.Replace(base, `"has_more":false`, `"next_page_token":"token","has_more":false`, 1)
	if _, err := DecodeResponse([]byte(contradictory), MethodEntryList); err == nil {
		t.Fatal("contradictory has_more accepted")
	}
}

func TestCanonicalErrors(t *testing.T) {
	t.Parallel()
	for _, code := range []ErrorCode{ErrorInvalidSelector, ErrorContextMismatch, ErrorScopeTooLarge, ErrorInvalidPageToken, ErrorPermissionDenied, ErrorSourceUnavailable, ErrorSourceDeleted, ErrorEntryNotFound, ErrorUnsupported, ErrorConflict} {
		encoded := EncodeResponse(NewErrorResponse("id", code))
		if bytes.Contains(encoded, []byte(`"code":"internal_error"`)) {
			t.Fatalf("canonical code %q rejected: %s", code, encoded)
		}
	}
}

func TestSizeCeiling(t *testing.T) {
	t.Parallel()
	wire := []byte(`{"request_id":"id","method":"entry.list","params":{"virtual_path":"/","page_size":1,"requested_properties":[]}}`)
	atLimit := append(wire, bytes.Repeat([]byte{' '}, MaxWireBytes-len(wire))...)
	if _, _, err := DecodeRequest(atLimit); err != nil {
		t.Fatalf("at limit: %#v", err)
	}
	if _, _, err := DecodeRequest(append(atLimit, ' ')); err == nil || err.Code != ErrorRequestTooLarge {
		t.Fatalf("over limit: %#v", err)
	}
}
