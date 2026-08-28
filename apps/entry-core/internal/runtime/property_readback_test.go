package runtime

import (
	"testing"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// 빈 many 배열은 원소로 유형을 추론할 수 없으므로 정의 valueType으로 복원해야
// 한다. boolean many 빈 값을 []string으로 만들면 NewPropertyPayload 검증이
// 실패해 커밋 후 internal_error가 된다.
func TestPayloadFromFactPreservesEmptyManyType(t *testing.T) {
	fact := domainentry.EntryPropertyAssignment{
		State: domainentry.AssignmentStateValue,
		Many:  []domainentry.OrderedAssignmentValue{},
	}
	booleanView := applicationproperty.DefinitionView{Definition: domainentry.WorkspacePropertyDefinition{
		ValueType: domainentry.PropertyTypeBoolean, Cardinality: domainentry.PropertyCardinalityMany,
	}}
	payload, ok := payloadFromFact(fact, booleanView)
	if !ok {
		t.Fatal("empty boolean many must convert")
	}
	if _, isBool := payload.Many().([]bool); !isBool {
		t.Fatalf("empty boolean many = %T, want []bool", payload.Many)
	}

	textView := applicationproperty.DefinitionView{Definition: domainentry.WorkspacePropertyDefinition{
		ValueType: domainentry.PropertyTypeText, Cardinality: domainentry.PropertyCardinalityMany,
	}}
	payload, ok = payloadFromFact(fact, textView)
	if !ok {
		t.Fatal("empty text many must convert")
	}
	if _, isText := payload.Many().([]string); !isText {
		t.Fatalf("empty text many = %T, want []string", payload.Many)
	}
}
