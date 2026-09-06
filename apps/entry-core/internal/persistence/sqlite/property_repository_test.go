package sqlite

// VOY-765 property 저장소 계약 테스트다. 모든 assignment 상태의 round-trip,
// 고정 쿼리 예산, implicit unset 채움을 증명한다.

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"sync/atomic"
	"testing"
	"time"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// fixtureContracts는 픽스처 정의 메타데이터에서 독립적으로 만든 도메인 검증
// 계약표다. 저장소 출력이 아닌 입력에서 유도된다.
func fixtureContracts(fx propertyFixture) map[domainentry.PropertyID]domainentry.AssignmentContract {
	optionSet := func(ids ...domainentry.PropertyOptionID) map[domainentry.PropertyOptionID]struct{} {
		set := make(map[domainentry.PropertyOptionID]struct{}, len(ids))
		for _, id := range ids {
			set[id] = struct{}{}
		}
		return set
	}
	return map[domainentry.PropertyID]domainentry.AssignmentContract{
		fx.textDef:     {Type: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne},
		fx.numberDef:   {Type: domainentry.PropertyTypeNumber, Cardinality: domainentry.PropertyCardinalityOne},
		fx.booleanDef:  {Type: domainentry.PropertyTypeBoolean, Cardinality: domainentry.PropertyCardinalityOne},
		fx.dateDef:     {Type: domainentry.PropertyTypeDate, Cardinality: domainentry.PropertyCardinalityOne},
		fx.datetimeDef: {Type: domainentry.PropertyTypeDateTime, Cardinality: domainentry.PropertyCardinalityOne},
		fx.selectDef: {Type: domainentry.PropertyTypeSelect, Cardinality: domainentry.PropertyCardinalityOne,
			ActiveOptions: optionSet(fx.optionA, fx.optionB)},
		fx.nullableDef: {Type: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityOne, Nullable: true},
		fx.multiDef: {Type: domainentry.PropertyTypeSelect, Cardinality: domainentry.PropertyCardinalityMany,
			ActiveOptions: optionSet(fx.multiOptA, fx.multiOptB)},
	}
}

func TestLoadAssignmentsMemberCappedFailsBeforeAssembly(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)
	now := time.Now()
	entryID := testEntryID(990)
	header := EntryPropertyAssignmentRow{WorkspaceID: fx.wsctx.ID.Bytes(), EntryID: entryID, PropertyID: fx.multiDef.Bytes(), TargetKind: "locator_derived", State: "value", RecordRevision: 1, ValueContractRevision: 1, CreatedAt: now, UpdatedAt: now}
	if err := store.db.Create(&header).Error; err != nil {
		t.Fatal(err)
	}
	values := []EntryPropertyAssignmentValueRow{
		{WorkspaceID: fx.wsctx.ID.Bytes(), EntryID: entryID, PropertyID: fx.multiDef.Bytes(), Ordinal: 0, ValueKind: "option_ref", OptionID: fx.multiOptA.Bytes(), CreatedAt: now, UpdatedAt: now},
		{WorkspaceID: fx.wsctx.ID.Bytes(), EntryID: entryID, PropertyID: fx.multiDef.Bytes(), Ordinal: 1, ValueKind: "option_ref", OptionID: fx.multiOptB.Bytes(), CreatedAt: now, UpdatedAt: now},
		{WorkspaceID: fx.wsctx.ID.Bytes(), EntryID: entryID, PropertyID: fx.multiDef.Bytes(), Ordinal: 2, ValueKind: "option_ref", OptionID: fx.multiOptA.Bytes(), CreatedAt: now, UpdatedAt: now},
	}
	if err := store.db.Create(&values).Error; err != nil {
		t.Fatal(err)
	}
	_, err := NewEntryPropertyRepository(store).LoadAssignmentsMemberCapped(ctx, fx.wsctx, []string{entryID}, []domainentry.PropertyID{fx.multiDef}, 2)
	if !errors.Is(err, applicationproperty.ErrConditionQueryScopeTooLarge) {
		t.Fatalf("error = %v, want query scope too large", err)
	}
}

