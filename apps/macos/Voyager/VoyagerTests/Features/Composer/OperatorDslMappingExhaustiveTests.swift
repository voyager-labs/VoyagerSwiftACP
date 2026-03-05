import XCTest

@testable import Voyager

@MainActor
final class OperatorDslMappingExhaustiveTests: XCTestCase {
    func testAllOperatorsEncodeExpectedDslShapeByType() {
        let snapshot = RegistrySnapshot.load()
        let operatorDefinitions = snapshot.operatorDefinitions
        let propertyTypes = snapshot.propertyTypes

        var failures: [String] = []
        var validatedCount = 0

        for (typeKey, propertyType) in propertyTypes {
            for operatorCode in propertyType.operators {
                guard let definition = operatorDefinitions[operatorCode] else {
                    failures.append("\(typeKey).\(operatorCode): missing operator definition")
                    continue
                }

                if let allowedTypes = definition.allowedTypes,
                   allowedTypes.contains(typeKey) == false
                {
                    continue
                }

                guard let uiKind = definition.uiValueKind?[typeKey], uiKind.isEmpty == false else {
                    failures.append("\(typeKey).\(operatorCode): missing ui_value_kind")
                    continue
                }

                let sampleValues = sampleValues(for: uiKind)
                if sampleValues == nil {
                    validatedCount += 1
                    continue
                }

                guard let values = sampleValues else {
                    continue
                }

                let encoded = ConditionValueEncoder.encodeValues(
                    values: values,
                    valueType: valueType(for: typeKey),
                    operatorCode: operatorCode,
                    operatorValueUIKind: uiKind,
                )

                validatedCount += 1

                guard let encoded else {
                    failures.append("\(typeKey).\(operatorCode): encoder returned nil")
                    continue
                }

                if matchesExpectedShape(encoded: encoded, uiKind: uiKind, expectedCount: values.count) == false {
                    failures.append("\(typeKey).\(operatorCode): unexpected encoded shape for \(uiKind)")
                }
            }
        }

        XCTAssertGreaterThan(validatedCount, 30)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testZeroArityOperatorsEncodeEmptyValueShape() {
        let snapshot = RegistrySnapshot.load()
        let operatorDefinitions = snapshot.operatorDefinitions

        var checked = 0
        var failures: [String] = []

        for (operatorCode, definition) in operatorDefinitions {
            guard case .fixed(0) = definition.valueCount else { continue }
            for (typeKey, uiKind) in definition.uiValueKind ?? [:] where uiKind == "none" {
                checked += 1
                let encoded = ConditionValueEncoder.encodeValues(
                    values: [],
                    valueType: valueType(for: typeKey),
                    operatorCode: operatorCode,
                    operatorValueUIKind: uiKind,
                )
                guard let encoded else { continue }
                if case let .array(values) = encoded, values.isEmpty {
                    continue
                }
                failures.append("\(typeKey).\(operatorCode): expected nil or empty array for zero-arity")
            }
        }

        XCTAssertGreaterThan(checked, 0)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    private func valueType(for typeKey: String) -> String {
        switch typeKey {
        case "number":
            "number"
        case "date":
            "date"
        case "boolean":
            "boolean"
        case "string_list":
            "string_list"
        case "categorical":
            "categorical"
        default:
            "string"
        }
    }

    private func sampleValues(for uiKind: String) -> [String]? {
        switch uiKind {
        case "none":
            nil
        case "singleText":
            ["sample"]
        case "singleNumber":
            ["42"]
        case "singleDate":
            ["2026-03-02"]
        case "toggle":
            ["true"]
        case "listText":
            ["a", "b"]
        case "listNumber":
            ["1", "2"]
        case "rangeNumber":
            ["10", "20"]
        case "rangeDate":
            ["2026-01-01", "2026-12-31"]
        default:
            ["sample"]
        }
    }

    private func matchesExpectedShape(encoded: JSONValue, uiKind: String, expectedCount: Int) -> Bool {
        if uiKind == "singleText" || uiKind == "singleDate" {
            return isStringValue(encoded)
        }
        if uiKind == "singleNumber" {
            return isNumberValue(encoded)
        }
        if uiKind == "toggle" {
            return isBoolValue(encoded)
        }
        if uiKind == "listText" || uiKind == "listNumber" || uiKind == "rangeNumber" || uiKind == "rangeDate" {
            return isArrayValue(encoded, expectedCount: expectedCount)
        }
        return true
    }

    private func isStringValue(_ encoded: JSONValue) -> Bool {
        if case .string = encoded { return true }
        return false
    }

    private func isNumberValue(_ encoded: JSONValue) -> Bool {
        if case .number = encoded { return true }
        return false
    }

    private func isBoolValue(_ encoded: JSONValue) -> Bool {
        if case .bool = encoded { return true }
        return false
    }

    private func isArrayValue(_ encoded: JSONValue, expectedCount: Int) -> Bool {
        if case let .array(values) = encoded {
            return values.count == expectedCount
        }
        return false
    }
}
