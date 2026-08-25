package property

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	schema "github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// TestExecuteAppliesMultiTargetChangesAtomicallyWithCanonicalReadBack은 다중 대상
// set·교체·clear가 하나의 트랜잭션에서 전부 적용되고 정준 read-back을 돌려주는
// 증거다.
func TestExecuteAppliesMultiTargetChangesAtomicallyWithCanonicalReadBack(t *testing.T) {
	harness := mustChangeHarness(t)
	mustSeedFact(t, harness.catalog, harness.facts, harness.workspace, harness.pathB.EntryRef.EntryID, harness.text.Definition.PropertyID, domainentry.AssignmentStateValue, 1, textValue("old"), nil)
	first := firstOptionID(t, harness.multi)
	second := harness.multi.Options[1].OptionID

	readBack, err := harness.service.Execute(context.Background(), harness.workspace, "req-execute-happy", []ChangeTarget{
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
			Desired:                    DesiredAssignment{State: domainentry.AssignmentStateValue, Many: manyOptions(second, first)},
		},
		{
			LocalPath:                  "/fixture/b.txt",
			PropertyID:                 harness.text.Definition.PropertyID,
			ExpectedDefinitionRevision: 1,
			ExpectedAssignmentRevision: 1,
			Desired:                    DesiredAssignment{State: domainentry.AssignmentStateUnset},
		},
	})
	if err != nil {
		t.Fatalf("execute error = %v", err)
	}
	if len(readBack) != 3 {
		t.Fatalf("read-back count = %d, want 3", len(readBack))
	}
	if readBack[0].RecordRevision != 1 || readBack[0].State != domainentry.AssignmentStateValue {
		t.Fatalf("first-touch read-back = rev %d state %s, want rev 1 value", readBack[0].RecordRevision, readBack[0].State)
	}
	if len(readBack[1].Many) != 2 || *readBack[1].Many[0].Value.OptionID != second || *readBack[1].Many[1].Value.OptionID != first {
		t.Fatal("ordered replace did not preserve request order")
	}
	if readBack[2].RecordRevision != 2 || readBack[2].State != domainentry.AssignmentStateUnset || readBack[2].Scalar != nil {
		t.Fatalf("clear read-back = rev %d state %s, want rev 2 unset without payload", readBack[2].RecordRevision, readBack[2].State)
	}
	if harness.runner.calls != 1 {
		t.Fatalf("execute ran %d WithinTx calls, want exactly 1", harness.runner.calls)
	}
	if harness.facts.saveCalls != 1 {
		t.Fatalf("execute issued %d save calls, want exactly 1 batched save", harness.facts.saveCalls)
	}
	committed, err := harness.facts.LoadAssignments(context.Background(), harness.workspace, []string{
		harness.pathA.EntryRef.EntryID, harness.pathB.EntryRef.EntryID,
	}, []domainentry.PropertyID{harness.text.Definition.PropertyID, harness.multi.Definition.PropertyID})
	if err != nil {
		t.Fatal(err)
	}
	committedByKey := make(map[factKey]domainentry.EntryPropertyAssignment, len(committed))
	for _, fact := range committed {
		committedByKey[keyOf(fact)] = fact
	}
	for index, row := range readBack {
		stored, ok := committedByKey[factKey{entryID: row.EntryID, propertyID: row.PropertyID}]
		if !ok || !reflect.DeepEqual(stored, row) {
			t.Fatalf("read-back %d differs from canonical persisted state", index)
		}
	}
}

// TestExecuteIsAllOrNoneWhenRepositoryFailsMidBatch는 저장소가 앞선 쓰기 뒤
// 실패하면 아무 것도 커밋되지 않음을 증명한다.
func TestExecuteIsAllOrNoneWhenRepositoryFailsMidBatch(t *testing.T) {
	harness := mustChangeHarness(t)
	harness.facts.failAfter = 1
	before := harness.facts.snapshot()
	_, err := harness.service.Execute(context.Background(), harness.workspace, "req-all-or-none", []ChangeTarget{
		textTarget(harness, "/fixture/a.txt", "one"),
		textTarget(harness, "/fixture/b.txt", "two"),
		textTarget(harness, "/fixture/c.txt", "three"),
	})
	if !errors.Is(err, errInjectedSaveFailure) {
		t.Fatalf("error = %v, want %v", err, errInjectedSaveFailure)
	}
	mustEqualFactSnapshot(t, before, harness.facts.snapshot())
}