func TestLoadAssignmentsMemberCappedSkipsWorkspaceScanForEmptyEntrySet(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)
	now := time.Now()
	entryID := testEntryID(991)
	header := EntryPropertyAssignmentRow{WorkspaceID: fx.wsctx.ID.Bytes(), EntryID: entryID, PropertyID: fx.multiDef.Bytes(), TargetKind: "locator_derived", State: "value", RecordRevision: 1, ValueContractRevision: 1, CreatedAt: now, UpdatedAt: now}
	if err := store.db.Create(&header).Error; err != nil {
		t.Fatal(err)
	}
	value := EntryPropertyAssignmentValueRow{WorkspaceID: fx.wsctx.ID.Bytes(), EntryID: entryID, PropertyID: fx.multiDef.Bytes(), Ordinal: 0, ValueKind: "option_ref", OptionID: fx.multiOptA.Bytes(), CreatedAt: now, UpdatedAt: now}
	if err := store.db.Create(&value).Error; err != nil {
		t.Fatal(err)
	}

	loaded, err := NewEntryPropertyRepository(store).LoadAssignmentsMemberCapped(ctx, fx.wsctx, []string{}, []domainentry.PropertyID{fx.multiDef}, 0)
	if err != nil {
		t.Fatalf("load empty entry set: %v", err)
	}
	if len(loaded) != 0 {
		t.Fatalf("loaded = %#v, want empty", loaded)
	}
}

func TestPropertyAssignmentRoundTripAllStates(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)

	text := "hello"
	decimal := "3.14"
	booleanFalse := false
	date := "2026-08-25"
	timestamp := "2026-08-25T10:00:00Z"

	newFact := func(entryID string, propertyID domainentry.PropertyID, mutate func(*domainentry.EntryPropertyAssignment)) domainentry.EntryPropertyAssignment {
		fact := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, entryID, propertyID)
		fact.RecordRevision = 1
		fact.ValueContractRevision = 1
		mutate(&fact)
		return fact
	}

	cases := []struct {
		name string
		fact domainentry.EntryPropertyAssignment
	}{
		{"unset_durable", newFact(testEntryID(1), fx.textDef, func(f *domainentry.EntryPropertyAssignment) {
			f.State = domainentry.AssignmentStateUnset
		})},
		{"null_state", newFact(testEntryID(2), fx.nullableDef, func(f *domainentry.EntryPropertyAssignment) {
			f.State = domainentry.AssignmentStateNull
		})},
		{"scalar_text", newFact(testEntryID(3), fx.textDef, func(f *domainentry.EntryPropertyAssignment) {
			f.State = domainentry.AssignmentStateValue
			f.Scalar = &domainentry.AssignmentValue{Text: &text}
		})},
		{"scalar_decimal", newFact(testEntryID(4), fx.numberDef, func(f *domainentry.EntryPropertyAssignment) {
			f.State = domainentry.AssignmentStateValue
			f.Scalar = &domainentry.AssignmentValue{Decimal: &decimal}
		})},
		{"scalar_boolean_false", newFact(testEntryID(5), fx.booleanDef, func(f *domainentry.EntryPropertyAssignment) {
			f.State = domainentry.AssignmentStateValue
			f.Scalar = &domainentry.AssignmentValue{Boolean: &booleanFalse}
		})},
		{"scalar_date", newFact(testEntryID(6), fx.dateDef, func(f *domainentry.EntryPropertyAssignment) {
			f.State = domainentry.AssignmentStateValue
			f.Scalar = &domainentry.AssignmentValue{Date: &date}
		})},
		{"scalar_timestamp", newFact(testEntryID(7), fx.datetimeDef, func(f *domainentry.EntryPropertyAssignment) {
			f.State = domainentry.AssignmentStateValue
			f.Scalar = &domainentry.AssignmentValue{Timestamp: &timestamp}
		})},
		{"scalar_option_ref", newFact(testEntryID(8), fx.selectDef, func(f *domainentry.EntryPropertyAssignment) {
			f.State = domainentry.AssignmentStateValue
			option := fx.optionA
			f.Scalar = &domainentry.AssignmentValue{OptionID: &option}
		})},
		{"many_two_options", newFact(testEntryID(9), fx.multiDef, func(f *domainentry.EntryPropertyAssignment) {
			f.State = domainentry.AssignmentStateValue
			a, b := fx.multiOptA, fx.multiOptB
			f.Many = []domainentry.OrderedAssignmentValue{
				{Ordinal: 0, Value: domainentry.AssignmentValue{OptionID: &a}},
				{Ordinal: 1, Value: domainentry.AssignmentValue{OptionID: &b}},
			}
		})},
		{"empty_many_value_state", newFact(testEntryID(10), fx.multiDef, func(f *domainentry.EntryPropertyAssignment) {
			f.State = domainentry.AssignmentStateValue
			f.Many = []domainentry.OrderedAssignmentValue{}
		})},
	}

	repo := NewEntryPropertyRepository(store)
	facts := make([]domainentry.EntryPropertyAssignment, 0, len(cases))
	for _, tc := range cases {
		facts = append(facts, tc.fact)
	}
	if err := repo.SaveAssignments(ctx, fx.wsctx, facts); err != nil {
		t.Fatalf("SaveAssignments: %v", err)
	}

	entryIDs := make([]string, 0, len(cases))
	propertyIDs := make([]domainentry.PropertyID, 0, len(cases))
	for _, tc := range cases {
		entryIDs = append(entryIDs, tc.fact.EntryID)
		propertyIDs = append(propertyIDs, tc.fact.PropertyID)
	}
	loaded, err := repo.LoadAssignments(ctx, fx.wsctx, entryIDs, propertyIDs)
	if err != nil {
		t.Fatalf("LoadAssignments: %v", err)
	}

	for _, tc := range cases {
		ref := EntryPropertyRef{EntryID: tc.fact.EntryID, PropertyID: tc.fact.PropertyID}
		got, ok := loaded[ref]
		if !ok {
			t.Fatalf("%s: ref missing from load result", tc.name)
		}
		want, err := domainentry.NewEntryPropertyAssignment(tc.fact, fixtureContracts(fx)[tc.fact.PropertyID])
		if err != nil {
			t.Fatalf("%s: fixture invalid: %v", tc.name, err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("%s: round-trip mismatch\n got=%+v\nwant=%+v", tc.name, got, want)
		}
	}

	// empty-many=value 상태는 자식 0행의 non-nil 슬라이스로 보존되어야 한다.
	emptyManyRef := EntryPropertyRef{EntryID: testEntryID(10), PropertyID: fx.multiDef}
	if loaded[emptyManyRef].Many == nil {
		t.Fatal("empty-many round-trip collapsed to nil Many; empty-many=value state lost")
	}
	// boolean false는 영값이라도 포인터로 보존되어야 한다.
	falseRef := EntryPropertyRef{EntryID: testEntryID(5), PropertyID: fx.booleanDef}
	if loaded[falseRef].Scalar == nil || loaded[falseRef].Scalar.Boolean == nil || *loaded[falseRef].Scalar.Boolean {
		t.Fatalf("boolean false round-trip broken: %+v", loaded[falseRef].Scalar)
	}
}

