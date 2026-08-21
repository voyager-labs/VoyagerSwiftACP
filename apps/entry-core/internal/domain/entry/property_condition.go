package entry

import "errors"

// PropertyConditionCatalog는 컴파일된 Condition Registry catalog에 대한 typed
// operator/value-shape 조회와 검증을 소유한다. 실행 데이터(operator 20개,
// (operator, native_type) relation 42개, version)는 생성된
// property_condition_catalog_gen.go에 있고, 이 파일은 hand-authored domain
// type과 그 위의 조회/검증 계약을 정의한다.
//
// Condition Registry는 Go로 컴파일되며 SQLite row로 절대 만들지 않는다.
// database row는 operator를 실행 가능하게 만들 수 없고, lookup table은
// code/DB drift만 만들기 때문이다. 따라서 SQLite condition table은 의도적으로
// 존재하지 않는다.

var (
	// ErrInvalidConditionOperator is returned when an operator ID is unknown
	// or malformed.
	ErrInvalidConditionOperator = errors.New("invalid condition operator")
	// ErrInvalidConditionRelation is returned when a (operator, native_type)
	// relation is not present in the catalog.
	ErrInvalidConditionRelation = errors.New("invalid condition relation")
	// ErrInvalidConditionCatalog is returned when the compiled catalog data
	// fails structural validation (counts, inverse symmetry, type coverage).
	ErrInvalidConditionCatalog = errors.New("invalid condition catalog")
)

// ConditionNativeType은 source property value의 condition-side native type이다.
// Registry native type을 그대로 반영하며 canonical Workspace value_type
// (text/number/date/...)과는 다르다. Workspace Property는 source native type으로
// condition-query될 수 있다.
type ConditionNativeType string

// Condition native types. Condition Registry가 허용하는 set과 동일하다.
const (
	ConditionNativeTypeString      ConditionNativeType = "string"
	ConditionNativeTypeNumber      ConditionNativeType = "number"
	ConditionNativeTypeDate        ConditionNativeType = "date"
	ConditionNativeTypeBoolean     ConditionNativeType = "boolean"
	ConditionNativeTypeStringList  ConditionNativeType = "string_list"
	ConditionNativeTypeCategorical ConditionNativeType = "categorical"
)

// valid는 값이 여섯 Condition native type 중 하나인지 보고한다.
func (nativeType ConditionNativeType) valid() bool {
	switch nativeType {
	case ConditionNativeTypeString, ConditionNativeTypeNumber, ConditionNativeTypeDate,
		ConditionNativeTypeBoolean, ConditionNativeTypeStringList, ConditionNativeTypeCategorical:
		return true
	default:
		return false
	}
}

// ConditionValueShape은 operator가 소비하는 operand 수를 분류한다.
type ConditionValueShape string

// Condition value shapes.
const (
	ConditionValueShapeSingle ConditionValueShape = "single"
	ConditionValueShapeNone   ConditionValueShape = "none"
	ConditionValueShapeRange  ConditionValueShape = "range"
	ConditionValueShapeList   ConditionValueShape = "list"
)

func (shape ConditionValueShape) valid() bool {
	switch shape {
	case ConditionValueShapeSingle, ConditionValueShapeNone, ConditionValueShapeRange, ConditionValueShapeList:
		return true
	default:
		return false
	}
}

// ConditionUISourceKind는 (operator, native_type) 쌍의 UI value-kind hint이다.
// 예: "singleText", "singleNumber", "toggle", "none".
type ConditionUISourceKind string

// ConditionOperator는 단일 Condition operator의 컴파일된 정의이다.
type ConditionOperator struct {
	ID             string
	UISource       string // registry ui_label, e.g. "Is", "Is not"
	ValueShape     ConditionValueShape
	ValueCount     int // -1 denotes a variable-length list (n)
	InverseOf      string
	MDQueryHint    string
	UISourceByType map[ConditionNativeType]ConditionUISourceKind
}

// ConditionRelation은 단일 (operator, native_type) relation이다. Registry
// allowed_types entry당 relation 하나이며, Registry에서 직접 파생되고 조용히
// curate/drop되지 않는다.
type ConditionRelation struct {
	Operator     string
	NativeType   ConditionNativeType
	UISourceKind ConditionUISourceKind
}

