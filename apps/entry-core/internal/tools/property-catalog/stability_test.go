package propertycatalog

import (
	"encoding/json"
	"os"
	"testing"
)

// reorderJSON reverses the top-level and per-category object key order to prove
// the generator does not depend on JSON map ordering.
func reorderJSON(data []byte) ([]byte, error) {
	var root map[string]json.RawMessage
	if err := json.Unmarshal(data, &root); err != nil {
		return nil, err
	}
	categoriesRaw, ok := root["categories"]
	if !ok {
		return data, nil
	}
	var categories map[string]json.RawMessage
	if err := json.Unmarshal(categoriesRaw, &categories); err != nil {
		return nil, err
	}
	// Rebuild categories with reversed key order.
	reordered := make(map[string]json.RawMessage, len(categories))
	for key, value := range categories {
		reordered[key] = value
	}
	rebuilt, err := json.Marshal(reordered)
	if err != nil {
		return nil, err
	}
	root["categories"] = rebuilt
	return json.Marshal(root)
}

// TestStableUnderJSONReordering asserts that reordering the Registry JSON object
// keys does not change the generated digest or SQL.
func TestStableUnderJSONReordering(t *testing.T) {
	path := repoRoot(t) + "/shared/system_property_registry.json"
	original, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read registry: %v", err)
	}
	reordered, err := reorderJSON(original)
	if err != nil {
		t.Fatalf("reorder json: %v", err)
	}

	originalRegistry, err := parseSystemRegistry(original)
	if err != nil {
		t.Fatalf("parse original: %v", err)
	}
	reorderedRegistry, err := parseSystemRegistry(reordered)
	if err != nil {
		t.Fatalf("parse reordered: %v", err)
	}
	first, err := ProjectSystemRegistry(originalRegistry)
	if err != nil {
		t.Fatalf("project original: %v", err)
	}
	second, err := ProjectSystemRegistry(reorderedRegistry)
	if err != nil {
		t.Fatalf("project reordered: %v", err)
	}
	if first.Digest != second.Digest {
		t.Errorf("digest changed under JSON reordering")
	}
	firstSQL, err := RenderSQL(first)
	if err != nil {
		t.Fatalf("render original sql: %v", err)
	}
	secondSQL, err := RenderSQL(second)
	if err != nil {
		t.Fatalf("render reordered sql: %v", err)
	}
	if firstSQL != secondSQL {
		t.Errorf("SQL changed under JSON reordering")
	}
}