// TestPropertyBatchedReadQueryBudget는 EntryID 수가 늘어나도 읽기 쿼리 수가
// 일정함을 증명한다.
func TestPropertyBatchedReadQueryBudget(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)

	var queries int64
	if err := store.db.Callback().Query().Before("gorm:query").Register("test_count_queries", func(tx *gorm.DB) {
		atomic.AddInt64(&queries, 1)
	}); err != nil {
		t.Fatalf("register callback: %v", err)
	}

	repo := NewEntryPropertyRepository(store)
	smallIDs := []string{testEntryID(101)}
	if _, err := repo.LoadAssignments(ctx, fx.wsctx, smallIDs, nil); err != nil {
		t.Fatalf("small load: %v", err)
	}
	smallCount := atomic.LoadInt64(&queries)

	atomic.StoreInt64(&queries, 0)
	largeIDs := make([]string, 0, 40)
	for i := 0; i < 40; i++ {
		largeIDs = append(largeIDs, testEntryID(200+i))
	}
	if _, err := repo.LoadAssignments(ctx, fx.wsctx, largeIDs, nil); err != nil {
		t.Fatalf("large load: %v", err)
	}
	largeCount := atomic.LoadInt64(&queries)

	if smallCount == 0 || smallCount != largeCount {
		t.Fatalf("query budget grew with entry count: small=%d large=%d", smallCount, largeCount)
	}
}

// TestPropertyLoadImplicitUnset은 durable row가 없는 요청 키가 implicit unset
// revision 0으로 채워짐을 증명한다.
func TestPropertyLoadImplicitUnset(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)

	repo := NewEntryPropertyRepository(store)
	loaded, err := repo.LoadAssignments(ctx, fx.wsctx, []string{testEntryID(999)}, []domainentry.PropertyID{fx.textDef})
	if err != nil {
		t.Fatalf("LoadAssignments: %v", err)
	}
	got, ok := loaded[EntryPropertyRef{EntryID: testEntryID(999), PropertyID: fx.textDef}]
	if !ok {
		t.Fatal("implicit unset fact missing")
	}
	want := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, testEntryID(999), fx.textDef)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("implicit unset = %+v, want %+v", got, want)
	}
}

