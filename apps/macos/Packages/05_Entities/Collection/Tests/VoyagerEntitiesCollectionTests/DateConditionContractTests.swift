import Foundation
import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

final class DateConditionContractTests: XCTestCase {
    private let relativeLiteral = "voyager.relativeDate:v1:past:3:day:2025-05-17"

    func testRegistryIncludesTodayAsZeroArityDateOperator() throws {
        let registry = try loadConditionRegistry()
        let dateOperators = try XCTUnwrap(registry.propertyTypes["date"]?.operators)

        XCTAssertTrue(dateOperators.contains("today"))
        XCTAssertEqual(registry.operators["today"]?.valueCount, .fixed(0))
        XCTAssertEqual(registry.operators["today"]?.valueShape, ValueShape.none)
        XCTAssertEqual(registry.operators["today"]?.uiValueKind?["date"], "none")
    }

    func testNormalizeSingleDatePreservesCanonicalRelativeLiteral() {
        let result = ValueNormalizerUtils.normalize(
            kind: "singleDate",
            rawValues: ["  \(relativeLiteral)  "],
            editingIndex: nil,
        )

        XCTAssertEqual(result.values, [relativeLiteral])
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.resetIndices, [])
    }

    func testNormalizeRangeDateRejectsRelativeLiteral() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeDate",
            rawValues: [relativeLiteral, "2025-05-20"],
            editingIndex: nil,
        )

        XCTAssertNil(result.values)
        XCTAssertEqual(result.errorMessage, "Enter valid dates.")
        XCTAssertEqual(result.resetIndices, [0])
    }

    func testEncodeSingleDatePreservesCanonicalRelativeLiteral() {
        let encoded = ConditionValueEncoder.encodeValues(
            values: [relativeLiteral],
            valueType: "date",
            operatorCode: "eq",
            operatorValueUIKind: "singleDate",
        )

        XCTAssertEqual(encoded, .string(relativeLiteral))
    }

    func testEncodeRangeDateCanonicalizesAbsoluteDatesOnly() throws {
        let start = "2025-05-17T12:00:00Z"
        let end = "2025-05-20T23:59:59Z"
        let encoded = ConditionValueEncoder.encodeValues(
            values: [start, end],
            valueType: "date",
            operatorCode: "btw",
            operatorValueUIKind: "rangeDate",
        )

        let canonicalStart = try XCTUnwrap(ValueNormalizerUtils.canonicalAbsoluteDateString(start))
        let canonicalEnd = try XCTUnwrap(ValueNormalizerUtils.canonicalAbsoluteDateString(end))

        XCTAssertEqual(
            encoded,
            .array([
                .string(canonicalStart),
                .string(canonicalEnd),
            ]),
        )
    }

    func testEncodeRangeDateRejectsRelativeLiteral() {
        let encoded = ConditionValueEncoder.encodeValues(
            values: [relativeLiteral, "2025-05-20"],
            valueType: "date",
            operatorCode: "btw",
            operatorValueUIKind: "rangeDate",
        )

        XCTAssertNil(encoded)
    }

    private func loadConditionRegistry() throws -> PropertyConditionRegistry {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/property_condition_registry.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PropertyConditionRegistry.self, from: data)
    }
}
