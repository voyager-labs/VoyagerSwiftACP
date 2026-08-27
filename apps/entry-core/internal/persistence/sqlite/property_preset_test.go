package sqlite

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"

	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// TestPropertyPreset은 VOY-765 todo 5의 Status/Project/Priority 사전 설정
// 멱등 재조정 상태 기계 전체를 검증한다.
func TestPropertyPreset(t *testing.T) {
	t.Run("Fresh", testPropertyPresetFresh)
	t.Run("SecondRunNoOp", testPropertyPresetSecondRunNoOp)
	t.Run("IndependentDatabasesDistinctIDs", testPropertyPresetIndependentDatabasesDistinctIDs)
	t.Run("UserEditsPreserved", testPropertyPresetUserEditsPreserved)
	t.Run("OptionRenameDoesNotDuplicate", testPropertyPresetOptionRenameDoesNotDuplicate)
	t.Run("PartialMissingGainsOnlyMissing", testPropertyPresetPartialMissingGainsOnlyMissing)
	t.Run("RollbackLeavesNoPartial", testPropertyPresetRollbackLeavesNoPartial)
	t.Run("DescriptorEnumerationCompleteness", testPropertyPresetDescriptorEnumerationCompleteness)
}

// presetTestStore는 마이그레이션된 temp DB에 워크스페이스 신원을 부트스트랩한다.
func presetTestStore(t *testing.T) (*Store, domainentry.WorkspaceContext) {
	t.Helper()
	store := migratedStore(t)
	wsctx, err := store.BootstrapOrRestoreWorkspace(context.Background())
	if err != nil {
		t.Fatalf("bootstrap workspace: %v", err)
	}
	return store, wsctx
}

// loadPresetRows는 preset 네임스페이스의 정의와 그 선택지를 읽어 온다.
func loadPresetRows(t *testing.T, store *Store, wsctx domainentry.WorkspaceContext) ([]WorkspacePropertyDefinitionRow, []WorkspacePropertyOptionRow) {
	t.Helper()
	ctx := context.Background()
	var defs []WorkspacePropertyDefinitionRow
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND namespace = ?", wsctx.ID.Bytes(), propertyPresetNamespace).
		Order("canonical_key").Find(&defs).Error; err != nil {
		t.Fatalf("load preset definitions: %v", err)
	}
	var options []WorkspacePropertyOptionRow
	if len(defs) > 0 {
		if err := store.db.WithContext(ctx).
			Where("workspace_id = ?", wsctx.ID.Bytes()).
			Order("property_id, ordinal").Find(&options).Error; err != nil {
			t.Fatalf("load preset options: %v", err)
		}
	}
	return defs, options
}

// requireVoyagerIssuedDefinition은 정의 행이 voyager_issued UUIDv7 built-in
// select-one 계약을 만족하는지 검사한다.
func requireVoyagerIssuedDefinition(t *testing.T, def WorkspacePropertyDefinitionRow) {
	t.Helper()
	id, err := parsePropertyIDBlob(def.PropertyID)
	if err != nil {
		t.Fatalf("definition property_id: %v", err)
	}
	// voyager_issued 계약은 RFC 9562 version 니블 7을 요구한다(도메인
	// acceptsVersion과 동일한 규칙; unexported라 원시 니블로 검사).
	if id[6]>>4 != 0x7 {
		t.Fatalf("definition id version = %d, want 7 (voyager_issued)", id[6]>>4)
	}
	if def.IdentityScheme != string(domainentry.PropertyIdentitySchemeVoyagerIssued) ||
		def.Origin != "built_in" || def.ValueType != "select" || def.Cardinality != "one" ||
		def.LifecycleState != "active" || !def.Editable || def.Nullable {
		t.Fatalf("definition %s/%s violates the preset contract: %+v",
			def.Namespace, def.CanonicalKey, def)
	}
	if def.SeedOwner != nil || def.SeedVersion != nil || def.SeedSourceVersion != nil {
		t.Fatalf("preset definition must keep a NULL seed trio: %+v", def)
	}
}

// mustParseBlob는 16-byte BLOB을 typed PropertyID로 복사한다(테스트 전용).
func mustParseBlob(t *testing.T, raw []byte) domainentry.PropertyID {
	t.Helper()
	id, err := parsePropertyIDBlob(raw)
	if err != nil {
		t.Fatalf("parse id blob: %v", err)
	}
	return id
}

