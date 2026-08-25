package sqlite

// VOY-765 property 저장소의 실패 닫기 계약 테스트다. 물리 제약(FK/CHECK/
// UNIQUE), 참조 고아, cross-workspace, 중복 ordinal, 원자적 롤백을 증명한다.

import (
	"context"
	"errors"
	"testing"
	"time"

	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

func TestPropertyRepositoryFailClosed(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)
	repo := NewEntryPropertyRepository(store)

	// cross-workspace 쓰기 거절.
	stranger := domainentry.WorkspaceContext{ID: domainentry.WorkspaceID([16]byte{1, 2, 3})}
	text := "x"
	foreignFact := domainentry.ImplicitUnsetEntryPropertyAssignment(stranger.ID, testEntryID(500), fx.textDef)
	foreignFact.RecordRevision = 1
	foreignFact.ValueContractRevision = 1
	foreignFact.State = domainentry.AssignmentStateValue
	foreignFact.Scalar = &domainentry.AssignmentValue{Text: &text}
	if err := repo.SaveAssignments(ctx, fx.wsctx, []domainentry.EntryPropertyAssignment{foreignFact}); !errors.Is(err, ErrEntryPropertyWorkspaceMismatch) {
		t.Fatalf("cross-workspace write = %v, want ErrEntryPropertyWorkspaceMismatch", err)
	}

	// 비활성 옵션 참조: 도메인은 many 값에만 active 검사를 적용하고 scalar
	// option_ref는 read-back 보존을 허용한다. 저장소는 도메인을 그대로 따른다.
	disabled := fx.optionOff
	inactiveFact := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, testEntryID(501), fx.selectDef)
	inactiveFact.RecordRevision = 1
	inactiveFact.ValueContractRevision = 1
	inactiveFact.State = domainentry.AssignmentStateValue
	inactiveFact.Scalar = &domainentry.AssignmentValue{OptionID: &disabled}
	if err := repo.SaveAssignments(ctx, fx.wsctx, []domainentry.EntryPropertyAssignment{inactiveFact}); err != nil {
		t.Fatalf("scalar inactive-option write = %v, want preserved per domain semantics", err)
	}
	loadedInactive, err := repo.LoadAssignments(ctx, fx.wsctx, []string{inactiveFact.EntryID}, []domainentry.PropertyID{fx.selectDef})
	gotInactive := loadedInactive[EntryPropertyRef{EntryID: inactiveFact.EntryID, PropertyID: fx.selectDef}]
	if gotInactive.Scalar == nil || gotInactive.Scalar.OptionID == nil || *gotInactive.Scalar.OptionID != disabled {
		t.Fatalf("scalar inactive-option round-trip broken: %+v", gotInactive.Scalar)
	}

	// many 값의 비활성 옵션 참조는 쓰기 시점에 거절된다(도메인 active 검사).
	inactiveMany := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, testEntryID(512), fx.multiDef)
	inactiveMany.RecordRevision = 1
	inactiveMany.ValueContractRevision = 1
	inactiveMany.State = domainentry.AssignmentStateValue
	inactiveMany.Many = []domainentry.OrderedAssignmentValue{{Ordinal: 0, Value: domainentry.AssignmentValue{OptionID: &disabled}}}
	if err := repo.SaveAssignments(ctx, fx.wsctx, []domainentry.EntryPropertyAssignment{inactiveMany}); !errors.Is(err, domainentry.ErrAssignmentInactiveOption) {
		t.Fatalf("many inactive-option write = %v, want ErrAssignmentInactiveOption", err)
	}

	// unknown 정의 쓰기 거절.
	ghost := domainentry.MustPropertyID("bbbbbbbb-cccc-5ddd-8eee-ffff00001111")
	unknownFact := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, testEntryID(502), ghost)
	unknownFact.RecordRevision = 1
	unknownFact.ValueContractRevision = 1
	unknownFact.State = domainentry.AssignmentStateUnset
	if err := repo.SaveAssignments(ctx, fx.wsctx, []domainentry.EntryPropertyAssignment{unknownFact}); !errors.Is(err, ErrEntryPropertyDefinitionMissing) {
		t.Fatalf("unknown definition write = %v, want ErrEntryPropertyDefinitionMissing", err)
	}

	// 같은 호출 안의 중복 참조 거절.
	dupFact := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, testEntryID(503), fx.textDef)
	dupFact.RecordRevision = 1
	dupFact.ValueContractRevision = 1
	dupFact.State = domainentry.AssignmentStateUnset
	err = repo.SaveAssignments(ctx, fx.wsctx, []domainentry.EntryPropertyAssignment{dupFact, dupFact})
	if !errors.Is(err, ErrDuplicateAssignmentRef) {
		t.Fatalf("duplicate ref write = %v, want ErrDuplicateAssignmentRef", err)
	}

	// FK를 우회해 심은 고아 값 행과 tombstoned 정의 header는 read에서 실패 닫기.
	if _, err := store.SQLDB().ExecContext(ctx, "PRAGMA foreign_keys = OFF"); err != nil {
		t.Fatalf("disable FK: %v", err)
	}
	orphanInsert := `INSERT INTO entry_property_assignment_values
		 (workspace_id, entry_id, property_id, ordinal, value_kind, text_value, created_at, updated_at)
		 VALUES (?, ?, ?, 0, 'text', 'orphan', datetime('now'), datetime('now'))`
	if _, err := store.SQLDB().ExecContext(ctx, orphanInsert,
		fx.wsctx.ID.Bytes(), testEntryID(510), fx.textDef.Bytes()); err != nil {
		t.Fatalf("seed orphan value: %v", err)
	}
	if _, err := store.SQLDB().ExecContext(ctx, "PRAGMA foreign_keys = ON"); err != nil {
		t.Fatalf("enable FK: %v", err)
	}
	if _, err := repo.LoadAssignments(ctx, fx.wsctx, []string{testEntryID(510)}, nil); !errors.Is(err, ErrEntryPropertyOrphanRef) {
		t.Fatalf("orphan value load = %v, want ErrEntryPropertyOrphanRef", err)
	}

	tombstoned := domainentry.MustPropertyID("cccccccc-dddd-5eee-8fff-000011112222")
	now := time.Now()
	tombRow := WorkspacePropertyDefinitionRow{
		WorkspaceID: fx.wsctx.ID.Bytes(), PropertyID: tombstoned.Bytes(),
		Origin: "built_in", IdentityScheme: "registry_derived",
		Namespace: "test", CanonicalKey: "voy765.tombstoned",
		DisplayName: "tombstoned", Description: "",
		ValueType: "text", Cardinality: "one",
		Nullable: false, Editable: true,
		DefaultHidden: false, DefaultPinned: false, DBIndexedHint: false,
		Provenance: "system", Unit: "",
		DefinitionRev: 1, LifecycleState: "tombstoned",
		CreatedAt: now, UpdatedAt: now,
	}
	if err := store.db.WithContext(ctx).Create(&tombRow).Error; err != nil {
		t.Fatalf("insert tombstoned def: %v", err)
	}
	if _, err := store.SQLDB().ExecContext(ctx,
		`INSERT INTO entry_property_assignments
		 (workspace_id, entry_id, property_id, target_kind, state, record_revision, value_contract_revision, created_at, updated_at)
		 VALUES (?, ?, ?, 'core_native', 'unset', 1, 1, datetime('now'), datetime('now'))`,
		fx.wsctx.ID.Bytes(), testEntryID(511), tombstoned.Bytes()); err != nil {
		t.Fatalf("seed tombstoned-header assignment: %v", err)
	}
	if _, err := repo.LoadAssignments(ctx, fx.wsctx, []string{testEntryID(511)}, nil); !errors.Is(err, ErrEntryPropertyOrphanRef) {
		t.Fatalf("tombstoned-definition header load = %v, want ErrEntryPropertyOrphanRef", err)
	}
}