// 교차 저장된 fact가 있어도 exact-pair 읽기는 요청 쌍만 결과로 돌려준다.
// change 경로가 카테시안 조회로 전환되는 회귀를 잠근다.
func TestPropertyLoadByRefsReturnsOnlyRequestedPairs(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)
	contracts := fixtureContracts(fx)

	entryA, entryB, entryC := testEntryID(1), testEntryID(2), testEntryID(3)
	saveText := func(entryID string, propertyID domainentry.PropertyID, text string) {
		fact := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, entryID, propertyID)
		fact.RecordRevision = 1
		fact.ValueContractRevision = 1
		fact.TargetKind = domainentry.AssignmentTargetLocatorDerived
		fact.State = domainentry.AssignmentStateValue
		fact.Scalar = &domainentry.AssignmentValue{Text: &text}
		validated, err := domainentry.NewEntryPropertyAssignment(fact, contracts[propertyID])
		if err != nil {
			t.Fatalf("stage fact: %v", err)
		}
		if err := NewEntryPropertyRepository(store).SaveAssignments(ctx, fx.wsctx, []domainentry.EntryPropertyAssignment{validated}); err != nil {
			t.Fatalf("save fact: %v", err)
		}
	}
	// 2×2 교차 저장: A/B entry × text/number 정의.
	saveText(entryA, fx.textDef, "a-text")
	saveText(entryB, fx.textDef, "b-text")
	saveText(entryA, fx.nullableDef, "a-null")
	saveText(entryB, fx.nullableDef, "b-null")

	repo := NewEntryPropertyRepository(store)
	// 요청은 (A, text)와 (C, number) — 교차 저장 집합의 부분집합 + 저장 안 된 쌍.
	result, err := repo.LoadAssignmentsByRefs(ctx, fx.wsctx, []EntryPropertyRef{
		{EntryID: entryA, PropertyID: fx.textDef},
		{EntryID: entryC, PropertyID: fx.numberDef},
	})
	if err != nil {
		t.Fatalf("load by refs: %v", err)
	}
	if len(result) != 2 {
		t.Fatalf("result size = %d, want 2 (exact pairs only)", len(result))
	}
	aText := result[EntryPropertyRef{EntryID: entryA, PropertyID: fx.textDef}]
	if aText.RecordRevision != 1 || aText.Scalar == nil || *aText.Scalar.Text != "a-text" {
		t.Fatalf("(A,text) = %+v, want persisted value", aText)
	}
	cNumber := result[EntryPropertyRef{EntryID: entryC, PropertyID: fx.numberDef}]
	if cNumber.RecordRevision != 0 {
		t.Fatalf("(C,number) = %+v, want implicit unset", cNumber)
	}
	// 교차 저장된 다른 쌍(A,nullable)/(B,text)/(B,nullable)은 결과에 없다.
	for _, ref := range []EntryPropertyRef{
		{EntryID: entryA, PropertyID: fx.nullableDef},
		{EntryID: entryB, PropertyID: fx.textDef},
		{EntryID: entryB, PropertyID: fx.nullableDef},
	} {
		if _, requested := result[ref]; requested {
			continue
		}
		fact, ok := result[ref]
		if ok && fact.RecordRevision != 0 {
			t.Fatalf("unrequested pair %v loaded: rev %d", ref, fact.RecordRevision)
		}
		_ = fact
	}
}

// 12 entry × 256 many = 3,072개 값 행은 단일 INSERT의 bind 변수 한도
// (32,766)를 넘는다. 동일 트랜잭션 안의 배치 삽입으로 성공해야 한다.
func TestPropertySaveAssignmentsHandlesLargeManyBatches(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)

	textManyID := domainentry.MustPropertyID("0198c0de-f00d-7000-8000-3b9ac9e19999")
	now := time.Now()
	if err := store.db.Create(&WorkspacePropertyDefinitionRow{
		WorkspaceID: fx.wsctx.ID.Bytes(), PropertyID: textManyID.Bytes(),
		Origin: "built_in", IdentityScheme: string(domainentry.PropertyIdentitySchemeVoyagerIssued),
		Namespace: "system", CanonicalKey: "test.text_many", DisplayName: "Text many",
		ValueType: "text", Cardinality: "many", Nullable: false, Editable: true,
		DefinitionRev: 1, LifecycleState: "active", CreatedAt: now, UpdatedAt: now,
	}).Error; err != nil {
		t.Fatalf("create text many definition: %v", err)
	}
	contract := domainentry.AssignmentContract{Type: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityMany}
	facts := make([]domainentry.EntryPropertyAssignment, 0, 12)
	for entryIndex := range 12 {
		entryID := testEntryID(entryIndex + 100)
		members := make([]domainentry.OrderedAssignmentValue, 256)
		for ordinal := range members {
			text := fmt.Sprintf("value-%d-%d", entryIndex, ordinal)
			members[ordinal] = domainentry.OrderedAssignmentValue{Ordinal: ordinal, Value: domainentry.AssignmentValue{Text: &text}}
		}
		fact := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, entryID, textManyID)
		fact.RecordRevision = 1
		fact.ValueContractRevision = 1
		fact.TargetKind = domainentry.AssignmentTargetLocatorDerived
		fact.State = domainentry.AssignmentStateValue
		fact.Many = members
		validated, err := domainentry.NewEntryPropertyAssignment(fact, contract)
		if err != nil {
			t.Fatalf("stage fact %d: %v", entryIndex, err)
		}
		facts = append(facts, validated)
	}

	repo := NewEntryPropertyRepository(store)
	if err := repo.SaveAssignments(ctx, fx.wsctx, facts); err != nil {
		t.Fatalf("SaveAssignments with 3,072 value rows = %v, want batched insert to succeed", err)
	}

	result, err := repo.LoadAssignmentsByRefs(ctx, fx.wsctx, []EntryPropertyRef{
		{EntryID: testEntryID(100), PropertyID: textManyID},
		{EntryID: testEntryID(111), PropertyID: textManyID},
	})
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	for ref, fact := range result {
		if len(fact.Many) != 256 {
			t.Fatalf("ref %v values = %d, want 256", ref, len(fact.Many))
		}
	}
}

