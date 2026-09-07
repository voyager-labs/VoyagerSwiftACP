package entry

import "testing"

// TestConditionCatalogData validates the compiled generated Condition Registry
// catalog: version, operator/relation counts, structural validity, per-type
// operator coverage, and inverse symmetry. This is the canonical owner for the
// Condition Registry -> generated Go parity contract.
func TestConditionCatalogData(t *testing.T) {
	if ConditionCatalogData.Version != "2.2.0" {
		t.Errorf("catalog version = %q, want 2.2.0", ConditionCatalogData.Version)
	}
	if got := len(ConditionCatalogData.Operators); got != 20 {
		t.Errorf("operators = %d, want 20", got)
	}
	if got := len(ConditionCatalogData.Relations); got != 42 {
		t.Errorf("relations = %d, want 42", got)
	}
	if err := ConditionCatalogData.Valid(); err != nil {
		t.Errorf("catalog invalid: %v", err)
	}
}

// TestConditionCatalogPerTypeCounts asserts the exact per-native-type operator
// coverage (string 11, number 9, date 10, boolean 2, string_list 6,
// categorical 4).
func TestConditionCatalogPerTypeCounts(t *testing.T) {
	counts := map[ConditionNativeType]int{}
	for _, relation := range ConditionCatalogData.Relations {
		counts[relation.NativeType]++
	}
	want := map[ConditionNativeType]int{
		ConditionNativeTypeString:      11,
		ConditionNativeTypeNumber:      9,
		ConditionNativeTypeDate:        10,
		ConditionNativeTypeBoolean:     2,
		ConditionNativeTypeStringList:  6,
		ConditionNativeTypeCategorical: 4,
	}
	for nativeType, expected := range want {
		if counts[nativeType] != expected {
			t.Errorf("native type %s operators = %d, want %d", nativeType, counts[nativeType], expected)
		}
	}
}

// TestConditionCatalogInverseSymmetry asserts every non-empty inverse_of is
// symmetric.
func TestConditionCatalogInverseSymmetry(t *testing.T) {
	for _, operator := range ConditionCatalogData.Operators {
		if operator.InverseOf == "" {
			continue
		}
		inverse, ok := ConditionCatalogData.LookupOperator(operator.InverseOf)
		if !ok {
			t.Errorf("operator %s inverse %q missing", operator.ID, operator.InverseOf)
			continue
		}
		if inverse.InverseOf != operator.ID {
			t.Errorf("inverse not symmetric: %s <-> %s", operator.ID, operator.InverseOf)
		}
	}
}

// TestConditionCatalogLookup asserts typed operator and UI value-kind lookup.
func TestConditionCatalogLookup(t *testing.T) {
	operator, ok := ConditionCatalogData.LookupOperator("eq")
	if !ok {
		t.Fatalf("operator eq missing")
	}
	if operator.ValueShape != ConditionValueShapeSingle || operator.ValueCount != 1 {
		t.Errorf("eq shape/count = %s/%d, want single/1", operator.ValueShape, operator.ValueCount)
	}
	kind, ok := ConditionCatalogData.UISourceKind("eq", ConditionNativeTypeString)
	if !ok || kind != "singleText" {
		t.Errorf("eq/string ui kind = %q/%v, want singleText/true", kind, ok)
	}
	if _, ok := ConditionCatalogData.UISourceKind("gt", ConditionNativeTypeString); ok {
		t.Errorf("gt/string should not be a valid relation")
	}
}
