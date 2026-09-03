package schema

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"reflect"
	"sort"
	"strings"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// --- fixtures ---

func fixturePropertyID(t *testing.T, seed int) string {
	t.Helper()
	id, err := domainentry.RegistryPropertyID(fmt.Sprintf("wire.fixture.%d", seed))
	if err != nil {
		t.Fatalf("fixture property id: %v", err)
	}
	return id.String()
}

func fixtureEntryID(seed int) string {
	digest := sha256.Sum256([]byte(fmt.Sprintf("fixture-entry-%d", seed)))
	return "ent:" + base64.RawURLEncoding.EncodeToString(digest[:])
}

func fixtureOptionID(seed int) string {
	return fmt.Sprintf("00000000-0000-7000-8000-%012x", seed)
}

// ascendingUUID는 오름차순 배열 픽스처용 canonical UUID 텍스트다.
// 네 번째 그룹 "8000"은 RFC 9562 variant 비트(0b10)를 강제한다.
func ascendingUUID(n int) string {
	return fmt.Sprintf("00000000-0000-0000-8000-%012x", n)
}

func fixtureDefinitionJSON(id string) string {
	return `{"property_id":"` + id + `","key":"k","name":"n","value_type":"text","cardinality":"one","state":"active","revision":1,"options":[],"condition_capability":` + fixtureConditionCapabilityJSON() + `}`
}

func fixtureConditionCapabilityJSON() string {
	return `{"supported":true,"evaluation_scope":"local_assignment","catalog_version":"2.2.0","native_type":"string","allowed_operators":["all","any","cn","empty","eq","ew","exists","nc","neq","rx","sw"]}`
}
func fixtureConditionCapability() PropertyConditionCapability {
	return PropertyConditionCapability{Supported: true, EvaluationScope: "local_assignment", CatalogVersion: "2.2.0", NativeType: "string", AllowedOperators: []string{"all", "any", "cn", "empty", "eq", "ew", "exists", "nc", "neq", "rx", "sw"}}
}

// fixtureConditionCapabilityForContract는 value contract에서 유도되는 정확한
// native type과 Registry operator 집합을 담은 capability를 만든다. capability
// exactness 검사가 definition value contract와의 일치를 강제하므로 text가 아닌
// definition fixture는 이 helper로 capability를 만들어야 한다.
func fixtureConditionCapabilityForContract(valueType, cardinality string) PropertyConditionCapability {
	nativeType, ok := domainentry.ConditionNativeTypeForContract(domainentry.PropertyType(valueType), domainentry.PropertyCardinality(cardinality))
	if !ok {
		panic("fixture value contract is not condition-queryable")
	}
	operators := append([]string(nil), domainentry.ConditionCatalogData.OperatorsForType(nativeType)...)
	sort.Strings(operators)
	return PropertyConditionCapability{Supported: true, EvaluationScope: "local_assignment", CatalogVersion: domainentry.ConditionCatalogVersion, NativeType: string(nativeType), AllowedOperators: operators}
}

func fixtureAssignmentJSON(id, entryID string) string {
	return `{"property_id":"` + id + `","entry_id":"` + entryID + `","value_type":"text","cardinality":"one","state":"value","revision":1,"value":"v"}`
}

func fixtureChangeTargetJSON(id string) string {
	return `{"target":{"kind":"local_path","local_path":"/a/b"},"property_id":"` + id + `","expected_definition_revision":1,"expected_assignment_revision":1,"desired":{"state":"null"}}`
}

func propertyRequest(method Method, params string) []byte {
	return []byte(`{"request_id":"id","method":"` + string(method) + `","params":` + params + `}`)
}

func decodePropertyParams(t *testing.T, wire []byte) (Request, *ProtocolError) {
	t.Helper()
	request, _, protocolError := DecodeRequest(wire)
	return request, protocolError
}

// --- 1. 메서드 계약 완전성: 12개 메서드 각각 디코드/게이트/유니언 오류 ---

func TestPropertyMethodContractCompleteness(t *testing.T) {
	t.Parallel()

	pid := fixturePropertyID(t, 1)
	pid2 := fixtureOptionID(2)
	changeTarget := fixtureChangeTargetJSON(pid)

	methods := []struct {
		method Method
		params string
	}{
		{MethodPropertyDefinitionList, `{"page_size":1,"requested_property_ids":[]}`},
		{MethodPropertyDefinitionCreate, `{"key":"k","name":"n","value_type":"text","cardinality":"one"}`},
		{MethodPropertyDefinitionUpdate, `{"property_id":"` + pid + `","expected_definition_revision":1,"name":"n"}`},
		{MethodPropertyDefinitionDisable, `{"property_id":"` + pid + `","expected_definition_revision":1}`},
		{MethodPropertyOptionCreate, `{"property_id":"` + pid + `","expected_definition_revision":1,"label":"l"}`},
		{MethodPropertyOptionUpdate, `{"property_id":"` + pid + `","option_id":"` + pid2 + `","expected_definition_revision":1,"label":"l"}`},
		{MethodPropertyOptionReorder, `{"property_id":"` + pid + `","expected_definition_revision":1,"option_ids":["` + pid2 + `"]}`},
		{MethodPropertyOptionDisable, `{"property_id":"` + pid + `","option_id":"` + pid2 + `","expected_definition_revision":1}`},
		{MethodPropertyAssignmentList, `{"page_size":1,"requested_property_ids":[],"target":{"kind":"local_path","local_path":"/a"}}`},
		{MethodPropertyChangePrepare, `{"changes":[` + changeTarget + `]}`},
		{MethodPropertyChangeExecute, `{"changes":[` + changeTarget + `]}`},
		{MethodPropertyConditionQuery, `{"targets":[{"kind":"local_path","local_path":"/a"}],"combinator":"all","conditions":[{"property_id":"` + pid + `","operator":"exists","operand":{"kind":"none"}}],"projection_property_ids":[],"evaluation_date":"2026-09-01","page_size":1}`},
	}

	for _, test := range methods {
		t.Run(string(test.method), func(t *testing.T) {
			if !test.method.valid() {
				t.Fatalf("method %q is not registered in the gate", test.method)
			}
			request, _, protocolError := DecodeRequest(propertyRequest(test.method, test.params))
			if protocolError != nil {
				t.Fatalf("minimal valid request rejected: %#v", protocolError)
			}
			if request.Method != test.method {
				t.Fatalf("method = %q, want %q", request.Method, test.method)
			}
			// workspace_id는 어떤 DTO도 받지 않는다.
			injected := strings.Replace(test.params, `{`, `{"workspace_id":"ws","`, 1)
			_, _, protocolError = DecodeRequest(propertyRequest(test.method, injected))
			if protocolError == nil || protocolError.Code != ErrorInvalidRequest {
				t.Fatalf("workspace_id accepted: %#v", protocolError)
			}
			// 중복 키 거부.
			duplicated := strings.Replace(test.params, `{`, `{"page_size":1,"page_size":1,"__x":`, 1)
			_, _, protocolError = DecodeRequest(propertyRequest(test.method, duplicated))
			if protocolError == nil || protocolError.Code != ErrorInvalidRequest {
				t.Fatalf("duplicate key accepted: %#v", protocolError)
			}
			// 미지 멤버 거부.
			_, _, protocolError = DecodeRequest(propertyRequest(test.method, strings.Replace(test.params, `{`, `{"future_member":1,`, 1)))
			if protocolError == nil || protocolError.Code != ErrorInvalidRequest {
				t.Fatalf("unknown member accepted: %#v", protocolError)
			}
		})
	}
}

