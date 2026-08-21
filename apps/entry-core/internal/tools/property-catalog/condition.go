package propertycatalog

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strconv"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// PropertyConditionRegistry is the raw Condition Registry document. Operator
// and relation data are rendered from the declared allowed_types without any
// curation or dropping.
type PropertyConditionRegistry struct {
	Version       string
	PropertyTypes []string
	Operators     map[string]ConditionOperatorSpec
}

// ConditionOperatorSpec is a single raw Condition operator definition.
type ConditionOperatorSpec struct {
	UISource       string
	MDQueryHint    string
	ValueShape     string
	ValueCount     string // "0", "1", "2", or "n"
	AllowedTypes   []string
	InverseOf      string
	UISourceByType map[string]string
}

type rawConditionRegistry struct {
	Kind          string                          `json:"$kind"`
	Version       string                          `json:"$version"`
	PropertyTypes map[string]rawPropertyType      `json:"property_types"`
	Operators     map[string]rawConditionOperator `json:"operators"`
}

type rawPropertyType struct {
	Operators []string `json:"operators"`
}

type rawConditionOperator struct {
	UISource       string            `json:"ui_label"`
	MDQueryHint    string            `json:"mdquery_operator"`
	ValueShape     string            `json:"value_shape"`
	ValueCount     any               `json:"value_count"`
	AllowedTypes   []string          `json:"allowed_types"`
	InverseOf      string            `json:"inverse_of"`
	UISourceByType map[string]string `json:"ui_value_kind"`
}

// LoadConditionRegistry reads and decodes the Condition Registry from path.
func LoadConditionRegistry(path string) (*PropertyConditionRegistry, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read condition registry: %w", err)
	}
	return parseConditionRegistry(raw)
}

func parseConditionRegistry(data []byte) (*PropertyConditionRegistry, error) {
	var raw rawConditionRegistry
	if err := decodeJSONDocument(data, &raw); err != nil {
		return nil, fmt.Errorf("decode condition registry: %w", err)
	}
	if raw.Kind != "property_condition_registry" {
		return nil, errors.New("condition registry $kind mismatch")
	}
	if raw.Version == "" {
		return nil, errors.New("condition registry missing $version")
	}
	propertyTypes := make([]string, 0, len(raw.PropertyTypes))
	for propertyType := range raw.PropertyTypes {
		propertyTypes = append(propertyTypes, propertyType)
	}
	sort.Strings(propertyTypes)
	registry := &PropertyConditionRegistry{
		Version:       raw.Version,
		PropertyTypes: propertyTypes,
		Operators:     make(map[string]ConditionOperatorSpec, len(raw.Operators)),
	}
	for name, operator := range raw.Operators {
		registry.Operators[name] = ConditionOperatorSpec{
			UISource:       operator.UISource,
			MDQueryHint:    operator.MDQueryHint,
			ValueShape:     operator.ValueShape,
			ValueCount:     valueCountToString(operator.ValueCount),
			AllowedTypes:   append([]string(nil), operator.AllowedTypes...),
			InverseOf:      operator.InverseOf,
			UISourceByType: cloneStringMap(operator.UISourceByType),
		}
	}
	if err := registry.Validate(); err != nil {
		return nil, err
	}
	return registry, nil
}

// Validate checks the Condition Registry invariants: every allowed_type is a
// declared property type, every operator referenced by an inverse exists, and
// every (operator, type) relation has a UI value-kind hint.
func (registry *PropertyConditionRegistry) Validate() error {
	if registry == nil || registry.Version == "" || len(registry.Operators) == 0 {
		return errors.New("invalid condition registry")
	}
	types := make(map[string]struct{}, len(registry.PropertyTypes))
	for _, propertyType := range registry.PropertyTypes {
		types[propertyType] = struct{}{}
	}
	for name, operator := range registry.Operators {
		if name == "" || operator.UISource == "" || operator.ValueShape == "" {
			return fmt.Errorf("operator %q missing required fields", name)
		}
		for _, allowedType := range operator.AllowedTypes {
			if _, exists := types[allowedType]; !exists {
				return fmt.Errorf("operator %q allowed_type %q is not a declared property type", name, allowedType)
			}
			if _, hasKind := operator.UISourceByType[allowedType]; !hasKind {
				return fmt.Errorf("operator %q allowed_type %q lacks ui_value_kind", name, allowedType)
			}
		}
		if operator.InverseOf != "" {
			if _, exists := registry.Operators[operator.InverseOf]; !exists {
				return fmt.Errorf("operator %q inverse_of %q does not exist", name, operator.InverseOf)
			}
		}
	}
	return nil
}

// Relations returns every (operator, allowed_type) pair in deterministic order.
// The set is derived directly from every allowed_types entry and is never
// curated or dropped.
func (registry *PropertyConditionRegistry) Relations() []entry.ConditionRelation {
	type pair struct {
		operator string
		native   entry.ConditionNativeType
		kind     string
	}
	pairs := make([]pair, 0)
	for name, operator := range registry.Operators {
		for _, allowedType := range operator.AllowedTypes {
			pairs = append(pairs, pair{name, entry.ConditionNativeType(allowedType), operator.UISourceByType[allowedType]})
		}
	}
	sort.Slice(pairs, func(i, j int) bool {
		if pairs[i].operator != pairs[j].operator {
			return pairs[i].operator < pairs[j].operator
		}
		return pairs[i].native < pairs[j].native
	})
	relations := make([]entry.ConditionRelation, 0, len(pairs))
	for _, pair := range pairs {
		relations = append(relations, entry.ConditionRelation{
			Operator:     pair.operator,
			NativeType:   pair.native,
			UISourceKind: entry.ConditionUISourceKind(pair.kind),
		})
	}
	return relations
}

// Operators returns operator specs sorted by name for deterministic rendering.
func (registry *PropertyConditionRegistry) OperatorsSorted() []ConditionOperatorSpecWithName {
	names := make([]string, 0, len(registry.Operators))
	for name := range registry.Operators {
		names = append(names, name)
	}
	sort.Strings(names)
	out := make([]ConditionOperatorSpecWithName, 0, len(names))
	for _, name := range names {
		out = append(out, ConditionOperatorSpecWithName{Name: name, Spec: registry.Operators[name]})
	}
	return out
}

// ConditionOperatorSpecWithName pairs an operator name with its spec.
type ConditionOperatorSpecWithName struct {
	Name string
	Spec ConditionOperatorSpec
}

// parseValueCount converts the registry value_count string ("0","1","2","n")
// into the typed int where -1 denotes a variable-length list.
func parseValueCount(value string) int {
	if value == "n" {
		return -1
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return 0
	}
	return parsed
}

// valueCountToString normalizes mixed-type value_count (integer or "n") to string.
func valueCountToString(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case json.Number:
		return typed.String()
	case float64:
		return strconv.FormatFloat(typed, 'f', -1, 64)
	case int:
		return strconv.Itoa(typed)
	default:
		return ""
	}
}

func cloneStringMap(source map[string]string) map[string]string {
	out := make(map[string]string, len(source))
	for key, value := range source {
		out[key] = value
	}
	return out
}
