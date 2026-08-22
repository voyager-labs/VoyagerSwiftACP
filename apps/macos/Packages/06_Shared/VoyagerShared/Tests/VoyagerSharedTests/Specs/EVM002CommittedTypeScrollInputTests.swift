import Foundation
@testable import VoyagerShared
import XCTest

final class EVM002CommittedTypeScrollInputTests: XCTestCase {
    /// 단일 그래핌(한 글자) 입력은 그대로 반환된다.
    func testSingleGraphemeReturnsOriginalString() {
        XCTAssertEqual(CommittedTypeScrollInput.character(from: "a"), "a")
        XCTAssertEqual(CommittedTypeScrollInput.character(from: "가"), "가")
        XCTAssertEqual(CommittedTypeScrollInput.character(from: "é"), "é")
        XCTAssertEqual(CommittedTypeScrollInput.character(from: "あ"), "あ")
        XCTAssertEqual(CommittedTypeScrollInput.character(from: "中"), "中")
    }

    /// 빈 문자열은 유효한 입력이 아니다.
    func testEmptyStringReturnsNil() {
        XCTAssertNil(CommittedTypeScrollInput.character(from: ""))
    }

    /// 그래핌 수가 2 이상이면 nil을 반환한다 (절대 prefix로 자르지 않는다).
    func testMultiGraphemeReturnsNil() {
        XCTAssertNil(CommittedTypeScrollInput.character(from: "ab"))
        XCTAssertNil(CommittedTypeScrollInput.character(from: "가나"))
    }

    /// 공백(스페이스/탭/개행)은 유효한 입력이 아니다.
    func testWhitespaceReturnsNil() {
        XCTAssertNil(CommittedTypeScrollInput.character(from: " "))
        XCTAssertNil(CommittedTypeScrollInput.character(from: "\t"))
        XCTAssertNil(CommittedTypeScrollInput.character(from: "\n"))
    }

    /// 제어 문자(컨트롤/함수 키)는 유효한 입력이 아니다.
    func testControlAndFunctionKeyScalarsReturnNil() {
        // NUL (0x00)
        XCTAssertNil(CommittedTypeScrollInput.character(from: "\u{0000}"))
        // DEL (0x7F)
        XCTAssertNil(CommittedTypeScrollInput.character(from: "\u{007F}"))
        // NSUpArrowFunctionKey (0xF700) 영역의 함수 키 문자
        XCTAssertNil(CommittedTypeScrollInput.character(from: "\u{F700}"))
        // 함수 키 영역 내 사적 사용 문자 (0xF702)
        XCTAssertNil(CommittedTypeScrollInput.character(from: "\u{F702}"))
    }

    /// 그래핌 클러스터 수가 1이면 여러 scalar로 구성되어도 유효하다 (count == 1 그래핌 의미).
    func testSingleGraphemeClusterWithMultipleScalarsIsValid() {
        // U+1100 U+1161 (한글 초성+중성)이 합쳐져 그래핌 수 1
        let nfd = "\u{1100}\u{1161}"
        XCTAssertEqual(nfd.count, 1)
        XCTAssertEqual(CommittedTypeScrollInput.character(from: nfd), nfd)
    }
}
