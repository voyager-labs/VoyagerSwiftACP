import Foundation
import SwiftUI
import VoyagerEntitiesAi

struct AiChatTranscriptRowID: Hashable {
    let index: Int
    let role: AiChatMessageRole
    let createdAtMs: Int64?
    func hash(into hasher: inout Hasher) {
        hasher.combine(index)
        hasher.combine(role.rawValue)
        hasher.combine(createdAtMs)
    }
}

enum AiChatTranscriptTimestampStyle: Equatable { case dateTime, relative, shortTime }
struct AiChatTranscriptRowPresentation: Identifiable, Equatable {
    let id: AiChatTranscriptRowID
    let message: AiChatMessage
    let timestampStyle: AiChatTranscriptTimestampStyle?
    let timestampLabel, accessibilityTimestampLabel: String?
    let isTimestampVisuallySuppressed: Bool
    var hasTimestampMetadata: Bool {
        (message.role == .user || message.role == .assistant) && message.createdAtMs != nil
    }

    var showsTimestampAffordance: Bool {
        hasTimestampMetadata && !isTimestampVisuallySuppressed
    }
}

struct AiChatTimestampAffordancePresentation: Equatable {
    enum Placement: Equatable {
        case userLeadingGutter, assistantTopTrailing

        var horizontalOffset: CGFloat {
            let offset = AiChatTimestampAffordancePresentation.controlSize + 4
            return self == .userLeadingGutter ? -offset : offset
        }
    }

    static let controlSize: CGFloat = 24, assistantTrailingGutter = controlSize + 4
    static let tooltipMaximumWidth: CGFloat = 320
    static let tooltipHorizontalPadding: CGFloat = 10, tooltipVerticalPadding: CGFloat = 6
    let placement: Placement

    static func presentsTooltip(hasTimestampMetadata: Bool, isClockHovered: Bool, isClockFocused: Bool) -> Bool {
        hasTimestampMetadata && (isClockHovered || isClockFocused)
    }
}

struct AiChatTranscriptPresentation: Equatable {
    let rows: [AiChatTranscriptRowPresentation]
    init(messages: [AiChatMessage], now: Date, locale: Locale, timeZone: TimeZone) {
        rows = messages.enumerated().map { index, message in
            let timestamp = Self.timestampPresentation(
                createdAtMs: message.createdAtMs, now: now, locale: locale, timeZone: timeZone,
            )
            return AiChatTranscriptRowPresentation(
                id: AiChatTranscriptRowID(index: index, role: message.role, createdAtMs: message.createdAtMs),
                message: message,
                timestampStyle: timestamp?.style,
                timestampLabel: timestamp?.label,
                accessibilityTimestampLabel: timestamp?.label,
                isTimestampVisuallySuppressed: Self.suppressesTimestamp(
                    message, after: index > 0 ? messages[index - 1] : nil,
                ),
            )
        }
    }

    static func timestampPresentation(
        createdAtMs: Int64?,
        now: Date,
        locale: Locale,
        timeZone: TimeZone,
    ) -> (style: AiChatTranscriptTimestampStyle, label: String)? {
        guard let createdAtMs else { return nil }
        let createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtMs) / 1000)
        if createdAt > now { return (.relative, "Just now") }
        var calendar = locale.calendar
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        if calendar.isDate(createdAt, inSameDayAs: now) {
            let age = now.timeIntervalSince(createdAt)
            if age < 60 { return (.relative, "Just now") }
            if age < 60 * 60 {
                let relativeFormatter = RelativeDateTimeFormatter()
                relativeFormatter.locale = locale
                relativeFormatter.dateTimeStyle = .numeric
                return (.relative, relativeFormatter.localizedString(for: createdAt, relativeTo: now))
            }
            formatter.timeStyle = .short
            return (.shortTime, formatter.string(from: createdAt))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(createdAt, inSameDayAs: yesterday)
        {
            formatter.doesRelativeDateFormatting = true
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        } else {
            let includesYear = calendar.component(.year, from: createdAt) != calendar.component(.year, from: now)
            formatter.setLocalizedDateFormatFromTemplate(includesYear ? "yMMMdjm" : "MMMdjm")
        }
        return (.dateTime, formatter.string(from: createdAt))
    }

    private static func suppressesTimestamp(_ message: AiChatMessage, after previousMessage: AiChatMessage?) -> Bool {
        guard let previousMessage,
              previousMessage.role == message.role,
              let earlier = previousMessage.createdAtMs,
              let later = message.createdAtMs,
              later >= earlier
        else { return false }
        let (delta, overflow) = later.subtractingReportingOverflow(earlier)
        return !overflow && delta < 60000
    }
}