func TestPropertyConditionQueryRequestBoundsAndStrictness(t *testing.T) {
	pid1, pid2 := ascendingUUID(1), ascendingUUID(2)
	base := `{"targets":[{"kind":"local_path","local_path":"/a"}],"combinator":"all","conditions":[{"property_id":"` + pid1 + `","operator":"exists","operand":{"kind":"none"}}],"projection_property_ids":["` + pid2 + `"],"evaluation_date":"2026-09-01","page_size":1}`
	request, protocolError := decodePropertyParams(t, propertyRequest(MethodPropertyConditionQuery, base))
	if protocolError != nil || request.PropertyConditionQueryParams == nil {
		t.Fatalf("valid query rejected: %#v", protocolError)
	}
	cases := []struct {
		name, params string
		code         ErrorCode
	}{
		{"duplicate target", strings.Replace(base, `[{"kind":"local_path","local_path":"/a"}]`, `[{"kind":"local_path","local_path":"/a"},{"kind":"local_path","local_path":"/a"}]`, 1), ErrorInvalidRequest},
		{"duplicate condition", strings.Replace(base, `[{"property_id":"`+pid1+`","operator":"exists","operand":{"kind":"none"}}]`, `[{"property_id":"`+pid1+`","operator":"exists","operand":{"kind":"none"}},{"property_id":"`+pid1+`","operator":"empty","operand":{"kind":"none"}}]`, 1), ErrorInvalidRequest},
		{"bad date", strings.Replace(base, "2026-09-01", "2026-9-1", 1), ErrorInvalidRequest},
		{"wrong operand shape", strings.Replace(base, `"operand":{"kind":"none"}`, `"operand":{"kind":"text","values":["x"]}`, 1), ErrorInvalidRequest},
		{"unsorted projection", strings.Replace(base, `"projection_property_ids":["`+pid2+`"]`, `"projection_property_ids":["`+pid2+`","`+pid1+`"]`, 1), ErrorInvalidRequest},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			_, got := decodePropertyParams(t, propertyRequest(MethodPropertyConditionQuery, test.params))
			if got == nil || got.Code != test.code {
				t.Fatalf("error = %#v, want %s", got, test.code)
			}
		})
	}

	targets := make([]string, 17)
	for index := range targets {
		targets[index] = `{"kind":"local_path","local_path":"/` + fmt.Sprint(index) + `"}`
	}
	conditions := make([]string, 256)
	for index := range conditions {
		conditions[index] = `{"property_id":"` + ascendingUUID(index+1) + `","operator":"exists","operand":{"kind":"none"}}`
	}
	atLimit := `{"targets":[` + strings.Join(targets[:16], ",") + `],"combinator":"all","conditions":[` + strings.Join(conditions[:256], ",") + `],"projection_property_ids":[],"evaluation_date":"2026-09-01","page_size":1}`
	if _, got := decodePropertyParams(t, propertyRequest(MethodPropertyConditionQuery, atLimit)); got != nil {
		t.Fatalf("4096 work units rejected: %#v", got)
	}
	over := `{"targets":[` + strings.Join(targets, ",") + `],"combinator":"all","conditions":[` + strings.Join(conditions[:241], ",") + `],"projection_property_ids":[],"evaluation_date":"2026-09-01","page_size":1}`
	if _, got := decodePropertyParams(t, propertyRequest(MethodPropertyConditionQuery, over)); got == nil || got.Code != ErrorScopeTooLarge {
		t.Fatalf("4097 work units error = %#v", got)
	}
}

// --- 2. definition.list 파라미터 매트릭스 ---

