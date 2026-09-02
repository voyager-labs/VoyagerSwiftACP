package property

import (
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

func TestConditionCapabilityMappingCompleteness(t *testing.T) {
	catalog := domainentry.ConditionCatalogData
	if len(catalog.Operators) != 20 || len(catalog.Relations) != 42 {
		t.Fatalf("registry inventory = %d operators/%d relations, want 20/42", len(catalog.Operators), len(catalog.Relations))
	}
	operatorCases := map[string]bool{
		"all": true, "any": true, "btw": true, "cn": true, "empty": true,
		"eq": true, "ew": true, "exists": true, "gt": true, "gte": true,
		"lt": true, "lte": true, "miss": true, "nbtw": true, "nc": true,
		"neq": true, "none": true, "rx": true, "sw": true, "today": true,
	}
	for _, operator := range catalog.Operators {
		if !operatorCases[operator.ID] {
			t.Errorf("operator %q is neither mapped nor rejected", operator.ID)
		}
	}
	if len(operatorCases) != len(catalog.Operators) {
		t.Fatalf("operator mapping has stale members: %d", len(operatorCases))
	}

	// Every Registry relation has one explicit evaluator disposition. Keep this
	// tuple set hand-enumerated: a native-type substitution under an existing
	// operator must fail even when the source count remains 42.
	mappedRelations := map[string]struct{}{
		"all/string": {}, "all/string_list": {},
		"any/categorical": {}, "any/string": {}, "any/string_list": {},
		"btw/date": {}, "btw/number": {}, "cn/string": {},
		"empty/categorical": {}, "empty/string": {}, "empty/string_list": {},
		"eq/boolean": {}, "eq/date": {}, "eq/number": {}, "eq/string": {},
		"ew/string":      {},
		"exists/boolean": {}, "exists/categorical": {}, "exists/date": {},
		"exists/number": {}, "exists/string": {}, "exists/string_list": {},
		"gt/date": {}, "gt/number": {}, "gte/date": {}, "gte/number": {},
		"lt/date": {}, "lt/number": {}, "lte/date": {}, "lte/number": {},
		"miss/string_list": {}, "nbtw/date": {}, "nbtw/number": {},
		"nc/string": {}, "neq/date": {}, "neq/number": {}, "neq/string": {},
		"none/categorical": {}, "none/string_list": {}, "rx/string": {},
		"sw/string": {}, "today/date": {},
	}
	rejectedRelations := map[string]struct{}{}
	classified := make(map[string]struct{}, len(mappedRelations)+len(rejectedRelations))
	for key := range mappedRelations {
		classified[key] = struct{}{}
	}
	for key := range rejectedRelations {
		if _, duplicate := classified[key]; duplicate {
			t.Fatalf("relation %s is both mapped and rejected", key)
		}
		classified[key] = struct{}{}
	}
	if len(classified) != 42 {
		t.Fatalf("explicit relation dispositions = %d, want 42", len(classified))
	}

	relationSeen := make(map[string]struct{}, len(catalog.Relations))
	for _, relation := range catalog.Relations {
		key := relation.Operator + "/" + string(relation.NativeType)
		if _, duplicate := relationSeen[key]; duplicate {
			t.Fatalf("duplicate relation %s", key)
		}
		relationSeen[key] = struct{}{}
		if _, classifiedExactly := classified[key]; !classifiedExactly {
			t.Errorf("relation %s is neither mapped nor rejected", key)
		}
	}
	if len(relationSeen) != 42 {
		t.Fatalf("classified relations = %d, want 42", len(relationSeen))
	}
	for key := range classified {
		if _, present := relationSeen[key]; !present {
			t.Errorf("stale relation disposition %s is absent from source catalog", key)
		}
	}

	contracts := []struct {
		valueType   domainentry.PropertyType
		cardinality domainentry.PropertyCardinality
		native      domainentry.ConditionNativeType
		supported   bool
	}{
		{domainentry.PropertyTypeText, domainentry.PropertyCardinalityOne, domainentry.ConditionNativeTypeString, true},
		{domainentry.PropertyTypeText, domainentry.PropertyCardinalityMany, domainentry.ConditionNativeTypeStringList, true},
		{domainentry.PropertyTypeNumber, domainentry.PropertyCardinalityOne, domainentry.ConditionNativeTypeNumber, true},
		{domainentry.PropertyTypeDate, domainentry.PropertyCardinalityOne, domainentry.ConditionNativeTypeDate, true},
		{domainentry.PropertyTypeBoolean, domainentry.PropertyCardinalityOne, domainentry.ConditionNativeTypeBoolean, true},
		{domainentry.PropertyTypeSelect, domainentry.PropertyCardinalityOne, domainentry.ConditionNativeTypeCategorical, true},
		{domainentry.PropertyTypeSelect, domainentry.PropertyCardinalityMany, domainentry.ConditionNativeTypeCategorical, true},
		{domainentry.PropertyTypeDateTime, domainentry.PropertyCardinalityOne, "", false},
		{domainentry.PropertyTypeNumber, domainentry.PropertyCardinalityMany, "", false},
		{domainentry.PropertyTypeDate, domainentry.PropertyCardinalityMany, "", false},
		{domainentry.PropertyTypeBoolean, domainentry.PropertyCardinalityMany, "", false},
	}
	for _, test := range contracts {
		capability := ConditionCapabilityFor(domainentry.WorkspacePropertyDefinition{Origin: domainentry.PropertyOriginUserDefined, ValueType: test.valueType, Cardinality: test.cardinality, Lifecycle: domainentry.PropertyLifecycleActive})
		if capability.Supported != test.supported || capability.NativeType != test.native {
			t.Errorf("%s/%s capability = %+v", test.valueType, test.cardinality, capability)
		}
		if !test.supported && capability.Reason != "unsupported_value_contract" {
			t.Errorf("unsupported reason = %q", capability.Reason)
		}
	}
	sourceBacked := ConditionCapabilityFor(domainentry.WorkspacePropertyDefinition{
		Origin:      domainentry.PropertyOriginBuiltIn,
		ValueType:   domainentry.PropertyTypeText,
		Cardinality: domainentry.PropertyCardinalityOne,
		Lifecycle:   domainentry.PropertyLifecycleActive,
	})
	if sourceBacked.Supported || sourceBacked.Reason != "source_runtime_unavailable" {
		t.Fatalf("source-backed capability = %+v", sourceBacked)
	}
}

func TestConditionEvaluatorStateAndOperatorMatrix(t *testing.T) {
	propertyID, err := domainentry.RegistryPropertyID("condition.query.test")
	if err != nil {
		t.Fatal(err)
	}
	text := "AlphaBeta"
	decimal := "10.5"
	date := "2026-09-01"
	definition := func(valueType domainentry.PropertyType, cardinality domainentry.PropertyCardinality) DefinitionView {
		return DefinitionView{Definition: domainentry.WorkspacePropertyDefinition{PropertyID: propertyID, Origin: domainentry.PropertyOriginUserDefined, ValueType: valueType, Cardinality: cardinality, Lifecycle: domainentry.PropertyLifecycleActive}}
	}
	condition := func(operator, kind string, values ...string) QueryCondition {
		return QueryCondition{PropertyID: propertyID, Operator: operator, Operand: ConditionOperand{Kind: kind, Values: values}}
	}
	tests := []struct {
		name      string
		view      DefinitionView
		fact      domainentry.EntryPropertyAssignment
		condition QueryCondition
		want      bool
	}{
		{"implicit unset empty", definition(domainentry.PropertyTypeText, domainentry.PropertyCardinalityOne), domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateUnset}, condition("empty", "none"), true},
		{"null exists false", definition(domainentry.PropertyTypeText, domainentry.PropertyCardinalityOne), domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateNull}, condition("exists", "none"), false},
		{"empty many is empty", definition(domainentry.PropertyTypeText, domainentry.PropertyCardinalityMany), domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateValue, Many: []domainentry.OrderedAssignmentValue{}}, condition("empty", "none"), true},
		{"text case sensitive contains", definition(domainentry.PropertyTypeText, domainentry.PropertyCardinalityOne), domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateValue, Scalar: &domainentry.AssignmentValue{Text: &text}}, condition("cn", "text", "Alpha"), true},
		{"text case mismatch", definition(domainentry.PropertyTypeText, domainentry.PropertyCardinalityOne), domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateValue, Scalar: &domainentry.AssignmentValue{Text: &text}}, condition("cn", "text", "alpha"), false},
		{"wildcard rx", definition(domainentry.PropertyTypeText, domainentry.PropertyCardinalityOne), domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateValue, Scalar: &domainentry.AssignmentValue{Text: &text}}, condition("rx", "text", "Alpha*"), true},
		{"number greater", definition(domainentry.PropertyTypeNumber, domainentry.PropertyCardinalityOne), domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateValue, Scalar: &domainentry.AssignmentValue{Decimal: &decimal}}, condition("gt", "number", "10.05"), true},
		{"today fixed date", definition(domainentry.PropertyTypeDate, domainentry.PropertyCardinalityOne), domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateValue, Scalar: &domainentry.AssignmentValue{Date: &date}}, condition("today", "none"), true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := evaluateCondition(test.view, test.fact, test.condition, "2026-09-01"); got != test.want {
				t.Fatalf("evaluate = %v, want %v", got, test.want)
			}
		})
	}
	emptyText := ""
	emptyTextFact := domainentry.EntryPropertyAssignment{
		State:  domainentry.AssignmentStateValue,
		Scalar: &domainentry.AssignmentValue{Text: &emptyText},
	}
	if !evaluateCondition(
		definition(domainentry.PropertyTypeText, domainentry.PropertyCardinalityOne),
		emptyTextFact,
		condition("empty", "none"),
		"2026-09-01",
	) {
		t.Fatal("empty scalar text did not match empty")
	}
	if evaluateCondition(
		definition(domainentry.PropertyTypeText, domainentry.PropertyCardinalityOne),
		emptyTextFact,
		condition("exists", "none"),
		"2026-09-01",
	) {
		t.Fatal("empty scalar text matched exists")
	}
	dateFact := domainentry.EntryPropertyAssignment{
		State:  domainentry.AssignmentStateValue,
		Scalar: &domainentry.AssignmentValue{Date: &date},
	}
	if evaluateCondition(
		definition(domainentry.PropertyTypeDate, domainentry.PropertyCardinalityOne),
		dateFact,
		condition("gt", "number", "1"),
		"2026-09-01",
	) {
		t.Fatal("date condition accepted a number operand")
	}
	optionID := domainentry.MustPropertyOptionID("00000000-0000-7000-8000-000000000001")
	selectFact := domainentry.EntryPropertyAssignment{
		State:  domainentry.AssignmentStateValue,
		Scalar: &domainentry.AssignmentValue{OptionID: &optionID},
	}
	if evaluateCondition(
		definition(domainentry.PropertyTypeSelect, domainentry.PropertyCardinalityOne),
		selectFact,
		condition("any", "text", optionID.String()),
		"2026-09-01",
	) {
		t.Fatal("categorical condition accepted a text operand")
	}
}

