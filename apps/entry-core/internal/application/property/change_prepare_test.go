package property

import (
	"context"
	"errors"
	"strings"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// mustTextDefinition은 편집 가능한 one-cardinality text 정의를 만든다.
func mustTextDefinition(t *testing.T, service *CatalogService, workspace domainentry.WorkspaceContext, key string) DefinitionView {
	t.Helper()
	return mustCreatedDefinition(t, service, workspace, key)
}

// mustMultiSelectDefinition은 선택지 둘을 가진 many-cardinality select 정의를 만든다.
func mustMultiSelectDefinition(t *testing.T, service *CatalogService, workspace domainentry.WorkspaceContext, key string) DefinitionView {
	t.Helper()
	view, err := service.CreateDefinition(context.Background(), workspace, CreateDefinitionInput{
		Key:          key,
		DisplayName:  key + " display",
		ValueType:    domainentry.PropertyTypeSelect,
		Cardinality:  domainentry.PropertyCardinalityMany,
		OptionLabels: []string{"first", "second"},
	})
	if err != nil {
		t.Fatal(err)
	}
	return view
}

// mustPreparedService는 text 정의 하나와 multi-select 정의 하나, 경로 세 개의
// resolver를 갖춘 변경 서비스 세트를 만든다.
type changeHarness struct {
	workspace domainentry.WorkspaceContext
	catalog   *memCatalogStore
	facts     *memFactStore
	service   *ChangeService
	runner    *changeTxRunner
	text      DefinitionView
	multi     DefinitionView
	pathA     ResolvedTarget
	pathB     ResolvedTarget
	pathC     ResolvedTarget
}

func mustChangeHarness(t *testing.T) changeHarness {
	t.Helper()
	workspace := mustWorkspaceContext(t)
	catalog := newMemCatalogStore()
	catalogService := mustCatalogService(t, catalog)
	text := mustTextDefinition(t, catalogService, workspace, "notes_note")
	multi := mustMultiSelectDefinition(t, catalogService, workspace, "notes_tags")
	pathA := mustResolvedTargetFor(t, "a.txt")
	pathB := mustResolvedTargetFor(t, "b.txt")
	pathC := mustResolvedTargetFor(t, "c.txt")
	resolver := stubPathResolver{paths: map[string]ResolvedTarget{
		"/fixture/a.txt": pathA,
		"/fixture/b.txt": pathB,
		"/fixture/c.txt": pathC,
	}}
	facts := newMemFactStore()
	service, runner := mustChangeService(t, catalog, facts, resolver)
	return changeHarness{
		workspace: workspace, catalog: catalog, facts: facts, service: service, runner: runner,
		text: text, multi: multi, pathA: pathA, pathB: pathB, pathC: pathC,
	}
}

// TestPrepareReturnsNonDurableProposalWithExpectedRevisions는 prepare가 어떤
// 쓰기도 하지 않으면서 대상 해석·정의 로드·revision 계산을 포함한 제안을
// 돌려주는 증거다.
func TestPrepareReturnsNonDurableProposalWithExpectedRevisions(t *testing.T) {
	harness := mustChangeHarness(t)
	proposal, err := harness.service.Prepare(context.Background(), harness.workspace, []ChangeTarget{
		{
			LocalPath:                  "/fixture/a.txt",
			PropertyID:                 harness.text.Definition.PropertyID,
			ExpectedDefinitionRevision: 1,
			ExpectedAssignmentRevision: 0,
			Desired:                    DesiredAssignment{State: domainentry.AssignmentStateValue, Scalar: textValue("hello")},
		},
		{
			LocalPath:                  "/fixture/b.txt",
			PropertyID:                 harness.multi.Definition.PropertyID,
			ExpectedDefinitionRevision: 1,
			ExpectedAssignmentRevision: 0,
			Desired:                    DesiredAssignment{State: domainentry.AssignmentStateValue, Many: manyOptions(firstOptionID(t, harness.multi))},
		},
	})
	if err != nil {
		t.Fatalf("prepare error = %v", err)
	}
	if len(proposal.Changes) != 2 {
		t.Fatalf("change count = %d, want 2", len(proposal.Changes))
	}
	for index, change := range proposal.Changes {
		if change.Before != nil {
			t.Fatalf("change %d Before = %v, want implicit unset", index, change.Before)
		}
		if change.After.RecordRevision != 1 {
			t.Fatalf("change %d first-touch revision = %d, want 1", index, change.After.RecordRevision)
		}
		if change.After.ValueContractRevision != 1 {
			t.Fatalf("change %d value contract revision = %d, want 1", index, change.After.ValueContractRevision)
		}
	}
	if proposal.RequiresConfirmation {
		t.Fatal("first-touch proposal must not require confirmation")
	}
	if harness.runner.calls != 0 {
		t.Fatalf("prepare ran %d WithinTx calls, want 0", harness.runner.calls)
	}
	if harness.facts.saveCalls != 0 {
		t.Fatalf("prepare issued %d save calls, want 0", harness.facts.saveCalls)
	}
}

// TestPrepareRejectsStaleDefinitionRevision은 정의 CAS 예상 revision 불일치를
// 거절하는 증거다.
func TestPrepareRejectsStaleDefinitionRevision(t *testing.T) {
	harness := mustChangeHarness(t)
	_, err := harness.service.Prepare(context.Background(), harness.workspace, []ChangeTarget{{
		LocalPath:                  "/fixture/a.txt",
		PropertyID:                 harness.text.Definition.PropertyID,
		ExpectedDefinitionRevision: 2,
		ExpectedAssignmentRevision: 0,
		Desired:                    DesiredAssignment{State: domainentry.AssignmentStateValue, Scalar: textValue("hello")},
	}})
	if !errors.Is(err, ErrStaleDefinitionRevision) {
		t.Fatalf("error = %v, want %v", err, ErrStaleDefinitionRevision)
	}
}

// TestPrepareRejectsStaleAndABAAssignmentRevisions은 예상 assignment revision이
// 현재와 다르면 상태가 같아도 거절함을 증명한다. unset@0 예상 뒤 set→clear로
// unset@2가 된 ABA 사례가 대표다.
func TestPrepareRejectsStaleAndABAAssignmentRevisions(t *testing.T) {
	harness := mustChangeHarness(t)
	mustSeedFact(t, harness.catalog, harness.facts, harness.workspace, harness.pathA.EntryRef.EntryID, harness.text.Definition.PropertyID, domainentry.AssignmentStateUnset, 2, nil, nil)
	_, err := harness.service.Prepare(context.Background(), harness.workspace, []ChangeTarget{{
		LocalPath:                  "/fixture/a.txt",
		PropertyID:                 harness.text.Definition.PropertyID,
		ExpectedDefinitionRevision: 1,
		ExpectedAssignmentRevision: 0,
		Desired:                    DesiredAssignment{State: domainentry.AssignmentStateValue, Scalar: textValue("hello")},
	}})
	if !errors.Is(err, ErrStaleAssignmentRevision) {
		t.Fatalf("ABA unset@0 expectation error = %v, want %v", err, ErrStaleAssignmentRevision)
	}
}

// TestPrepareRejectsInactiveOption은 비활성 선택지 참조를 거절하는 증거다.
func TestPrepareRejectsInactiveOption(t *testing.T) {
	harness := mustChangeHarness(t)
	disabled := firstOptionID(t, harness.multi)
	for index := range harness.catalog.opts[harness.multi.Definition.PropertyID] {
		if harness.catalog.opts[harness.multi.Definition.PropertyID][index].OptionID == disabled {
			harness.catalog.opts[harness.multi.Definition.PropertyID][index].Active = false
		}
	}
	_, err := harness.service.Prepare(context.Background(), harness.workspace, []ChangeTarget{{
		LocalPath:                  "/fixture/a.txt",
		PropertyID:                 harness.multi.Definition.PropertyID,
		ExpectedDefinitionRevision: 1,
		ExpectedAssignmentRevision: 0,
		Desired:                    DesiredAssignment{State: domainentry.AssignmentStateValue, Many: manyOptions(disabled)},
	}})
	if !errors.Is(err, domainentry.ErrAssignmentInactiveOption) {
		t.Fatalf("error = %v, want %v", err, domainentry.ErrAssignmentInactiveOption)
	}
}

// TestPrepareRejectsInvalidDesiredStates는 원하는 상태 변형별 실패 닫기 표다.
func TestPrepareRejectsInvalidDesiredStates(t *testing.T) {
	boolean := false
	cases := []struct {
		name   string
		change func(harness changeHarness) ChangeTarget
		want   error
	}{
		{
			name: "boolean scalar on text definition",
			change: func(harness changeHarness) ChangeTarget {
				return ChangeTarget{LocalPath: "/fixture/a.txt", PropertyID: harness.text.Definition.PropertyID, ExpectedDefinitionRevision: 1,
					Desired: DesiredAssignment{State: domainentry.AssignmentStateValue, Scalar: &domainentry.AssignmentValue{Boolean: &boolean}}}
			},
			want: domainentry.ErrAssignmentValueTypeMismatch,
		},
		{
			name: "many payload on one cardinality",
			change: func(harness changeHarness) ChangeTarget {
				return ChangeTarget{LocalPath: "/fixture/a.txt", PropertyID: harness.text.Definition.PropertyID, ExpectedDefinitionRevision: 1,
					Desired: DesiredAssignment{State: domainentry.AssignmentStateValue, Many: manyOptions()}}
			},
			want: domainentry.ErrAssignmentCardinalityMismatch,
		},
		{
			name: "unknown state",
			change: func(harness changeHarness) ChangeTarget {
				return ChangeTarget{LocalPath: "/fixture/a.txt", PropertyID: harness.text.Definition.PropertyID, ExpectedDefinitionRevision: 1,
					Desired: DesiredAssignment{State: "bogus"}}
			},
			want: ErrInvalidChangeRequest,
		},
		{
			name: "oversized scalar",
			change: func(harness changeHarness) ChangeTarget {
				return ChangeTarget{LocalPath: "/fixture/a.txt", PropertyID: harness.text.Definition.PropertyID, ExpectedDefinitionRevision: 1,
					Desired: DesiredAssignment{State: domainentry.AssignmentStateValue, Scalar: textValue(strings.Repeat("x", 4097))}}
			},
			want: ErrInvalidChangeRequest,
		},
		{
			name: "unknown property",
			change: func(harness changeHarness) ChangeTarget {
				return ChangeTarget{LocalPath: "/fixture/a.txt", PropertyID: mustUnknownPropertyID(t), ExpectedDefinitionRevision: 1,
					Desired: DesiredAssignment{State: domainentry.AssignmentStateUnset}}
			},
			want: ErrDefinitionNotFound,
		},
		{
			name: "duplicate target",
			change: func(harness changeHarness) ChangeTarget {
				return ChangeTarget{LocalPath: "/fixture/a.txt", PropertyID: harness.text.Definition.PropertyID, ExpectedDefinitionRevision: 1,
					Desired: DesiredAssignment{State: domainentry.AssignmentStateUnset}}
			},
			want: ErrDuplicateChangeTarget,
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			harness := mustChangeHarness(t)
			changes := []ChangeTarget{testCase.change(harness)}
			if testCase.want == ErrDuplicateChangeTarget {
				changes = append(changes, changes[0])
			}
			_, err := harness.service.Prepare(context.Background(), harness.workspace, changes)
			if !errors.Is(err, testCase.want) {
				t.Fatalf("error = %v, want %v", err, testCase.want)
			}
		})
	}
}