func TestPropertyDefinitionListParamsMatrix(t *testing.T) {
	t.Parallel()

	pid := fixturePropertyID(t, 3)
	tests := []struct {
		name   string
		params string
		want   ErrorCode
	}{
		{name: "happy minimal", params: `{"page_size":1,"requested_property_ids":[]}`},
		{name: "happy with filter and token", params: `{"page_size":256,"requested_property_ids":["` + pid + `"],"include_disabled":true,"page_token":"tok"}`},
		{name: "missing requested_property_ids", params: `{"page_size":1}`, want: ErrorInvalidRequest},
		{name: "filter not array", params: `{"page_size":1,"requested_property_ids":"x"}`, want: ErrorInvalidRequest},
		{name: "filter item not uuid", params: `{"page_size":1,"requested_property_ids":["nope"]}`, want: ErrorInvalidRequest},
		{name: "filter duplicate uuid", params: `{"page_size":1,"requested_property_ids":["` + pid + `","` + pid + `"]}`, want: ErrorInvalidRequest},
		{name: "include_disabled not bool", params: `{"page_size":1,"requested_property_ids":[],"include_disabled":"yes"}`, want: ErrorInvalidRequest},
		{name: "token not ascii opaque", params: `{"page_size":1,"requested_property_ids":[],"page_token":"🚀"}`, want: ErrorInvalidRequest},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request, protocolError := decodePropertyParams(t, propertyRequest(MethodPropertyDefinitionList, test.params))
			if test.want != "" {
				if protocolError == nil || protocolError.Code != test.want {
					t.Fatalf("error = %#v, want %q", protocolError, test.want)
				}
				return
			}
			if protocolError != nil {
				t.Fatalf("unexpected error: %#v", protocolError)
			}
			if request.PropertyDefinitionListParams == nil || request.PropertyDefinitionListParams.PageSize < 1 {
				t.Fatalf("params not decoded: %#v", request.PropertyDefinitionListParams)
			}
		})
	}
}

// --- 3. definition 생성/갱신/비활성 파라미터 매트릭스 ---

func TestPropertyDefinitionMutationParamsMatrix(t *testing.T) {
	t.Parallel()

	pid := fixturePropertyID(t, 4)
	optionLabel := func(n int) string {
		items := make([]string, n)
		for i := range items {
			items[i] = `{"label":"o` + fmt.Sprint(i) + `"}`
		}
		return "[" + strings.Join(items, ",") + "]"
	}
	tests := []struct {
		name   string
		method Method
		params string
		want   ErrorCode
	}{
		{name: "create happy", method: MethodPropertyDefinitionCreate, params: `{"key":"k","name":"n","value_type":"select","cardinality":"many","options":` + optionLabel(2) + `}`},
		{name: "create select without options", method: MethodPropertyDefinitionCreate, params: `{"key":"k","name":"n","value_type":"select","cardinality":"one"}`},
		{name: "create non-select with options", method: MethodPropertyDefinitionCreate, params: `{"key":"k","name":"n","value_type":"text","cardinality":"one","options":[{"label":"o"}]}`, want: ErrorInvalidRequest},
		{name: "create unknown value type", method: MethodPropertyDefinitionCreate, params: `{"key":"k","name":"n","value_type":"float","cardinality":"one"}`, want: ErrorInvalidRequest},
		{name: "create unknown cardinality", method: MethodPropertyDefinitionCreate, params: `{"key":"k","name":"n","value_type":"text","cardinality":"some"}`, want: ErrorInvalidRequest},
		{name: "update happy", method: MethodPropertyDefinitionUpdate, params: `{"property_id":"` + pid + `","expected_definition_revision":3,"name":"n2"}`},
		{name: "update zero revision", method: MethodPropertyDefinitionUpdate, params: `{"property_id":"` + pid + `","expected_definition_revision":0,"name":"n2"}`, want: ErrorInvalidRequest},
		{name: "disable happy", method: MethodPropertyDefinitionDisable, params: `{"property_id":"` + pid + `","expected_definition_revision":1}`},
		{name: "disable missing revision", method: MethodPropertyDefinitionDisable, params: `{"property_id":"` + pid + `"}`, want: ErrorInvalidRequest},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, protocolError := decodePropertyParams(t, propertyRequest(test.method, test.params))
			if test.want != "" {
				if protocolError == nil || protocolError.Code != test.want {
					t.Fatalf("error = %#v, want %q", protocolError, test.want)
				}
				return
			}
			if protocolError != nil {
				t.Fatalf("unexpected error: %#v", protocolError)
			}
		})
	}
}

// --- 4. option 변형 파라미터 매트릭스 ---

func TestPropertyOptionMutationParamsMatrix(t *testing.T) {
	t.Parallel()

	pid, oid := fixturePropertyID(t, 5), fixtureOptionID(6)
	wrongVersionOptionID := fixturePropertyID(t, 6)
	tests := []struct {
		name   string
		method Method
		params string
		want   ErrorCode
	}{
		{name: "create happy", method: MethodPropertyOptionCreate, params: `{"property_id":"` + pid + `","expected_definition_revision":1,"label":"l"}`},
		{name: "create empty label", method: MethodPropertyOptionCreate, params: `{"property_id":"` + pid + `","expected_definition_revision":1,"label":""}`, want: ErrorInvalidRequest},
		{name: "update happy", method: MethodPropertyOptionUpdate, params: `{"property_id":"` + pid + `","option_id":"` + oid + `","expected_definition_revision":1,"label":"l2"}`},
		{name: "update bad option id", method: MethodPropertyOptionUpdate, params: `{"property_id":"` + pid + `","option_id":"zz","expected_definition_revision":1,"label":"l2"}`, want: ErrorInvalidRequest},
		{name: "update wrong option id version", method: MethodPropertyOptionUpdate, params: `{"property_id":"` + pid + `","option_id":"` + wrongVersionOptionID + `","expected_definition_revision":1,"label":"l2"}`, want: ErrorInvalidRequest},
		{name: "reorder happy", method: MethodPropertyOptionReorder, params: `{"property_id":"` + pid + `","expected_definition_revision":1,"option_ids":["` + oid + `"]}`},
		{name: "reorder wrong option id version", method: MethodPropertyOptionReorder, params: `{"property_id":"` + pid + `","expected_definition_revision":1,"option_ids":["` + wrongVersionOptionID + `"]}`, want: ErrorInvalidRequest},
		{name: "reorder duplicate ids", method: MethodPropertyOptionReorder, params: `{"property_id":"` + pid + `","expected_definition_revision":1,"option_ids":["` + oid + `","` + oid + `"]}`, want: ErrorInvalidRequest},
		{name: "reorder empty ids", method: MethodPropertyOptionReorder, params: `{"property_id":"` + pid + `","expected_definition_revision":1,"option_ids":[]}`, want: ErrorInvalidRequest},
		{name: "disable happy", method: MethodPropertyOptionDisable, params: `{"property_id":"` + pid + `","option_id":"` + oid + `","expected_definition_revision":1}`},
		{name: "disable wrong option id version", method: MethodPropertyOptionDisable, params: `{"property_id":"` + pid + `","option_id":"` + wrongVersionOptionID + `","expected_definition_revision":1}`, want: ErrorInvalidRequest},
		{name: "disable missing option id", method: MethodPropertyOptionDisable, params: `{"property_id":"` + pid + `","expected_definition_revision":1}`, want: ErrorInvalidRequest},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, protocolError := decodePropertyParams(t, propertyRequest(test.method, test.params))
			if test.want != "" {
				if protocolError == nil || protocolError.Code != test.want {
					t.Fatalf("error = %#v, want %q", protocolError, test.want)
				}
				return
			}
			if protocolError != nil {
				t.Fatalf("unexpected error: %#v", protocolError)
			}
		})
	}
}

