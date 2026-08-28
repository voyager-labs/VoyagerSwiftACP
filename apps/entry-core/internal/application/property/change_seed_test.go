package property

import (
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// mustUnknownPropertyID는 유효한 UUIDv7 형식이지만 어느 정의에도 없는 PropertyID를
// 만든다.
func mustUnknownPropertyID(t *testing.T) domainentry.PropertyID {
	t.Helper()
	workspaceID, err := domainentry.NewWorkspaceID()
	if err != nil {
		t.Fatal(err)
	}
	return domainentry.PropertyID(workspaceID)
}

// writeTimeContract는 카탈로그 정의와 활성 선택지로 쓰기 시점 검증 계약을 만든다.
// sqlite assignmentContractFor(writeTime=true)와 같은 규칙을 따른다.
func writeTimeContract(catalog *memCatalogStore, propertyID domainentry.PropertyID) (domainentry.AssignmentContract, bool) {
	definition, ok := catalog.defs[propertyID]
	if !ok {
		return domainentry.AssignmentContract{}, false
	}
	contract := domainentry.AssignmentContract{
		Type:        definition.ValueType,
		Cardinality: definition.Cardinality,
		Nullable:    definition.Nullable,
	}
	if contract.Type != domainentry.PropertyTypeSelect {
		return contract, true
	}
	contract.ActiveOptions = make(map[domainentry.PropertyOptionID]struct{}, len(catalog.opts[propertyID]))
	for _, option := range catalog.opts[propertyID] {
		if option.Active {
			contract.ActiveOptions[option.OptionID] = struct{}{}
		}
	}
	return contract, true
}

// mustSeedFact는 검증된 내구 assignment fact를 커밋된 상태로 심는다.
func mustSeedFact(
	t *testing.T,
	catalog *memCatalogStore,
	facts *memFactStore,
	workspace domainentry.WorkspaceContext,
	entryID string,
	propertyID domainentry.PropertyID,
	state domainentry.AssignmentState,
	revision int,
	scalar *domainentry.AssignmentValue,
	many []domainentry.OrderedAssignmentValue,
) {
	t.Helper()
	contract, ok := writeTimeContract(catalog, propertyID)
	if !ok {
		t.Fatalf("unknown property fixture %s", propertyID)
	}
	fact, err := domainentry.NewEntryPropertyAssignment(domainentry.EntryPropertyAssignment{
		WorkspaceID:           workspace.ID,
		EntryID:               entryID,
		PropertyID:            propertyID,
		TargetKind:            domainentry.AssignmentTargetLocatorDerived,
		State:                 state,
		RecordRevision:        domainentry.RecordRevision(revision),
		ValueContractRevision: 1,
		Scalar:                scalar,
		Many:                  many,
	}, contract)
	if err != nil {
		t.Fatal(err)
	}
	facts.facts[keyOf(fact)] = fact
}
