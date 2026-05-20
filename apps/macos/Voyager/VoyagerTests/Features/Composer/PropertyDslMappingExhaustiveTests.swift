import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
/// 속성→연산자 DSL 매핑 — 모든 비-NSURL 속성에 대한 완전성을 검증.
final class PropertyDslMappingExhaustiveTests: XCTestCase {
    /// testAllNonNSURLPropertiesHaveValidOperatorMapping 테스트 동작을 검증한다.
    func testAllNonNSURLPropertiesHaveValidOperatorMapping() {
        let snapshot = RegistrySnapshot.load()
        let registry = RegistryClient.live(snapshot: snapshot)
        let properties = snapshot.allProperties.filter { isNonNSURLProperty($0.definition.systemKeys) }

        XCTAssertFalse(properties.isEmpty)

        var failures: [String] = []

        for property in properties {
            guard let typeKey = VoyagerEntitiesCollection.SystemPropertyTypeKey
                .operatorKeyOrNil(from: property.definition.type)
            else {
                failures.append("\(property.key): unsupported type \(property.definition.type)")
                continue
            }

            let operators = registry.operatorCodes(for: property.key)
            if operators.isEmpty {
                failures.append("\(property.key): no operators")
                continue
            }

            for operatorCode in operators {
                let definition = registry.operatorDefinition(operatorCode)
                if (definition.uiLabel ?? "").isEmpty {
                    failures.append("\(property.key)/\(operatorCode): empty operator label")
                }

                guard let uiKind = definition.uiValueKind?[typeKey], uiKind.isEmpty == false else {
                    failures.append("\(property.key)/\(operatorCode): missing uiValueKind for \(typeKey)")
                    continue
                }

                let arity = registry.valueArity(for: uiKind)
                if arity == 0, uiKind != "none" {
                    failures.append("\(property.key)/\(operatorCode): unexpected zero arity uiKind \(uiKind)")
                }
            }
        }

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// testAllNonNSURLPropertiesEncodeDslAcrossSupportedOperators 테스트 동작을 검증한다.
    func testAllNonNSURLPropertiesEncodeDslAcrossSupportedOperators() {
        let snapshot = RegistrySnapshot.load()
        let registry = RegistryClient.live(snapshot: snapshot)
        let properties = snapshot.allProperties.filter { isNonNSURLProperty($0.definition.systemKeys) }

        XCTAssertFalse(properties.isEmpty)

        var failures: [String] = []

        for property in properties {
            guard let typeKey = VoyagerEntitiesCollection.SystemPropertyTypeKey
                .operatorKeyOrNil(from: property.definition.type)
            else {
                failures.append("\(property.key): unsupported type \(property.definition.type)")
                continue
            }

            let operators = registry.operatorCodes(for: property.key)
            if operators.isEmpty {
                failures.append("\(property.key): no operators")
                continue
            }

            for operatorCode in operators {
                let uiKind = registry.operatorUIKind(for: operatorCode, typeKey: typeKey)
                let arity = registry.valueArity(for: uiKind)
                let valueType = registry.valueType(for: uiKind)

                if arity == 0 {
                    continue
                }

                let rawValues = sampleValues(for: uiKind)
                let condition = Condition(
                    propertyKey: property.key,
                    propertyLabel: registry.label(for: property.key),
                    propertyType: property.definition.type,
                    operatorCode: operatorCode,
                    operatorLabel: registry.operatorLabel(for: operatorCode),
                    operatorValueArity: arity,
                    operatorValueUIKind: uiKind,
                    valueType: valueType,
                    values: rawValues,
                    isActive: true,
                )

                guard let encoded = ConditionValueEncoder.encode(condition: condition, values: rawValues) else {
                    failures.append("\(property.key)/\(operatorCode)/\(uiKind): nil DSL")
                    continue
                }

                if matchesExpectedShape(encoded: encoded, uiKind: uiKind, rawValues: rawValues) == false {
                    failures.append("\(property.key)/\(operatorCode)/\(uiKind): unexpected shape \(encoded)")
                }
            }
        }

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    private func isNonNSURLProperty(_ systemKeys: [String]) -> Bool {
        systemKeys.contains(where: { $0.hasPrefix("nsurl:") }) == false
    }

    private func sampleValues(for uiKind: String) -> [String] {
        switch uiKind {
        case "singleText":
            ["alpha"]
        case "listText":
            ["alpha", "beta"]
        case "singleNumber":
            ["10"]
        case "rangeNumber":
            ["10", "20"]
        case "listNumber":
            ["10", "20"]
        case "singleDate":
            ["2026-02-26T13:45:12Z"]
        case "rangeDate":
            ["2026-02-26T13:45:12Z", "2026-02-27 09:00:00"]
        case "toggle":
            ["true"]
        default:
            ["alpha"]
        }
    }

    private func matchesExpectedShape(encoded: VoyagerShared.JSONValue, uiKind: String, rawValues: [String]) -> Bool {
        if uiKind == "singleText" { return isString(encoded) }
        if uiKind == "singleNumber" { return isNumber(encoded) }
        if uiKind == "singleDate" { return isSingleDate(encoded) }
        if uiKind == "toggle" { return isBool(encoded) }
        if uiKind == "listText" || uiKind == "rangeNumber" || uiKind == "listNumber" {
            return isArrayWithCount(encoded, rawValues.count)
        }
        if uiKind == "rangeDate" {
            return isRangeDate(encoded)
        }
        return true
    }

    private func isString(_ encoded: VoyagerShared.JSONValue) -> Bool {
        if case .string = encoded { return true }
        return false
    }

    private func isNumber(_ encoded: VoyagerShared.JSONValue) -> Bool {
        if case .number = encoded { return true }
        return false
    }

    private func isBool(_ encoded: VoyagerShared.JSONValue) -> Bool {
        if case .bool = encoded { return true }
        return false
    }

    private func isArrayWithCount(_ encoded: VoyagerShared.JSONValue, _ expectedCount: Int) -> Bool {
        if case let .array(items) = encoded {
            return items.count == expectedCount
        }
        return false
    }

    private func isSingleDate(_ encoded: VoyagerShared.JSONValue) -> Bool {
        if case let .string(value) = encoded {
            return value == "2026-02-26"
        }
        return false
    }

    private func isRangeDate(_ encoded: VoyagerShared.JSONValue) -> Bool {
        if case let .array(items) = encoded {
            return items == [.string("2026-02-26"), .string("2026-02-27")]
        }
        return false
    }
}