// --- 5. assignment.list 대상 선택자 매트릭스 ---

func TestPropertyAssignmentListTargetMatrix(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		target string
		want   ErrorCode
	}{
		{name: "happy local path", target: `{"kind":"local_path","local_path":"/Users/me/file.txt"}`},
		{name: "root path", target: `{"kind":"local_path","local_path":"/"}`, want: ErrorInvalidPath},
		{name: "relative path", target: `{"kind":"local_path","local_path":"Users/me"}`, want: ErrorInvalidPath},
		{name: "non-clean path", target: `{"kind":"local_path","local_path":"/a//b"}`, want: ErrorInvalidPath},
		{name: "dot segment", target: `{"kind":"local_path","local_path":"/a/./b"}`, want: ErrorInvalidPath},
		{name: "dotdot segment", target: `{"kind":"local_path","local_path":"/a/../b"}`, want: ErrorInvalidPath},
		{name: "trailing slash", target: `{"kind":"local_path","local_path":"/a/"}`, want: ErrorInvalidPath},
		{name: "nul byte", target: "{\"kind\":\"local_path\",\"local_path\":\"/a\\u0000b\"}", want: ErrorInvalidPath},
		{name: "unknown kind", target: `{"kind":"smb_path","local_path":"/a"}`, want: ErrorInvalidRequest},
		{name: "missing kind", target: `{"local_path":"/a"}`, want: ErrorInvalidRequest},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			params := `{"page_size":1,"requested_property_ids":[],"target":` + test.target + `}`
			request, protocolError := decodePropertyParams(t, propertyRequest(MethodPropertyAssignmentList, params))
			if test.want != "" {
				if protocolError == nil || protocolError.Code != test.want {
					t.Fatalf("error = %#v, want %q", protocolError, test.want)
				}
				return
			}
			if protocolError != nil {
				t.Fatalf("unexpected error: %#v", protocolError)
			}
			if request.PropertyAssignmentListParams == nil || request.PropertyAssignmentListParams.Target.LocalPath != "/Users/me/file.txt" && request.PropertyAssignmentListParams.Target.LocalPath != "/" {
				t.Fatalf("target not decoded: %#v", request.PropertyAssignmentListParams)
			}
		})
	}
}

// --- 6. change prepare/execute 원하는 상태 유니언 매트릭스 ---

func TestPropertyChangeDesiredStateMatrix(t *testing.T) {
	t.Parallel()

	pid := fixturePropertyID(t, 7)
	selectID := fixtureOptionID(8)
	wrongVersionOptionID := fixturePropertyID(t, 8)
	target := func(desired string) string {
		return `{"changes":[{"target":{"kind":"local_path","local_path":"/a"},"property_id":"` + pid + `","expected_definition_revision":1,"expected_assignment_revision":1,"desired":` + desired + `}]}`
	}
	tests := []struct {
		name    string
		desired string
		want    ErrorCode
	}{
		{name: "null state", desired: `{"state":"null"}`},
		{name: "unknown state", desired: `{"state":"unknown"}`},
		{name: "not_applicable state", desired: `{"state":"not_applicable"}`},
		{name: "value text one", desired: `{"state":"value","value_type":"text","cardinality":"one","value":"hello"}`},
		{name: "value boolean many", desired: `{"state":"value","value_type":"boolean","cardinality":"many","value":[true,false]}`},
		{name: "value select option id", desired: `{"state":"value","value_type":"select","cardinality":"one","value":"` + selectID + `"}`},
		{name: "select value wrong option id version", desired: `{"state":"value","value_type":"select","cardinality":"one","value":"` + wrongVersionOptionID + `"}`, want: ErrorInvalidRequest},
		{name: "error state not writable", desired: `{"state":"error"}`, want: ErrorInvalidRequest},
		{name: "null with payload", desired: `{"state":"null","value":1}`, want: ErrorInvalidRequest},
		{name: "value missing payload", desired: `{"state":"value","value_type":"text","cardinality":"one"}`, want: ErrorInvalidRequest},
		{name: "value type mismatch", desired: `{"state":"value","value_type":"boolean","cardinality":"one","value":"x"}`, want: ErrorInvalidRequest},
		{name: "select value not option id", desired: `{"state":"value","value_type":"select","cardinality":"one","value":"label"}`, want: ErrorInvalidRequest},
		{name: "number not canonical decimal", desired: `{"state":"value","value_type":"number","cardinality":"one","value":"1e5"}`, want: ErrorInvalidRequest},
		{name: "datetime not canonical", desired: `{"state":"value","value_type":"datetime","cardinality":"one","value":"2026-08-25"}`, want: ErrorInvalidRequest},
		{name: "extra member", desired: `{"state":"null","extra":1}`, want: ErrorInvalidRequest},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, protocolError := decodePropertyParams(t, propertyRequest(MethodPropertyChangeExecute, target(test.desired)))
			if test.want != "" {
				if protocolError == nil || protocolError.Code != test.want {
					t.Fatalf("error = %#v, want %q", protocolError, test.want)
				}
				return
			}
			if protocolError != nil {
				t.Fatalf("unexpected error: %#v", protocolError)
			}
		})
	}

	// 준비와 실행이 동일한 변경 대상 DTO를 공유한다.
	request, protocolError := decodePropertyParams(t, propertyRequest(MethodPropertyChangePrepare, target(`{"state":"null"}`)))
	if protocolError != nil || len(request.PropertyChangePrepareParams.Changes) != 1 {
		t.Fatalf("prepare decode failed: %#v %#v", request.PropertyChangePrepareParams, protocolError)
	}
}

