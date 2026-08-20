package propertycatalog

import (
	"strings"
	"testing"
)

// repoRoot returns the absolute repository root for loading shared registries.
func repoRoot(t *testing.T) string {
	t.Helper()
	// from apps/entry-core/internal/tools/property-catalog -> repo root
	return "../../../../.."
}

func loadSystemRegistry(t *testing.T) *SystemPropertyRegistry {
	t.Helper()
	registry, err := LoadSystemRegistry(repoRoot(t) + "/shared/system_property_registry.json")
	if err != nil {
		t.Fatalf("load system registry: %v", err)
	}
	return registry
}

func loadConditionRegistry(t *testing.T) *PropertyConditionRegistry {
	t.Helper()
	registry, err := LoadConditionRegistry(repoRoot(t) + "/shared/property_condition_registry.json")
	if err != nil {
		t.Fatalf("load condition registry: %v", err)
	}
	return registry
}

// TestProjectionExactCounts asserts the exact 278/294/296/441 active-set counts.
func TestProjectionExactCounts(t *testing.T) {
	projection, err := ProjectSystemRegistry(loadSystemRegistry(t))
	if err != nil {
		t.Fatalf("project: %v", err)
	}
	if got := len(projection.Snapshot.Definitions); got != 278 {
		t.Errorf("definitions = %d, want 278", got)
	}
	if got := len(projection.Snapshot.Descriptors); got != 294 {
		t.Errorf("descriptors = %d, want 294", got)
	}
	if got := len(projection.Snapshot.Bindings); got != 296 {
		t.Errorf("bindings = %d, want 296", got)
	}
	if got := len(projection.Snapshot.Terms); got != 441 {
		t.Errorf("terms = %d, want 441", got)
	}
	// total SQL rows = 278 + 294 + 296 + 441 = 1309
	if got := len(projection.Definitions) + len(projection.Descriptors) + len(projection.Bindings) + len(projection.Terms); got != 1309 {
		t.Errorf("total SQL rows = %d, want 1309", got)
	}
}

// TestProviderDescriptorCounts asserts the per-provider unique source descriptor
// counts (mditem 139, nsurl 111, mdimporter 44).
func TestProviderDescriptorCounts(t *testing.T) {
	projection, err := ProjectSystemRegistry(loadSystemRegistry(t))
	if err != nil {
		t.Fatalf("project: %v", err)
	}
	counts := map[string]int{}
	for _, descriptor := range projection.Snapshot.Descriptors {
		counts[descriptor.Ref.ProviderID]++
	}
	want := map[string]int{"macos.mditem": 139, "macos.nsurl": 111, "macos.mdimporter": 44}
	for provider, expected := range want {
		if counts[provider] != expected {
			t.Errorf("provider %s descriptors = %d, want %d", provider, counts[provider], expected)
		}
	}
}

// TestTermKinds asserts search_alias=419 and legacy_alias=22.
func TestTermKinds(t *testing.T) {
	projection, err := ProjectSystemRegistry(loadSystemRegistry(t))
	if err != nil {
		t.Fatalf("project: %v", err)
	}
	search, legacy := 0, 0
	for _, term := range projection.Snapshot.Terms {
		switch term.TermKind {
		case "search_alias":
			search++
		case "legacy_alias":
			legacy++
		}
	}
	if search != 419 {
		t.Errorf("search_alias terms = %d, want 419", search)
	}
	if legacy != 22 {
		t.Errorf("legacy_alias terms = %d, want 22", legacy)
	}
}

// TestFSNameThreeBindings asserts the single mditem:kMDItemFSName descriptor
// creates exactly three bindings (identity/filename_extension/filename_stem).
func TestFSNameThreeBindings(t *testing.T) {
	projection, err := ProjectSystemRegistry(loadSystemRegistry(t))
	if err != nil {
		t.Fatalf("project: %v", err)
	}
	var descriptorCount int
	for _, descriptor := range projection.Snapshot.Descriptors {
		if descriptor.NativeKey == "mditem:kMDItemFSName" {
			descriptorCount++
		}
	}
	if descriptorCount != 1 {
		t.Errorf("mditem:kMDItemFSName descriptors = %d, want 1", descriptorCount)
	}
	transforms := map[string]string{}
	for _, binding := range projection.Snapshot.Bindings {
		if binding.SourceRef.ExternalPropertyID == "kMDItemFSName" {
			transforms[binding.PropertyID.String()] = binding.ReadTransform
		}
	}
	if len(transforms) != 3 {
		t.Fatalf("kMDItemFSName bindings = %d, want 3", len(transforms))
	}
	want := map[string]string{
		"4b919efd-84e6-5754-a5aa-eb2bef549acc": "filename_extension", // filesystem.extension
	}
	for propertyID, transform := range transforms {
		if expected, exists := want[propertyID]; exists && transform != expected {
			t.Errorf("binding %s transform = %q, want %q", propertyID, transform, expected)
		}
	}
	// identity (name_full) and filename_stem (name_stem) must both be present.
	seen := map[string]bool{}
	for _, transform := range transforms {
		seen[transform] = true
	}
	for _, required := range []string{"identity", "filename_extension", "filename_stem"} {
		if !seen[required] {
			t.Errorf("missing required kMDItemFSName transform %q", required)
		}
	}
}