// textTarget은 같은 (경로, text 정의) 변경을 만드는 헬퍼다. 같은 경로를 재사용해도
// PropertyID가 다르면 중복이 아니다.
func textTarget(harness changeHarness, path string, value string) ChangeTarget {
	return ChangeTarget{
		LocalPath:                  path,
		PropertyID:                 harness.text.Definition.PropertyID,
		ExpectedDefinitionRevision: 1,
		ExpectedAssignmentRevision: 0,
		Desired:                    DesiredAssignment{State: domainentry.AssignmentStateValue, Scalar: textValue(value)},
	}
}

// TestExecuteRejectsResponseBudgetBeforeAnyWrite는 개별 캡은 모두 통과해도 정준
// read-back 인코딩이 봉투를 넘으면 쓰기 전에 scope 예산으로 거절함을 증명한다.
func TestExecuteRejectsResponseBudgetBeforeAnyWrite(t *testing.T) {
	harness := mustChangeHarness(t)
	resolverPaths := make(map[string]ResolvedTarget, 32)
	targets := make([]ChangeTarget, 0, 32)
	entryIDs := make([]string, 0, 32)
	for index := 0; index < 32; index++ {
		name := "budget-" + string(rune('a'+index)) + ".txt"
		target := mustResolvedTargetFor(t, name)
		path := "/fixture/" + name
		resolverPaths[path] = target
		entryIDs = append(entryIDs, target.EntryRef.EntryID)
		targets = append(targets, ChangeTarget{
			LocalPath:                  path,
			PropertyID:                 harness.text.Definition.PropertyID,
			ExpectedDefinitionRevision: 1,
			ExpectedAssignmentRevision: 0,
			Desired:                    DesiredAssignment{State: domainentry.AssignmentStateValue, Scalar: textValue(strings.Repeat("x", 4096))},
		})
	}
	service, runner := mustChangeService(t, harness.catalog, harness.facts, stubPathResolver{paths: resolverPaths})
	before := harness.facts.snapshot()
	_, err := service.Execute(context.Background(), harness.workspace, "req-budget", targets)
	if !errors.Is(err, ErrScopeTooLarge) {
		t.Fatalf("error = %v, want %v", err, ErrScopeTooLarge)
	}
	if runner.calls != 1 {
		t.Fatalf("budget rejection ran %d WithinTx calls, want exactly 1", runner.calls)
	}
	if harness.facts.saveCalls != 0 {
		t.Fatalf("budget rejection issued %d save calls, want 0", harness.facts.saveCalls)
	}
	mustEqualFactSnapshot(t, before, harness.facts.snapshot())
}

// TestExecuteRejectsStaleMiddleTargetWithoutWriting은 중간 대상의 CAS 불일치가
// 전체 배치를 거절하는 증거다.
func TestExecuteRejectsStaleMiddleTargetWithoutWriting(t *testing.T) {
	harness := mustChangeHarness(t)
	stale := textTarget(harness, "/fixture/b.txt", "stale")
	stale.ExpectedAssignmentRevision = 7
	before := harness.facts.snapshot()
	_, err := harness.service.Execute(context.Background(), harness.workspace, "req-middle", []ChangeTarget{
		textTarget(harness, "/fixture/a.txt", "one"),
		stale,
		textTarget(harness, "/fixture/c.txt", "three"),
	})
	if !errors.Is(err, ErrStaleAssignmentRevision) {
		t.Fatalf("error = %v, want %v", err, ErrStaleAssignmentRevision)
	}
	mustEqualFactSnapshot(t, before, harness.facts.snapshot())
	if harness.facts.saveCalls != 0 {
		t.Fatalf("rejected execute issued %d save calls, want 0", harness.facts.saveCalls)
	}
}

