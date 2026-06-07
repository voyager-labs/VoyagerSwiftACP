import Foundation
import Testing
@testable import VoyagerShared

@Suite("RelativeDateConditionLiteral")
struct RelativeDateConditionLiteralTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private let fixedNow = Date(timeIntervalSince1970: 1_747_433_600) // 2025-05-17T00:00:00Z

    @Test
    func `parses canonical literal`() {
        let literal = RelativeDateConditionLiteral.parse("voyager.relativeDate:v1:past:3:day:2025-05-17")
        #expect(literal != nil)
        #expect(literal?.direction == .past)
        #expect(literal?.amount == 3)
        #expect(literal?.unit == .day)
        #expect(literal?.anchorDateLiteral == "2025-05-17")
    }

    @Test
    func `rejects invalid relative literal`() {
        #expect(RelativeDateConditionLiteral.parse("voyager.relativeDate:v1:past:0:day:2025-05-17") == nil)
        #expect(RelativeDateConditionLiteral.parse("voyager.relativeDate:v2:past:3:day:2025-05-17") == nil)
        #expect(RelativeDateConditionLiteral.parse("voyager.relativeDate:v1:past:3:century:2025-05-17") == nil)
        #expect(RelativeDateConditionLiteral.parse("voyager.relativeDate:v1:past:3:day:2025-5-17") == nil)
    }

    @Test
    func `encodes canonical literal`() {
        let encoded = RelativeDateConditionLiteral.encode(
            direction: .future,
            amount: 7,
            unit: .week,
            anchorDateLiteral: "2025-05-17",
        )
        #expect(encoded == "voyager.relativeDate:v1:future:7:week:2025-05-17")
    }

    @Test
    func `display text is human readable`() {
        let literal = RelativeDateConditionLiteral(
            direction: .past,
            amount: 2,
            unit: .month,
            anchorDateLiteral: "2025-05-17",
        )
        #expect(literal.displayText() == "2 months ago")
    }

    @Test
    func `resolve uses calendar units`() {
        let pastMonth = RelativeDateConditionLiteral(
            direction: .past,
            amount: 1,
            unit: .month,
            anchorDateLiteral: "2025-05-17",
        )
        let resolved = pastMonth.resolve(now: fixedNow, calendar: calendar)
        #expect(resolved != nil)
        #expect(DateNormalizerUtils.formatDateOnly(resolved ?? fixedNow) == "2025-04-17")
    }

    @Test
    func `resolve week forward and day backward remain deterministic`() {
        let futureWeek = RelativeDateConditionLiteral(
            direction: .future,
            amount: 2,
            unit: .week,
            anchorDateLiteral: "2025-05-17",
        )
        let pastDay = RelativeDateConditionLiteral(
            direction: .past,
            amount: 7,
            unit: .day,
            anchorDateLiteral: "2025-05-17",
        )
        #expect(DateNormalizerUtils
            .formatDateOnly(futureWeek.resolve(now: fixedNow, calendar: calendar) ?? fixedNow) == "2025-05-31")
        #expect(DateNormalizerUtils
            .formatDateOnly(pastDay.resolve(now: fixedNow, calendar: calendar) ?? fixedNow) == "2025-05-10")
    }
}