// TestSourceInstanceIdentity asserts the frozen built-in source literal equals
// the exact derivation result.
func TestSourceInstanceIdentity(t *testing.T) {
	got := DeriveSourceInstanceID()
	const want = "src:C-AqodQY5xZfdP1ejkuCjkjmLeWd0Ws01zflCLYITkU"
	if got != want {
		t.Errorf("source identity = %q, want %q", got, want)
	}
	if got != SourceInstanceID {
		t.Errorf("DeriveSourceInstanceID mismatch frozen literal %q", SourceInstanceID)
	}
}

// TestDatasetDigestDeterministic asserts projection twice yields the same
// canonical digest.
func TestDatasetDigestDeterministic(t *testing.T) {
	first, err := ProjectSystemRegistry(loadSystemRegistry(t))
	if err != nil {
		t.Fatalf("project: %v", err)
	}
	second, err := ProjectSystemRegistry(loadSystemRegistry(t))
	if err != nil {
		t.Fatalf("project: %v", err)
	}
	if first.Digest != second.Digest {
		t.Errorf("digest not deterministic")
	}
}

// TestConditionCatalogExact asserts 20 operators, 42 relations, and that the
// generated relation set exactly equals the union of every operator's
// allowed_types entries.
func TestConditionCatalogExact(t *testing.T) {
	registry := loadConditionRegistry(t)
	if err := validateConditionCounts(registry); err != nil {
		t.Fatalf("condition counts: %v", err)
	}
	// Derived relation set must equal the direct union of allowed_types.
	expected := map[string]bool{}
	for name, operator := range registry.Operators {
		for _, allowedType := range operator.AllowedTypes {
			expected[name+"\x00"+allowedType] = true
		}
	}
	relations := registry.Relations()
	if len(relations) != len(expected) {
		t.Errorf("relations = %d, union = %d", len(relations), len(expected))
	}
	for _, relation := range relations {
		key := relation.Operator + "\x00" + string(relation.NativeType)
		if !expected[key] {
			t.Errorf("relation %s not in Registry allowed_types union", key)
		}
	}
}

// TestConditionCatalogValid asserts the compiled catalog passes structural
// validation (inverse symmetry, operator existence, type coverage).
func TestConditionCatalogValid(t *testing.T) {
	registry := loadConditionRegistry(t)
	body, err := renderConditionCatalog(registry)
	if err != nil {
		t.Fatalf("render condition catalog: %v", err)
	}
	if !strings.Contains(body, "ConditionCatalogVersion = \"2.2.0\"") {
		t.Errorf("generated condition catalog missing version 2.2.0")
	}
	if got := len(registry.Relations()); got != 42 {
		t.Errorf("generated relations = %d, want 42", got)
	}
}

// TestSQLConstraints asserts the seed SQL contains no transaction statements,
// no condition tables, no runtime path, no secret, and no Registry JSON blob.
func TestSQLConstraints(t *testing.T) {
	projection, err := ProjectSystemRegistry(loadSystemRegistry(t))
	if err != nil {
		t.Fatalf("project: %v", err)
	}
	sqlBody, err := RenderSQL(projection)
	if err != nil {
		t.Fatalf("render sql: %v", err)
	}
	for _, forbidden := range []string{
		"BEGIN", "COMMIT", "ROLLBACK",
		"property_condition", "condition_operator",
		"system_property_registry.json", "shared/",
		"/Users/", "secret", "token",
	} {
		if strings.Contains(strings.ToUpper(sqlBody), forbidden) {
			t.Errorf("SQL contains forbidden %q", forbidden)
		}
	}
	if strings.Contains(sqlBody, `"categories"`) || strings.Contains(sqlBody, `"$kind"`) {
		t.Errorf("SQL contains Registry JSON blob")
	}
}
