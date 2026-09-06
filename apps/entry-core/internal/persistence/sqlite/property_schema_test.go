package sqlite

// 0007 property 스키마의 물리 제약 계약 테스트다. FK/CHECK/UNIQUE와 cascade
// 삭제를 PRAGMA와 제약 위반 삽입으로 증명한다.

import (
	"context"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

func TestPropertySchemaConstraints(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)
	db := store.SQLDB()

	// pragma foreign_key_list는 선언 역순으로 반환한다(0002 검사와 같은 관례).
	assertForeignKeys(t, db, "workspace_property_options", [][2]string{
		{"workspace_property_definitions", "workspace_id"},
		{"workspace_metadata", "workspace_id"},
	})
	assertForeignKeys(t, db, "entry_property_assignments", [][2]string{
		{"workspace_property_definitions", "workspace_id"},
		{"workspace_metadata", "workspace_id"},
	})
	assertForeignKeys(t, db, "entry_property_assignment_values", [][2]string{
		{"workspace_property_options", "workspace_id"},
		{"entry_property_assignments", "workspace_id"},
	})

	insertOption := func(optionID domainentry.PropertyOptionID, ws []byte, ordinal int) error {
		_, err := db.ExecContext(ctx,
			`INSERT INTO workspace_property_options
			 (workspace_id, option_id, property_id, label, color, ordinal, active, created_at, updated_at)
			 VALUES (?, ?, ?, 'X', '', ?, 1, datetime('now'), datetime('now'))`,
			ws, optionID.Bytes(), fx.selectDef.Bytes(), ordinal)
		return err
	}
	if err := insertOption(domainentry.MustPropertyOptionID("01a2b3c4-d5e6-7f83-9a0d-1c2d3e4f5a63"), fx.wsctx.ID.Bytes(), 0); err == nil {
		t.Fatal("duplicate option ordinal accepted; unique index missing")
	}
	otherWS := []byte("fedcba9876544321")
	if err := insertOption(domainentry.MustPropertyOptionID("01a2b3c4-d5e6-7f84-9a0e-1c2d3e4f5a64"), otherWS, 9); err == nil {
		t.Fatal("cross-workspace option accepted; workspace FK missing")
	}

	unknownProp := domainentry.MustPropertyID("aaaaaaaa-bbbb-5ccc-8ddd-eeeeffff0000")
	if _, err := db.ExecContext(ctx,
		`INSERT INTO entry_property_assignments
		 (workspace_id, entry_id, property_id, target_kind, state, record_revision, value_contract_revision, created_at, updated_at)
		 VALUES (?, ?, ?, 'core_native', 'unset', 1, 1, datetime('now'), datetime('now'))`,
		fx.wsctx.ID.Bytes(), testEntryID(300), unknownProp.Bytes()); err == nil {
		t.Fatal("assignment with unknown property accepted; definition FK missing")
	}
	badStateInsert := `INSERT INTO entry_property_assignments
		 (workspace_id, entry_id, property_id, target_kind, state, record_revision, value_contract_revision, created_at, updated_at)
		 VALUES (?, ?, ?, 'core_native', 'bogus', 1, 1, datetime('now'), datetime('now'))`
	if _, err := db.ExecContext(ctx, badStateInsert, fx.wsctx.ID.Bytes(), testEntryID(301), fx.textDef.Bytes()); err == nil {
		t.Fatal("invalid state accepted; CHECK missing")
	}
	if _, err := db.ExecContext(ctx,
		`INSERT INTO entry_property_assignments
		 (workspace_id, entry_id, property_id, target_kind, state, record_revision, value_contract_revision, created_at, updated_at)
		 VALUES (?, ?, ?, 'core_native', 'unset', 0, 0, datetime('now'), datetime('now'))`,
		fx.wsctx.ID.Bytes(), testEntryID(302), fx.textDef.Bytes()); err == nil {
		t.Fatal("revision 0 durable row accepted; CHECK missing")
	}
	if _, err := db.ExecContext(ctx, badStateInsert, fx.wsctx.ID.Bytes(), testEntryID(303)+"x", fx.textDef.Bytes()); err == nil {
		t.Fatal("malformed entry_id accepted; length CHECK missing")
	}

	// 값 행의 FK는 header를 요구하므로 검증 대상 앞에 header를 심는다.
	if _, err := db.ExecContext(ctx,
		`INSERT INTO entry_property_assignments
		 (workspace_id, entry_id, property_id, target_kind, state, record_revision, value_contract_revision, created_at, updated_at)
		 VALUES (?, ?, ?, 'core_native', 'value', 1, 1, datetime('now'), datetime('now'))`,
		fx.wsctx.ID.Bytes(), testEntryID(304), fx.textDef.Bytes()); err != nil {
		t.Fatalf("seed header for value check: %v", err)
	}
	valueInsert := `INSERT INTO entry_property_assignment_values
		 (workspace_id, entry_id, property_id, ordinal, value_kind, boolean_value, decimal_value,
		  date_value, timestamp_value, text_value, option_id, created_at, updated_at)
		 VALUES (?, ?, ?, 0, 'text', NULL, NULL, NULL, NULL, 'valid', NULL, datetime('now'), datetime('now'))`
	if _, err := db.ExecContext(ctx, valueInsert,
		fx.wsctx.ID.Bytes(), testEntryID(304), fx.textDef.Bytes()); err != nil {
		t.Fatalf("valid text value rejected: %v", err)
	}
	mismatchInsert := `INSERT INTO entry_property_assignment_values
		 (workspace_id, entry_id, property_id, ordinal, value_kind, boolean_value, decimal_value,
		  date_value, timestamp_value, text_value, option_id, created_at, updated_at)
		 VALUES (?, ?, ?, 0, 'text', NULL, '3.14', NULL, NULL, NULL, NULL, datetime('now'), datetime('now'))`
	if _, err := db.ExecContext(ctx, mismatchInsert,
		fx.wsctx.ID.Bytes(), testEntryID(305), fx.textDef.Bytes()); err == nil {
		t.Fatal("kind/payload mismatch accepted; XOR CHECK missing")
	}
	noPayloadInsert := `INSERT INTO entry_property_assignment_values
		 (workspace_id, entry_id, property_id, ordinal, value_kind, boolean_value, decimal_value,
		  date_value, timestamp_value, text_value, option_id, created_at, updated_at)
		 VALUES (?, ?, ?, 0, 'option_ref', NULL, NULL, NULL, NULL, NULL, NULL, datetime('now'), datetime('now'))`
	if _, err := db.ExecContext(ctx, noPayloadInsert,
		fx.wsctx.ID.Bytes(), testEntryID(306), fx.selectDef.Bytes()); err == nil {
		t.Fatal("option_ref without option_id accepted; XOR CHECK missing")
	}
}

