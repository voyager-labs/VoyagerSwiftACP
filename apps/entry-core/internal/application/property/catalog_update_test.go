package property

import (
	"context"
	"errors"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// TestUpdateDefinitionMetadataIncrementsRevisionExactlyOnce는 이름 갱신이
// revision을 정확히 한 번 올리고 불변 필드를 보존하는지 증명한다.
func TestUpdateDefinitionMetadataIncrementsRevisionExactlyOnce(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)

	created := mustCreatedDefinition(t, service, workspace, "due_date")
	updated, err := service.UpdateDefinitionMetadata(context.Background(), workspace,
		created.Definition.PropertyID, created.Definition.DefinitionRev, "req-test", "Renamed due date")
	if err != nil {
		t.Fatal(err)
	}
	if updated.Definition.DisplayName != "Renamed due date" {
		t.Fatalf("display name = %q", updated.Definition.DisplayName)
	}
	if updated.Definition.DefinitionRev != created.Definition.DefinitionRev+1 {
		t.Fatalf("revision = %d, want exactly +1 over %d", updated.Definition.DefinitionRev, created.Definition.DefinitionRev)
	}
	if updated.Definition.CanonicalKey != created.Definition.CanonicalKey ||
		updated.Definition.ValueType != created.Definition.ValueType ||
		updated.Definition.Cardinality != created.Definition.Cardinality ||
		updated.Definition.PropertyID != created.Definition.PropertyID {
		t.Fatalf("immutable fields moved: %+v", updated.Definition)
	}
}

// TestUpdateDefinitionMetadataRejectsStaleRevisionAndLeavesStateUnchanged는
// CAS 실패가 typed 오류와 상태 불변을 함께 만족하는지 증명한다.
func TestUpdateDefinitionMetadataRejectsStaleRevisionAndLeavesStateUnchanged(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	created := mustCreatedDefinition(t, service, workspace, "due_date")
	staleRevision := created.Definition.DefinitionRev - 1
	before := snapshotStore(store)

	_, err := service.UpdateDefinitionMetadata(ctx, workspace, created.Definition.PropertyID, staleRevision, "Too late", "req-test")
	if !errors.Is(err, ErrStaleDefinitionRevision) {
		t.Fatalf("stale revision error = %v, want %v", err, ErrStaleDefinitionRevision)
	}
	mustEqualSnapshot(t, before, snapshotStore(store))
}

// TestUpdateDefinitionMetadataRejectsInactiveTarget은 비활성 정의 대상
// mutation을 거절하는지 증명한다.
func TestUpdateDefinitionMetadataRejectsInactiveTarget(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	created := mustCreatedDefinition(t, service, workspace, "due_date")
	disabled, err := service.DisableDefinition(ctx, workspace, created.Definition.PropertyID, created.Definition.DefinitionRev, "req-test")
	if err != nil {
		t.Fatal(err)
	}
	before := snapshotStore(store)

	_, err = service.UpdateDefinitionMetadata(ctx, workspace, created.Definition.PropertyID, disabled.Definition.DefinitionRev, "Zombie", "req-test")
	if !errors.Is(err, ErrDefinitionInactive) {
		t.Fatalf("inactive target error = %v, want %v", err, ErrDefinitionInactive)
	}
	mustEqualSnapshot(t, before, snapshotStore(store))
}

// TestApplyDefinitionUpdateRejectsImmutableFieldChanges는 불변 필드 변경
// 시도가 typed 오류로 거절되는지 증명한다.
func TestApplyDefinitionUpdateRejectsImmutableFieldChanges(t *testing.T) {
	current := domainentry.WorkspacePropertyDefinition{
		Namespace:    userDefinitionNamespace,
		CanonicalKey: "due_date",
		ValueType:    domainentry.PropertyTypeDate,
		Cardinality:  domainentry.PropertyCardinalityOne,
	}
	renameOnly := current
	renameOnly.DisplayName = "New name"
	if _, err := applyDefinitionUpdate(current, renameOnly); err != nil {
		t.Fatalf("rename-only update error = %v", err)
	}
	for name, mutate := range map[string]func(*domainentry.WorkspacePropertyDefinition){
		"key":        func(def *domainentry.WorkspacePropertyDefinition) { def.CanonicalKey = "other_key" },
		"value_type": func(def *domainentry.WorkspacePropertyDefinition) { def.ValueType = domainentry.PropertyTypeText },
		"cardinality": func(def *domainentry.WorkspacePropertyDefinition) {
			def.Cardinality = domainentry.PropertyCardinalityMany
		},
		"namespace": func(def *domainentry.WorkspacePropertyDefinition) { def.Namespace = "escaped" },
	} {
		t.Run(name, func(t *testing.T) {
			requested := current
			requested.DisplayName = "New name"
			mutate(&requested)
			if _, err := applyDefinitionUpdate(current, requested); !errors.Is(err, ErrImmutableDefinitionField) {
				t.Fatalf("immutable change error = %v, want %v", err, ErrImmutableDefinitionField)
			}
		})
	}
}