// TestPropertyPresetFresh는 첫 실행에서 정확히 세 정의와 규정된 선택지를
// 만드는지 검증한다.
func testPropertyPresetFresh(t *testing.T) {
	store, wsctx := presetTestStore(t)

	if err := store.ApplyPropertyPresets(context.Background(), wsctx); err != nil {
		t.Fatalf("ApplyPropertyPresets: %v", err)
	}

	defs, options := loadPresetRows(t, store, wsctx)
	if len(defs) != 3 {
		t.Fatalf("preset definitions = %d, want 3", len(defs))
	}
	defByKey := make(map[string]WorkspacePropertyDefinitionRow, len(defs))
	for _, def := range defs {
		requireVoyagerIssuedDefinition(t, def)
		defByKey[def.CanonicalKey] = def
	}

	wantOptions := map[string][]string{
		"status":   {"Backlog", "Todo", "In progress", "Done", "Canceled"},
		"project":  {},
		"priority": {"No priority", "Urgent", "High", "Medium", "Low"},
	}
	optionsByDef := make(map[string][]WorkspacePropertyOptionRow, len(defs))
	for _, option := range options {
		for key, def := range defByKey {
			if string(option.PropertyID) == string(def.PropertyID) {
				optionsByDef[key] = append(optionsByDef[key], option)
			}
		}
	}
	for key, wantLabels := range wantOptions {
		rows := optionsByDef[key]
		if len(rows) != len(wantLabels) {
			t.Fatalf("%s options = %d, want %d", key, len(rows), len(wantLabels))
		}
		for index, row := range rows {
			if row.Ordinal != index {
				t.Fatalf("%s option %q ordinal = %d, want %d", key, row.Label, row.Ordinal, index)
			}
			if row.Label != wantLabels[index] {
				t.Fatalf("%s option at ordinal %d = %q, want %q", key, index, row.Label, wantLabels[index])
			}
			if !row.Active || row.Color != "" {
				t.Fatalf("%s option %q must be active with unset color: %+v", key, row.Label, row)
			}
			parsed, parseErr := parsePropertyIDBlob(row.OptionID)
			if parseErr != nil {
				t.Fatalf("%s option id: %v", key, parseErr)
			}
			if _, err := domainentry.ParsePropertyOptionID(parsed.String()); err != nil {
				t.Fatalf("%s option id %s is not a valid UUIDv7 option id: %v",
					key, parsed.String(), err)
			}
			if domainentry.PropertyID(mustParseBlob(t, row.PropertyID)) !=
				domainentry.PropertyID(mustParseBlob(t, defByKey[key].PropertyID)) {
				t.Fatalf("%s option %q references a foreign property", key, row.Label)
			}
		}
	}
}

// TestPropertyPresetSecondRunNoOp는 재실행이 어떤 행도 바꾸지 않는지 검증한다.
func testPropertyPresetSecondRunNoOp(t *testing.T) {
	store, wsctx := presetTestStore(t)
	if err := store.ApplyPropertyPresets(context.Background(), wsctx); err != nil {
		t.Fatalf("first ApplyPropertyPresets: %v", err)
	}
	beforeDefs, beforeOptions := loadPresetRows(t, store, wsctx)

	time.Sleep(2 * time.Millisecond) // updated_at 타임스탬프 구분 보장
	if err := store.ApplyPropertyPresets(context.Background(), wsctx); err != nil {
		t.Fatalf("second ApplyPropertyPresets: %v", err)
	}

	afterDefs, afterOptions := loadPresetRows(t, store, wsctx)
	if !reflect.DeepEqual(beforeDefs, afterDefs) {
		t.Fatalf("definitions changed on second run:\nbefore=%+v\nafter=%+v",
			beforeDefs, afterDefs)
	}
	if !reflect.DeepEqual(beforeOptions, afterOptions) {
		t.Fatalf("options changed on second run:\nbefore=%+v\nafter=%+v",
			beforeOptions, afterOptions)
	}
}

