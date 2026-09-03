package schema

import (
	"sort"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// validConditionCapabilityForDefinition은 supported condition capability가
// definition의 value contract에서 유도되는 정확한 native type과 Registry
// relation이 허용하는 전체 operator 집합과 일치하는지 검사한다. wire가
// evaluator가 항상 false로 평가하는 operator를 광고하면 client가 잘못된
// operand UI를 구성할 수 있으므로 fail-closed로 거절한다. application의
// ConditionCapabilityFor가 capability를 발행할 때 쓰는 것과 동일한 domain
// derivation을 공유한다. unsupported capability도 definition lifecycle 및
// value contract에서 유도되는 사유와 정확히 일치해야 한다.
func validConditionCapabilityForDefinition(definition PropertyDefinition) bool {
	capability := definition.ConditionCapability
	nativeType, valueContractSupported := domainentry.ConditionNativeTypeForContract(
		domainentry.PropertyType(definition.ValueType),
		domainentry.PropertyCardinality(definition.Cardinality),
	)
	if !capability.Supported {
		switch capability.Reason {
		case "definition_disabled":
			return definition.State == "disabled"
		case "source_runtime_unavailable":
			return definition.State == "active"
		case "unsupported_value_contract":
			return definition.State == "active" && !valueContractSupported
		default:
			return false
		}
	}
	if !valueContractSupported || capability.NativeType != string(nativeType) {
		return false
	}
	expected := append([]string(nil), domainentry.ConditionCatalogData.OperatorsForType(nativeType)...)
	sort.Strings(expected)
	if len(capability.AllowedOperators) != len(expected) {
		return false
	}
	for index, operator := range capability.AllowedOperators {
		if operator != expected[index] {
			return false
		}
	}
	return true
}
