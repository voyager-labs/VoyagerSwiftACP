package property

import (
	"context"
	"errors"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// TestCreateDefinitionAssignsIdentityAndCanonicalDefaults는 생성이 ID 발급과
// canonical 기본값을 하나의 트랜잭션으로 규정하는지 증명한다.
func TestCreateDefinitionAssignsIdentityAndCanonicalDefaults(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)

	view, err := service.CreateDefinition(context.Background(), workspace, CreateDefinitionInput{
		Key:         "due_date",
		DisplayName: "Due date",
		ValueType:   domainentry.PropertyTypeDate,
		Cardinality: domainentry.PropertyCardinalityOne,
		RequestID:   "req",
	})
	if err != nil {
		t.Fatal(err)
	}

	def := view.Definition
	if def.PropertyID == (domainentry.PropertyID{}) || def.IdentityScheme != domainentry.PropertyIdentitySchemeVoyagerIssued {
		t.Fatalf("issued identity = %+v scheme %s", def.PropertyID, def.IdentityScheme)
	}
	if parsed, err := domainentry.ParsePropertyID(def.PropertyID.String()); err != nil || parsed != def.PropertyID {
		t.Fatalf("issued property id not a canonical UUIDv7: %v", err)
	}
	if def.Namespace != userDefinitionNamespace || def.CanonicalKey != "due_date" {
		t.Fatalf("namespace/key = %s/%s", def.Namespace, def.CanonicalKey)
	}
	if def.Origin != domainentry.PropertyOriginUserDefined || def.Provenance != domainentry.PropertyProvenanceUserDefined {
		t.Fatalf("origin/provenance = %s/%s", def.Origin, def.Provenance)
	}
	if def.Lifecycle != domainentry.PropertyLifecycleActive || def.DefinitionRev != 1 {
		t.Fatalf("lifecycle/revision = %s/%d, want active/1", def.Lifecycle, def.DefinitionRev)
	}
	if !def.Editable || !def.Nullable {
		t.Fatalf("editable/nullable = %v/%v", def.Editable, def.Nullable)
	}
	if err := def.Validate(); err != nil {
		t.Fatalf("created definition invalid: %v", err)
	}
}

// TestCreateDefinitionSelectRequiresNonEmptyOptionSet은 select는 선택지 집합을
// 요구하고 비선택 유형은 선택지를 거절하는지 증명한다.
func TestCreateDefinitionSelectRequiresNonEmptyOptionSet(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	if _, err := service.CreateDefinition(ctx, workspace, CreateDefinitionInput{
		Key:         "status",
		DisplayName: "Status",
		ValueType:   domainentry.PropertyTypeSelect,
		Cardinality: domainentry.PropertyCardinalityOne,
		RequestID:   "req",
	}); !errors.Is(err, domainentry.ErrInvalidPropertyOptionSet) {
		t.Fatalf("select without options error = %v, want %v", err, domainentry.ErrInvalidPropertyOptionSet)
	}
	if _, err := service.CreateDefinition(ctx, workspace, CreateDefinitionInput{
		Key:          "title",
		DisplayName:  "Title",
		ValueType:    domainentry.PropertyTypeText,
		Cardinality:  domainentry.PropertyCardinalityOne,
		OptionLabels: []string{"unused"},
		RequestID:    "req",
	}); !errors.Is(err, domainentry.ErrInvalidPropertyOptionSet) {
		t.Fatalf("text with options error = %v, want %v", err, domainentry.ErrInvalidPropertyOptionSet)
	}
	if len(store.defs) != 0 {
		t.Fatalf("rejected creates left %d definitions behind", len(store.defs))
	}
}

// TestCreateDefinitionRejectsDuplicateKeyAgainstAnyLifecycle는 활성·비활성
// 무관하게 물리 유일 키 충돌을 거절하는지 증명한다.
func TestCreateDefinitionRejectsDuplicateKeyAgainstAnyLifecycle(t *testing.T) {
	for name, disableFirst := range map[string]bool{"active": false, "tombstoned": true} {
		t.Run(name, func(t *testing.T) {
			store := newMemCatalogStore()
			service := mustCatalogService(t, store)
			workspace := mustWorkspaceContext(t)
			ctx := context.Background()

			first := mustCreatedDefinition(t, service, workspace, "due_date")
			if disableFirst {
				if _, err := service.DisableDefinition(ctx, workspace, first.Definition.PropertyID, first.Definition.DefinitionRev, "req-test"); err != nil {
					t.Fatal(err)
				}
			}
			before := snapshotStore(store)

			_, err := service.CreateDefinition(ctx, workspace, CreateDefinitionInput{
				Key:         "due_date",
				DisplayName: "Another due date",
				ValueType:   domainentry.PropertyTypeText,
				Cardinality: domainentry.PropertyCardinalityOne,
				RequestID:   "req",
			})
			if !errors.Is(err, ErrDuplicateDefinitionKey) {
				t.Fatalf("duplicate key error = %v, want %v", err, ErrDuplicateDefinitionKey)
			}
			mustEqualSnapshot(t, before, snapshotStore(store))
		})
	}
}

// TestListDefinitionsIncludesDisabledAndGetResolvesHistoricalRows는 읽기가
// 비활성 행을 잃지 않고 명시적 필터링만 제공하는지 증명한다.
func TestListDefinitionsIncludesDisabledAndGetResolvesHistoricalRows(t *testing.T) {
	store := newMemCatalogStore()
	service := mustCatalogService(t, store)
	workspace := mustWorkspaceContext(t)
	ctx := context.Background()

	kept := mustCreatedDefinition(t, service, workspace, "kept")
	disabled := mustCreatedDefinition(t, service, workspace, "disabled")
	if _, err := service.DisableDefinition(ctx, workspace, disabled.Definition.PropertyID, disabled.Definition.DefinitionRev, "req-test"); err != nil {
		t.Fatal(err)
	}

	listed, err := service.ListDefinitions(ctx, workspace)
	if err != nil {
		t.Fatal(err)
	}
	if len(listed) != 2 {
		t.Fatalf("listed definitions = %d, want 2 (disabled included)", len(listed))
	}
	activeByID := make(map[domainentry.PropertyID]bool, len(listed))
	for _, view := range listed {
		activeByID[view.Definition.PropertyID] = view.IsActive()
	}
	if !activeByID[kept.Definition.PropertyID] || activeByID[disabled.Definition.PropertyID] {
		t.Fatalf("active flags = %v, want kept=true disabled=false", activeByID)
	}

	historical, err := service.Definition(ctx, workspace, disabled.Definition.PropertyID)
	if err != nil {
		t.Fatalf("disabled definition read = %v, want preserved historical row", err)
	}
	if historical.Definition.Lifecycle != domainentry.PropertyLifecycleTombstoned {
		t.Fatalf("historical lifecycle = %s", historical.Definition.Lifecycle)
	}
	unknownID := domainentry.MustPropertyID("0198c0a2-7b3f-7c3e-9f2a-4b6e8d0f1a2b")
	if _, err := service.Definition(ctx, workspace, unknownID); !errors.Is(err, ErrDefinitionNotFound) {
		t.Fatalf("unknown id error = %v, want %v", err, ErrDefinitionNotFound)
	}
}