// TestPropertyPresetIndependentDatabasesDistinctIDs는 서로 다른 데이터베이스가
// 서로 다른 발급 ID를 받는지(결정적 ID 금지) 검증한다.
func testPropertyPresetIndependentDatabasesDistinctIDs(t *testing.T) {
	storeA, wsA := presetTestStore(t)
	storeB, wsB := presetTestStore(t)

	if err := storeA.ApplyPropertyPresets(context.Background(), wsA); err != nil {
		t.Fatalf("ApplyPropertyPresets A: %v", err)
	}
	if err := storeB.ApplyPropertyPresets(context.Background(), wsB); err != nil {
		t.Fatalf("ApplyPropertyPresets B: %v", err)
	}

	defsA, _ := loadPresetRows(t, storeA, wsA)
	defsB, _ := loadPresetRows(t, storeB, wsB)
	seen := make(map[string]struct{})
	for _, def := range append(append([]WorkspacePropertyDefinitionRow{}, defsA...), defsB...) {
		key := def.CanonicalKey + ":" + domainentry.PropertyID(mustParseBlob(t, def.PropertyID)).String()
		if _, duplicate := seen[key]; duplicate {
			t.Fatalf("deterministic cross-database id for %s: %s", def.CanonicalKey, key)
		}
		seen[key] = struct{}{}
	}
}

// TestPropertyPresetUserEditsPreserved는 사용자의 이름 변경·재정렬·색상·비활성화가
// 재실행 후에도 유지되고 비활성 정의·선택지가 재활성화되지 않는지 검증한다.
func testPropertyPresetUserEditsPreserved(t *testing.T) {
	store, wsctx := presetTestStore(t)
	if err := store.ApplyPropertyPresets(context.Background(), wsctx); err != nil {
		t.Fatalf("ApplyPropertyPresets: %v", err)
	}
	ctx := context.Background()
	defs, options := loadPresetRows(t, store, wsctx)

	var statusDef WorkspacePropertyDefinitionRow
	for _, def := range defs {
		if def.CanonicalKey == "status" {
			statusDef = def
		}
	}
	// 사용자 흔적: 정의 이름 변경 + 정의 비활성화, 선택지 이름/색 변경 + 하나 비활성화.
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND property_id = ?", wsctx.ID.Bytes(), statusDef.PropertyID).
		Updates(map[string]any{"display_name": "My workflow", "lifecycle_state": "tombstoned"}).Error; err != nil {
		t.Fatalf("edit definition: %v", err)
	}
	first := options[0]
	last := options[len(options)-1]
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyOptionRow{}).
		Where("workspace_id = ? AND option_id = ?", wsctx.ID.Bytes(), first.OptionID).
		Updates(map[string]any{"label": "Renamed", "color": "#ff0000", "ordinal": 9}).Error; err != nil {
		t.Fatalf("edit option: %v", err)
	}
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyOptionRow{}).
		Where("workspace_id = ? AND option_id = ?", wsctx.ID.Bytes(), last.OptionID).
		Update("active", false).Error; err != nil {
		t.Fatalf("disable option: %v", err)
	}

	time.Sleep(2 * time.Millisecond)
	if err := store.ApplyPropertyPresets(context.Background(), wsctx); err != nil {
		t.Fatalf("re-apply: %v", err)
	}

	afterDefs, afterOptions := loadPresetRows(t, store, wsctx)
	for _, def := range afterDefs {
		if def.CanonicalKey != "status" {
			continue
		}
		if def.DisplayName != "My workflow" || def.LifecycleState != "tombstoned" {
			t.Fatalf("user-edited definition overwritten: %+v", def)
		}
	}
	for _, option := range afterOptions {
		switch string(option.OptionID) {
		case string(first.OptionID):
			if option.Label != "Renamed" || option.Color != "#ff0000" || option.Ordinal != 9 || !option.Active {
				t.Fatalf("user-edited option overwritten: %+v", option)
			}
		case string(last.OptionID):
			if option.Active {
				t.Fatalf("disabled option reactivated: %+v", option)
			}
		}
	}
}

