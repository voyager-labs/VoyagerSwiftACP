@testable import VoyagerEntitiesTag
import XCTest

@MainActor
final class EOP004EditEntryTagsParserTests: XCTestCase {
    // MARK: - EOP-004-edit_entry_tags

    /// EOP-004-edit_entry_tags: Finder 색상 코드가 포함된 태그 문자열 파싱
        /// Finder 태그 원본 문자열에서 이름과 색상 코드를 보존하는지 검증합니다.
        /// - 검증 내용: `name\ncolorCode` 형식이 `Tag` 이름과 색상 코드로 변환됨
        /// - 사전 조건: 유효한 정수 색상 코드가 포함된 MDItem 태그 문자열
        /// - 기대 결과: 태그 이름과 색상 코드가 입력과 동일하게 보존
    func testParse_WithValidColorCode_ReturnsTagWithCorrectColorCode() {
        let result = TagMDItemUserTagParser.parse("blue\n6")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// EOP-004-edit_entry_tags: 유효하지 않은 색상 코드 기본값 처리
        /// Finder 태그 색상 코드가 숫자가 아닐 때 안전한 기본값으로 파싱되는지 검증합니다.
        /// - 검증 내용: 숫자가 아닌 색상 코드가 `0`으로 대체됨
        /// - 사전 조건: 이름은 유효하지만 색상 코드가 정수가 아닌 태그 문자열
        /// - 기대 결과: 태그 이름은 유지되고 색상 코드는 `0`
    func testParse_WithInvalidColorCode_FallsBackToZero() {
        let result = TagMDItemUserTagParser.parse("blue\nxyz")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// EOP-004-edit_entry_tags: 색상 코드 없는 태그 문자열 파싱
        /// Finder 태그 문자열에 색상 코드가 없을 때 기본 색상 코드가 적용되는지 검증합니다.
        /// - 검증 내용: 이름만 있는 입력이 `Tag`로 변환됨
        /// - 사전 조건: 색상 코드 구분자가 없는 태그 이름 문자열
        /// - 기대 결과: 태그 이름은 유지되고 색상 코드는 `0`
    func testParse_WithoutColorCode_ReturnsZero() {
        let result = TagMDItemUserTagParser.parse("blue")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// EOP-004-edit_entry_tags: 빈 태그 이름 거부
        /// 태그 편집 메타데이터에서 빈 이름이 유효한 태그로 생성되지 않는지 검증합니다.
        /// - 검증 내용: 빈 문자열 입력은 nil로 처리됨
        /// - 사전 조건: 빈 태그 문자열
        /// - 기대 결과: 파서 결과가 nil
    func testParse_WithEmptyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parse("")

        XCTAssertNil(result)
    }

    /// EOP-004-edit_entry_tags: 공백뿐인 태그 이름 거부
        /// 공백만 포함된 태그 이름이 유효한 태그로 저장되지 않도록 검증합니다.
        /// - 검증 내용: 공백 문자열 입력은 nil로 처리됨
        /// - 사전 조건: 공백 문자만 포함된 태그 문자열
        /// - 기대 결과: 파서 결과가 nil
    func testParse_WithWhitespaceOnlyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parse("   ")

        XCTAssertNil(result)
    }

    /// EOP-004-edit_entry_tags: 태그 이름 앞뒤 공백 정규화
        /// Finder 태그 이름 주변 공백이 저장 모델로 들어가기 전에 제거되는지 검증합니다.
        /// - 검증 내용: 앞뒤 공백이 제거된 이름과 색상 코드가 반환됨
        /// - 사전 조건: 이름 주변에 공백이 포함된 태그 문자열
        /// - 기대 결과: 이름은 trim되고 색상 코드는 유지
    func testParse_TrimsWhitespaceFromName() {
        let result = TagMDItemUserTagParser.parse("  blue  \n6")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// EOP-004-edit_entry_tags: 색상 코드 주변 공백 정규화
        /// 색상 코드 뒤쪽 공백이 있어도 색상 코드가 안정적으로 파싱되는지 검증합니다.
        /// - 검증 내용: 공백이 포함된 색상 코드 문자열이 정수로 변환됨
        /// - 사전 조건: 색상 코드 뒤에 공백이 포함된 태그 문자열
        /// - 기대 결과: 색상 코드가 입력 정수로 유지
    func testParse_TrimsWhitespaceFromColorCode() {
        let result = TagMDItemUserTagParser.parse("blue\n6  ")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// EOP-004-edit_entry_tags: 0 색상 코드 보존
        /// 기본 색상 코드 값이 명시적으로 입력됐을 때 그대로 보존되는지 검증합니다.
        /// - 검증 내용: `0` 색상 코드가 누락값과 충돌하지 않고 반환됨
        /// - 사전 조건: 색상 코드 `0`이 포함된 태그 문자열
        /// - 기대 결과: 색상 코드가 `0`
    func testParse_WithZeroColorCode_ReturnsZero() {
        let result = TagMDItemUserTagParser.parse("blue\n0")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// EOP-004-edit_entry_tags: 비표준 음수 색상 코드 파싱
        /// 파서가 Finder 표준 범위 밖 정수도 손실 없이 통과시키는 현재 계약을 검증합니다.
        /// - 검증 내용: 음수 색상 코드가 정수로 파싱됨
        /// - 사전 조건: 음수 색상 코드가 포함된 태그 문자열
        /// - 기대 결과: 색상 코드가 입력 음수 값과 동일
    func testParse_WithNegativeColorCode_ReturnsNegativeValue() {
        let result = TagMDItemUserTagParser.parse("blue\n-1")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, -1)
    }

    /// EOP-004-edit_entry_tags: relaxed 파서의 표준 형식 처리
        /// relaxed 파서가 표준 Finder 태그 문자열을 일반 파서와 동일하게 처리하는지 검증합니다.
        /// - 검증 내용: 유효한 `name\ncolorCode` 입력이 태그로 변환됨
        /// - 사전 조건: 유효한 색상 코드가 포함된 태그 문자열
        /// - 기대 결과: 이름과 색상 코드가 보존
    func testParseRelaxed_WithValidFormat_ReturnsParsedTag() {
        let result = TagMDItemUserTagParser.parseRelaxed("blue\n6")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// EOP-004-edit_entry_tags: relaxed 파서의 기본 색상 코드 적용
        /// relaxed 파서가 이름만 있는 입력에 기본 색상 코드를 적용하는지 검증합니다.
        /// - 검증 내용: 색상 코드 없는 입력이 기본 색상 코드로 변환됨
        /// - 사전 조건: 태그 이름만 포함된 문자열
        /// - 기대 결과: 태그 이름은 유지되고 색상 코드는 `0`
    func testParseRelaxed_WithInvalidInput_ReturnsTagWithDefaultColorCode() {
        let result = TagMDItemUserTagParser.parseRelaxed("blue")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// EOP-004-edit_entry_tags: relaxed 파서의 사용자 지정 기본 색상 코드 적용
        /// 호출자가 제공한 기본 색상 코드가 색상 코드 없는 태그에 사용되는지 검증합니다.
        /// - 검증 내용: custom defaultColorCode가 결과 태그에 반영됨
        /// - 사전 조건: 태그 이름만 포함된 입력과 custom defaultColorCode
        /// - 기대 결과: 결과 색상 코드가 custom 값과 동일
    func testParseRelaxed_WithCustomDefaultColorCode_UsesCustomDefault() {
        let result = TagMDItemUserTagParser.parseRelaxed("blue", defaultColorCode: 5)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 5)
    }

    /// EOP-004-edit_entry_tags: relaxed 파서의 빈 이름 거부
        /// relaxed 파서에서도 빈 태그 이름이 유효한 태그로 생성되지 않는지 검증합니다.
        /// - 검증 내용: 빈 문자열 입력은 nil로 처리됨
        /// - 사전 조건: 빈 태그 문자열
        /// - 기대 결과: 파서 결과가 nil
    func testParseRelaxed_WithEmptyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parseRelaxed("")

        XCTAssertNil(result)
    }

    /// EOP-004-edit_entry_tags: relaxed 파서의 공백 이름 거부
        /// relaxed 파서에서도 공백뿐인 태그 이름이 거부되는지 검증합니다.
        /// - 검증 내용: 공백 문자열 입력은 nil로 처리됨
        /// - 사전 조건: 공백 문자만 포함된 태그 문자열
        /// - 기대 결과: 파서 결과가 nil
    func testParseRelaxed_WithWhitespaceOnlyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parseRelaxed("   ")

        XCTAssertNil(result)
    }

    /// EOP-004-edit_entry_tags: relaxed 파서의 이름 공백 정규화
        /// relaxed 파서가 태그 이름 주변 공백을 제거하는지 검증합니다.
        /// - 검증 내용: 앞뒤 공백이 제거된 이름과 기본 색상 코드가 반환됨
        /// - 사전 조건: 이름 주변에 공백이 포함된 태그 문자열
        /// - 기대 결과: 이름은 trim되고 색상 코드는 `0`
    func testParseRelaxed_TrimsWhitespaceFromName() {
        let result = TagMDItemUserTagParser.parseRelaxed("  blue  ")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// EOP-004-edit_entry_tags: 여러 줄바꿈이 포함된 태그 문자열 처리
        /// Finder 태그 문자열에 추가 줄바꿈이 포함되어도 이름을 보존하고 색상 코드를 안전하게 기본값으로 낮추는지 검증합니다.
        /// - 검증 내용: 첫 줄은 이름으로 유지되고 파싱 불가능한 색상 문자열은 `0` 처리됨
        /// - 사전 조건: 이름, 색상 코드 후보, 추가 텍스트가 줄바꿈으로 연결된 문자열
        /// - 기대 결과: 태그 이름은 유지되고 색상 코드는 `0`
    func testParse_WithMultipleNewlines_HandlesGracefully() {
        // 참고: maxSplits: 1이므로 최대 2개의 컴포넌트를 얻습니다
        // "blue\n6\nextra" → ["blue", "6\nextra"]
        // Int("6\nextra")가 실패하므로 colorCode는 0이 됩니다
        let result = TagMDItemUserTagParser.parse("blue\n6\nextra")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0) // Int("6\nextra") 실패
    }

    /// EOP-004-edit_entry_tags: Finder 표준 색상 코드 범위 보존
        /// Finder가 사용하는 1-7 색상 코드가 모두 손실 없이 파싱되는지 검증합니다.
        /// - 검증 내용: 각 Finder 색상 코드 입력이 동일한 `Tag.colorCode`로 반환됨
        /// - 사전 조건: 색상 코드 1부터 7까지의 태그 문자열 목록
        /// - 기대 결과: 모든 결과 색상 코드가 입력 코드와 동일
    func testParse_WithFinderColorCodes_ReturnsCorrectColorCode() {
        let colorCodes = [1, 2, 3, 4, 5, 6, 7]

        for code in colorCodes {
            let result = TagMDItemUserTagParser.parse("tag\n\(code)")
            XCTAssertEqual(result?.colorCode, code, "Expected colorCode \(code) for input 'tag\\n\(code)'")
        }
    }
}
