@testable import Voyager
import XCTest

@MainActor
final class UnitValueUtilsTests: XCTestCase {
    func testFromCanonicalConvertsBytesToDisplayUnit() {
        let spec = tryUnwrapSizeSpec()

        XCTAssertEqual(
            UnitValueUtils.fromCanonical(canonicalText: "1048576", to: "MB", spec: spec),
            "1",
        )
        XCTAssertEqual(
            UnitValueUtils.fromCanonical(canonicalText: "1536", to: "KB", spec: spec),
            "1.5",
        )
    }

    func testToCanonicalConvertsDisplayUnitToBytes() {
        let spec = tryUnwrapSizeSpec()

        XCTAssertEqual(
            UnitValueUtils.toCanonical(displayValueText: "50", from: "MB", spec: spec),
            "52428800",
        )
        XCTAssertEqual(
            UnitValueUtils.toCanonical(displayValueText: "1.5", from: "KB", spec: spec),
            "1536",
        )
    }

    func testStripUnitSuffixIfNeededRemovesKnownUnits() {
        let spec = tryUnwrapSizeSpec()

        XCTAssertEqual(UnitValueUtils.stripUnitSuffixIfNeeded("50 MB", spec: spec), "50")
        XCTAssertEqual(UnitValueUtils.stripUnitSuffixIfNeeded("2 GB", spec: spec), "2")
        XCTAssertEqual(UnitValueUtils.stripUnitSuffixIfNeeded("128", spec: spec), "128")
    }

    private func tryUnwrapSizeSpec(
        file: StaticString = #filePath,
        line: UInt = #line,
    ) -> UnitValueUtils.UnitSpec {
        guard let spec = UnitValueUtils.spec(for: "size") else {
            XCTFail("Expected size unit spec", file: file, line: line)
            fatalError("Missing size spec")
        }
        return spec
    }
}
