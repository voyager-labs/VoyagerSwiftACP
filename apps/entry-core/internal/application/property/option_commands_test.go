package property

import (
	"context"
	"errors"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// TestCreateOptionAppendsOrdinalAndBumpsOwnerRevision은 option 생성이 소유
// 정의의 revision을 정확히 한 번 올리는지 증명한다.
func TestCreateOptionAppendsOrdinalAndBumpsOwnerRevision(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	created := mustCreatedSelectDefinition(t, service, workspace, "status")
	updated, err := service.CreateOption(ctx, workspace, created.Definition.PropertyID, created.Definition.DefinitionRev, "req-test", "third")
	if err != nil {
		t.Fatal(err)
	}
	if updated.Definition.DefinitionRev != created.Definition.DefinitionRev+1 {
		t.Fatalf("owner revision = %d, want exactly +1 over %d", updated.Definition.DefinitionRev, created.Definition.DefinitionRev)
	}
	if len(updated.Options) != 3 {
		t.Fatalf("option count = %d, want 3", len(updated.Options))
	}
	last := updated.Options[2]
	if last.Ordinal != 2 || !last.Active || last.Label != "third" || last.OptionID == (domainentry.PropertyOptionID{}) {
		t.Fatalf("appended option = %+v", last)
	}
	if err := domainentry.ValidatePropertyOptions(updated.Options); err != nil {
		t.Fatalf("option set invalid after append: %v", err)
	}
}

// TestCreateOptionRejectsWrongOwnerTypeState는 알 수 없는 정의·비선택
// 유형·비활성 정의 대상 option 생성을 거절하는지 증명한다.
func TestCreateOptionRejectsWrongOwnerTypeState(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	textDef := mustCreatedDefinition(t, service, workspace, "title")
	selectDef := mustCreatedSelectDefinition(t, service, workspace, "status")
	disabled, err := service.DisableDefinition(ctx, workspace, selectDef.Definition.PropertyID, selectDef.Definition.DefinitionRev, "req-test")
	if err != nil {
		t.Fatal(err)
	}
	before := snapshotStore(store)

	unknownID := domainentry.MustPropertyID("0198c0a2-7b3f-7c3e-9f2a-4b6e8d0f1a2c")
	cases := []struct {
		name       string
		propertyID domainentry.PropertyID
		revision   int
		want       error
	}{
		{"unknown_definition", unknownID, 1, ErrDefinitionNotFound},
		{"non_select_owner", textDef.Definition.PropertyID, textDef.Definition.DefinitionRev, ErrDefinitionNotSelectable},
		{"inactive_owner", selectDef.Definition.PropertyID, disabled.Definition.DefinitionRev, ErrDefinitionInactive},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			_, err := service.CreateOption(ctx, workspace, testCase.propertyID, testCase.revision, "late", "req-test")
			if !errors.Is(err, testCase.want) {
				t.Fatalf("error = %v, want %v", err, testCase.want)
			}
			mustEqualSnapshot(t, before, snapshotStore(store))
		})
	}
}

// TestRenameRecolorAndDisableOptionPreserveIdentity는 rename·recolor가
// identity를 보존하고 비활성 option 대상 mutation을 거절하는지 증명한다.
func TestRenameRecolorAndDisableOptionPreserveIdentity(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	created := mustCreatedSelectDefinition(t, service, workspace, "status")
	optionID := created.Options[0].OptionID

	renamed, err := service.RenameOption(ctx, workspace, created.Definition.PropertyID, optionID, created.Definition.DefinitionRev, "req-test", "primary")
	if err != nil {
		t.Fatal(err)
	}
	if renamed.Options[0].Label != "primary" || renamed.Options[0].OptionID != optionID {
		t.Fatalf("rename broke identity: %+v", renamed.Options[0])
	}
	if renamed.Definition.DefinitionRev != created.Definition.DefinitionRev+1 {
		t.Fatalf("revision after rename = %d, want +1", renamed.Definition.DefinitionRev)
	}

	recolorTarget := renamed.Definition.DefinitionRev
	colored, err := service.RecolorOption(ctx, workspace, created.Definition.PropertyID, optionID, recolorTarget, "req-test", "#ff0000")
	if err != nil {
		t.Fatal(err)
	}
	if colored.Options[0].Color != "#ff0000" || colored.Options[0].Label != "primary" {
		t.Fatalf("recolor lost label or color: %+v", colored.Options[0])
	}
	if colored.Definition.DefinitionRev != recolorTarget+1 {
		t.Fatalf("revision after recolor = %d, want +1", colored.Definition.DefinitionRev)
	}

	disabled, err := service.DisableOption(ctx, workspace, created.Definition.PropertyID, optionID, colored.Definition.DefinitionRev, "req-test")
	if err != nil {
		t.Fatal(err)
	}
	if disabled.Options[0].Active {
		t.Fatalf("disabled option still active: %+v", disabled.Options[0])
	}
	if disabled.Options[0].OptionID != optionID || disabled.Options[0].Label != "primary" {
		t.Fatalf("disable did not preserve identity: %+v", disabled.Options[0])
	}

	before := snapshotStore(store)
	staleRevision := disabled.Definition.DefinitionRev - 1
	if _, err := service.RenameOption(ctx, workspace, created.Definition.PropertyID, optionID, staleRevision, "zombie", "req-test"); !errors.Is(err, ErrStaleDefinitionRevision) {
		t.Fatalf("stale revision error = %v, want %v", err, ErrStaleDefinitionRevision)
	}
	currentRevision := disabled.Definition.DefinitionRev
	if _, err := service.RenameOption(ctx, workspace, created.Definition.PropertyID, optionID, currentRevision, "zombie", "req-test"); !errors.Is(err, ErrOptionInactive) {
		t.Fatalf("inactive option error = %v, want %v", err, ErrOptionInactive)
	}
	mustEqualSnapshot(t, before, snapshotStore(store))
}

// TestCrossDefinitionOptionReferenceIsRejected는 다른 정의의 option을 대상으로
// 한 조작이 ownership 오류로 거절되는지 증명한다.
func TestCrossDefinitionOptionReferenceIsRejected(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	first := mustCreatedSelectDefinition(t, service, workspace, "status")
	second := mustCreatedSelectDefinition(t, service, workspace, "priority")
	foreignOptionID := second.Options[0].OptionID
	before := snapshotStore(store)

	_, err := service.RenameOption(ctx, workspace, first.Definition.PropertyID, foreignOptionID,
		first.Definition.DefinitionRev, "hijacked", "req-test")
	if !errors.Is(err, ErrInvalidOptionOwner) {
		t.Fatalf("cross-definition error = %v, want %v", err, ErrInvalidOptionOwner)
	}
	mustEqualSnapshot(t, before, snapshotStore(store))
}
