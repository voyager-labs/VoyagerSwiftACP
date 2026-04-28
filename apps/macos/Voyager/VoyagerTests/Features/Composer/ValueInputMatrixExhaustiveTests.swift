import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ValueInputMatrixExhaustiveTests: XCTestCase {
    func testRegistryOperatorTypeMatrixCountIsExpected() {
        let matrix = makeMatrixEntries()
        XCTAssertEqual(matrix.count, 33)
    }

    func testRegistryOperatorTypeMatrixValidInputsNormalizeSuccessfully() {
        let matrix = makeMatrixEntries()

        for entry in matrix {
            let sample = validSample(for: entry.uiKind)
            let result = ValueNormalizerUtils.normalize(
                kind: entry.uiKind,
                rawValues: sample.rawValues,
                editingIndex: sample.editingIndex,
            )

            XCTAssertNil(
                result.errorMessage,
                "Expected valid sample to pass: \(entry.operatorCode)/\(entry.typeKey)/\(entry.uiKind)",
            )
            XCTAssertEqual(
                result.values,
                sample.expectedValues,
                "Unexpected normalized values: \(entry.operatorCode)/\(entry.typeKey)/\(entry.uiKind)",
            )
        }
    }

    func testRegistryOperatorTypeMatrixInvalidInputsMatchExpectedFailureBehavior() {
        let matrix = makeMatrixEntries()

        for entry in matrix {
            let sample = invalidSample(for: entry.uiKind)
            let result = ValueNormalizerUtils.normalize(
                kind: entry.uiKind,
                rawValues: sample.rawValues,
                editingIndex: sample.editingIndex,
            )

            XCTAssertEqual(
                result.errorMessage,
                sample.expectedErrorMessage,
                "Unexpected invalid error handling: \(entry.operatorCode)/\(entry.typeKey)/\(entry.uiKind)",
            )
            XCTAssertEqual(
                result.values,
                sample.expectedValues,
                "Unexpected invalid value result: \(entry.operatorCode)/\(entry.typeKey)/\(entry.uiKind)",
            )
            XCTAssertEqual(
                result.resetIndices,
                sample.expectedResetIndices,
                "Unexpected reset indices: \(entry.operatorCode)/\(entry.typeKey)/\(entry.uiKind)",
            )
        }
    }
}

private struct MatrixEntry: Hashable {
    let operatorCode: String
    let typeKey: String
    let uiKind: String
}

private struct NormalizeSample {
    let rawValues: [String]
    let editingIndex: Int?
    let expectedValues: [String]?
}

private struct InvalidNormalizeSample {
    let rawValues: [String]
    let editingIndex: Int?
    let expectedErrorMessage: String?
    let expectedValues: [String]?
    let expectedResetIndices: [Int]
}

@MainActor
private func makeMatrixEntries() -> [MatrixEntry] {
    let snapshot = RegistrySnapshot.load()
    var entries: [MatrixEntry] = []

    for (typeKey, propertyType) in snapshot.propertyTypes {
        for operatorCode in propertyType.operators {
            guard let definition = snapshot.operatorDefinitions[operatorCode],
                  let kind = definition.uiValueKind?[typeKey]
            else {
                continue
            }
            entries.append(
                MatrixEntry(operatorCode: operatorCode, typeKey: typeKey, uiKind: kind),
            )
        }
    }

    return Array(Set(entries)).sorted {
        if $0.operatorCode != $1.operatorCode { return $0.operatorCode < $1.operatorCode }
        if $0.typeKey != $1.typeKey { return $0.typeKey < $1.typeKey }
        return $0.uiKind < $1.uiKind
    }
}