func TestConditionEvaluatorStateTruthTableAndFailClosedRows(t *testing.T) {
	propertyID, err := domainentry.RegistryPropertyID("condition.query.truth-table")
	if err != nil {
		t.Fatal(err)
	}
	text := "value"
	activeView := DefinitionView{Definition: domainentry.WorkspacePropertyDefinition{PropertyID: propertyID, Origin: domainentry.PropertyOriginUserDefined, ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityMany, Lifecycle: domainentry.PropertyLifecycleActive}}
	states := []struct {
		name   string
		fact   domainentry.EntryPropertyAssignment
		empty  bool
		exists bool
	}{
		{"unset", domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateUnset}, true, false},
		{"null", domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateNull}, true, false},
		{"empty_many", domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateValue, Many: []domainentry.OrderedAssignmentValue{}}, true, false},
		{"value", domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateValue, Many: []domainentry.OrderedAssignmentValue{{Ordinal: 0, Value: domainentry.AssignmentValue{Text: &text}}}}, false, true},
	}
	operators := []struct {
		id   string
		want func(struct {
			name          string
			fact          domainentry.EntryPropertyAssignment
			empty, exists bool
		}) bool
	}{
		{"empty", func(row struct {
			name          string
			fact          domainentry.EntryPropertyAssignment
			empty, exists bool
		}) bool {
			return row.empty
		}},
		{"exists", func(row struct {
			name          string
			fact          domainentry.EntryPropertyAssignment
			empty, exists bool
		}) bool {
			return row.exists
		}},
	}
	for _, state := range states {
		for _, operator := range operators {
			t.Run(state.name+"/"+operator.id, func(t *testing.T) {
				condition := QueryCondition{PropertyID: propertyID, Operator: operator.id, Operand: ConditionOperand{Kind: "none"}}
				if got, want := evaluateCondition(activeView, state.fact, condition, "2026-09-01"), operator.want(state); got != want {
					t.Fatalf("evaluate = %v, want %v", got, want)
				}
			})
		}
	}

	valueFact := states[3].fact
	disabled := activeView
	disabled.Definition.Lifecycle = domainentry.PropertyLifecycleTombstoned
	if evaluateCondition(disabled, valueFact, QueryCondition{PropertyID: propertyID, Operator: "exists", Operand: ConditionOperand{Kind: "none"}}, "2026-09-01") {
		t.Fatal("disabled definition matched")
	}
	unsupported := activeView
	unsupported.Definition.ValueType = domainentry.PropertyTypeDateTime
	unsupported.Definition.Cardinality = domainentry.PropertyCardinalityOne
	if evaluateCondition(unsupported, valueFact, QueryCondition{PropertyID: propertyID, Operator: "exists", Operand: ConditionOperand{Kind: "none"}}, "2026-09-01") {
		t.Fatal("unsupported value contract matched")
	}

	optionID := domainentry.MustPropertyOptionID("00000000-0000-7000-8000-000000000001")
	selectView := DefinitionView{Definition: domainentry.WorkspacePropertyDefinition{PropertyID: propertyID, Origin: domainentry.PropertyOriginUserDefined, ValueType: domainentry.PropertyTypeSelect, Cardinality: domainentry.PropertyCardinalityOne, Lifecycle: domainentry.PropertyLifecycleActive}, Options: []domainentry.PropertyOption{{OptionID: optionID, PropertyID: propertyID, Active: false}}}
	selectFact := domainentry.EntryPropertyAssignment{State: domainentry.AssignmentStateValue, Scalar: &domainentry.AssignmentValue{OptionID: &optionID}}
	if evaluateCondition(selectView, selectFact, QueryCondition{PropertyID: propertyID, Operator: "any", Operand: ConditionOperand{Kind: "option_ref", Values: []string{optionID.String()}}}, "2026-09-01") {
		t.Fatal("inactive option operand matched")
	}
}
