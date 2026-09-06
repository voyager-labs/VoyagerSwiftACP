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
// derivation을 공유한다. identity scheme은 lifecycle과 무관하게 두 canonical
// 값 중 하나여야 하고, unsupported capability도 definition lifecycle, identity
// scheme 및 value contract에서 유도되는 사유와 정확히 일치해야 한다 — 특히
// source_runtime_unavailable은 registry-derived 정의에만, 나머지 결과는
// voyager-issued 정의에만 나타날 수 있다.
func validConditionCapabilityForDefinition(definition PropertyDefinition) bool {
	capability := definition.ConditionCapability
	scheme := domainentry.PropertyIdentityScheme(definition.IdentityScheme)
	if scheme != domainentry.PropertyIdentitySchemeRegistryDerived && scheme != domainentry.PropertyIdentitySchemeVoyagerIssued {
		return false
	}
	nativeType, valueContractSupported := domainentry.ConditionNativeTypeForContract(
		domainentry.PropertyType(definition.ValueType),
		domainentry.PropertyCardinality(definition.Cardinality),
	)
	if !capability.Supported {
		switch capability.Reason {
		case "definition_disabled":
			return definition.State == "disabled"
		case "source_runtime_unavailable":
			return definition.State == "active" && scheme == domainentry.PropertyIdentitySchemeRegistryDerived
		case "unsupported_value_contract":
			return definition.State == "active" &&
				scheme == domainentry.PropertyIdentitySchemeVoyagerIssued &&
				!valueContractSupported
		default:
			return false
		}
	}
	if definition.State != "active" ||
		scheme != domainentry.PropertyIdentitySchemeVoyagerIssued ||
		!valueContractSupported ||
		capability.NativeType != string(nativeType) {
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