func TestPropertyWriteRollbackAtomic(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)
	repo := NewEntryPropertyRepository(store)

	validFact := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, testEntryID(600), fx.textDef)
	validFact.RecordRevision = 1
	validFact.ValueContractRevision = 1
	validFact.State = domainentry.AssignmentStateUnset

	// tx 내부에서 header 쓰기 성공 뒤 강제 실패: 전체 롤백을 증명한다.
	if err := store.WithinTx(ctx, func(tx *gorm.DB) error {
		if err := WriteEntryPropertyAssignments(tx, fx.wsctx, []domainentry.EntryPropertyAssignment{validFact}); err != nil {
			return err
		}
		return errors.New("boom")
	}); err == nil {
		t.Fatal("injected failure did not fail the transaction")
	}
	loaded, err := repo.LoadAssignments(ctx, fx.wsctx, []string{validFact.EntryID}, []domainentry.PropertyID{fx.textDef})
	if err != nil {
		t.Fatalf("LoadAssignments after rollback: %v", err)
	}
	ref := EntryPropertyRef{EntryID: validFact.EntryID, PropertyID: fx.textDef}
	if loaded[ref].RecordRevision != 0 {
		t.Fatalf("rolled-back assignment survived: %+v", loaded[ref])
	}

	// 진입점 수준에서도 부분 상태가 남지 않는다(두 번째 fact가 실패).
	ghost := domainentry.MustPropertyID("dddddddd-eeee-5fff-8000-111122223333")
	invalidFact := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, testEntryID(601), ghost)
	invalidFact.RecordRevision = 1
	invalidFact.ValueContractRevision = 1
	invalidFact.State = domainentry.AssignmentStateUnset
	if err := repo.SaveAssignments(ctx, fx.wsctx, []domainentry.EntryPropertyAssignment{validFact, invalidFact}); err == nil {
		t.Fatal("SaveAssignments with invalid second fact succeeded")
	}
	loaded, err = repo.LoadAssignments(ctx, fx.wsctx, []string{validFact.EntryID}, []domainentry.PropertyID{fx.textDef})
	if err != nil {
		t.Fatalf("LoadAssignments after partial save: %v", err)
	}
	if loaded[ref].RecordRevision != 0 {
		t.Fatalf("partial-save assignment survived: %+v", loaded[ref])
	}
}
