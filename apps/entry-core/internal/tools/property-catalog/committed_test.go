package propertycatalog

import (
	"os"
	"testing"
)

// committedPaths maps generated artifact to its committed repository path.
var committedPaths = map[string]string{
	"sql":         repoRootPrefix + "/apps/entry-core/internal/persistence/sqlite/seeds/0001_system_property_catalog_v2_4_1.sql",
	"catalog_gen": repoRootPrefix + "/apps/entry-core/internal/persistence/sqlite/seeds/catalog_gen.go",
	"condition":   repoRootPrefix + "/apps/entry-core/internal/domain/entry/property_condition_catalog_gen.go",
}

const repoRootPrefix = "../../../../.."

// TestCommittedOutputsCurrent regenerates every artifact and asserts it is
// byte-identical to the committed file. A missing or stale artifact fails,
// which is the RED gate for the generator --write step.
func TestCommittedOutputsCurrent(t *testing.T) {
	projection, err := ProjectSystemRegistry(loadSystemRegistry(t))
	if err != nil {
		t.Fatalf("project: %v", err)
	}
	sqlBody, err := RenderSQL(projection)
	if err != nil {
		t.Fatalf("render sql: %v", err)
	}
	registry := loadSystemRegistry(t)
	conditionRegistry := loadConditionRegistry(t)

	conditionBody, err := renderConditionCatalog(conditionRegistry)
	if err != nil {
		t.Fatalf("render condition: %v", err)
	}
	conditionBody, err = formatGo(conditionBody)
	if err != nil {
		t.Fatalf("format condition: %v", err)
	}
	catalogGenBody, err := renderCatalogGen(projection, sqlBody, registry)
	if err != nil {
		t.Fatalf("render catalog gen: %v", err)
	}
	catalogGenBody, err = formatGo(catalogGenBody)
	if err != nil {
		t.Fatalf("format catalog gen: %v", err)
	}

	for name, path := range committedPaths {
		existing, err := os.ReadFile(path)
		if err != nil {
			t.Errorf("committed %s missing: %v (run mise run entry-core-property-catalog-generate)", name, err)
			continue
		}
		var want string
		switch name {
		case "sql":
			want = sqlBody
		case "catalog_gen":
			want = catalogGenBody
		case "condition":
			want = conditionBody
		}
		if string(existing) != want {
			t.Errorf("committed %s is stale (run mise run entry-core-property-catalog-generate)", name)
		}
	}
}