// TestPrepareRequiresConfirmationOnlyWhenReplacingDurableValue는 내구 row 교체에만
// 확인 플래그가 붙는 증거다.
func TestPrepareRequiresConfirmationOnlyWhenReplacingDurableValue(t *testing.T) {
	harness := mustChangeHarness(t)
	mustSeedFact(t, harness.catalog, harness.facts, harness.workspace, harness.pathA.EntryRef.EntryID, harness.text.Definition.PropertyID, domainentry.AssignmentStateValue, 1, textValue("old"), nil)
	proposal, err := harness.service.Prepare(context.Background(), harness.workspace, []ChangeTarget{{
		LocalPath:                  "/fixture/a.txt",
		PropertyID:                 harness.text.Definition.PropertyID,
		ExpectedDefinitionRevision: 1,
		ExpectedAssignmentRevision: 1,
		Desired:                    DesiredAssignment{State: domainentry.AssignmentStateUnset},
	}})
	if err != nil {
		t.Fatalf("prepare error = %v", err)
	}
	if !proposal.RequiresConfirmation {
		t.Fatal("replacing durable value must require confirmation")
	}
	if proposal.Changes[0].After.RecordRevision != 2 {
		t.Fatalf("clear revision = %d, want 2", proposal.Changes[0].After.RecordRevision)
	}
}
