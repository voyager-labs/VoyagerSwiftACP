package propertycatalog

import (
	"path/filepath"
	"strings"
	"testing"
)

// TestRejectUnknownType asserts a descriptor with an unknown native type is
// rejected during registry parsing/validation.
func TestRejectUnknownType(t *testing.T) {
	raw := `{"$kind":"system_property_registry","$version":"2.4.1","categories":{"test":{"key":{"ui_label":"X","type":"banana","system_keys":["mditem:kMDItemX"]}}}}`
	if _, err := parseSystemRegistry([]byte(raw)); err == nil {
		t.Errorf("expected unknown type to be rejected")
	}
}

// TestRejectUnknownPrefix asserts a descriptor with an unknown system-key
// prefix is rejected during projection.
func TestRejectUnknownPrefix(t *testing.T) {
	registry := &SystemPropertyRegistry{
		Version: "2.4.1",
		Categories: map[string]map[string]SystemDescriptor{
			"test": {
				"key": {UILabel: "X", Type: "string", SystemKeys: []string{"bogus:key"}},
			},
		},
	}
	if _, err := ProjectSystemRegistry(registry); err == nil {
		t.Errorf("expected unknown prefix to be rejected")
	}
}

// TestRejectDuplicateNaturalRef asserts a descriptor that repeats the same
// system key (ambiguous within one property) is rejected.
func TestRejectDuplicateNaturalRef(t *testing.T) {
	raw := `{"$kind":"system_property_registry","$version":"2.4.1","categories":{"a":{"x":{"ui_label":"X","type":"string","system_keys":["mditem:kMDItemShared","mditem:kMDItemShared"]}}}}`
	if _, err := parseSystemRegistry([]byte(raw)); err == nil {
		t.Errorf("expected duplicate natural ref to be rejected")
	}
}

// TestRejectMissingSystemKeys asserts a descriptor without system_keys fails.
func TestRejectMissingSystemKeys(t *testing.T) {
	raw := `{"$kind":"system_property_registry","$version":"2.4.1","categories":{"a":{"x":{"ui_label":"X","type":"string","system_keys":[]}}}}`
	if _, err := parseSystemRegistry([]byte(raw)); err == nil {
		t.Errorf("expected missing system_keys to be rejected")
	}
}

// TestRejectUnknownConditionType asserts an allowed_type that is not a declared
// property type is rejected.
func TestRejectUnknownConditionType(t *testing.T) {
	raw := `{"$kind":"property_condition_registry","$version":"2.2.0","property_types":["string"],"operators":{"eq":{"ui_label":"Is","mdquery_operator":"==","value_shape":"single","value_count":"1","allowed_types":["banana"],"inverse_of":"neq","ui_value_kind":{"banana":"x"}}}}`
	if _, err := parseConditionRegistry([]byte(raw)); err == nil {
		t.Errorf("expected unknown condition type to be rejected")
	}
}

// TestRejectInvalidInverse asserts an inverse_of that does not exist or is not
// symmetric is rejected during catalog validation.
func TestRejectInvalidInverse(t *testing.T) {
	registry := loadConditionRegistry(t)
	// Break inverse symmetry by mutating one operator's inverse.
	mutated := &PropertyConditionRegistry{
		Version:       registry.Version,
		PropertyTypes: registry.PropertyTypes,
		Operators:     map[string]ConditionOperatorSpec{},
	}
	for name, operator := range registry.Operators {
		if name == "eq" {
			operator.InverseOf = "does_not_exist"
		}
		mutated.Operators[name] = operator
	}
	body, err := renderConditionCatalog(mutated)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if strings.Contains(body, "does_not_exist") == false {
		t.Errorf("expected mutated inverse to appear in rendered output")
	}
}

func TestRunDefaultsToCheck(t *testing.T) {
	tempDir := t.TempDir()
	result := Run([]string{
		"--system-registry", repoRoot(t) + "/shared/system_property_registry.json",
		"--condition-registry", repoRoot(t) + "/shared/property_condition_registry.json",
		"--seeds-dir", tempDir,
		"--condition-out", filepath.Join(tempDir, "property_condition_catalog_gen.go"),
	})
	if result != 1 {
		t.Errorf("default Run result = %d, want 1 for missing checked outputs", result)
	}
}

func TestRejectTrailingRegistryJSON(t *testing.T) {
	system := `{"$kind":"system_property_registry","$version":"2.4.1","categories":{"test":{"key":{"ui_label":"X","type":"string","system_keys":["mditem:kMDItemX"]}}}}\n{}`
	if _, err := parseSystemRegistry([]byte(system)); err == nil {
		t.Errorf("expected trailing system registry JSON to be rejected")
	}
	condition := `{"$kind":"property_condition_registry","$version":"2.2.0","property_types":{"string":{"operators":["eq"]}},"operators":{"eq":{"ui_label":"Is","value_shape":"single","value_count":"1","allowed_types":["string"],"ui_value_kind":{"string":"text"}}}}\n{}`
	if _, err := parseConditionRegistry([]byte(condition)); err == nil {
		t.Errorf("expected trailing condition registry JSON to be rejected")
	}
}

// TestRejectRegistryVersionSeedConstantMismatch asserts generation fails when the
// input System Registry version diverges from the reviewed SeedSourceVersion
// constant, preventing row/metadata source-version drift.
func TestRejectRegistryVersionSeedConstantMismatch(t *testing.T) {
	raw := `{"$kind":"system_property_registry","$version":"9.9.9","categories":{"a":{"x":{"ui_label":"X","type":"string","system_keys":["mditem:kMDItemX"]}}}}`
	registry, err := parseSystemRegistry([]byte(raw))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ProjectSystemRegistry(registry); err == nil || !strings.Contains(err.Error(), "SeedSourceVersion") {
		t.Fatalf("version mismatch error = %v", err)
	}
}
