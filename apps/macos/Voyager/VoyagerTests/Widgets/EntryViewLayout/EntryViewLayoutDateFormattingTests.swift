@testable import Voyager
import XCTest

final class EntryViewLayoutDateFormattingTests: XCTestCase {
    func testTemplateMapping() {
        // < 140 -> yMd
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 50), "yMd")
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 139), "yMd")

        // < 220 -> MMMd
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 140), "MMMd")
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 219), "MMMd")

        // >= 220 -> yMMMdjm
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 220), "yMMMdjm")
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 500), "yMMMdjm")

        // width <= 0 -> safe fallback (yMd)
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 0), "yMd")
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: -10), "yMd")
    }

    func testFormattingWithFixedLocaleAndTimeZone() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
        let locale = Locale(identifier: "en_US_POSIX")
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let seoul = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))

        let yMd = EntryListDateFormatting.format(date, width: 100, locale: locale, timeZone: utc)
        XCTAssertTrue(yMd.contains("11"))
        XCTAssertTrue(yMd.contains("14"))
        XCTAssertTrue(yMd.contains("2023") || yMd.contains("23"))

        let mMMdd = EntryListDateFormatting.format(date, width: 150, locale: locale, timeZone: utc)
        XCTAssertTrue(mMMdd.contains("Nov"))
        XCTAssertTrue(mMMdd.contains("14"))

        let detailedUTC = EntryListDateFormatting.format(date, width: 250, locale: locale, timeZone: utc)
        XCTAssertTrue(detailedUTC.contains("Nov"))
        XCTAssertTrue(detailedUTC.contains("2023") || detailedUTC.contains("23"))

        let detailedSeoul = EntryListDateFormatting.format(date, width: 250, locale: locale, timeZone: seoul)
        XCTAssertNotEqual(detailedUTC, detailedSeoul)
    }

    func testRepeatedFormattingIsStable() throws {
        let date = Date()
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        let first = EntryListDateFormatting.format(date, width: 100, locale: locale, timeZone: timeZone)
        let second = EntryListDateFormatting.format(date, width: 100, locale: locale, timeZone: timeZone)
        XCTAssertEqual(first, second)
    }
}