// TestDisableDefinitionIsDurableIdentityPreservingAndTerminal은 disable이
// durable하고 identity를 보존하며 재사용을 거절하는지 증명한다.
func TestDisableDefinitionIsDurableIdentityPreservingAndTerminal(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	selectDef := mustCreatedSelectDefinition(t, service, workspace, "status")
	disabled, err := service.DisableDefinition(ctx, workspace, selectDef.Definition.PropertyID, selectDef.Definition.DefinitionRev, "req-test")
	if err != nil {
		t.Fatal(err)
	}
	if disabled.Definition.Lifecycle != domainentry.PropertyLifecycleTombstoned {
		t.Fatalf("lifecycle after disable = %s", disabled.Definition.Lifecycle)
	}
	if disabled.Definition.DefinitionRev != selectDef.Definition.DefinitionRev+1 {
		t.Fatalf("revision = %d, want exactly +1", disabled.Definition.DefinitionRev)
	}

	reread, err := service.Definition(ctx, workspace, selectDef.Definition.PropertyID)
	if err != nil {
		t.Fatal(err)
	}
	if reread.Definition.Lifecycle != domainentry.PropertyLifecycleTombstoned ||
		reread.Definition.PropertyID != selectDef.Definition.PropertyID ||
		reread.Definition.CanonicalKey != selectDef.Definition.CanonicalKey {
		t.Fatalf("disable did not preserve identity durably: %+v", reread.Definition)
	}
	if len(reread.Options) != len(selectDef.Options) {
		t.Fatalf("options survived = %d, want %d (rows preserved)", len(reread.Options), len(selectDef.Options))
	}

	before := snapshotStore(store)
	if _, err := service.DisableDefinition(ctx, workspace, selectDef.Definition.PropertyID, disabled.Definition.DefinitionRev, "req-test"); !errors.Is(err, ErrDefinitionInactive) {
		t.Fatalf("repeat disable error = %v, want %v", err, ErrDefinitionInactive)
	}
	mustEqualSnapshot(t, before, snapshotStore(store))
}

// System Registry 시드(registry_derived) 정의는 사용자 mutation 대상이 아니다.
// update/disable이 seed digest나 lifecycle을 바꾸면 다음 시작의 seed 검증이
// 실패해 daemon이 기동 전에 종료된다.
func TestRegistryOwnedDefinitionsRejectCatalogMutations(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	registryScheme := domainentry.PropertyIdentityScheme("registry_derived")
	propertyID := domainentry.MustPropertyID("0198c0de-f00d-7000-8000-3b9ac9e18888")

	store.defs[propertyID] = domainentry.WorkspacePropertyDefinition{
		PropertyID: propertyID, Origin: domainentry.PropertyOriginBuiltIn,
		IdentityScheme: registryScheme, Namespace: "system", CanonicalKey: "seeded.text",
		DisplayName: "Seeded", ValueType: domainentry.PropertyTypeText,
		Cardinality: domainentry.PropertyCardinalityOne, Editable: true,
		DefinitionRev: 1, Lifecycle: domainentry.PropertyLifecycleActive,
	}
	before := snapshotStore(store)
	ctx := context.Background()

	if _, err := service.UpdateDefinitionMetadata(ctx, workspace, propertyID, 1, "req-seed", "Renamed"); !errors.Is(err, ErrRegistryOwnedDefinition) {
		t.Fatalf("registry update error = %v, want ErrRegistryOwnedDefinition", err)
	}
	if _, err := service.DisableDefinition(ctx, workspace, propertyID, 1, "req-seed"); !errors.Is(err, ErrRegistryOwnedDefinition) {
		t.Fatalf("registry disable error = %v, want ErrRegistryOwnedDefinition", err)
	}
	if _, err := service.CreateOption(ctx, workspace, propertyID, 1, "req-seed", "extra"); !errors.Is(err, ErrRegistryOwnedDefinition) {
		t.Fatalf("registry create option error = %v, want ErrRegistryOwnedDefinition", err)
	}
	mustEqualSnapshot(t, before, snapshotStore(store))
}

// 생성 중복 검사는 (namespace, key) exact 조회로 bounded하다. tombstoned 행도
// 유일성 판정에 포함되며(UNIQUE 인덱스 계약), 전체 정의 열거는 생략한다.
func TestCreateDefinitionDuplicateKeyIncludesTombstoned(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	first, err := service.CreateDefinition(ctx, workspace, CreateDefinitionInput{
		Key: "dup", DisplayName: "First", ValueType: domainentry.PropertyTypeText,
		Cardinality: domainentry.PropertyCardinalityOne, RequestID: "req-1",
	})
	if err != nil {
		t.Fatalf("first create: %v", err)
	}
	if _, err := service.DisableDefinition(ctx, workspace, first.Definition.PropertyID, first.Definition.DefinitionRev, "req-2"); err != nil {
		t.Fatalf("disable: %v", err)
	}
	before := snapshotStore(store)

	if _, err := service.CreateDefinition(ctx, workspace, CreateDefinitionInput{
		Key: "dup", DisplayName: "Second", ValueType: domainentry.PropertyTypeText,
		Cardinality: domainentry.PropertyCardinalityOne, RequestID: "req-3",
	}); !errors.Is(err, ErrDuplicateDefinitionKey) {
		t.Fatalf("duplicate key over tombstoned = %v, want ErrDuplicateDefinitionKey", err)
	}
	mustEqualSnapshot(t, before, snapshotStore(store))
}
