package sqlite

import (
	"context"
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// 비활성(tombstoned) 정의의 기존 assignment도 읽기 경로에서 해석되어야 한다.
// canonical 계약상 disable은 신규 지정만 차단하고 과거 read-back을 보존하므로,
// 읽기 정의 조회가 tombstoned 행을 제외하면 orphan 거절로 전체 read가 실패한다.
func TestLoadEntryPropertyAssignmentsIncludesDisabledDefinitions(t *testing.T) {
	ctx := context.Background()
	store, err := Open(ctx, tempDBPath(t))
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp: %v", err)
	}

	workspace := mustWorkspaceContext(t)
	if _, err := store.SQLDB().ExecContext(ctx,
		`INSERT INTO workspace_metadata (singleton, workspace_id, created_at, updated_at)
		 VALUES (1, ?, datetime('now'), datetime('now'))`, workspace.ID.Bytes()); err != nil {
		t.Fatalf("seed workspace: %v", err)
	}

	propertyID := domainentry.PropertyID(mustWorkspaceContext(t).ID)
	now := time.Now()
	definition := domainentry.WorkspacePropertyDefinition{
		PropertyID:     propertyID,
		Origin:         domainentry.PropertyOriginUserDefined,
		IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
		Namespace:      "user",
		CanonicalKey:   "legacy",
		DisplayName:    "Legacy",
		ValueType:      domainentry.PropertyTypeText,
		Cardinality:    domainentry.PropertyCardinalityOne,
		Nullable:       true,
		Editable:       true,
		DefinitionRev:  2,
		Provenance:     domainentry.PropertyProvenanceUserDefined,
		Lifecycle:      domainentry.PropertyLifecycleTombstoned,
	}
	row, err := definitionToRow(definition, workspace.ID.Bytes(), nil, now)
	if err != nil {
		t.Fatalf("definitionToRow: %v", err)
	}
	if err := store.db.Create(&row).Error; err != nil {
		t.Fatalf("seed tombstoned definition: %v", err)
	}

	entryID := domainentry.DeriveEntryID("source-instance-1", "text", "legacy.txt")
	header := EntryPropertyAssignmentRow{
		WorkspaceID:           workspace.ID.Bytes(),
		EntryID:               entryID,
		PropertyID:            propertyID.Bytes(),
		TargetKind:            "core_native",
		State:                 "unset",
		RecordRevision:        1,
		ValueContractRevision: 1,
		CreatedAt:             now,
		UpdatedAt:             now,
	}
	if err := store.db.Create(&header).Error; err != nil {
		t.Fatalf("seed assignment header: %v", err)
	}

	facts, err := LoadEntryPropertyAssignments(store.db, workspace, []string{entryID}, []domainentry.PropertyID{propertyID})
	if err != nil {
		t.Fatalf("LoadEntryPropertyAssignments: %v", err)
	}
	fact, ok := facts[EntryPropertyRef{EntryID: entryID, PropertyID: propertyID}]
	if !ok {
		t.Fatalf("assignment fact missing for disabled definition read-back")
	}
	if fact.State != domainentry.AssignmentStateUnset {
		t.Fatalf("state = %q, want unset", fact.State)
	}
}
