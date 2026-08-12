package schema

import (
	"bytes"
	"encoding/json"
	"testing"
)

func TestEntryListValidationRejectsApprovalWithoutActionableCapability(t *testing.T) {
	result := listResultWithApprovalWithoutActionableCapability()

	if err := result.Validate(); err == nil {
		t.Fatal("approval requirement without actionable capability accepted")
	}
}

func TestEncodeResponseRejectsApprovalWithoutActionableCapability(t *testing.T) {
	result := listResultWithApprovalWithoutActionableCapability()

	encoded := EncodeResponse(NewSuccessResponse("trusted", result))
	if !bytes.Contains(encoded, []byte(`"code":"internal_error"`)) {
		t.Fatalf("EncodeResponse() = %s, want internal_error fallback", encoded)
	}
}

func TestDecodeResponseRejectsApprovalWithoutActionableCapability(t *testing.T) {
	result := listResultWithApprovalWithoutActionableCapability()
	wire, err := json.Marshal(successWire{RequestID: "trusted", OK: true, Result: result})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := DecodeResponse(wire, MethodEntryList); err == nil {
		t.Fatalf("DecodeResponse() accepted approval without actionable capability: %s", wire)
	}
}

func listResultWithApprovalWithoutActionableCapability() EntryListResult {
	result := validLargeListResult()
	result.Entries = result.Entries[:1]
	result.Entries[0].AccessContext.Capabilities = Capabilities{
		Readable:         true,
		RequiresApproval: true,
	}
	return result
}