// TestPropertyPresetPartialMissingGainsOnlyMissing은 부분 누락 상태에서 누락
// 멤버만 새로 만들어지고 나머지는 그대로인지 검증한다.
func testPropertyPresetPartialMissingGainsOnlyMissing(t *testing.T) {
	store, wsctx := presetTestStore(t)
	if err := store.ApplyPropertyPresets(context.Background(), wsctx); err != nil {
		t.Fatalf("ApplyPropertyPresets: %v", err)
	}
	ctx := context.Background()
	defs, options := loadPresetRows(t, store, wsctx)

	var priorityDef WorkspacePropertyDefinitionRow
	var survivorIDs [][]byte
	for _, def := range defs {
		if def.CanonicalKey == "priority" {
			priorityDef = def
		} else {
			survivorIDs = append(survivorIDs, def.PropertyID)
		}
	}
	// Priority 정의 전체와 한 개 선택지(Todo)를 삭제해 부분 누락을 만든다. FK
	// 제약(옵션→정의) 때문에 선택지를 먼저 지운 뒤 정의를 지운다.
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND property_id = ?", wsctx.ID.Bytes(), priorityDef.PropertyID).
		Delete(&WorkspacePropertyOptionRow{}).Error; err != nil {
		t.Fatalf("delete priority options: %v", err)
	}
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND property_id = ?", wsctx.ID.Bytes(), priorityDef.PropertyID).
		Delete(&WorkspacePropertyDefinitionRow{}).Error; err != nil {
		t.Fatalf("delete priority definition: %v", err)
	}
	var todoOption WorkspacePropertyOptionRow
	for _, option := range options {
		if option.Label == "Todo" {
			todoOption = option
		}
	}
	if err := store.db.WithContext(ctx).
		Where("workspace_id = ? AND option_id = ?", wsctx.ID.Bytes(), todoOption.OptionID).
		Delete(&WorkspacePropertyOptionRow{}).Error; err != nil {
		t.Fatalf("delete Todo option: %v", err)
	}

	time.Sleep(2 * time.Millisecond)
	if err := store.ApplyPropertyPresets(context.Background(), wsctx); err != nil {
		t.Fatalf("re-apply: %v", err)
	}

	afterDefs, afterOptions := loadPresetRows(t, store, wsctx)
	if len(afterDefs) != 3 {
		t.Fatalf("definitions after repair = %d, want 3", len(afterDefs))
	}
	var newPriority WorkspacePropertyDefinitionRow
	for _, def := range afterDefs {
		if def.CanonicalKey == "priority" {
			newPriority = def
		}
		if string(def.PropertyID) == string(priorityDef.PropertyID) {
			t.Fatal("deleted priority definition was resurrected with its old id")
		}
	}
	requireVoyagerIssuedDefinition(t, newPriority)

	statusCount := 0
	for _, option := range afterOptions {
		if string(option.PropertyID) == string(newPriority.PropertyID) {
			statusCount++
		}
		if string(option.OptionID) == string(todoOption.OptionID) {
			t.Fatal("deleted Todo option was resurrected with its old id")
		}
	}
	if statusCount != 5 {
		t.Fatalf("priority options after repair = %d, want 5", statusCount)
	}
	// 생존 정의 두 개는 여전히 원래 ID를 유지한다.
	foundSurvivors := 0
	for _, def := range afterDefs {
		for _, survivor := range survivorIDs {
			if string(def.PropertyID) == string(survivor) {
				foundSurvivors++
			}
		}
	}
	if foundSurvivors != len(survivorIDs) {
		t.Fatalf("surviving definitions changed ids: %d of %d", foundSurvivors, len(survivorIDs))
	}
}

// TestPropertyPresetRollbackLeavesNoPartial은 재조정 도중 실패가 부분 사전 설정을
// 남기지 않는지(단일 트랜잭션) 검증한다.
func testPropertyPresetRollbackLeavesNoPartial(t *testing.T) {
	store, wsctx := presetTestStore(t)

	// applyPropertyPresetsInTx는 커밋 경계가 없는 tx-scoped 원시 함수다. 같은
	// WithinTx 안에서 재조정 직후 강제 오류를 반환하면 전체가 롤백되어야 한다.
	if err := store.WithinTx(context.Background(), func(tx *gorm.DB) error {
		if applyErr := applyPropertyPresetsInTx(tx, wsctx); applyErr != nil {
			return applyErr
		}
		return errors.New("forced rollback")
	}); err == nil {
		t.Fatal("expected forced rollback to fail")
	}

	defs, options := loadPresetRows(t, store, wsctx)
	if len(defs) != 0 || len(options) != 0 {
		t.Fatalf("partial preset survived rollback: %d definitions, %d options",
			len(defs), len(options))
	}
}

