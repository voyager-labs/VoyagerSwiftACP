package runtime

import (
	"context"
	"testing"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

func TestPropertyConditionQueryTokenAuthenticatesOffsetAndContext(t *testing.T) {
	key := [32]byte{1, 2, 3}
	otherKey := [32]byte{4, 5, 6}
	params := &schema.PropertyConditionQueryParams{
		Targets:               []schema.PropertyTargetSelector{{Kind: "local_path", LocalPath: "/a"}},
		Combinator:            "all",
		Conditions:            []schema.PropertyCondition{{PropertyID: "00000000-0000-0000-8000-000000000001", Operator: "exists", Operand: schema.PropertyConditionOperand{Kind: "none"}}},
		ProjectionPropertyIDs: []string{}, EvaluationDate: "2026-09-01", PageSize: 1,
	}
	digest, ok := propertyQueryContextDigest("ws", params)
	if !ok {
		t.Fatal("context digest failed")
	}
	token := encodePropertyQueryToken(1, digest, key)
	offset, decoded, valid := decodePropertyQueryToken(token, key)
	if !valid || offset != 1 || decoded != digest {
		t.Fatalf("decoded = %d %x valid=%v", offset, decoded, valid)
	}
	if _, _, valid := decodePropertyQueryToken(token+"x", key); valid {
		t.Fatal("tampered token accepted")
	}
	if _, _, valid := decodePropertyQueryToken(token, otherKey); valid {
		t.Fatal("token survived daemon key restart")
	}

	changed := *params
	changed.Combinator = "any"
	changedDigest, _ := propertyQueryContextDigest("ws", &changed)
	if decoded == changedDigest {
		t.Fatal("combinator omitted from context")
	}
}

type conditionQueryErrorService struct {
	*recordingPropertyService
	err error
}

func (service conditionQueryErrorService) Query(context.Context, entry.WorkspaceContext, applicationproperty.ConditionQuery) (applicationproperty.ConditionQueryResult, error) {
	return applicationproperty.ConditionQueryResult{}, service.err
}

func TestConditionQueryMapsSourceRuntimeUnavailableToCanonicalCode(t *testing.T) {
	params := &schema.PropertyConditionQueryParams{
		Targets:               []schema.PropertyTargetSelector{{Kind: "local_path", LocalPath: "/a"}},
		Combinator:            "all",
		Conditions:            []schema.PropertyCondition{{PropertyID: "00000000-0000-0000-8000-000000000001", Operator: "exists", Operand: schema.PropertyConditionOperand{Kind: "none"}}},
		ProjectionPropertyIDs: []string{}, EvaluationDate: "2026-09-01", PageSize: 1,
	}
	runtime, err := NewWithPropertyService(testWorkspaceText, conditionQueryErrorService{
		recordingPropertyService: newRecordingPropertyService(),
		err:                      source.ErrSourceUnavailable,
	})
	if err != nil {
		t.Fatal(err)
	}
	response := runtime.Dispatch(context.Background(), schema.Request{
		RequestID:                    "condition-error",
		Method:                       schema.MethodPropertyConditionQuery,
		PropertyConditionQueryParams: params,
	})
	if response.Error == nil || response.Error.Code != schema.ErrorSourceRuntimeUnavailable {
		t.Fatalf("response error = %#v, want %q", response.Error, schema.ErrorSourceRuntimeUnavailable)
	}
}
