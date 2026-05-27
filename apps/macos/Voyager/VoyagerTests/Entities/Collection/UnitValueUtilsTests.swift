@testable import Voyager
import VoyagerEntitiesCollection
import XCTest

@MainActor
final class UnitValueUtilsTests: XCTestCase {
    private let registryClient = RegistryTestSupport.makeRegistryClient()

    /// testFromCanonicalConvertsBytesToDisplayUnit 테스트 동작을 검증한다.
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

    /// testToCanonicalConvertsDisplayUnitToBytes 테스트 동작을 검증한다.
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

    /// testStripUnitSuffixIfNeededRemovesKnownUnits 테스트 동작을 검증한다.
    func testStripUnitSuffixIfNeededRemovesKnownUnits() {
        let spec = tryUnwrapSizeSpec()

        XCTAssertEqual(UnitValueUtils.stripUnitSuffixIfNeeded("50 MB", spec: spec), "50")
        XCTAssertEqual(UnitValueUtils.stripUnitSuffixIfNeeded("2 GB", spec: spec), "2")
        XCTAssertEqual(UnitValueUtils.stripUnitSuffixIfNeeded("128", spec: spec), "128")
    }

    /// testFromCanonicalConvertsBitrateToDisplayUnit 테스트 동작을 검증한다.
    func testFromCanonicalConvertsBitrateToDisplayUnit() {
        let spec = tryUnwrapAudioBitRateSpec()

        XCTAssertEqual(
            UnitValueUtils.fromCanonical(canonicalText: "320000", to: "Kbps", spec: spec),
            "320",
        )
        XCTAssertEqual(
            UnitValueUtils.fromCanonical(canonicalText: "2500000", to: "Mbps", spec: spec),
            "2.5",
        )
    }

    /// testToCanonicalConvertsDisplayUnitToBitrate 테스트 동작을 검증한다.
    func testToCanonicalConvertsDisplayUnitToBitrate() {
        let spec = tryUnwrapAudioBitRateSpec()

        XCTAssertEqual(
            UnitValueUtils.toCanonical(displayValueText: "320", from: "Kbps", spec: spec),
            "320000",
        )
        XCTAssertEqual(
            UnitValueUtils.toCanonical(displayValueText: "2.5", from: "Mbps", spec: spec),
            "2500000",
        )
    }

    /// testStripUnitSuffixIfNeededRemovesBitrateUnits 테스트 동작을 검증한다.
    func testStripUnitSuffixIfNeededRemovesBitrateUnits() {
        let spec = tryUnwrapAudioBitRateSpec()

        XCTAssertEqual(UnitValueUtils.stripUnitSuffixIfNeeded("320 Kbps", spec: spec), "320")
        XCTAssertEqual(UnitValueUtils.stripUnitSuffixIfNeeded("2.5 Mbps", spec: spec), "2.5")
        XCTAssertEqual(UnitValueUtils.stripUnitSuffixIfNeeded("128000", spec: spec), "128000")
    }

    /// testVideoBitRateUsesSameUnitSpecAsAudioBitRate 테스트 동작을 검증한다.
    func testVideoBitRateUsesSameUnitSpecAsAudioBitRate() {
        let spec = tryUnwrapSpec(for: "video_bit_rate")

        XCTAssertEqual(spec.canonicalUnit, "bps")
        XCTAssertEqual(spec.units.map(\.code), ["bps", "Kbps", "Mbps"])
        XCTAssertEqual(
            UnitValueUtils.toCanonical(displayValueText: "8", from: "Mbps", spec: spec),
            "8000000",
        )
    }

    /// testTotalBitRateUsesSameUnitSpecAsAudioBitRate 테스트 동작을 검증한다.
    func testTotalBitRateUsesSameUnitSpecAsAudioBitRate() {
        let spec = tryUnwrapSpec(for: "total_bit_rate")

        XCTAssertEqual(spec.canonicalUnit, "bps")
        XCTAssertEqual(spec.units.map(\.code), ["bps", "Kbps", "Mbps"])
        XCTAssertEqual(
            UnitValueUtils.fromCanonical(canonicalText: "1411000", to: "Mbps", spec: spec),
            "1.411",
        )
    }

    private func tryUnwrapSizeSpec(
        file: StaticString = #filePath,
        line: UInt = #line,
    ) -> UnitValueUtils.UnitSpec {
        guard let spec = UnitValueUtils.spec(for: "size", registryClient: registryClient) else {
            XCTFail("Expected size unit spec", file: file, line: line)
            fatalError("Missing size spec")
        }
        return spec
    }

    private func tryUnwrapAudioBitRateSpec(
        file: StaticString = #filePath,
        line: UInt = #line,
    ) -> UnitValueUtils.UnitSpec {
        tryUnwrapSpec(for: "audio_bit_rate", file: file, line: line)
    }

    private func tryUnwrapSpec(
        for propertyKey: String,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) -> UnitValueUtils.UnitSpec {
        guard let spec = UnitValueUtils.spec(for: propertyKey, registryClient: registryClient) else {
            XCTFail("Expected \(propertyKey) unit spec", file: file, line: line)
            fatalError("Missing \(propertyKey) spec")
        }
        return spec
    }
}