// --- 7. 숫자 캡 경계 (min / max / max+1) ---

func TestPropertyNumericCapBoundaries(t *testing.T) {
	t.Parallel()

	uuidArray := func(n int) string {
		items := make([]string, n)
		for i := range items {
			items[i] = `"` + ascendingUUID(i) + `"`
		}
		return "[" + strings.Join(items, ",") + "]"
	}
	changeArray := func(n int) string {
		items := make([]string, n)
		for i := range items {
			items[i] = fixtureChangeTargetJSON(fixturePropertyID(t, 200+i))
		}
		return "[" + strings.Join(items, ",") + "]"
	}
	boolArray := func(n int) string {
		items := make([]string, n)
		for i := range items {
			items[i] = "true"
		}
		return "[" + strings.Join(items, ",") + "]"
	}

	tests := []struct {
		name    string
		method  Method
		params  string
		wantErr bool
	}{
		{name: "page_size min", method: MethodPropertyDefinitionList, params: `{"page_size":1,"requested_property_ids":[]}`},
		{name: "page_size max", method: MethodPropertyDefinitionList, params: `{"page_size":256,"requested_property_ids":[]}`},
		{name: "page_size zero", method: MethodPropertyDefinitionList, params: `{"page_size":0,"requested_property_ids":[]}`, wantErr: true},
		{name: "page_size max+1", method: MethodPropertyDefinitionList, params: `{"page_size":257,"requested_property_ids":[]}`, wantErr: true},
		{name: "property ids empty", method: MethodPropertyDefinitionList, params: `{"page_size":1,"requested_property_ids":[]}`},
		{name: "property ids max", method: MethodPropertyDefinitionList, params: `{"page_size":1,"requested_property_ids":` + uuidArray(256) + `}`},
		{name: "property ids max+1", method: MethodPropertyDefinitionList, params: `{"page_size":1,"requested_property_ids":` + uuidArray(257) + `}`, wantErr: true},
		{name: "targets min", method: MethodPropertyChangeExecute, params: `{"changes":` + changeArray(1) + `}`},
		{name: "targets max", method: MethodPropertyChangeExecute, params: `{"changes":` + changeArray(256) + `}`},
		{name: "targets empty", method: MethodPropertyChangeExecute, params: `{"changes":[]}`, wantErr: true},
		{name: "targets max+1", method: MethodPropertyChangeExecute, params: `{"changes":` + changeArray(257) + `}`, wantErr: true},
		{name: "many members empty", method: MethodPropertyChangeExecute, params: `{"changes":[` + fixtureChangeTargetJSON(fixturePropertyID(t, 300)) + `]}`},
		{name: "revision zero", method: MethodPropertyDefinitionUpdate, params: `{"property_id":"` + fixturePropertyID(t, 301) + `","expected_definition_revision":0,"name":"n"}`, wantErr: true},
		{name: "boolean many max", method: MethodPropertyChangeExecute, params: `{"changes":[{"target":{"kind":"local_path","local_path":"/a"},"property_id":"` + fixturePropertyID(t, 302) + `","expected_definition_revision":1,"expected_assignment_revision":1,"desired":{"state":"value","value_type":"boolean","cardinality":"many","value":` + boolArray(256) + `}}]}`},
		{name: "boolean many max+1", method: MethodPropertyChangeExecute, params: `{"changes":[{"target":{"kind":"local_path","local_path":"/a"},"property_id":"` + fixturePropertyID(t, 303) + `","expected_definition_revision":1,"expected_assignment_revision":1,"desired":{"state":"value","value_type":"boolean","cardinality":"many","value":` + boolArray(257) + `}}]}`, wantErr: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, protocolError := decodePropertyParams(t, propertyRequest(test.method, test.params))
			if (protocolError != nil) != test.wantErr {
				t.Fatalf("error = %#v, wantErr = %v", protocolError, test.wantErr)
			}
		})
	}
}

// --- 8. 스칼라 캡 경계 (4096 / 256) ---

func TestPropertyScalarCapBoundaries(t *testing.T) {
	t.Parallel()

	textValue := func(n int) string {
		return `{"state":"value","value_type":"text","cardinality":"one","value":"` + strings.Repeat("a", n) + `"}`
	}
	executeWithDesired := func(desired string) []byte {
		return propertyRequest(MethodPropertyChangeExecute, `{"changes":[{"target":{"kind":"local_path","local_path":"/a"},"property_id":"`+fixturePropertyID(t, 400)+`","expected_definition_revision":1,"expected_assignment_revision":1,"desired":`+desired+`}]}`)
	}
	listWithPath := func(path string) []byte {
		return propertyRequest(MethodPropertyAssignmentList, `{"page_size":1,"requested_property_ids":[],"target":{"kind":"local_path","local_path":"`+path+`"}}`)
	}
	pathBytes := func(total int) string { return "/" + strings.Repeat("a", total-1) }
	definitionListWithToken := func(token string) []byte {
		return propertyRequest(MethodPropertyDefinitionList, `{"page_size":1,"requested_property_ids":[],"page_token":"`+token+`","include_disabled":true}`)
	}
	createWithKey := func(key, name string) []byte {
		return propertyRequest(MethodPropertyDefinitionCreate, `{"key":"`+key+`","name":"`+name+`","value_type":"text","cardinality":"one"}`)
	}
	optionWithLabel := func(label string) []byte {
		return propertyRequest(MethodPropertyOptionCreate, `{"property_id":"`+fixturePropertyID(t, 401)+`","expected_definition_revision":1,"label":"`+label+`"}`)
	}

	tests := []struct {
		name    string
		wire    []byte
		wantErr bool
	}{
		{name: "path min", wire: listWithPath("/a")},
		{name: "path max", wire: listWithPath(pathBytes(4096))},
		{name: "path max+1", wire: listWithPath(pathBytes(4097)), wantErr: true},
		{name: "page token min", wire: definitionListWithToken("t")},
		{name: "page token max", wire: definitionListWithToken(strings.Repeat("t", 4096))},
		{name: "page token max+1", wire: definitionListWithToken(strings.Repeat("t", 4097)), wantErr: true},
		{name: "key max", wire: createWithKey(strings.Repeat("k", 256), "n")},
		{name: "key max+1", wire: createWithKey(strings.Repeat("k", 257), "n"), wantErr: true},
		{name: "name max", wire: createWithKey("k", strings.Repeat("n", 256))},
		{name: "name max+1", wire: createWithKey("k", strings.Repeat("n", 257)), wantErr: true},
		{name: "label max", wire: optionWithLabel(strings.Repeat("l", 256))},
		{name: "label max+1", wire: optionWithLabel(strings.Repeat("l", 257)), wantErr: true},
		{name: "text scalar max", wire: executeWithDesired(textValue(4096))},
		{name: "text scalar max+1", wire: executeWithDesired(textValue(4097)), wantErr: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, protocolError := decodePropertyParams(t, test.wire)
			if (protocolError != nil) != test.wantErr {
				t.Fatalf("error = %#v, wantErr = %v", protocolError, test.wantErr)
			}
		})
	}
}

