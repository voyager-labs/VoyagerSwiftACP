import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatSessionDisplayModelTests: XCTestCase {
    func testBucketingGroupsRowsUsingContentPaneDateSections() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = makeDate(year: 2026, month: 5, day: 25, calendar: calendar)

        let today = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111")),
            title: "Today session",
            updatedAtMs: milliseconds(for: now)
        )
        let yesterday = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222")),
            title: "Yesterday session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 5, day: 24, calendar: calendar))
        )
        let previous7Days = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333")),
            title: "Previous 7 Days session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 5, day: 21, calendar: calendar))
        )
        let previous30Days = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444")),
            title: "Previous 30 Days session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 5, day: 1, calendar: calendar))
        )
        let month = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555")),
            title: "Month session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 2, day: 1, calendar: calendar))
        )
        let year = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("66666666-6666-6666-6666-666666666666")),
            title: "Year session",
            updatedAtMs: milliseconds(for: makeDate(year: 2024, month: 12, day: 1, calendar: calendar))
        )

        let displayModel = AiChatSessionsDisplayModel(
            rows: [year, previous30Days, today, month, yesterday, previous7Days],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(displayModel.sections.map { $0.bucket }, [
            .today,
            .yesterday,
            .previous7Days,
            .previous30Days,
            .month(2),
            .year(2024),
        ])
        XCTAssertEqual(displayModel.sections.map { $0.title }, [
            "Today",
            "Yesterday",
            "Previous 7 Days",
            "Previous 30 Days",
            "February",
            "2024",
        ])
        XCTAssertEqual(displayModel.sections.map { $0.rows.map(\.title) }, [
            ["Today session"],
            ["Yesterday session"],
            ["Previous 7 Days session"],
            ["Previous 30 Days session"],
            ["Month session"],
            ["Year session"],
        ])
    }

    func testEmptyStateUsesExactStrings() {
        let displayModel = AiChatSessionsDisplayModel(rows: [], now: makeFixedDate(milliseconds: 1_700_000_000_000))

        XCTAssertTrue(displayModel.isEmpty)
        XCTAssertEqual(displayModel.title, "Sessions")
        XCTAssertEqual(displayModel.newChatTitle, "New Chat")
        XCTAssertEqual(displayModel.searchPlaceholder, "Search sessions")
        XCTAssertEqual(displayModel.emptyTitle, "No sessions yet")
        XCTAssertEqual(displayModel.emptyDetail, "Start a new chat with the current context")
        XCTAssertTrue(displayModel.sections.isEmpty)
    }

    func testSearchEmptyStateUsesExactStringsWhenRowsAreFilteredOut() {
        let displayModel = AiChatSessionsDisplayModel(
            rows: [],
            now: makeFixedDate(milliseconds: 1_700_000_000_000),
            query: "  missing  ",
            totalRowCount: 2
        )

        XCTAssertTrue(displayModel.isEmpty)
        XCTAssertEqual(displayModel.emptyTitle, "No matching sessions")
        XCTAssertEqual(displayModel.emptyDetail, "Try a different search term.")
        XCTAssertTrue(displayModel.sections.isEmpty)
    }

    func testSearchQueryStillUsesNoSessionsCopyWhenThereAreNoSavedSessions() {
        let displayModel = AiChatSessionsDisplayModel(
            rows: [],
            now: makeFixedDate(milliseconds: 1_700_000_000_000),
            query: "  missing  ",
            totalRowCount: 0
        )

        XCTAssertTrue(displayModel.isEmpty)
        XCTAssertEqual(displayModel.emptyTitle, "No sessions yet")
        XCTAssertEqual(displayModel.emptyDetail, "Start a new chat with the current context")
        XCTAssertTrue(displayModel.sections.isEmpty)
    }
}

private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    calendar: Calendar
) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
}

private func milliseconds(for date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1000)
}

private func makeSessionSummary(
    sessionID: AiChatSessionID,
    title: String,
    updatedAtMs: Int64
) -> AiChatSessionSummary {
    AiChatSessionSummary(
        sessionID: sessionID,
        title: title,
        preview: "Preview",
        messageCount: 2,
        contextTitle: "Context",
        provider: .openai,
        model: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
        createdAtMs: updatedAtMs,
        updatedAtMs: updatedAtMs,
        status: .active
    )
}
