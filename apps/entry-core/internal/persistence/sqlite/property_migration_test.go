package sqlite

// 0007_entry_properties 마이그레이션 계약 테스트다. fresh replay, populated
// upgrade(기존 행 byte 보존), down/re-up, reopen 안정성을 증명한다.

import (
	"bytes"
	"context"
	"io/fs"
	"testing"
)

// fsReadEmbeddedFile은 임베디드 마이그레이션 디렉터리에서 파일 하나를 읽는다.
func fsReadEmbeddedFile(name string) (string, error) {
	raw, err := fs.ReadFile(migrationsFS, name)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

// propertyTableNames는 0007이 만드는 세 테이블이다.
var propertyTableNames = []string{
	"workspace_property_options",
	"entry_property_assignments",
	"entry_property_assignment_values",
}

func TestMigration0007EntryPropertiesFreshReplay(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)
	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp: %v", err)
	}
	assertLedger(t, store.SQLDB(), 7, false)
	for _, name := range propertyTableNames {
		assertTablePresent(t, store.SQLDB(), name)
	}
}

func TestMigration0007EntryPropertiesPopulatedUpgrade(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)
	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	// 0006까지 적용한 뒤 워크스페이스 식별 행을 채운다.
	if err := MigrateUpFS(ctx, store.SQLDB(), catalogFixtureFS(t)); err != nil {
		t.Fatalf("MigrateUpFS to version 6: %v", err)
	}
	row := []byte("0123456789abcdef")
	if _, err := store.SQLDB().ExecContext(ctx,
		`INSERT INTO workspace_metadata (singleton, workspace_id, created_at, updated_at)
		 VALUES (1, ?, datetime('now'), datetime('now'))`, row); err != nil {
		t.Fatalf("insert populated workspace row: %v", err)
	}
	before := readWorkspaceRow(t, ctx, store.SQLDB())

	// head까지 업그레이드: 0007이 적용되고 기존 행은 byte 그대로 보존된다.
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp populated 0006→head: %v", err)
	}
	assertLedger(t, store.SQLDB(), 7, false)
	for _, name := range propertyTableNames {
		assertTablePresent(t, store.SQLDB(), name)
	}
	after := readWorkspaceRow(t, ctx, store.SQLDB())
	if !bytes.Equal(after.workspaceID, before.workspaceID) {
		t.Fatalf("workspace_id = %x, want %x (row corrupted by 0007)", after.workspaceID, before.workspaceID)
	}
	if after.createdAt != before.createdAt || after.updatedAt != before.updatedAt {
		t.Fatalf("timestamps changed across 0007: before=(%q,%q) after=(%q,%q)",
			before.createdAt, before.updatedAt, after.createdAt, after.updatedAt)
	}
}

func TestMigration0007EntryPropertiesDownAndReUp(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)
	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer store.Close()

	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp: %v", err)
	}
	assertLedger(t, store.SQLDB(), 7, false)

	// .down.sql은 런타임에 실행되지 않지만 ADR-014 산출물 규약으로 유효해야
	// 한다. 임베디드 down SQL을 직접 실행해 되돌리고, 다시 up이 성공하는지
	// 증명한다.
	downSQL, err := fsReadEmbeddedFile("migrations/0007_entry_properties.down.sql")
	if err != nil {
		t.Fatalf("read embedded down: %v", err)
	}
	if _, err := store.SQLDB().ExecContext(ctx, downSQL); err != nil {
		t.Fatalf("exec down SQL: %v", err)
	}
	for _, name := range propertyTableNames {
		assertTableAbsent(t, store.SQLDB(), name)
	}

	// golang-migrate의 down은 ledger를 함께 되돌린다. 수동 down 실행이므로
	// 같은 효과를 시뮬레이션한 뒤 재적용한다.
	if _, err := store.SQLDB().ExecContext(ctx,
		"UPDATE schema_migrations SET version = 6"); err != nil {
		t.Fatalf("rewind ledger: %v", err)
	}
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("re-up after down: %v", err)
	}
	assertLedger(t, store.SQLDB(), 7, false)
	for _, name := range propertyTableNames {
		assertTablePresent(t, store.SQLDB(), name)
	}
}

func TestMigration0007EntryPropertiesReopenStable(t *testing.T) {
	ctx := context.Background()
	path := tempDBPath(t)
	store, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if err := MigrateUp(ctx, store.SQLDB()); err != nil {
		t.Fatalf("MigrateUp: %v", err)
	}
	if err := store.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	reopened, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer reopened.Close()
	assertLedger(t, reopened.SQLDB(), 7, false)
	for _, name := range propertyTableNames {
		assertTablePresent(t, reopened.SQLDB(), name)
	}
}
