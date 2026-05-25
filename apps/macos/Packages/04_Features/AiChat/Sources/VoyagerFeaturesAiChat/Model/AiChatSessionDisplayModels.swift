import Foundation
import VoyagerEntitiesAi

public enum AiChatSessionDateBucket: String, Equatable, Sendable {
    case today = "Today"
    case yesterday = "Yesterday"
    case older = "Older"

    public var title: String { rawValue }
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

        return [AiChatSessionDateBucket.today, .yesterday, .older]
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
        if calendar.isDate(updatedAt, inSameDayAs: now) {
            return .today
        }

        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            return .older
        }

        if calendar.isDate(updatedAt, inSameDayAs: yesterday) {
            return .yesterday
        }

        return .older
    }
}