func TestPropertyCascadeDeleteRemovesValues(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)

	text := "cascade"
	repo := NewEntryPropertyRepository(store)
	fact := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, testEntryID(400), fx.textDef)
	fact.RecordRevision = 1
	fact.ValueContractRevision = 1
	fact.State = domainentry.AssignmentStateValue
	fact.Scalar = &domainentry.AssignmentValue{Text: &text}
	if err := repo.SaveAssignments(ctx, fx.wsctx, []domainentry.EntryPropertyAssignment{fact}); err != nil {
		t.Fatalf("SaveAssignments: %v", err)
	}

	res := store.db.WithContext(ctx).
		Where("workspace_id = ? AND entry_id = ? AND property_id = ?",
			fx.wsctx.ID.Bytes(), fact.EntryID, fact.PropertyID.Bytes()).
		Delete(&EntryPropertyAssignmentRow{})
	if res.Error != nil {
		t.Fatalf("delete header: %v", res.Error)
	}
	var n int
	if err := store.SQLDB().QueryRowContext(ctx,
		"SELECT count(*) FROM entry_property_assignment_values WHERE workspace_id = ? AND entry_id = ?",
		fx.wsctx.ID.Bytes(), fact.EntryID).Scan(&n); err != nil {
		t.Fatalf("count values: %v", err)
	}
	if n != 0 {
		t.Fatalf("cascade left %d orphan value rows", n)
	}
}