// --- 9. 봉투 크기: 정확히 65,536 통과, +1은 dispatch 전 request_too_large ---

func TestPropertyRequestEnvelopeSize(t *testing.T) {
	t.Parallel()

	base := []byte(`{"request_id":"id","method":"property.assignment.list","params":{"page_size":1,"requested_property_ids":[],"target":{"kind":"local_path","local_path":"/a"}}}`)
	atLimit := append(base, bytes.Repeat([]byte{' '}, MaxWireBytes-len(base))...)
	if _, _, err := DecodeRequest(atLimit); err != nil {
		t.Fatalf("65,536-byte request rejected: %#v", err)
	}
	_, _, protocolError := DecodeRequest(append(atLimit, ' '))
	if protocolError == nil || protocolError.Code != ErrorRequestTooLarge {
		t.Fatalf("65,537-byte request error = %#v, want %q", protocolError, ErrorRequestTooLarge)
	}
	// 크기 검사가 dispatch보다 앞선다: 알려지지 않은 메서드여도 request_too_large가 우선.
	oversizeUnknown := append([]byte(`{"request_id":"id","method":"future","params":{}}`), bytes.Repeat([]byte{' '}, MaxWireBytes-46)...)
	_, _, protocolError = DecodeRequest(append(oversizeUnknown, ' '))
	if protocolError == nil || protocolError.Code != ErrorRequestTooLarge {
		t.Fatalf("oversize precedence error = %#v, want %q", protocolError, ErrorRequestTooLarge)
	}
}

// --- 10. 결과 인코딩 정확한 형태 + encode→decode 왕복 ---

func TestPropertyResultEncodeShapeAndRoundTrip(t *testing.T) {
	t.Parallel()

	pid := fixturePropertyID(t, 500)
	entryID := fixtureEntryID(1)
	definition := PropertyDefinition{PropertyID: pid, Key: "k", Name: "n", ValueType: "text", Cardinality: "one", State: "active", Revision: 1, Options: []PropertyOption{}, ConditionCapability: fixtureConditionCapability()}
	assignment := PropertyAssignment{PropertyID: pid, EntryID: entryID, ValueType: "text", Cardinality: "one", State: "value", Revision: 1, Payload: &PropertyPayload{kind: "text", one: "v"}}
	prepared := PropertyPreparedChange{
		Target:     PropertyTargetSelector{Kind: "local_path", LocalPath: "/a"},
		PropertyID: pid,
		EntryID:    entryID,
		Before:     nil,
		After:      PropertyDesiredState{State: "null"},
	}

	results := []struct {
		method Method
		result Result
		want   string
	}{
		{
			MethodPropertyDefinitionList,
			PropertyDefinitionListResult{Definitions: []PropertyDefinition{definition}, HasMore: false},
			`{"request_id":"id","ok":true,"result":{"definitions":[` + fixtureDefinitionJSON(pid) + `],"has_more":false}}`,
		},
		{
			MethodPropertyDefinitionUpdate,
			PropertyDefinitionResult{Definition: definition},
			`{"request_id":"id","ok":true,"result":{"definition":` + fixtureDefinitionJSON(pid) + `}}`,
		},
		{
			MethodPropertyOptionReorder,
			PropertyDefinitionResult{Definition: definition},
			`{"request_id":"id","ok":true,"result":{"definition":` + fixtureDefinitionJSON(pid) + `}}`,
		},
		{
			MethodPropertyAssignmentList,
			PropertyAssignmentListResult{Assignments: []PropertyAssignment{assignment}},
			`{"request_id":"id","ok":true,"result":{"assignments":[` + fixtureAssignmentJSON(pid, entryID) + `],"has_more":false}}`,
		},
		{
			MethodPropertyChangePrepare,
			PropertyChangePrepareResult{Changes: []PropertyPreparedChange{prepared}, RequiresConfirmation: true},
			`{"request_id":"id","ok":true,"result":{"changes":[{"target":{"kind":"local_path","local_path":"/a"},"property_id":"` + pid + `","entry_id":"` + entryID + `","before":null,"after":{"state":"null"}}],"requires_confirmation":true}}`,
		},
		{
			MethodPropertyChangeExecute,
			PropertyChangeExecuteResult{Assignments: []PropertyAssignment{assignment}},
			`{"request_id":"id","ok":true,"result":{"assignments":[` + fixtureAssignmentJSON(pid, entryID) + `]}}`,
		},
	}

	for _, test := range results {
		t.Run(string(test.method), func(t *testing.T) {
			encoded := EncodeResponse(NewSuccessResponse("id", test.result))
			if got := string(encoded); got != test.want {
				t.Fatalf("encoded =\n%s\nwant\n%s", got, test.want)
			}
			decoded, err := DecodeResponse(encoded, test.method)
			if err != nil {
				t.Fatalf("decode failed: %v", err)
			}
			if !reflect.DeepEqual(decoded.Result, test.result) {
				t.Fatalf("round trip mismatch:\ndecoded %#v\nwant    %#v", decoded.Result, test.result)
			}
		})
	}
}

