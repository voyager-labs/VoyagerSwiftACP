// Portions adapted from Conduit (MIT License).
// Original: Sources/Conduit/Utilities/ServerSentEventParser.swift
// Commit: bd57239663e63c3ad28647a73ae761a7aa46e123

import Foundation

/// A parsed Server-Sent Event.
///
/// Mirrors the semantics of common `EventSource` implementations:
/// - `event == nil` implies the default type `"message"`
/// - `id` is only set when an `id:` field is present for that event
public struct ServerSentEvent: Sendable, Equatable {
    /// The event ID (if provided by the server for this event).
    public var id: String?

    /// The event type name (if provided via `event:`; `nil` implies `"message"`).
    public var event: String?

    /// The event data payload (may contain newlines if multiple `data:` lines were present).
    public var data: String

    /// Optional reconnection retry interval (ms) if provided by a `retry:` field.
    public var retry: Int?

    public init(id: String? = nil, event: String? = nil, data: String, retry: Int? = nil) {
        self.id = id
        self.event = event
        self.data = data
        self.retry = retry
    }
}

/// Incremental parser for Server-Sent Events (SSE).
///
/// Feed the parser newline-delimited lines (without the trailing `\n`). A blank line
/// terminates the current event and causes it to be emitted.
public struct ServerSentEventParser: Sendable {
    private var currentEventId: String?
    private var currentEventType: String?
    private var currentData: String = ""
    private var currentRetry: Int?

    private var lastEventId: String = ""
    private var reconnectionTime: Int = 3000

    private var seenFields: Set<String> = []

    public init() {}

    /// Ingests one SSE line (without its trailing newline) and returns any complete events.
    public mutating func ingestLine(_ line: String) -> [ServerSentEvent] {
        let normalizedLine = normalizeLine(line)

        // Empty line dispatches the event.
        if normalizedLine.isEmpty {
            let events = dispatchIfNeeded()
            seenFields.removeAll(keepingCapacity: true)
            return events
        }

        // Comments begin with ":" and are ignored.
        if normalizedLine.hasPrefix(":") {
            return []
        }

        let (field, value) = parseFieldValue(normalizedLine)

        switch field {
        case "event":
            currentEventType = value
            seenFields.insert("event")
        case "data":
            if !currentData.isEmpty {
                currentData.append("\n")
            }
            currentData.append(value)
            seenFields.insert("data")
        case "id":
            if !value.contains("\u{0000}") {
                currentEventId = value
                lastEventId = value
            }
            seenFields.insert("id")
        case "retry":
            if let milliseconds = Int(value), milliseconds > 0 {
                reconnectionTime = milliseconds
                currentRetry = milliseconds
            }
            seenFields.insert("retry")
        default:
            break
        }

        return []
    }

    /// Call at end-of-stream to flush any pending event.
    public mutating func finish() -> [ServerSentEvent] {
        guard !currentData.isEmpty || currentEventId != nil || currentEventType != nil else {
            return []
        }
        let events = dispatchIfNeeded()
        seenFields.removeAll(keepingCapacity: true)
        return events
    }

    // MARK: - Internals

    private func normalizeLine(_ line: String) -> String {
        var normalized = line
        if normalized.hasSuffix("\r") {
            normalized = String(normalized.dropLast())
        }
        if normalized.hasPrefix("\u{FEFF}") {
            normalized = String(normalized.dropFirst())
        }
        return normalized
    }

    private func parseFieldValue(_ line: String) -> (field: String, value: String) {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return (field: line, value: "")
        }

        let field = String(line[..<colonIndex])
        var valueStart = line.index(after: colonIndex)

        if valueStart < line.endIndex, line[valueStart] == " " {
            valueStart = line.index(after: valueStart)
        }

        let value = String(line[valueStart...])
        return (field: field, value: value)
    }

    private mutating func dispatchIfNeeded() -> [ServerSentEvent] {
        let isDataField = currentData.isEmpty && seenFields.contains("data")
        let isRetryOnly =
            currentData.isEmpty && currentEventId == nil && currentEventType == nil
                && !isDataField

        defer {
            currentEventType = nil
            currentData = ""
            currentEventId = nil
            currentRetry = nil
        }

        guard !isRetryOnly else { return [] }

        let event = ServerSentEvent(
            id: currentEventId,
            event: currentEventType,
            data: currentData,
            retry: currentRetry,
        )
        return [event]
    }
}