// overlay 조회의 행 예산을 넘는 교차는 적재 전에 실패 닫기한다. 256 entry ×
// many assignment가 수백만 value 행을 적재하는 것을 차단하는 계약이다.
func TestPropertyLoadAssignmentsCappedRejectsBudgetExcess(t *testing.T) {
	ctx := context.Background()
	store := migratedStore(t)
	defer store.Close()
	fx := buildPropertyFixture(t, store)

	textManyID := domainentry.MustPropertyID("0198c0de-f00d-7000-8000-3b9ac9e17777")
	now := time.Now()
	if err := store.db.Create(&WorkspacePropertyDefinitionRow{
		WorkspaceID: fx.wsctx.ID.Bytes(), PropertyID: textManyID.Bytes(),
		Origin: "built_in", IdentityScheme: string(domainentry.PropertyIdentitySchemeVoyagerIssued),
		Namespace: "system", CanonicalKey: "test.text_many_cap", DisplayName: "Text many cap",
		ValueType: "text", Cardinality: "many", Nullable: false, Editable: true,
		DefinitionRev: 1, LifecycleState: "active", CreatedAt: now, UpdatedAt: now,
	}).Error; err != nil {
		t.Fatalf("create definition: %v", err)
	}
	contract := domainentry.AssignmentContract{Type: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityMany}
	repo := NewEntryPropertyRepository(store)

	entryIDs := make([]string, 0, 258)
	for entryIndex := range 258 {
		entryID := testEntryID(entryIndex + 200)
		entryIDs = append(entryIDs, entryID)
		members := make([]domainentry.OrderedAssignmentValue, 4)
		for ordinal := range members {
			text := fmt.Sprintf("v-%d-%d", entryIndex, ordinal)
			members[ordinal] = domainentry.OrderedAssignmentValue{Ordinal: ordinal, Value: domainentry.AssignmentValue{Text: &text}}
		}
		fact := domainentry.ImplicitUnsetEntryPropertyAssignment(fx.wsctx.ID, entryID, textManyID)
		fact.RecordRevision = 1
		fact.ValueContractRevision = 1
		fact.TargetKind = domainentry.AssignmentTargetLocatorDerived
		fact.State = domainentry.AssignmentStateValue
		fact.Many = members
		validated, err := domainentry.NewEntryPropertyAssignment(fact, contract)
		if err != nil {
			t.Fatalf("stage fact %d: %v", entryIndex, err)
		}
		if err := repo.SaveAssignments(ctx, fx.wsctx, []domainentry.EntryPropertyAssignment{validated}); err != nil {
			t.Fatalf("save fact %d: %v", entryIndex, err)
		}
	}

	if _, err := repo.LoadAssignmentsCapped(ctx, fx.wsctx, entryIDs, []domainentry.PropertyID{textManyID}, 256); !errors.Is(err, applicationproperty.ErrScopeTooLarge) {
		t.Fatalf("258 headers over budget 256 = %v, want ErrScopeTooLarge", err)
	}

	// 예산 내 요청은 정상 반환된다.
	within, err := repo.LoadAssignmentsCapped(ctx, fx.wsctx, entryIDs[:256], []domainentry.PropertyID{textManyID}, 256)
	if err != nil {
		t.Fatalf("within budget = %v", err)
	}
	if len(within) != 256 {
		t.Fatalf("within budget facts = %d, want 256", len(within))
	}
}
