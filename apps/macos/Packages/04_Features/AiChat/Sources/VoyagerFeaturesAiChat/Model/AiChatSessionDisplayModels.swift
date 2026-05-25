import Foundation
import VoyagerEntitiesAi
import VoyagerShared

public enum AiChatSessionDateBucket: Hashable, Sendable {
    case today
    case yesterday
    case previous7Days
    case previous30Days
    case month(Int)
    case year(Int)

    public init(_ bucket: DateGroupBucket) {
        switch bucket {
        case .today:
            self = .today
        case .yesterday:
            self = .yesterday
        case .previous7Days:
            self = .previous7Days
        case .previous30Days:
            self = .previous30Days
        case let .month(month):
            self = .month(month)
        case let .year(year):
            self = .year(year)
        }
    }

    public var title: String {
        switch self {
        case .today:
            "Today"
        case .yesterday:
            "Yesterday"
        case .previous7Days:
            "Previous 7 Days"
        case .previous30Days:
            "Previous 30 Days"
        case let .month(month):
            Self.monthTitle(month)
        case let .year(year):
            "\(year)"
        }
    }

    public var dateGroupBucket: DateGroupBucket {
        switch self {
        case .today:
            .today
        case .yesterday:
            .yesterday
        case .previous7Days:
            .previous7Days
        case .previous30Days:
            .previous30Days
        case let .month(month):
            .month(month)
        case let .year(year):
            .year(year)
        }
    }

    private static func monthTitle(_ month: Int) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        guard let date = calendar.date(from: DateComponents(year: currentYear, month: month, day: 1)) else {
            return "\(month)"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
}

public struct AiChatSessionRowDisplayModel: Identifiable, Equatable, Sendable {
    public var id: AiChatSessionID { summary.sessionID }

    public let summary: AiChatSessionSummary
    public let title: String
    public let detail: String?

    public init(summary: AiChatSessionSummary) {
        self.summary = summary
        self.title = summary.title
        self.detail = summary.preview ?? summary.contextTitle
    }
}

public struct AiChatSessionSectionDisplayModel: Identifiable, Equatable, Sendable {
    public var id: AiChatSessionDateBucket { bucket }

    public let bucket: AiChatSessionDateBucket
    public let title: String
    public let rows: [AiChatSessionRowDisplayModel]

    public init(bucket: AiChatSessionDateBucket, rows: [AiChatSessionRowDisplayModel]) {
        self.bucket = bucket
        self.title = bucket.title
        self.rows = rows
    }
}

public struct AiChatSessionsDisplayModel: Equatable, Sendable {
    public let title: String
    public let newChatTitle: String
    public let searchPlaceholder: String
    public let emptyTitle: String
    public let emptyDetail: String
    public let sections: [AiChatSessionSectionDisplayModel]

    public init(
        rows: [AiChatSessionSummary],
        now: Date,
        calendar: Calendar = .current,
        query: String = "",
        totalRowCount: Int? = nil
    ) {
        title = "Sessions"
        newChatTitle = "New Chat"
        searchPlaceholder = "Search sessions"

        let hasActiveSearch = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSessionsBeforeFiltering = (totalRowCount ?? rows.count) > 0
        if rows.isEmpty, hasActiveSearch, hasSessionsBeforeFiltering {
            emptyTitle = "No matching sessions"
            emptyDetail = "Try a different search term."
        } else {
            emptyTitle = "No sessions yet"
            emptyDetail = "Start a new chat with the current context"
        }

        sections = Self.makeSections(rows: rows, now: now, calendar: calendar)
    }

    public var isEmpty: Bool {
        sections.allSatisfy(\.rows.isEmpty)
    }

    public static func makeSections(
        rows: [AiChatSessionSummary],
        now: Date,
        calendar: Calendar = .current
    ) -> [AiChatSessionSectionDisplayModel] {
        let grouped = Dictionary(grouping: rows) { summary in
            bucket(forUpdatedAtMs: summary.updatedAtMs, now: now, calendar: calendar)
        }

        return grouped.keys
            .sorted { lhs, rhs in
                DateGroupBucket.ordered(lhs.dateGroupBucket, rhs.dateGroupBucket)
            }
            .compactMap { bucket in
                guard let bucketRows = grouped[bucket], !bucketRows.isEmpty else { return nil }
                return AiChatSessionSectionDisplayModel(
                    bucket: bucket,
                    rows: bucketRows.map(AiChatSessionRowDisplayModel.init(summary:))
                )
            }
    }

    public static func bucket(
        forUpdatedAtMs updatedAtMs: Int64,
        now: Date,
        calendar: Calendar = .current
    ) -> AiChatSessionDateBucket {
        let updatedAt = Date(timeIntervalSince1970: TimeInterval(updatedAtMs) / 1000)
        return AiChatSessionDateBucket(DateGroupBucket.bucket(for: updatedAt, now: now, calendar: calendar))
    }
}