// --- 11. 결과 무효 유니언 거부 ---

func TestPropertyResultRejectsInvalidUnions(t *testing.T) {
	t.Parallel()

	pid := fixturePropertyID(t, 600)
	entryID := fixtureEntryID(2)
	badDefinitions := []PropertyDefinition{
		{PropertyID: pid, Key: "k", Name: "n", ValueType: "float", Cardinality: "one", State: "active", Revision: 1, Options: []PropertyOption{}},
		{PropertyID: pid, Key: "k", Name: "n", ValueType: "text", Cardinality: "one", State: "archived", Revision: 1, Options: []PropertyOption{}},
		{PropertyID: pid, Key: "", Name: "n", ValueType: "text", Cardinality: "one", State: "active", Revision: 1, Options: []PropertyOption{}},
		{PropertyID: pid, Key: "k", Name: "n", ValueType: "text", Cardinality: "one", State: "active", Revision: 0, Options: []PropertyOption{}},
		{PropertyID: pid, Key: "k", Name: "n", ValueType: "text", Cardinality: "one", State: "active", Revision: 1, Options: []PropertyOption{{OptionID: oidBad(), Label: "l", Position: 0, State: "active"}}},
		{PropertyID: pid, Key: "k", Name: "n", ValueType: "select", Cardinality: "one", State: "active", Revision: 1, Options: []PropertyOption{{OptionID: fixturePropertyID(t, 601), Label: "l", Position: 0, State: "active"}}},
	}
	for index, definition := range badDefinitions {
		if definition.Validate() == nil {
			t.Fatalf("bad definition %d accepted", index)
		}
	}

	valuePayload := &PropertyPayload{kind: "text", one: "v"}
	badAssignments := []PropertyAssignment{
		{PropertyID: pid, EntryID: "ent-bad", ValueType: "text", Cardinality: "one", State: "value", Revision: 1, Payload: valuePayload},
		{PropertyID: pid, EntryID: entryID, ValueType: "text", Cardinality: "one", State: "error", Revision: 1},
		{PropertyID: pid, EntryID: entryID, ValueType: "text", Cardinality: "one", State: "value", Revision: 1},
		{PropertyID: pid, EntryID: entryID, ValueType: "text", Cardinality: "one", State: "null", Revision: 1, Payload: valuePayload},
		{PropertyID: pid, EntryID: entryID, ValueType: "text", Cardinality: "one", State: "value", Revision: 0, Payload: valuePayload},
	}
	for index, assignment := range badAssignments {
		if assignment.Validate() == nil {
			t.Fatalf("bad assignment %d accepted", index)
		}
	}

	badDesired := []PropertyDesiredState{
		{State: "value"},
		{State: "null", Payload: &PropertyPayload{}},
		{State: "value", ValueType: "text", Cardinality: "one", Payload: &PropertyPayload{kind: "text", one: strings.Repeat("a", 4097)}},
		{State: "frozen"},
	}
	for index, desired := range badDesired {
		if desired.Validate() == nil {
			t.Fatalf("bad desired state %d accepted", index)
		}
	}

	if (&PropertyChangePrepareResult{Changes: []PropertyPreparedChange{}, RequiresConfirmation: true}).Validate() == nil {
		t.Fatal("empty prepare changes accepted")
	}
	if (&PropertyChangePrepareResult{Changes: []PropertyPreparedChange{}, RequiresConfirmation: false}).Validate() == nil {
		t.Fatal("prepare without confirmation accepted")
	}
	if (&PropertyChangeExecuteResult{Assignments: []PropertyAssignment{}}).Validate() == nil {
		t.Fatal("empty execute read-back accepted")
	}
}

// --- 11a. capability exactness: native type과 operator 집합은 value contract에서 유도된 것과 정확히 일치해야 한다 ---

func TestPropertyCapabilityExactnessAgainstValueContract(t *testing.T) {
	t.Parallel()

	pid := fixturePropertyID(t, 610)
	base := func(valueType, cardinality string) PropertyDefinition {
		return PropertyDefinition{PropertyID: pid, Key: "k", Name: "n", ValueType: valueType, Cardinality: cardinality, State: "active", Revision: 1, Options: []PropertyOption{}, ConditionCapability: fixtureConditionCapabilityForContract(valueType, cardinality)}
	}

	if definition := base("text", "one"); definition.Validate() != nil {
		t.Fatal("text/one with derived capability rejected")
	}
	if definition := base("boolean", "one"); definition.Validate() != nil {
		t.Fatal("boolean/one with derived capability rejected")
	}
	if definition := base("text", "many"); definition.Validate() != nil {
		t.Fatal("text/many with derived capability rejected")
	}

	mismatchedNative := base("text", "one")
	mismatchedNative.ConditionCapability.NativeType = "date"
	if mismatchedNative.Validate() == nil {
		t.Fatal("text definition with date capability accepted")
	}

	wrongOperators := base("boolean", "one")
	wrongOperators.ConditionCapability.AllowedOperators = []string{"rx"}
	if wrongOperators.Validate() == nil {
		t.Fatal("boolean capability advertising rx accepted")
	}

	full := fixtureConditionCapabilityForContract("boolean", "one")
	if len(full.AllowedOperators) < 2 {
		t.Fatalf("boolean relation inventory unexpectedly small: %d", len(full.AllowedOperators))
	}
	partialOperators := base("boolean", "one")
	partialOperators.ConditionCapability.AllowedOperators = full.AllowedOperators[:len(full.AllowedOperators)-1]
	if partialOperators.Validate() == nil {
		t.Fatal("boolean capability missing a relation operator accepted")
	}

	unevaluable := PropertyDefinition{PropertyID: pid, Key: "k", Name: "n", ValueType: "datetime", Cardinality: "one", State: "active", Revision: 1, Options: []PropertyOption{}, ConditionCapability: fixtureConditionCapability()}
	if unevaluable.Validate() == nil {
		t.Fatal("datetime definition with supported capability accepted")
	}

	unsupported := PropertyDefinition{PropertyID: pid, Key: "k", Name: "n", ValueType: "datetime", Cardinality: "one", State: "active", Revision: 1, Options: []PropertyOption{}, ConditionCapability: PropertyConditionCapability{Reason: "unsupported_value_contract"}}
	if unsupported.Validate() != nil {
		t.Fatal("datetime definition with unsupported capability rejected")
	}
}