// TestExecuteEmptyManyPersistsAsValueWithoutMembers는 빈 many가 멤버 없는 value로
// 기록됨을 증명한다.
func TestExecuteEmptyManyPersistsAsValueWithoutMembers(t *testing.T) {
	harness := mustChangeHarness(t)
	readBack, err := harness.service.Execute(context.Background(), harness.workspace, "req-empty-many", []ChangeTarget{{
		LocalPath:                  "/fixture/a.txt",
		PropertyID:                 harness.multi.Definition.PropertyID,
		ExpectedDefinitionRevision: 1,
		ExpectedAssignmentRevision: 0,
		Desired:                    DesiredAssignment{State: domainentry.AssignmentStateValue, Many: []domainentry.AssignmentValue{}},
	}})
	if err != nil {
		t.Fatalf("execute error = %v", err)
	}
	if readBack[0].State != domainentry.AssignmentStateValue || readBack[0].Many == nil || len(readBack[0].Many) != 0 {
		t.Fatalf("empty-many read-back = state %s many %v, want value with zero members", readBack[0].State, readBack[0].Many)
	}
}

// TestListAssignmentsReturnsSortedBoundedFacts는 단일 대상의 bounded assignment
// 목록을 증명한다.
func TestListAssignmentsReturnsSortedBoundedFacts(t *testing.T) {
	harness := mustChangeHarness(t)
	mustSeedFact(t, harness.catalog, harness.facts, harness.workspace, harness.pathA.EntryRef.EntryID, harness.multi.Definition.PropertyID, domainentry.AssignmentStateUnset, 3, nil, nil)
	facts, err := harness.service.ListAssignments(context.Background(), harness.workspace, "/fixture/a.txt", []domainentry.PropertyID{
		harness.multi.Definition.PropertyID, harness.text.Definition.PropertyID,
	})
	if err != nil {
		t.Fatalf("list error = %v", err)
	}
	if len(facts) != 1 {
		t.Fatalf("fact count = %d, want 1", len(facts))
	}
	if facts[0].PropertyID != harness.multi.Definition.PropertyID || facts[0].RecordRevision != 3 {
		t.Fatalf("unexpected fact %+v", facts[0])
	}
	tooMany := make([]domainentry.PropertyID, 257)
	for index := range tooMany {
		tooMany[index] = harness.text.Definition.PropertyID
	}
	if _, err := harness.service.ListAssignments(context.Background(), harness.workspace, "/fixture/a.txt", tooMany); !errors.Is(err, ErrInvalidChangeRequest) {
		t.Fatalf("unbounded list error = %v, want %v", err, ErrInvalidChangeRequest)
	}
}

// TestEncodedExecuteResponseBytesMatchProtocolEnvelope는 애플리케이션 read-back
// 인코더가 protocol EncodedSuccessBytes와 바이트 단위로 동일한 봉투를 만들고
// 초과를 같은 기준으로 판정함을 잠근다. payload가 nil인 행만 양쪽에서 직접
// 구성할 수 있어 그 경우 parity로 모양을 고정한다.
func TestEncodedExecuteResponseBytesMatchProtocolEnvelope(t *testing.T) {
	propertyID := mustUnknownPropertyID(t)
	entryID := mustResolvedTargetFor(t, "parity.txt").EntryRef.EntryID
	rows := []executeAssignmentWire{
		{PropertyID: propertyID.String(), EntryID: entryID, ValueType: "text", Cardinality: "one", State: "null", Revision: 4},
	}
	gotBytes, gotOK := encodedExecuteResponseBytes("req-parity", rows)
	wantResult := schema.PropertyChangeExecuteResult{Assignments: []schema.PropertyAssignment{{
		PropertyID: propertyID.String(), EntryID: entryID, ValueType: "text", Cardinality: "one", State: "null", Revision: 4,
	}}}
	wantBytes, wantOK := schema.EncodedSuccessBytes("req-parity", wantResult)
	if gotOK != wantOK || gotBytes != wantBytes {
		t.Fatalf("parity mismatch: got (%d,%v), want (%d,%v)", gotBytes, gotOK, wantBytes, wantOK)
	}
	huge := executeAssignmentWire{PropertyID: propertyID.String(), EntryID: entryID, ValueType: "text", Cardinality: "one", State: "value", Revision: 1, Value: strings.Repeat("x", 70000)}
	if _, ok := encodedExecuteResponseBytes("req-parity", []executeAssignmentWire{huge}); ok {
		t.Fatal("oversized read-back must not fit the wire envelope")
	}
}