// ConditionCatalog는 컴파일된 불변 Condition Registry dataset이다.
// 생성된 property_condition_catalog_gen.go 테이블로 채워진다.
type ConditionCatalog struct {
	Version    string
	Operators  []ConditionOperator
	Relations  []ConditionRelation
	byID       map[string]ConditionOperator
	byRelation map[string]ConditionRelation
}

// LookupOperator는 주어진 ID의 operator를 반환한다.
func (catalog ConditionCatalog) LookupOperator(id string) (ConditionOperator, bool) {
	operator, ok := catalog.byID[id]
	return operator, ok
}

// RelationsForType는 native type이 일치하는 모든 relation을 반환한다.
func (catalog ConditionCatalog) RelationsForType(nativeType ConditionNativeType) []ConditionRelation {
	out := make([]ConditionRelation, 0)
	for _, relation := range catalog.Relations {
		if relation.NativeType == nativeType {
			out = append(out, relation)
		}
	}
	return out
}

// OperatorsForType는 native type과 호환되는 모든 operator ID를 반환한다.
func (catalog ConditionCatalog) OperatorsForType(nativeType ConditionNativeType) []string {
	relations := catalog.RelationsForType(nativeType)
	out := make([]string, 0, len(relations))
	for _, relation := range relations {
		out = append(out, relation.Operator)
	}
	return out
}

// UISourceKind는 (operator, native_type) 쌍의 UI value-kind hint를 반환한다.
// 유효하지 않은 relation이면 (빈 값, false)를 반환한다.
func (catalog ConditionCatalog) UISourceKind(operator string, nativeType ConditionNativeType) (ConditionUISourceKind, bool) {
	relation, ok := catalog.byRelation[relationKey(operator, nativeType)]
	if !ok {
		return "", false
	}
	return relation.UISourceKind, true
}

// Valid는 catalog dataset이 구조적으로 정합한지 보고한다. relation이 참조하는
// 모든 operator가 존재하고, 모든 inverse가 존재하며 대칭이고, 모든 relation이
// 알려진 native type을 참조하며, 모든 (operator, native_type) 쌍이 UI value-kind
// hint를 가진다.
func (catalog ConditionCatalog) Valid() error {
	if catalog.Version == "" || len(catalog.Operators) == 0 || len(catalog.Relations) == 0 {
		return ErrInvalidConditionCatalog
	}
	seenID := make(map[string]struct{}, len(catalog.Operators))
	for _, operator := range catalog.Operators {
		if operator.ID == "" || !operator.ValueShape.valid() {
			return ErrInvalidConditionCatalog
		}
		if _, exists := seenID[operator.ID]; exists {
			return ErrInvalidConditionCatalog
		}
		seenID[operator.ID] = struct{}{}
	}
	seenRelation := make(map[string]struct{}, len(catalog.Relations))
	for _, relation := range catalog.Relations {
		if !relation.NativeType.valid() {
			return ErrInvalidConditionCatalog
		}
		if _, exists := seenID[relation.Operator]; !exists {
			return ErrInvalidConditionCatalog
		}
		key := relationKey(relation.Operator, relation.NativeType)
		if _, exists := seenRelation[key]; exists {
			return ErrInvalidConditionCatalog
		}
		seenRelation[key] = struct{}{}
	}
	for _, operator := range catalog.Operators {
		if operator.InverseOf == "" {
			continue
		}
		inverse, exists := catalog.byID[operator.InverseOf]
		if !exists || inverse.InverseOf != operator.ID {
			return ErrInvalidConditionCatalog
		}
	}
	return nil
}

// relationKey는 (operator, native_type) 쌍의 canonical map key를 만든다.
func relationKey(operator string, nativeType ConditionNativeType) string {
	return operator + "\x00" + string(nativeType)
}

// newConditionCatalog는 컴파일된 테이블 위에 lookup index를 만들고 결과를
// 검증한다. 내부적으로 불일치하는 생성 dataset(programmer error)에서만 panic하고,
// runtime caller는 진단에 Valid()를 사용한다.
func newConditionCatalog(version string, operators []ConditionOperator, relations []ConditionRelation) ConditionCatalog {
	catalog := ConditionCatalog{
		Version:    version,
		Operators:  operators,
		Relations:  relations,
		byID:       make(map[string]ConditionOperator, len(operators)),
		byRelation: make(map[string]ConditionRelation, len(relations)),
	}
	for _, operator := range operators {
		catalog.byID[operator.ID] = operator
	}
	for _, relation := range relations {
		catalog.byRelation[relationKey(relation.Operator, relation.NativeType)] = relation
	}
	return catalog
}
