package schema

import (
	"bytes"
	"encoding/json"
	"testing"
)

func TestEntryListValidationRejectsInvalidScopeOutcomes(t *testing.T) {
	for _, test := range invalidScopeOutcomeCases() {
		t.Run(test.name, func(t *testing.T) {
			result := test.result()

			if err := result.Validate(); err == nil {
				t.Fatal("invalid scope outcome accepted")
			}
		})
	}
}

func TestEncodeResponseRejectsInvalidScopeOutcomes(t *testing.T) {
	for _, test := range invalidScopeOutcomeCases() {
		t.Run(test.name, func(t *testing.T) {
			result := test.result()

			encoded := EncodeResponse(NewSuccessResponse("trusted", result))
			if !bytes.Contains(encoded, []byte(`"code":"internal_error"`)) {
				t.Fatalf("EncodeResponse() = %s, want internal_error fallback", encoded)
			}
		})
	}
}

func TestDecodeResponseRejectsInvalidScopeOutcomes(t *testing.T) {
	for _, test := range invalidScopeOutcomeCases() {
		t.Run(test.name, func(t *testing.T) {
			result := test.result()
			wire, err := json.Marshal(successWire{RequestID: "trusted", OK: true, Result: result})
			if err != nil {
				t.Fatal(err)
			}

			if _, err := DecodeResponse(wire, MethodEntryList); err == nil {
				t.Fatalf("DecodeResponse() accepted invalid scope outcome: %s", wire)
			}
		})
	}
}

func invalidScopeOutcomeCases() []struct {
	name   string
	result func() EntryListResult
} {
	return []struct {
		name   string
		result func() EntryListResult
	}{
		{"stale scope with current freshness", listResultWithStaleScopeAndCurrentFreshness},
		{"stale scope without stale warning", listResultWithStaleScopeWithoutWarning},
		{"failed scope with current freshness", listResultWithFailedScopeAndCurrentFreshness},
	}
}

func listResultWithStaleScopeAndCurrentFreshness() EntryListResult {
	result := validLargeListResult()
	result.Entries = []Entry{}
	result.Availability[0].State = "stale"
	result.Warnings = []Warning{{
		SourceInstanceID: testSourceID,
		MountID:          "m",
		Code:             "stale_snapshot",
		Message:          warningMessage("stale_snapshot"),
	}}
	return result
}

func listResultWithStaleScopeWithoutWarning() EntryListResult {
	result := validLargeListResult()
	result.Entries = []Entry{}
	result.Availability[0].State = "stale"
	result.Freshness[0].State = "stale"
	return result
}

func listResultWithFailedScopeAndCurrentFreshness() EntryListResult {
	result := validLargeListResult()
	result.Entries = []Entry{}
	result.Availability[0] = SourceAvailability{
		SourceInstanceID: testSourceID,
		MountID:          "m",
		State:            "offline",
		Error: &SourceError{
			SourceInstanceID: testSourceID,
			MountID:          "m",
			Code:             "source_unavailable",
			Message:          sourceErrorMessage("source_unavailable"),
		},
	}
	result.SourceRevision = append(result.SourceRevision, RevisionSummary{
		SourceInstanceID: testSourceID,
		MountID:          "n",
		SourceRevision:   Revision{Strength: "unknown"},
		ObservedRevision: Revision{Strength: "observed", Token: stringPointer("1")},
	})
	result.Availability = append(result.Availability, SourceAvailability{
		SourceInstanceID: testSourceID,
		MountID:          "n",
		State:            "available",
	})
	result.Freshness = append(result.Freshness, SourceFreshness{
		SourceInstanceID: testSourceID,
		MountID:          "n",
		State:            "current",
		ObservedAt:       "2026-08-03T00:00:00Z",
		SourceRevision:   Revision{Strength: "unknown"},
	})
	return result
}
