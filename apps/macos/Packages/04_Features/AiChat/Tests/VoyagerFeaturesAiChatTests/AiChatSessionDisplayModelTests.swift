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

        let rows = makeBucketingTestRows(calendar: calendar, now: now)

        let displayModel = AiChatSessionsDisplayModel(
            rows: [rows.year, rows.previous30Days, rows.today, rows.month, rows.yesterday, rows.previous7Days],
            now: now,
            calendar: calendar,
        )

        assertBucketingSections(displayModel)
        assertBucketingTitles(displayModel)
        assertBucketingRowTitles(displayModel)
    }

    func testEmptyStateUsesExactStrings() {
        let displayModel = AiChatSessionsDisplayModel(rows: [], now: makeFixedDate(milliseconds: 1_700_000_000_000))

        XCTAssertTrue(displayModel.isEmpty)
        XCTAssertEqual(displayModel.title, "Sessions")
        XCTAssertEqual(displayModel.newChatTitle, "New Chat")
        XCTAssertEqual(displayModel.searchPlaceholder, "Search")
        XCTAssertEqual(displayModel.emptyTitle, "No sessions yet")
        XCTAssertEqual(displayModel.emptyDetail, "Start a new chat with the current context")
        XCTAssertTrue(displayModel.sections.isEmpty)
    }

    func testSearchEmptyStateUsesExactStringsWhenRowsAreFilteredOut() {
        let displayModel = AiChatSessionsDisplayModel(
            rows: [],
            now: makeFixedDate(milliseconds: 1_700_000_000_000),
            query: "  missing  ",
            totalRowCount: 2,
        )

        XCTAssertTrue(displayModel.isEmpty)
        XCTAssertEqual(displayModel.emptyTitle, "No matching sessions")
        XCTAssertEqual(displayModel.emptyDetail, "Try a different search term.")
        XCTAssertTrue(displayModel.sections.isEmpty)
    }

    func testRowActivityStatesPreferProcessingOverUnreadCompletion() {
        let now = makeFixedDate(milliseconds: 1_700_000_000_000)
        let processingID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111181"))
        let unreadID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111182"))
        let idleID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111183"))
        let processing = makeSessionSummary(
            sessionID: processingID,
            title: "Processing",
            updatedAtMs: milliseconds(for: now),
        )
        let unread = makeSessionSummary(sessionID: unreadID, title: "Unread", updatedAtMs: milliseconds(for: now))
        let idle = makeSessionSummary(sessionID: idleID, title: "Idle", updatedAtMs: milliseconds(for: now))

        let displayModel = AiChatSessionsDisplayModel(
            rows: [processing, unread, idle],
            now: now,
            processingSessionID: processingID,
            unreadCompletedSessionIDs: [processingID, unreadID],
        )
        let rows = displayModel.sections.flatMap(\.rows)

        XCTAssertEqual(rows.map(\.id), [processingID, unreadID, idleID])
        XCTAssertEqual(rows.map(\.activityState), [.processing, .unreadCompleted, .idle])
        XCTAssertNil(rows[0].detail)
        XCTAssertEqual(rows[1].detail, "Preview")
        XCTAssertEqual(rows[2].detail, "Preview")
    }

    func testHiddenEmptyDraftRowsAreExcludedFromSections() {
        let now = makeFixedDate(milliseconds: 1_700_000_000_000)
        let draftID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111184"))
        let visibleID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111185"))
        let draft = makeSessionSummary(sessionID: draftID, title: "New Chat", updatedAtMs: milliseconds(for: now))
        let visible = makeSessionSummary(
            sessionID: visibleID,
            title: "Visible prompt",
            updatedAtMs: milliseconds(for: now),
        )

        let displayModel = AiChatSessionsDisplayModel(
            rows: [draft, visible],
            now: now,
            totalRowCount: 2,
            hiddenSessionIDs: [draftID],
        )
        let rows = displayModel.sections.flatMap(\.rows)

        XCTAssertEqual(rows.map(\.id), [visibleID])
        XCTAssertEqual(rows.map(\.title), ["Visible prompt"])
    }

    func testSearchQueryStillUsesNoSessionsCopyWhenThereAreNoSavedSessions() {
        let displayModel = AiChatSessionsDisplayModel(
            rows: [],
            now: makeFixedDate(milliseconds: 1_700_000_000_000),
            query: "  missing  ",
            totalRowCount: 0,
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
    calendar: Calendar,
) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
}

private func milliseconds(for date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1000)
}

private func makeSessionSummary(
    sessionID: AiChatSessionID,
    title: String,
    updatedAtMs: Int64,
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
        status: .active,
    )
}

private struct BucketingTestRows {
    let today: AiChatSessionSummary
    let yesterday: AiChatSessionSummary
    let previous7Days: AiChatSessionSummary
    let previous30Days: AiChatSessionSummary
    let month: AiChatSessionSummary
    let year: AiChatSessionSummary
}

private func makeBucketingTestRows(calendar: Calendar, now: Date) -> BucketingTestRows {
    BucketingTestRows(
        today: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111")),
            title: "Today session",
            updatedAtMs: milliseconds(for: now),
        ),
        yesterday: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222")),
            title: "Yesterday session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 5, day: 24, calendar: calendar)),
        ),
        previous7Days: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333")),
            title: "Previous 7 Days session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 5, day: 21, calendar: calendar)),
        ),
        previous30Days: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444")),
            title: "Previous 30 Days session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 5, day: 1, calendar: calendar)),
        ),
        month: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555")),
            title: "Month session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 2, day: 1, calendar: calendar)),
        ),
        year: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("66666666-6666-6666-6666-666666666666")),
            title: "Year session",
            updatedAtMs: milliseconds(for: makeDate(year: 2024, month: 12, day: 1, calendar: calendar)),
        ),
    )
}

private func assertBucketingSections(_ displayModel: AiChatSessionsDisplayModel) {
    XCTAssertEqual(displayModel.sections.map(\.bucket), [
        .today,
        .yesterday,
        .previous7Days,
        .previous30Days,
        .month(2),
        .year(2024),
    ])
}

private func assertBucketingTitles(_ displayModel: AiChatSessionsDisplayModel) {
    XCTAssertEqual(displayModel.sections.map(\.title), [
        "Today",
        "Yesterday",
        "Previous 7 Days",
        "Previous 30 Days",
        "February",
        "2024",
    ])
}

private func assertBucketingRowTitles(_ displayModel: AiChatSessionsDisplayModel) {
    XCTAssertEqual(displayModel.sections.map { $0.rows.map(\.title) }, [
        ["Today session"],
        ["Yesterday session"],
        ["Previous 7 Days session"],
        ["Previous 30 Days session"],
        ["Month session"],
        ["Year session"],
    ])
}
