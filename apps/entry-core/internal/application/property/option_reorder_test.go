package property

import (
	"context"
	"errors"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// TestReorderOptionsRequiresExactActivePermutation은 reorder가 활성 option
// 순열만 받고 비활성 행을 뒤에 보존하는지 증명한다.
func TestReorderOptionsRequiresExactActivePermutation(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	created := mustCreatedSelectDefinition(t, service, workspace, "status")
	third, err := service.CreateOption(ctx, workspace, created.Definition.PropertyID, created.Definition.DefinitionRev, "third")
	if err != nil {
		t.Fatal(err)
	}
	disabled, err := service.DisableOption(ctx, workspace, created.Definition.PropertyID,
		third.Options[0].OptionID, third.Definition.DefinitionRev)
	if err != nil {
		t.Fatal(err)
	}
	inactiveFirst := disabled.Options[0].OptionID
	activeSecond := disabled.Options[1].OptionID
	activeThird := disabled.Options[2].OptionID

	reordered, err := service.ReorderOptions(ctx, workspace, created.Definition.PropertyID,
		disabled.Definition.DefinitionRev, []domainentry.PropertyOptionID{activeThird, activeSecond})
	if err != nil {
		t.Fatal(err)
	}
	if reordered.Definition.DefinitionRev != disabled.Definition.DefinitionRev+1 {
		t.Fatalf("revision after reorder = %d, want +1", reordered.Definition.DefinitionRev)
	}
	wantOrder := []domainentry.PropertyOptionID{activeThird, activeSecond, inactiveFirst}
	for index, wantID := range wantOrder {
		got := reordered.Options[index]
		if got.OptionID != wantID || got.Ordinal != index {
			t.Fatalf("option %d = %+v, want %s at ordinal %d", index, got, wantID, index)
		}
	}
	if err := domainentry.ValidatePropertyOptions(reordered.Options); err != nil {
		t.Fatalf("option set invalid after reorder: %v", err)
	}

	before := snapshotStore(store)
	foreignDef := mustCreatedSelectDefinition(t, service, workspace, "priority")
	before = snapshotStore(store)
	cases := []struct {
		name  string
		order []domainentry.PropertyOptionID
	}{
		{"missing_active", []domainentry.PropertyOptionID{activeThird}},
		{"duplicate", []domainentry.PropertyOptionID{activeThird, activeThird}},
		{"unknown_id", []domainentry.PropertyOptionID{activeThird, domainentry.MustPropertyOptionID("0198c0a2-7b3f-7c3e-9f2a-4b6e8d0f1a2d")}},
		{"foreign_option", []domainentry.PropertyOptionID{activeThird, foreignDef.Options[0].OptionID}},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			_, err := service.ReorderOptions(ctx, workspace, created.Definition.PropertyID,
				reordered.Definition.DefinitionRev, testCase.order)
			if !errors.Is(err, ErrInvalidOptionOrder) {
				t.Fatalf("illegal reorder error = %v, want %v", err, ErrInvalidOptionOrder)
			}
			mustEqualSnapshot(t, before, snapshotStore(store))
		})
	}
}

