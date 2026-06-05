@testable import VoyagerEntitiesTag
import XCTest

/// TagMDItemUserTagParser 동작에 대한 명세 테스트
/// MDItem kMDItemUserTags 형식의 현재 파싱 동작을 규격화합니다.
/// 형식: "name\ncolorCode" (예: "blue\n6")
@MainActor
final class TagMDItemUserTagParserTests: XCTestCase {
    // MARK: - parse(_:) 테스트

    /// 유효한 색상 코드가 파싱 중 보존되는지 테스트합니다.
    /// 기대 결과: "blue\n6" → Tag(name: "blue", colorCode: 6)
    func testParse_WithValidColorCode_ReturnsTagWithCorrectColorCode() {
        let result = TagMDItemUserTagParser.parse("blue\n6")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// 유효하지 않은(숫자가 아닌) 색상 코드가 0으로 폴백되는지 테스트합니다.
    /// 기대 결과: "blue\nxyz" → Tag(name: "blue", colorCode: 0)
    func testParse_WithInvalidColorCode_FallsBackToZero() {
        let result = TagMDItemUserTagParser.parse("blue\nxyz")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// 색상 코드가 없는 태그가 colorCode 0을 받는지 테스트합니다.
    /// 기대 결과: "blue" → Tag(name: "blue", colorCode: 0)
    func testParse_WithoutColorCode_ReturnsZero() {
        let result = TagMDItemUserTagParser.parse("blue")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// 빈 이름이 nil을 반환하는지 테스트합니다.
    /// 기대 결과: "" → nil
    func testParse_WithEmptyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parse("")

        XCTAssertNil(result)
    }

    /// 공백만 있는 이름이 nil을 반환하는지 테스트합니다.
    /// 기대 결과: "   " → nil
    func testParse_WithWhitespaceOnlyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parse("   ")

        XCTAssertNil(result)
    }

    /// 이름의 앞뒤 공백이 잘리는지 테스트합니다.
    /// 기대 결과: "  blue  \n6" → Tag(name: "blue", colorCode: 6)
    func testParse_TrimsWhitespaceFromName() {
        let result = TagMDItemUserTagParser.parse("  blue  \n6")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// 색상 코드의 뒤 공백/줄바꿈이 올바르게 파싱되는지 테스트합니다.
    /// 기대 결과: "blue\n6  " → Tag(name: "blue", colorCode: 6)
    func testParse_TrimsWhitespaceFromColorCode() {
        let result = TagMDItemUserTagParser.parse("blue\n6  ")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// 0인 색상 코드가 보존되는지 테스트합니다.
    /// 기대 결과: "blue\n0" → Tag(name: "blue", colorCode: 0)
    func testParse_WithZeroColorCode_ReturnsZero() {
        let result = TagMDItemUserTagParser.parse("blue\n0")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// 음수 색상 코드가 파싱되는지 테스트합니다 (Finder는 1-7을 허용하지만 파서는 모든 Int를 받습니다).
    /// 기대 결과: "blue\n-1" → Tag(name: "blue", colorCode: -1)
    func testParse_WithNegativeColorCode_ReturnsNegativeValue() {
        let result = TagMDItemUserTagParser.parse("blue\n-1")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, -1)
    }

    // MARK: - parseRelaxed(_:defaultColorCode:) 테스트

    /// parseRelaxed가 유효한 형식일 때 parse로 폴백하는지 테스트합니다.
    /// 기대 결과: "blue\n6" → Tag(name: "blue", colorCode: 6)
    func testParseRelaxed_WithValidFormat_ReturnsParsedTag() {
        let result = TagMDItemUserTagParser.parseRelaxed("blue\n6")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// parseRelaxed가 이름만 있는 입력에서 기본 색상 코드를 사용하는지 테스트합니다.
    /// 기대 결과: "blue" → Tag(name: "blue", colorCode: 0)
    func testParseRelaxed_WithInvalidInput_ReturnsTagWithDefaultColorCode() {
        let result = TagMDItemUserTagParser.parseRelaxed("blue")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// parseRelaxed가 커스텀 defaultColorCode를 사용하는지 테스트합니다.
    /// 기대 결과: "blue" with defaultColorCode: 5 → Tag(name: "blue", colorCode: 5)
    func testParseRelaxed_WithCustomDefaultColorCode_UsesCustomDefault() {
        let result = TagMDItemUserTagParser.parseRelaxed("blue", defaultColorCode: 5)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 5)
    }

    /// parseRelaxed가 빈 이름에서 nil을 반환하는지 테스트합니다.
    /// 기대 결과: "" → nil
    func testParseRelaxed_WithEmptyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parseRelaxed("")

        XCTAssertNil(result)
    }

    /// parseRelaxed가 공백만 있는 이름에서 nil을 반환하는지 테스트합니다.
    /// 기대 결과: "   " → nil
    func testParseRelaxed_WithWhitespaceOnlyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parseRelaxed("   ")

        XCTAssertNil(result)
    }

    /// parseRelaxed가 이름의 공백을 자르는지 테스트합니다.
    /// 기대 결과: "  blue  " → Tag(name: "blue", colorCode: 0)
    func testParseRelaxed_TrimsWhitespaceFromName() {
        let result = TagMDItemUserTagParser.parseRelaxed("  blue  ")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    // MARK: - 엣지 케이스

    /// 여러 줄바꿈이 처리되는지 테스트합니다 (첫 번째 분할만 적용).
    /// 기대 결과: "blue\n6\nextra" → Tag(name: "blue", colorCode: 6) - "extra"는 colorCode 문자열의 일부가 되어 실패
    /// Int()
    func testParse_WithMultipleNewlines_HandlesGracefully() {
        // 참고: maxSplits: 1이므로 최대 2개의 컴포넌트를 얻습니다
        // "blue\n6\nextra" → ["blue", "6\nextra"]
        // Int("6\nextra")가 실패하므로 colorCode는 0이 됩니다
        let result = TagMDItemUserTagParser.parse("blue\n6\nextra")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0) // Int("6\nextra") 실패
    }

    /// 다양한 Finder 색상 코드(1-7)를 테스트합니다.
    func testParse_WithFinderColorCodes_ReturnsCorrectColorCode() {
        let colorCodes = [1, 2, 3, 4, 5, 6, 7]

        for code in colorCodes {
            let result = TagMDItemUserTagParser.parse("tag\n\(code)")
            XCTAssertEqual(result?.colorCode, code, "Expected colorCode \(code) for input 'tag\\n\(code)'")
        }
    }
}
