import Foundation
@testable import VoyagerEntitiesEntry
import XCTest

final class EOP007EntryContextActionsTests: XCTestCase {
    /// EOP-007-reveal_entries_in_finder: Finder reveal은 global NSFileViewer 설정과 무관하게 Finder를 대상으로 한다.
    /// - 검증 내용: 생성된 AppleScript가 Finder bundle ID와 reveal 명령을 명시하는지 확인한다.
    /// - 사전 조건: 일반 파일 URL 하나가 있다.
    /// - 기대 결과: script가 default viewer가 아닌 `com.apple.finder`를 직접 대상으로 한다.
    func testFinderRevealTargetsFinderBundleDirectly() {
        let source = EntryFinderReveal.scriptSource(for: [URL(fileURLWithPath: "/tmp/report.txt")])

        XCTAssertTrue(source.contains("tell application id \"com.apple.finder\""))
        XCTAssertTrue(source.contains("activate"))
        XCTAssertTrue(source.contains("reveal POSIX file \"/tmp/report.txt\""))
    }

    /// EOP-007-reveal_entries_in_finder: Finder reveal script는 파일 경로의 backslash와 따옴표를 escape한다.
    /// - 검증 내용: 특수문자 파일명이 AppleScript 문자열을 깨뜨리지 않는지 확인한다.
    /// - 사전 조건: backslash와 따옴표가 포함된 파일 URL이 있다.
    /// - 기대 결과: 생성된 script가 escape된 POSIX file literal을 포함한다.
    func testFinderRevealEscapesAppleScriptPathLiteral() {
        let source = EntryFinderReveal.scriptSource(for: [
            URL(fileURLWithPath: "/tmp/quote\"\\report.txt"),
        ])

        XCTAssertTrue(source.contains(#"reveal POSIX file "/tmp/quote\"\\report.txt"#))
    }
}