func oidBad() string { return "not-a-uuid" }

// --- 12. 에러 코드 계약: 신규 2종 + 전체 코드 고정 메시지 완전성 ---

func TestPropertyErrorCodeContract(t *testing.T) {
	t.Parallel()

	if ErrorPropertyNotFound != ErrorCode("property_not_found") || errorMessage(ErrorPropertyNotFound) != "property was not found" {
		t.Fatalf("property_not_found contract drifted: %q %q", ErrorPropertyNotFound, errorMessage(ErrorPropertyNotFound))
	}
	if ErrorResponseTooLarge != ErrorCode("response_too_large") || errorMessage(ErrorResponseTooLarge) != "response is too large" {
		t.Fatalf("response_too_large contract drifted: %q %q", ErrorResponseTooLarge, errorMessage(ErrorResponseTooLarge))
	}

	allCodes := []ErrorCode{
		ErrorRequestTooLarge, ErrorInvalidRequest, ErrorUnknownMethod, ErrorInvalidPath,
		ErrorMountNotFound, ErrorSourceNotFound, ErrorInvalidSelector, ErrorContextMismatch,
		ErrorScopeTooLarge, ErrorInvalidPageToken, ErrorPermissionDenied, ErrorSourceUnavailable,
		ErrorSourceDeleted, ErrorEntryNotFound, ErrorUnsupported, ErrorConflict,
		ErrorAdapterFailure, ErrorInternal, ErrorPropertyNotFound, ErrorResponseTooLarge,
	}
	for _, code := range allCodes {
		protocolError := newProtocolError(code)
		if protocolError.Message == "" || protocolError.Message != errorMessage(code) {
			t.Fatalf("code %q has no stable message", code)
		}
		if !validProtocolError(protocolError) {
			t.Fatalf("code %q rejected by validProtocolError", code)
		}
		want := `{"request_id":"id","ok":false,"error":{"code":"` + string(code) + `","message":"` + errorMessage(code) + `"}}`
		if got := string(EncodeResponse(NewErrorResponse("id", code))); got != want {
			t.Fatalf("encoded error for %q =\n%s\nwant\n%s", code, got, want)
		}
	}
}

// --- 13. 응답 예산: 정확한 바이트 계산과 초과 플래그 ---

func TestEncodedSuccessBytesExactness(t *testing.T) {
	t.Parallel()

	pid := fixturePropertyID(t, 700)
	definition := PropertyDefinition{PropertyID: pid, Key: "k", Name: "n", ValueType: "text", Cardinality: "one", State: "active", Revision: 1, Options: []PropertyOption{}, ConditionCapability: fixtureConditionCapability()}
	result := PropertyDefinitionResult{Definition: definition}

	size, fits := EncodedSuccessBytes("id", result)
	if !fits {
		t.Fatal("small result flagged as overflow")
	}
	encoded := EncodeResponse(NewSuccessResponse("id", result))
	if size != len(encoded) {
		t.Fatalf("size = %d, want exact %d", size, len(encoded))
	}

	// 메타데이터 확장으로 봉투 초과: 옵션 200개 × 라벨 256바이트.
	options := make([]PropertyOption, 200)
	for index := range options {
		options[index] = PropertyOption{OptionID: fixtureOptionID(1000 + index), Label: strings.Repeat("l", 256), Position: int64(index), State: "active"}
	}
	fat := PropertyDefinitionListResult{Definitions: []PropertyDefinition{{PropertyID: pid, Key: "k", Name: "n", ValueType: "select", Cardinality: "one", State: "active", Revision: 1, Options: options, ConditionCapability: fixtureConditionCapabilityForContract("select", "one")}}, HasMore: false}
	fatSize, fatFits := EncodedSuccessBytes("id", fat)
	if fatFits || fatSize <= MaxWireBytes {
		t.Fatalf("oversized read-back not flagged: size=%d fits=%v", fatSize, fatFits)
	}
	if got := string(EncodeResponse(NewSuccessResponse("id", fat))); !strings.Contains(got, "internal_error") {
		t.Fatalf("oversized success did not fall back to internal_error: %s", got)
	}
}

// expected_assignment_revision 0은 implicit unset@0 첫 쓰기의 CAS 토큰으로
// 유효하고, 음수는 거절된다. read-back revision을 그대로 재사용하는 계약의
// 일부다.
func TestDecodeChangeTargetAcceptsZeroAssignmentRevision(t *testing.T) {
	pid := fixturePropertyID(t, 900)
	base := `{"target":{"kind":"local_path","local_path":"/a/b"},"property_id":"` + pid + `","expected_definition_revision":1,"expected_assignment_revision":%d,"desired":{"state":"null"}}`
	if _, protocolError := decodePropertyParams(t, propertyRequest(MethodPropertyChangeExecute, `{"changes":[`+fmt.Sprintf(base, 0)+`]}`)); protocolError != nil {
		t.Fatalf("assignment revision 0 decode = %v, want accepted", protocolError)
	}
	if _, protocolError := decodePropertyParams(t, propertyRequest(MethodPropertyChangeExecute, `{"changes":[`+fmt.Sprintf(base, -1)+`]}`)); protocolError == nil {
		t.Fatal("negative assignment revision must be rejected")
	}
}
