package shared

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

func TestPropertyWireFixtureInventoryCompleteness(t *testing.T) {
	data, err := os.ReadFile("entry_core_property_wire_cases.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		CatalogVersion  string   `json:"catalog_version"`
		InventoryDigest string   `json:"inventory_digest"`
		Methods         []string `json:"methods"`
		Operators       []string `json:"operators"`
		Relations       []string `json:"relations"`
	}
	if err := json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	wantMethods := []string{
		string(schema.MethodPropertyDefinitionList), string(schema.MethodPropertyDefinitionCreate), string(schema.MethodPropertyDefinitionUpdate), string(schema.MethodPropertyDefinitionDisable),
		string(schema.MethodPropertyOptionCreate), string(schema.MethodPropertyOptionUpdate), string(schema.MethodPropertyOptionReorder), string(schema.MethodPropertyOptionDisable),
		string(schema.MethodPropertyAssignmentList), string(schema.MethodPropertyChangePrepare), string(schema.MethodPropertyChangeExecute), string(schema.MethodPropertyConditionQuery),
	}
	if !reflect.DeepEqual(fixture.Methods, wantMethods) {
		t.Fatalf("method inventory = %#v", fixture.Methods)
	}
	if fixture.CatalogVersion != domainentry.ConditionCatalogVersion || len(fixture.Operators) != 20 || len(fixture.Relations) != 42 {
		t.Fatalf("catalog fixture = version %s, %d operators, %d relations", fixture.CatalogVersion, len(fixture.Operators), len(fixture.Relations))
	}
	inventory, err := json.Marshal(struct {
		CatalogVersion string   `json:"catalog_version"`
		Methods        []string `json:"methods"`
		Operators      []string `json:"operators"`
		Relations      []string `json:"relations"`
	}{CatalogVersion: fixture.CatalogVersion, Methods: fixture.Methods, Operators: fixture.Operators, Relations: fixture.Relations})
	if err != nil {
		t.Fatal(err)
	}
	if got := fmt.Sprintf("%x", sha256.Sum256(inventory)); got != fixture.InventoryDigest {
		t.Fatalf("inventory digest = %s, want %s", got, fixture.InventoryDigest)
	}
	for index, operator := range domainentry.ConditionCatalogData.Operators {
		if fixture.Operators[index] != operator.ID {
			t.Fatalf("operator %d = %q, want %q", index, fixture.Operators[index], operator.ID)
		}
	}
	for index, relation := range domainentry.ConditionCatalogData.Relations {
		want := relation.Operator + "/" + string(relation.NativeType)
		if fixture.Relations[index] != want {
			t.Fatalf("relation %d = %q, want %q", index, fixture.Relations[index], want)
		}
	}
}
