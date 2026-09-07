package main

import (
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// TestAssignmentFactOverlayConversion은 assignment fact에서 overlay PropertyValue로의
// 사상 표를 고정한다. unset fact는 overlay 단계에서 생략되며 변환기는 실패 닫기한다.
func TestAssignmentFactOverlayConversion(t *testing.T) {
	textDefinition := domainentry.WorkspacePropertyDefinition{
		PropertyID:     domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12301"),
		Origin:         domainentry.PropertyOriginUserDefined,
		IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
		Namespace:      "test",
		CanonicalKey:   "overlay_text",
		DisplayName:    "Overlay Text",
		Lifecycle:      domainentry.PropertyLifecycleActive,
		ValueType:      domainentry.PropertyTypeText,
		Cardinality:    domainentry.PropertyCardinalityOne,
		Nullable:       true,
		Editable:       true,
		Provenance:     domainentry.PropertyProvenanceUserDefined,
		DefinitionRev:  1,
	}
	selectDefinition := textDefinition
	selectDefinition.PropertyID = domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12302")
	selectDefinition.CanonicalKey = "overlay_select"
	selectDefinition.ValueType = domainentry.PropertyTypeSelect
	manyDefinition := textDefinition
	manyDefinition.PropertyID = domainentry.MustPropertyID("0198dead-beef-7000-8000-3b9ac9e12304")
	manyDefinition.CanonicalKey = "overlay_tags"
	manyDefinition.Cardinality = domainentry.PropertyCardinalityMany

	entryID := domainentry.DeriveEntryID("src:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "file", "object")
	optionID := domainentry.MustPropertyOptionID("0198dead-beef-7000-8000-3b9ac9e12303")
	text := "cached value"
	observedAt := time.Unix(10, 0).UTC()
	revision := mustUnknownRevision(t)
	sourceRevision, revisionErr := domainentry.NewSourceRevision(revision)
	if revisionErr != nil {
		t.Fatal(revisionErr)
	}
	observation := overlayObservation{observedAt: observedAt, sourceRevision: sourceRevision}

	tests := []struct {
		name          string
		definition    domainentry.WorkspacePropertyDefinition
		fact          domainentry.EntryPropertyAssignment
		wantState     domainentry.PropertyState
		wantText      *string
		wantSelect    *string
		wantManyFirst string
		wantErr       bool
	}{
		{
			name:       "text value fact maps to text payload",
			definition: textDefinition,
			fact: domainentry.EntryPropertyAssignment{
				EntryID: entryID, PropertyID: textDefinition.PropertyID,
				State: domainentry.AssignmentStateValue, RecordRevision: 1, ValueContractRevision: 1,
				Scalar: &domainentry.AssignmentValue{Text: &text},
			},
			wantState: domainentry.PropertyStateValue,
			wantText:  &text,
		},
		{
			name:       "null fact maps to null state with empty payload",
			definition: textDefinition,
			fact: domainentry.EntryPropertyAssignment{
				EntryID: entryID, PropertyID: textDefinition.PropertyID,
				State: domainentry.AssignmentStateNull, RecordRevision: 1, ValueContractRevision: 1,
			},
			wantState: domainentry.PropertyStateNull,
		},
		{
			name:       "select value fact maps to option ref payload",
			definition: selectDefinition,
			fact: domainentry.EntryPropertyAssignment{
				EntryID: entryID, PropertyID: selectDefinition.PropertyID,
				State: domainentry.AssignmentStateValue, RecordRevision: 1, ValueContractRevision: 1,
				Scalar: &domainentry.AssignmentValue{OptionID: &optionID},
			},
			wantState:  domainentry.PropertyStateValue,
			wantSelect: strPtr(optionID.String()),
		},
		{
			name:       "ordered many fact preserves member order",
			definition: manyDefinition,
			fact: domainentry.EntryPropertyAssignment{
				EntryID: entryID, PropertyID: manyDefinition.PropertyID,
				State: domainentry.AssignmentStateValue, RecordRevision: 1, ValueContractRevision: 1,
				Many: []domainentry.OrderedAssignmentValue{{Ordinal: 0, Value: domainentry.AssignmentValue{Text: &text}}},
			},
			wantState:     domainentry.PropertyStateValue,
			wantManyFirst: text,
		},
		{
			name:       "unset fact fails closed in converter",
			definition: textDefinition,
			fact: domainentry.EntryPropertyAssignment{
				EntryID: entryID, PropertyID: textDefinition.PropertyID,
				State: domainentry.AssignmentStateUnset, RecordRevision: 1, ValueContractRevision: 1,
			},
			wantErr: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			value, err := assignmentFactToPropertyValue(test.definition, test.fact, observation)
			if test.wantErr {
				if err == nil {
					t.Fatal("assignmentFactToPropertyValue() error = nil, want failure")
				}
				return
			}
			if err != nil {
				t.Fatalf("assignmentFactToPropertyValue() error = %v", err)
			}
			if value.State != test.wantState {
				t.Fatalf("state = %q, want %q", value.State, test.wantState)
			}
			if test.wantText != nil && (value.Payload.Text == nil || *value.Payload.Text != *test.wantText) {
				t.Fatalf("payload text = %v, want %q", value.Payload.Text, *test.wantText)
			}
			if test.wantSelect != nil && (value.Payload.Select == nil || *value.Payload.Select != *test.wantSelect) {
				t.Fatalf("payload select = %v, want %q", value.Payload.Select, *test.wantSelect)
			}
			if test.wantManyFirst != "" {
				if value.Payload.TextMany == nil || len(*value.Payload.TextMany) != 1 || (*value.Payload.TextMany)[0] != test.wantManyFirst {
					t.Fatalf("payload text many = %v, want [%q]", value.Payload.TextMany, test.wantManyFirst)
				}
			}
		})
	}
}

func mustUnknownRevision(t *testing.T) domainentry.Revision {
	t.Helper()
	revision, err := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	if err != nil {
		t.Fatal(err)
	}
	return revision
}

func strPtr(value string) *string { return &value }