private func validSample(for kind: String) -> NormalizeSample {
    switch kind {
    case "none":
        .init(rawValues: [], editingIndex: nil, expectedValues: [])
    case "singleText":
        .init(rawValues: ["hello"], editingIndex: nil, expectedValues: ["hello"])
    case "singleNumber":
        .init(rawValues: ["42.5"], editingIndex: nil, expectedValues: ["42.5"])
    case "singleDate":
        .init(rawValues: ["2026-02-26"], editingIndex: nil, expectedValues: ["2026-02-26"])
    case "rangeNumber":
        .init(rawValues: ["10", "20"], editingIndex: nil, expectedValues: ["10", "20"])
    case "rangeDate":
        .init(
            rawValues: ["2026-02-26", "2026-02-27"],
            editingIndex: nil,
            expectedValues: ["2026-02-26", "2026-02-27"],
        )
    case "listText":
        .init(rawValues: ["alpha, beta"], editingIndex: nil, expectedValues: ["alpha", "beta"])
    case "toggle":
        .init(rawValues: ["true"], editingIndex: nil, expectedValues: ["true"])
    default:
        .init(rawValues: ["hello"], editingIndex: nil, expectedValues: ["hello"])
    }
}

private func invalidSample(for kind: String) -> InvalidNormalizeSample {
    switch kind {
    case "none":
        invalidNoneSample()
    case "singleText":
        invalidSingleTextSample()
    case "singleNumber":
        invalidSingleNumberSample()
    case "singleDate":
        invalidSingleDateSample()
    case "rangeNumber":
        invalidRangeNumberSample()
    case "rangeDate":
        invalidRangeDateSample()
    case "listText":
        invalidListTextSample()
    case "toggle":
        invalidToggleSample()
    default:
        .init(
            rawValues: ["   "],
            editingIndex: nil,
            expectedErrorMessage: "Value is required.",
            expectedValues: nil,
            expectedResetIndices: [0],
        )
    }
}

private func invalidNoneSample() -> InvalidNormalizeSample {
    .init(
        rawValues: ["ignored"],
        editingIndex: nil,
        expectedErrorMessage: nil,
        expectedValues: [],
        expectedResetIndices: [],
    )
}

private func invalidSingleTextSample() -> InvalidNormalizeSample {
    .init(
        rawValues: ["   "],
        editingIndex: nil,
        expectedErrorMessage: "Value is required.",
        expectedValues: nil,
        expectedResetIndices: [0],
    )
}

private func invalidSingleNumberSample() -> InvalidNormalizeSample {
    .init(
        rawValues: ["abc"],
        editingIndex: nil,
        expectedErrorMessage: "Enter a valid number.",
        expectedValues: nil,
        expectedResetIndices: [0],
    )
}

private func invalidSingleDateSample() -> InvalidNormalizeSample {
    .init(
        rawValues: ["invalid-date"],
        editingIndex: nil,
        expectedErrorMessage: "Enter a valid date.",
        expectedValues: nil,
        expectedResetIndices: [0],
    )
}

private func invalidRangeNumberSample() -> InvalidNormalizeSample {
    .init(
        rawValues: ["10", "xx"],
        editingIndex: 1,
        expectedErrorMessage: "Enter valid numbers.",
        expectedValues: nil,
        expectedResetIndices: [1],
    )
}

private func invalidRangeDateSample() -> InvalidNormalizeSample {
    .init(
        rawValues: ["2026-02-26", "invalid-date"],
        editingIndex: 1,
        expectedErrorMessage: "Enter valid dates.",
        expectedValues: nil,
        expectedResetIndices: [1],
    )
}

private func invalidListTextSample() -> InvalidNormalizeSample {
    .init(
        rawValues: ["  ,  \n   "],
        editingIndex: nil,
        expectedErrorMessage: "Value is required.",
        expectedValues: nil,
        expectedResetIndices: [0],
    )
}

private func invalidToggleSample() -> InvalidNormalizeSample {
    .init(
        rawValues: ["yes"],
        editingIndex: nil,
        expectedErrorMessage: "Enter true or false.",
        expectedValues: nil,
        expectedResetIndices: [0],
    )
}
