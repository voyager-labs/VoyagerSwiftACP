import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatSessionDisplayModelTests: XCTestCase {
    func testBucketingGroupsRowsIntoTodayYesterdayAndOlder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let today = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111")),
            title: "Today session",
            updatedAtMs: Int64(now.timeIntervalSince1970 * 1000)
        )
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterday = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222")),
            title: "Yesterday session",
            updatedAtMs: Int64(yesterdayDate.timeIntervalSince1970 * 1000)
        )
        let olderDate = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let older = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333")),
            title: "Older session",
            updatedAtMs: Int64(olderDate.timeIntervalSince1970 * 1000)
        )

        let displayModel = AiChatSessionsDisplayModel(
            rows: [today, yesterday, older],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(displayModel.sections.map { $0.bucket }, [.today, .yesterday, .older])
        XCTAssertEqual(displayModel.sections[0].rows.map { $0.title }, ["Today session"])
        XCTAssertEqual(displayModel.sections[1].rows.map { $0.title }, ["Yesterday session"])
        XCTAssertEqual(displayModel.sections[2].rows.map { $0.title }, ["Older session"])
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
