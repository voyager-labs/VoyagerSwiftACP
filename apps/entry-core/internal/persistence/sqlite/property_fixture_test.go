package sqlite

// VOY-765 property 저장소 테스트 픽스처다. 활성 정의 8개와 select 옵션을
// 채운 표준 워크스페이스를 만든다.

import (
	"context"
	"encoding/base64"
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// testEntryID는 유효한 형태(ent:+정규 base64url 43자)의 테스트 entry id를
// 만든다. 32-byte digest를 실제 인코딩해야 validPrefixedDigest의 재인코딩
// 동등성 검사를 통과한다.
func testEntryID(n int) string {
	var digest [32]byte
	digest[0] = byte(n)
	digest[1] = byte(n >> 8)
	digest[2] = byte(n >> 16)
	return "ent:" + base64.RawURLEncoding.EncodeToString(digest[:])
}

// propertyFixture는 정의/선택지 픽스처와 워크스페이스 컨텍스트를 담는다.
type propertyFixture struct {
	wsctx       domainentry.WorkspaceContext
	textDef     domainentry.PropertyID
	numberDef   domainentry.PropertyID
	booleanDef  domainentry.PropertyID
	dateDef     domainentry.PropertyID
	datetimeDef domainentry.PropertyID
	selectDef   domainentry.PropertyID
	nullableDef domainentry.PropertyID
	multiDef    domainentry.PropertyID
	optionA     domainentry.PropertyOptionID
	optionB     domainentry.PropertyOptionID
	optionOff   domainentry.PropertyOptionID
	multiOptA   domainentry.PropertyOptionID
	multiOptB   domainentry.PropertyOptionID
}

// buildPropertyFixture는 활성 정의 8개와 선택지를 채운 표준 픽스처를 만든다.
func buildPropertyFixture(t *testing.T, store *Store) propertyFixture {
	t.Helper()
	ctx := context.Background()
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("bootstrap workspace: %v", err)
	}
	fx := propertyFixture{
		wsctx: wsctx,
	}
	for _, item := range []struct {
		key         string
		target      *domainentry.PropertyID
		valueType   string
		cardinality string
		nullable    bool
	}{
		{"text", &fx.textDef, "text", "one", false},
		{"number", &fx.numberDef, "number", "one", false},
		{"boolean", &fx.booleanDef, "boolean", "one", false},
		{"date", &fx.dateDef, "date", "one", false},
		{"datetime", &fx.datetimeDef, "datetime", "one", false},
		{"select", &fx.selectDef, "select", "one", false},
		{"nullable_text", &fx.nullableDef, "text", "one", true},
		{"multi_select", &fx.multiDef, "select", "many", false},
	} {
		id, err := domainentry.RegistryPropertyID("voy765." + item.key)
		if err != nil {
			t.Fatalf("RegistryPropertyID(%s): %v", item.key, err)
		}
		*item.target = id
	}

	now := time.Now()
	defRows := make([]WorkspacePropertyDefinitionRow, 0, 8)
	appendDef := func(id domainentry.PropertyID, key, valueType, cardinality string, nullable bool) {
		defRows = append(defRows, WorkspacePropertyDefinitionRow{
			WorkspaceID: wsctx.ID.Bytes(), PropertyID: id.Bytes(),
			Origin: "built_in", IdentityScheme: "registry_derived",
			Namespace: "test", CanonicalKey: key,
			DisplayName: key, Description: "",
			ValueType: valueType, Cardinality: cardinality,
			Nullable: nullable, Editable: true,
			DefaultHidden: false, DefaultPinned: false, DBIndexedHint: false,
			Provenance: "system", Unit: "",
			DefinitionRev: 1, LifecycleState: "active",
			CreatedAt: now, UpdatedAt: now,
		})
	}
	appendDef(fx.textDef, "voy765.text", "text", "one", false)
	appendDef(fx.numberDef, "voy765.number", "number", "one", false)
	appendDef(fx.booleanDef, "voy765.boolean", "boolean", "one", false)
	appendDef(fx.dateDef, "voy765.date", "date", "one", false)
	appendDef(fx.datetimeDef, "voy765.datetime", "datetime", "one", false)
	appendDef(fx.selectDef, "voy765.select", "select", "one", false)
	appendDef(fx.nullableDef, "voy765.nullable_text", "text", "one", true)
	appendDef(fx.multiDef, "voy765.multi_select", "select", "many", false)
	if err := store.db.WithContext(ctx).Create(&defRows).Error; err != nil {
		t.Fatalf("insert definitions: %v", err)
	}

	fx.optionA = domainentry.MustPropertyOptionID("01a2b3c4-d5e6-7f80-9a0b-1c2d3e4f5a60")
	fx.optionB = domainentry.MustPropertyOptionID("01a2b3c4-d5e6-7f81-9a0b-1c2d3e4f5a61")
	fx.optionOff = domainentry.MustPropertyOptionID("01a2b3c4-d5e6-7f82-9a0c-1c2d3e4f5a62")
	fx.multiOptA = domainentry.MustPropertyOptionID("01a2b3c4-d5e6-7f90-abbb-1c2d3e4f5a70")
	fx.multiOptB = domainentry.MustPropertyOptionID("01a2b3c4-d5e6-7f91-accc-1c2d3e4f5a71")

	optionRows := []WorkspacePropertyOptionRow{
		optionRow(wsctx, fx.optionA, fx.selectDef, "A", 0, true, now),
		optionRow(wsctx, fx.optionB, fx.selectDef, "B", 1, true, now),
		optionRow(wsctx, fx.optionOff, fx.selectDef, "Off", 2, false, now),
		optionRow(wsctx, fx.multiOptA, fx.multiDef, "MA", 0, true, now),
		optionRow(wsctx, fx.multiOptB, fx.multiDef, "MB", 1, true, now),
	}
	if err := store.db.WithContext(ctx).Create(&optionRows).Error; err != nil {
		t.Fatalf("insert options: %v", err)
	}
	return fx
}

func optionRow(
	wsctx domainentry.WorkspaceContext,
	optionID domainentry.PropertyOptionID,
	propertyID domainentry.PropertyID,
	label string,
	ordinal int,
	active bool,
	now time.Time,
) WorkspacePropertyOptionRow {
	return WorkspacePropertyOptionRow{
		WorkspaceID: wsctx.ID.Bytes(), OptionID: optionID.Bytes(), PropertyID: propertyID.Bytes(),
		Label: label, Color: "", Ordinal: ordinal, Active: active,
		CreatedAt: now, UpdatedAt: now,
	}
}