// TestDefinitionRevisionMatrixCoversEveryMutationKind는 모든 성공 mutation
// 종류와 revision 증가 규칙의 완전 열거를 증명한다. 새 mutation 종류는 이
// 표에 행을 추가해야 한다(구조적 완전성 게이트).
func TestDefinitionRevisionMatrixCoversEveryMutationKind(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	steps := []struct {
		name         string
		run          func() error
		wantRevDelta int
	}{
		{"create_definition", func() error {
			_, err := service.CreateDefinition(ctx, workspace, CreateDefinitionInput{
				Key:          "matrix_status",
				DisplayName:  "Matrix status",
				ValueType:    domainentry.PropertyTypeSelect,
				Cardinality:  domainentry.PropertyCardinalityOne,
				OptionLabels: []string{"open"},
			})
			return err
		}, 1},
		{"update_metadata", func() error {
			view, err := service.definitionByKey(ctx, workspace, userDefinitionNamespace, "matrix_status")
			if err != nil {
				return err
			}
			_, err = service.UpdateDefinitionMetadata(ctx, workspace, view.Definition.PropertyID, view.Definition.DefinitionRev, "Matrix status v2")
			return err
		}, 1},
		{"create_option", func() error {
			view, err := service.definitionByKey(ctx, workspace, userDefinitionNamespace, "matrix_status")
			if err != nil {
				return err
			}
			_, err = service.CreateOption(ctx, workspace, view.Definition.PropertyID, view.Definition.DefinitionRev, "closed")
			return err
		}, 1},
		{"rename_option", func() error {
			view, err := service.definitionByKey(ctx, workspace, userDefinitionNamespace, "matrix_status")
			if err != nil {
				return err
			}
			_, err = service.RenameOption(ctx, workspace, view.Definition.PropertyID, view.Options[0].OptionID, view.Definition.DefinitionRev, "reopened")
			return err
		}, 1},
		{"recolor_option", func() error {
			view, err := service.definitionByKey(ctx, workspace, userDefinitionNamespace, "matrix_status")
			if err != nil {
				return err
			}
			_, err = service.RecolorOption(ctx, workspace, view.Definition.PropertyID, view.Options[0].OptionID, view.Definition.DefinitionRev, "#00ff00")
			return err
		}, 1},
		{"reorder_options", func() error {
			view, err := service.definitionByKey(ctx, workspace, userDefinitionNamespace, "matrix_status")
			if err != nil {
				return err
			}
			_, err = service.ReorderOptions(ctx, workspace, view.Definition.PropertyID, view.Definition.DefinitionRev,
				[]domainentry.PropertyOptionID{view.Options[1].OptionID, view.Options[0].OptionID})
			return err
		}, 1},
		{"disable_option", func() error {
			view, err := service.definitionByKey(ctx, workspace, userDefinitionNamespace, "matrix_status")
			if err != nil {
				return err
			}
			_, err = service.DisableOption(ctx, workspace, view.Definition.PropertyID, view.Options[0].OptionID, view.Definition.DefinitionRev)
			return err
		}, 1},
		{"disable_definition", func() error {
			view, err := service.definitionByKey(ctx, workspace, userDefinitionNamespace, "matrix_status")
			if err != nil {
				return err
			}
			_, err = service.DisableDefinition(ctx, workspace, view.Definition.PropertyID, view.Definition.DefinitionRev)
			return err
		}, 1},
	}

	revision := 0
	for _, step := range steps {
		t.Run(step.name, func(t *testing.T) {
			if err := step.run(); err != nil {
				t.Fatal(err)
			}
			view, err := service.definitionByKey(ctx, workspace, userDefinitionNamespace, "matrix_status")
			if err != nil {
				t.Fatal(err)
			}
			if view.Definition.DefinitionRev != revision+step.wantRevDelta {
				t.Fatalf("revision after %s = %d, want %d", step.name, view.Definition.DefinitionRev, revision+step.wantRevDelta)
			}
			revision = view.Definition.DefinitionRev
		})
	}
}

// TestZeroWorkspaceIsRejectedForEveryServiceMethod는 모든 서비스 메서드가
// 주입된 workspace를 요구하는지 증명한다.
func TestZeroWorkspaceIsRejectedForEveryServiceMethod(t *testing.T) {
	service := mustCatalogService(t, newMemCatalogStore())
	zero := domainentry.WorkspaceContext{}
	ctx := context.Background()
	propertyID := domainentry.MustPropertyID("0198c0a2-7b3f-7c3e-9f2a-4b6e8d0f1a2b")
	optionID := domainentry.MustPropertyOptionID("0198c0a2-7b3f-7c3e-9f2a-4b6e8d0f1a2e")

	checks := map[string]func() error{
		"create": func() error {
			_, err := service.CreateDefinition(ctx, zero, CreateDefinitionInput{Key: "k"})
			return err
		},
		"list":            func() error { _, err := service.ListDefinitions(ctx, zero); return err },
		"get":             func() error { _, err := service.Definition(ctx, zero, propertyID); return err },
		"get_by_key":      func() error { _, err := service.definitionByKey(ctx, zero, userDefinitionNamespace, "k"); return err },
		"update":          func() error { _, err := service.UpdateDefinitionMetadata(ctx, zero, propertyID, 1, "n"); return err },
		"disable_def":     func() error { _, err := service.DisableDefinition(ctx, zero, propertyID, 1); return err },
		"create_option":   func() error { _, err := service.CreateOption(ctx, zero, propertyID, 1, "l"); return err },
		"rename_option":   func() error { _, err := service.RenameOption(ctx, zero, propertyID, optionID, 1, "l"); return err },
		"recolor_option":  func() error { _, err := service.RecolorOption(ctx, zero, propertyID, optionID, 1, "#fff"); return err },
		"reorder_options": func() error { _, err := service.ReorderOptions(ctx, zero, propertyID, 1, nil); return err },
		"disable_option":  func() error { _, err := service.DisableOption(ctx, zero, propertyID, optionID, 1); return err },
	}
	for name, check := range checks {
		t.Run(name, func(t *testing.T) {
			if err := check(); !errors.Is(err, ErrWorkspaceRequired) {
				t.Fatalf("%s zero workspace error = %v, want %v", name, err, ErrWorkspaceRequired)
			}
		})
	}
}