// TestPropertyPresetDescriptorEnumerationCompleteness는 사전 설정 디스크립터 표가
// 규정된 멤버 집합과 정확히 일치하는지 양방향으로 검증한다. 새 멤버 추가 시 이
// 표를 갱신하지 않으면 테스트가 실패한다(structural completeness gate).
func testPropertyPresetDescriptorEnumerationCompleteness(t *testing.T) {
	want := map[string]struct {
		displayName string
		labels      map[string]int // label -> ordinal
	}{
		"status": {
			displayName: "Status",
			labels: map[string]int{
				"Backlog": 0, "Todo": 1, "In progress": 2, "Done": 3, "Canceled": 4,
			},
		},
		"project": {
			displayName: "Project",
			labels:      map[string]int{},
		},
		"priority": {
			displayName: "Priority",
			labels: map[string]int{
				"No priority": 0, "Urgent": 1, "High": 2, "Medium": 3, "Low": 4,
			},
		},
	}

	descriptors := propertyPresetDescriptors()
	gotKeys := make(map[string]struct{}, len(descriptors))
	for _, descriptor := range descriptors {
		if descriptor.ValueType != "select" || descriptor.Cardinality != "one" {
			t.Fatalf("preset %s must be a single-select definition", descriptor.CanonicalKey)
		}
		gotKeys[descriptor.CanonicalKey] = struct{}{}
		expected, ok := want[descriptor.CanonicalKey]
		if !ok {
			t.Fatalf("unexpected preset member %q; update the enumeration table in this test",
				descriptor.CanonicalKey)
		}
		if descriptor.DisplayName != expected.displayName {
			t.Fatalf("preset %s display name = %q, want %q",
				descriptor.CanonicalKey, descriptor.DisplayName, expected.displayName)
		}
		gotLabels := make(map[string]int, len(descriptor.Options))
		for _, option := range descriptor.Options {
			gotLabels[option.Label] = option.Ordinal
		}
		if !reflect.DeepEqual(gotLabels, expected.labels) {
			t.Fatalf("preset %s options = %v, want %v",
				descriptor.CanonicalKey, gotLabels, expected.labels)
		}
	}
	if len(descriptors) != len(want) {
		t.Fatalf("descriptor count = %d, want %d", len(descriptors), len(want))
	}
	for key := range want {
		if _, ok := gotKeys[key]; !ok {
			t.Fatalf("missing preset member %q", key)
		}
	}
}

// 사용자가 option.update로 프리셋 멤버 라벨을 바꾼 뒤 재조정하면, label 매칭
// 누락 복구는 그 편집을 누락으로 오판해 중복 행을 만든다. 기존 정의는
// 아무것도 건드리지 않는 계약을 잠근다.
func testPropertyPresetOptionRenameDoesNotDuplicate(t *testing.T) {
	store, wsctx := presetTestStore(t)
	if err := store.ApplyPropertyPresets(context.Background(), wsctx); err != nil {
		t.Fatalf("ApplyPropertyPresets: %v", err)
	}
	ctx := context.Background()
	defs, options := loadPresetRows(t, store, wsctx)

	var statusDef WorkspacePropertyDefinitionRow
	var todoOption WorkspacePropertyOptionRow
	for _, def := range defs {
		if def.CanonicalKey == "status" {
			statusDef = def
		}
	}
	for _, option := range options {
		if option.Label == "Todo" && string(option.PropertyID) == string(statusDef.PropertyID) {
			todoOption = option
		}
	}
	if err := store.db.WithContext(ctx).Model(&WorkspacePropertyOptionRow{}).
		Where("workspace_id = ? AND option_id = ?", wsctx.ID.Bytes(), todoOption.OptionID).
		Update("label", "Next").Error; err != nil {
		t.Fatalf("rename option: %v", err)
	}

	time.Sleep(2 * time.Millisecond)
	if err := store.ApplyPropertyPresets(context.Background(), wsctx); err != nil {
		t.Fatalf("re-apply: %v", err)
	}

	afterDefs, afterOptions := loadPresetRows(t, store, wsctx)
	if len(afterDefs) != len(defs) || len(afterOptions) != len(options) {
		t.Fatalf("re-apply changed row counts: defs %d→%d options %d→%d, want unchanged",
			len(defs), len(afterDefs), len(options), len(afterOptions))
	}
	renamedStillThere := false
	for _, option := range afterOptions {
		if string(option.OptionID) == string(todoOption.OptionID) {
			if option.Label == "Next" && option.Active {
				renamedStillThere = true
			}
		}
		if option.Label == "Todo" && string(option.PropertyID) == string(statusDef.PropertyID) {
			t.Fatal("duplicate Todo option created after user rename")
		}
	}
	if !renamedStillThere {
		t.Fatal("user-renamed option lost")
	}
}
